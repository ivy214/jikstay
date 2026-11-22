# -*- coding: utf-8 -*-
"""
자연·액티비티 걷기길(kind=outdoor, sub=trail): 한국관광공사 두루누비 코리아둘레길 코스 → 허브 spots.

  - Durunubi courseList 전체(약 170코스: 해파랑길·남파랑길·서해랑길·DMZ 평화의 길)를 받아 코스마다
    거리·소요 시간·난이도·순환 여부·설명·찾아가는 길을 넣는다. 값은 두루누비 그대로이고 없는 칸은 만들지 않는다.
  - 좌표: 코스 GPX 의 첫 점(시작)·끝 점. GPX 는 backend/trail_gpx_cache.json 에 (코스, 수정 시각)별로 기억해
    바뀐 코스만 다시 받는다.
  - 사진: 두루누비에는 사진이 없다. 관광공사 TourAPI 에 같은 길·같은 코스 번호의 항목이 딱 하나 있을 때만 그 사진을 쓰고,
    아니면 사진 없이 둔다(다른 코스 사진을 잘못 붙이지 않도록).
  - 같은 코스가 두 번 나오지 않게, 레포츠 수집으로 들어온 같은 코리아둘레길 코스(TourAPI)는 spots 에서 뺀다.
  - 공식 링크: 두루누비 코스 상세 페이지 (지도·GPX 내려받기).
  - Firebase 자격 증명이 있으면 Firestore spots 문서를 만들고(후기·찜·사이트맵), 목록에서 사라진 코스는 closed.

  python backend/refresh_trails.py --dry-run
  python backend/refresh_trails.py --no-firestore
  python backend/refresh_trails.py
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import requests

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    _https,
    _split_editorial_paragraphs,
    _strip_overview_html,
    _fetch_naver_place_blog_snippets,
    _tour_get,
    upload_spots_to_firestore,
)
from collect_half_price_spots import HUB_PATH, _items, _load_env  # noqa: E402
from curate_public_stays import classify_region_group, normalize_place_name  # noqa: E402

DURUNUBI = "https://apis.data.go.kr/B551011/Durunubi"
COURSE_PAGE = "https://www.durunubi.kr/4-2-1-1-walk-mobility-view-detail.do?crs_idx="
GPX_CACHE = ROOT / "backend" / "trail_gpx_cache.json"
MAX_REMOVE_RATIO = 0.10
PROVINCES = ("서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종", "경기", "강원",
             "충북", "충남", "전북", "전남", "경북", "경남", "제주")
LEVELS = {"1": "쉬움", "2": "보통", "3": "어려움"}
# 코리아둘레길 4개 길. '해파랑길 35코스 바우길 09구간' · '[해파랑길] 38코스(바우길 6구간)' → ('해파랑길', 35)
THEME_RE = re.compile(r"(해파랑길|남파랑길|서해랑길|DMZ\s?평화의\s?길)\D{0,6}?(\d{1,3})\s?코스")


def course_key(title: str) -> tuple[str, int] | None:
    m = THEME_RE.search(title or "")
    return (re.sub(r"\s", "", m.group(1)), int(m.group(2))) if m else None


def _get(endpoint: str, params: dict[str, Any]) -> dict[str, Any] | None:
    key = os.environ.get("TOUR_API_KEY") or os.environ.get("DATA_GO_KR_SERVICE_KEY") or ""
    try:
        r = requests.get(f"{DURUNUBI}/{endpoint}", params={
            "serviceKey": key, "MobileOS": "ETC", "MobileApp": "jikstay", "_type": "json", **params}, timeout=60)
        if r.status_code != 200:
            print(f"  [두루누비] {endpoint} HTTP {r.status_code}")
            return None
        return r.json().get("response", {}).get("body", {})
    except Exception as exc:  # noqa: BLE001
        print(f"  [두루누비] {endpoint} 실패: {str(exc)[:120]}")
        return None


def fetch_courses() -> tuple[list[dict[str, Any]], dict[str, str]] | None:
    body = _get("courseList", {"numOfRows": 1000, "pageNo": 1})
    routes = _get("routeList", {"numOfRows": 100, "pageNo": 1})
    if body is None or routes is None:
        return None
    courses = _items(body)
    if len(courses) < int(body.get("totalCount") or 0):
        return None  # 일부만 받은 목록으로 닫지 않도록
    return courses, {str(r.get("routeIdx")): str(r.get("themeNm") or "") for r in _items(routes)}


def gpx_points(text: str) -> list[tuple[float, float]]:
    pts = re.findall(r'<(?:trkpt|rtept)[^>]*?lat="([-\d.]+)"[^>]*?lon="([-\d.]+)"', text)
    if not pts:
        pts = [(a, b) for b, a in re.findall(r'<(?:trkpt|rtept)[^>]*?lon="([-\d.]+)"[^>]*?lat="([-\d.]+)"', text)]
    return [(float(a), float(b)) for a, b in pts]


def gpx_endpoints(text: str) -> tuple[float, float, float, float] | None:
    pts = gpx_points(text)
    if not pts:
        return None
    (la1, lo1), (la2, lo2) = pts[0], pts[-1]
    return la1, lo1, la2, lo2


def _xy_m(p: tuple[float, float], lat0: float) -> tuple[float, float]:
    return p[1] * 111_320 * math.cos(math.radians(lat0)), p[0] * 110_540


def _seg_dist_m(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    lat0 = p[0]
    (px, py), (ax, ay), (bx, by) = _xy_m(p, lat0), _xy_m(a, lat0), _xy_m(b, lat0)
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def simplify(pts: list[tuple[float, float]], tol_m: float) -> list[tuple[float, float]]:
    """Douglas-Peucker (반복형). 모양을 tol_m 미터 오차 안에서 유지하며 점을 줄인다."""
    if len(pts) < 3:
        return list(pts)
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        best, idx = 0.0, -1
        for k in range(i + 1, j):
            d = _seg_dist_m(pts[k], pts[i], pts[j])
            if d > best:
                best, idx = d, k
        if idx >= 0 and best > tol_m:
            keep[idx] = True
            stack += [(i, idx), (idx, j)]
    return [p for p, k in zip(pts, keep) if k]


def simplify_to(pts: list[tuple[float, float]], max_points: int) -> list[tuple[float, float]]:
    tol = 30.0
    out = simplify(pts, tol)
    while len(out) > max_points and tol < 50_000:
        tol *= 1.5
        out = simplify(pts, tol)
    return out


def encode_polyline(pts: list[tuple[float, float]]) -> str:
    """Google encoded polyline (정밀도 1e-5). 앱 lib/trail_route.dart 의 decodePolyline 과 짝."""
    out, plat, plng = [], 0, 0
    for lat, lng in pts:
        ilat, ilng = round(lat * 1e5), round(lng * 1e5)
        for v in (ilat - plat, ilng - plng):
            v = ~(v << 1) if v < 0 else v << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        plat, plng = ilat, ilng
    return "".join(out)


def decode_polyline(s: str) -> list[tuple[float, float]]:
    pts, i, lat, lng = [], 0, 0, 0
    while i < len(s):
        vals = []
        for _ in range(2):
            shift = res = 0
            while True:
                b = ord(s[i]) - 63
                i += 1
                res |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            vals.append(~(res >> 1) if res & 1 else res >> 1)
        lat += vals[0]
        lng += vals[1]
        pts.append((lat / 1e5, lng / 1e5))
    return pts


def dist_to_route_km(lat: float, lng: float, route: list[tuple[float, float]]) -> float:
    if not route:
        return 1e9
    if len(route) == 1:
        return _seg_dist_m((lat, lng), route[0], route[0]) / 1000
    return min(_seg_dist_m((lat, lng), a, b) for a, b in zip(route, route[1:])) / 1000


ROUTE_MAX_POINTS = 32  # 카드·상세의 경로 그림용 (첫 화면 데이터에 들어가므로 작게, 코스당 약 200바이트)


def load_gpx(courses: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """코스별 {pts: [시작 위도, 경도, 끝 위도, 경도], route: 그림용 경로, track: 거리 판정용 경로}. 바뀐 코스만 다시 받는다."""
    cache: dict[str, Any] = json.loads(GPX_CACHE.read_text(encoding="utf-8")) if GPX_CACHE.exists() else {}
    todo = [c for c in courses if c.get("gpxpath") and (
        (cache.get(c["crsIdx"]) or {}).get("modified") != c.get("modifiedtime") or not (cache.get(c["crsIdx"]) or {}).get("route"))]

    def fetch(c: dict[str, Any]) -> tuple[str, list[tuple[float, float]]]:
        try:
            r = requests.get(_https(str(c["gpxpath"])), timeout=40)
            return c["crsIdx"], gpx_points(r.text) if r.status_code == 200 else []
        except Exception:  # noqa: BLE001
            return c["crsIdx"], []

    if todo:
        with ThreadPoolExecutor(max_workers=6) as pool:
            for (cid, pts), c in zip(pool.map(fetch, todo), todo):
                if not pts:
                    continue
                old = cache.get(cid) or {}
                entry = {
                    "modified": c.get("modifiedtime"),
                    "pts": [round(x, 6) for x in (*pts[0], *pts[-1])],
                    "route": encode_polyline(simplify_to(pts, ROUTE_MAX_POINTS)),
                    "track": encode_polyline(simplify(pts, 60.0)),
                }
                if old.get("modified") == c.get("modifiedtime") and "photo" in old:
                    entry["photo"] = old["photo"]  # 코스가 그대로면 사진 판정도 그대로
                cache[cid] = entry
        save_gpx_cache(cache)
        print(f"  GPX {len(todo)}개 새로 받음")
    return {k: v for k, v in cache.items() if isinstance(v, dict) and v.get("pts")}


def save_gpx_cache(cache: dict[str, Any]) -> None:
    GPX_CACHE.write_text(json.dumps(cache, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8")


def fetch_tour_photos() -> dict[tuple[str, int], str]:
    """TourAPI 에서 같은 길·같은 코스 번호가 딱 하나인 항목의 사진만."""
    found: dict[tuple[str, int], set[str]] = {}
    for kw in ("해파랑길", "남파랑길", "서해랑길", "평화의 길"):
        body = _tour_get("searchKeyword2", {"keyword": kw, "numOfRows": 500, "pageNo": 1, "arrange": "O"}, timeout=40)
        for it in _items(body):
            k = course_key(str(it.get("title") or ""))
            img = _https(str(it.get("firstimage") or ""))
            if k and img:
                found.setdefault(k, set()).add(img)
    return {k: next(iter(v)) for k, v in found.items() if len(v) == 1}


# 코스 설명 '주요 볼거리'의 따옴표 속 이름: "부산의 상징 '오륙도'" → 오륙도
_QUOTED_RE = re.compile(r"[‘'\"“]([^’'\"”<>]{2,24})[’'\"”]")
ON_COURSE_MAX_KM = 2.0  # 같은 이름의 다른 곳을 잡지 않도록, 코스 경로에서 이 거리 안에 있는 곳만
PHOTO_CONTENT_TYPES = ("12", "14", "28")  # 관광지·문화시설·레포츠 (음식점·숙박 사진은 쓰지 않는다)
_CAMP_RE = re.compile(r"(캠핑|글램핑|카라반|야영)")  # 캠핑장 사진은 걷기길 대표 사진으로 맞지 않는다


def tour_names(raw: str) -> list[str]:
    names: list[str] = []
    for m in _QUOTED_RE.finditer(_strip_overview_html(re.sub(r"<br\s*/?>", " ", raw or "", flags=re.I))):
        n = m.group(1).strip()
        if n and n not in names:
            names.append(n)
    return names[:4]


def find_on_course_photo(names: list[str], track: list[tuple[float, float]]) -> dict[str, str] | None:
    """코스 위 볼거리 중 관광공사 사진이 있는 첫 곳. 조회가 실패하면 None(다음에 다시), 없으면 {}."""
    def norm(x: str) -> str:
        return re.sub(r"[\s·()\[\]]", "", x or "")

    for name in names:
        body = _tour_get("searchKeyword2", {"keyword": name, "numOfRows": 30, "pageNo": 1, "arrange": "O"}, timeout=20)
        if body is None:
            return None
        best: tuple[float, dict[str, str]] | None = None
        for it in _items(body):
            img = _https(str(it.get("firstimage") or ""))
            t = str(it.get("title") or "")
            if not img or str(it.get("contenttypeid") or "") not in PHOTO_CONTENT_TYPES or _CAMP_RE.search(t):
                continue
            if norm(name) not in norm(t) and norm(t) not in norm(name):
                continue
            try:
                d = dist_to_route_km(float(it.get("mapy") or 0), float(it.get("mapx") or 0), track)
            except ValueError:
                continue
            if d <= ON_COURSE_MAX_KM and (best is None or d < best[0]):
                best = (d, {"img": img, "title": normalize_place_name(t) or t})
        if best:
            return best[1]
    return {}


def _lines(raw: str) -> list[str]:
    txt = re.sub(r"<br\s*/?>", "\n", raw or "", flags=re.I)
    txt = _strip_overview_html(txt.replace("\n", " ␤ ")).replace("␤", "\n")
    return [re.sub(r"^\s*[-·•]\s*", "", ln).strip() for ln in txt.split("\n") if ln.strip(" -")]


def _duration(minutes: int) -> str:
    h, m = divmod(minutes, 60)
    return f"약 {h}시간" + (f" {m}분" if m else "") if h else f"약 {m}분"


def build_trail_doc(c: dict[str, Any], theme: str, ends: list[float] | None, photo: str = "",
                    route: str = "", photo_place: str = "") -> dict[str, Any] | None:
    cid = str(c.get("crsIdx") or "").strip()
    title = re.sub(r"\s+", " ", str(c.get("crsKorNm") or "")).strip()
    sigun = re.sub(r"\s+", " ", str(c.get("sigun") or "")).strip()
    prov = sigun.split(" ")[0] if sigun else ""
    if not cid or not title or prov not in PROVINCES or not ends:
        return None
    lat, lng, end_lat, end_lng = ends
    if not (32.0 <= lat <= 39.5 and 124.0 <= lng <= 132.0):
        return None

    rows: list[dict[str, str]] = []
    try:
        km = float(str(c.get("crsDstnc") or "").strip())
    except ValueError:
        km = 0.0
    try:
        minutes = int(str(c.get("crsTotlRqrmHour") or "").strip())
    except ValueError:
        minutes = 0
    level = LEVELS.get(str(c.get("crsLevel") or "").strip(), "")
    if km > 0:
        rows.append({"label": "거리", "value": f"{km:g}km"})
    if minutes > 0:
        rows.append({"label": "걷는 시간", "value": _duration(minutes)})
    if level:
        rows.append({"label": "난이도", "value": level})
    if str(c.get("crsCycle") or "").strip():
        rows.append({"label": "코스 형태", "value": str(c["crsCycle"]).strip()})
    if theme:
        rows.append({"label": "길 이름", "value": f"코리아둘레길 {theme}"})

    summary = " ".join(_lines(str(c.get("crsSummary") or "")))
    contents = " ".join(_lines(str(c.get("crsContents") or "")))
    tour = _lines(str(c.get("crsTourInfo") or ""))
    travel = _lines(str(c.get("travelerinfo") or ""))
    paragraphs = _split_editorial_paragraphs(contents or summary)[:2]
    if tour:
        paragraphs.append("주요 볼거리: " + " / ".join(tour)[:500])
    if travel:
        paragraphs.append("찾아가는 길: " + " / ".join(travel)[:500])

    doc: dict[str, Any] = {
        "id": f"spot_tr_{re.sub(r'[^0-9A-Za-z]', '', cid)[-12:]}",
        "kind": "outdoor",
        "sub": "trail",
        "content_id": f"durunubi:{cid}",
        "title": title,
        "province": prov,
        "region_group": classify_region_group(prov) or "전체",
        "region_label": sigun,
        "addr": sigun,
        "lat": lat,
        "lng": lng,
        "end_lat": end_lat,
        "end_lng": end_lng,
        "image_url": photo,
        "url": COURSE_PAGE + cid,
        "practical_header": "걷기 전 확인 · 거리 · 시간 · 난이도 · 찾아가는 길",
        "practical_info": rows,
        "source": "한국관광공사 두루누비",
    }
    if route:
        doc["route"] = route  # 경로 그림 (encoded polyline)
    if photo and photo_place:
        doc["image_place"] = photo_place  # 코스 자체가 아닌 코스 위 볼거리 사진 → 앱이 "코스 위 볼거리: …" 로 밝힌다
    if km > 0:
        doc["distance_km"] = km
    if minutes > 0:
        doc["duration_min"] = minutes
    if level:
        doc["level"] = level
    if summary or contents:
        doc["overview"] = (summary or contents)[:220]
    if paragraphs:
        doc["paragraphs"] = paragraphs[:4]
    if tour:
        doc["pull_quote"] = tour[0][:130]
    if c.get("gpxpath"):
        doc["gpx_url"] = _https(str(c["gpxpath"]))
    return doc


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="두루누비 코리아둘레길 걷기길 갱신")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-firestore", action="store_true")
    args = ap.parse_args()
    _load_env()

    got = fetch_courses()
    if got is None:
        print("[trails] 두루누비 목록 조회 실패 (키·활용신청 또는 호출 한도) — 변경 없이 종료")
        return
    courses, themes = got
    geo = load_gpx(courses)
    photos = fetch_tour_photos()
    # 같은 코스 사진이 없으면 코스 위 볼거리 사진 (코스·수정 시각별로 기억해 바뀐 코스만 다시 찾는다)
    looked = 0
    for c in courses:
        cid = str(c.get("crsIdx") or "")
        theme = themes.get(str(c.get("routeIdx")), "")
        k = course_key(f"{theme} {c.get('crsKorNm') or ''}") or course_key(str(c.get("crsKorNm") or ""))
        g = geo.get(cid)
        if not g or (k and k in photos) or "photo" in g:
            continue
        found = find_on_course_photo(tour_names(str(c.get("crsTourInfo") or "")), decode_polyline(g.get("track") or g["route"]))
        looked += 1
        if found is not None:
            g["photo"] = found
    if looked:
        save_gpx_cache({**(json.loads(GPX_CACHE.read_text(encoding="utf-8")) if GPX_CACHE.exists() else {}), **geo})

    docs: list[dict[str, Any]] = []
    for c in courses:
        cid = str(c.get("crsIdx") or "")
        theme = themes.get(str(c.get("routeIdx")), "")
        k = course_key(f"{theme} {c.get('crsKorNm') or ''}") or course_key(str(c.get("crsKorNm") or ""))
        g = geo.get(cid) or {}
        photo, caption = (photos.get(k, "") if k else ""), ""
        if not photo and (g.get("photo") or {}).get("img"):
            photo, caption = g["photo"]["img"], g["photo"]["title"]
        doc = build_trail_doc(c, theme, g.get("pts"), photo, g.get("route", ""), caption)
        if doc:
            docs.append(doc)
    n_same = sum(1 for d in docs if d["image_url"] and not d.get("image_place"))
    n_on = sum(1 for d in docs if d.get("image_place"))
    print(f"[trails] 두루누비 {len(courses)}코스 → {len(docs)}코스 · 사진: 같은 코스 {n_same} · 코스 위 볼거리 {n_on} · "
          f"경로 그림만 {len(docs) - n_same - n_on}")
    if args.dry_run:
        from collections import Counter
        print("  시·도별:", dict(Counter(d["province"] for d in docs).most_common()))
        for d in docs:
            if d.get("image_place"):
                print(f"    {d['title']} ← 코스 위 볼거리: {d['image_place']}")
        return

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    spots = hub.get("spots") or []
    prev = [s for s in spots if str(s.get("id") or "").startswith("spot_tr_")]
    now_ids = {d["id"] for d in docs}
    closed = [s for s in prev if s["id"] not in now_ids]
    if prev and len(closed) > len(prev) * MAX_REMOVE_RATIO:
        print(f"[trails] 사라진 코스 {len(closed)}개가 10%를 넘어 API 이상으로 보고 닫지 않음")
        docs += closed
        closed = []
    # 레포츠(TourAPI)로 들어온 같은 코리아둘레길 코스는 두루누비 것으로 대체
    keys = {course_key(d["title"]) for d in docs} - {None}
    dup = [s for s in spots if not str(s.get("id") or "").startswith("spot_tr_")
           and s.get("kind") == "outdoor" and course_key(str(s.get("title") or "")) in keys]

    today = dt.date.today().strftime("%Y%m%d")
    prev_by_id = {s["id"]: s for s in prev}
    fetched = 0
    for d in docs:
        old = prev_by_id.get(d["id"]) or {}
        d["added_at"] = old.get("added_at") or today
        # 네이버 블로그 방문기(원문 링크): 지난번 결과를 쓰고, 처음 보는 코스만 검색한다
        if "naver_reviews" in old:
            if old["naver_reviews"]:
                d["naver_reviews"] = old["naver_reviews"]
            continue
        k = course_key(d["title"])
        name = f"{k[0]} {k[1]}코스" if k else d["title"]
        d["naver_reviews"] = _fetch_naver_place_blog_snippets(
            f"{name} 후기", max_items=2, place_title=name, region_label=d["region_label"], province=d["province"])
        fetched += 1
    if fetched:
        print(f"  네이버 방문기 검색 {fetched}코스 · 찾은 코스 {sum(1 for d in docs if d.get('naver_reviews'))}")

    if not args.no_firestore:
        upload_spots_to_firestore(docs)
        if closed or dup:
            from firebase_admin import firestore

            from firebase_client import db

            col = db().collection("spots")
            for s in [*closed, *dup]:
                ref = col.document(str(s["id"]))
                if ref.get().exists:
                    ref.update({"status": "closed",
                                "closed_reason": "두루누비 목록에서 삭제됨" if s in closed else "두루누비 코스로 대체",
                                "closed_at": firestore.SERVER_TIMESTAMP})

    drop = {s["id"] for s in [*prev, *dup]}
    hub["spots"] = [s for s in spots if s.get("id") not in drop] + docs
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[trails] 저장: 걷기길 {len(docs)}코스 · 닫음 {len(closed)} · 중복 대체 {len(dup)} ({', '.join(s['title'] for s in dup)})")


if __name__ == "__main__":
    main()
