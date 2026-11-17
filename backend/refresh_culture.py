# -*- coding: utf-8 -*-
"""
공연·전시 갱신 (한국문화정보원 한눈에보는문화정보조회서비스 + KOPIS 공연예술통합전산망).

  - 오늘부터 WINDOW_DAYS 일 안에 열리는(진행 중 포함) 공연·전시를 받아 허브 JSON 의 culture 섹션을 통째로 다시 만든다.
    과거(이미 끝난) 공연·전시는 가져오지 않는다. 끝난 항목은 앱·사이트맵이 종료일로 바로 숨긴다.
  - 상세(요금·공식/예매 링크·문의·장소 주소)는 backend/culture_detail_cache.json 에 저장해 새 항목만 호출한다.
    캐시에서 끝난 항목은 지운다.
  - Firebase 자격 증명이 있으면 Firestore spots 문서를 만든다(후기·찜·사이트맵).
  - KOPIS_API_KEY 가 있으면 지방 공연을 보강한다 (서울·해외 제외, 학생·발표회 제외, 문화정보원과 겹치는 공연 제외):
    이번 주(7일) 안에 시작하는 공연은 모두, 여러 날 하는 공연은 4주 안에 시작하는 것까지.
    공연 상세·공연장(좌표)은 backend/kopis_cache.json 에 저장해 새 것만 호출한다.

  python backend/refresh_culture.py               # 전체
  python backend/refresh_culture.py --dry-run     # 집계만
  python backend/refresh_culture.py --no-firestore
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import normalize_province_short, parse_korean_address, upload_spots_to_firestore  # noqa: E402
from collect_half_price_spots import HUB_PATH, _load_env  # noqa: E402

API = "https://apis.data.go.kr/B553457/cultureinfo"
CACHE_PATH = ROOT / "backend" / "culture_detail_cache.json"
WINDOW_DAYS = 56
# 여행지에서 들를 만한 것만: 공연·전시. (교육/체험은 수강 모집 성격, 행사/축제는 관광공사 축제와 겹침)
KEEP_TYPES = {"공연", "전시"}
PAGE_ROWS = 500
MAX_CONSECUTIVE_FAILS = 5
# 공공데이터포털 게이트웨이의 초당 호출 제한(넘으면 HTTP 429) — 상세는 이 간격으로 차례대로 받는다
DETAIL_GAP_SEC = 1.1
KOPIS_API = "http://www.kopis.or.kr/openApi/restful"
KOPIS_CACHE_PATH = ROOT / "backend" / "kopis_cache.json"
KOPIS_WEEK_DAYS = 7          # 이번 주: 하루짜리 공연도 넣는 범위
KOPIS_LONG_DAYS = 28         # 여러 날 하는 공연은 이 안에 시작하는 것까지
KOPIS_GAP_SEC = 0.15
KOPIS_AMATEUR_RE = re.compile(r"학생|졸업|발표회|동호회|학예회|아마추어")
PROVINCES = ("서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종", "경기", "강원",
             "충북", "충남", "전북", "전남", "경북", "경남", "제주")


def _key() -> str:
    import os

    return os.environ.get("DATA_GO_KR_SERVICE_KEY", "").strip()


def _get(endpoint: str, params: dict[str, Any], timeout: int = 40) -> ET.Element | None:
    url = f"{API}/{endpoint}?" + urllib.parse.urlencode({"serviceKey": _key(), **params})
    for attempt in range(4):
        try:
            root = ET.fromstring(urllib.request.urlopen(url, timeout=timeout).read())
            code = root.findtext(".//resultCode")
            if code not in (None, "00", "0000"):
                print(f"[culture] {endpoint} 결과 코드 {code}: {root.findtext('.//resultMsg')}", file=sys.stderr)
                return None
            return root
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < 3:
                time.sleep(10.0 * (attempt + 1))  # 초당 제한 → 잠시 쉬고 다시
                continue
            print(f"[culture] {endpoint} 실패: {exc}", file=sys.stderr)
            return None
        except (urllib.error.URLError, ET.ParseError, TimeoutError) as exc:
            if attempt == 3:
                print(f"[culture] {endpoint} 실패: {exc}", file=sys.stderr)
                return None
            time.sleep(2.0 * (attempt + 1))
    return None


def _fields(el: ET.Element) -> dict[str, str]:
    return {c.tag: (c.text or "").strip() for c in el}


def clean_text(s: str) -> str:
    """API 제목은 '&amp;lt;' 처럼 두 번 이스케이프되어 온다 → 두 번 풀고 공백 정리"""
    t = html.unescape(html.unescape(str(s or "")))
    t = re.sub(r"<[^>]+>", " ", t) if "<br" in t.lower() or "<p" in t.lower() else t
    return re.sub(r"\s+", " ", t).strip()


def _https(u: str) -> str:
    u = str(u or "").strip()
    return "https://" + u[len("http://"):] if u.startswith("http://") else u


def fetch_list(today: dt.date) -> list[dict[str, str]] | None:
    fr = today.strftime("%Y%m%d")
    to = (today + dt.timedelta(days=WINDOW_DAYS)).strftime("%Y%m%d")
    out: list[dict[str, str]] = []
    page = 1
    while True:
        root = _get("period2", {"PageNo": page, "numOfrows": PAGE_ROWS, "from": fr, "to": to})
        if root is None:
            return None
        items = [_fields(i) for i in root.iter("item")]
        out += items
        if len(items) < PAGE_ROWS:
            break
        page += 1
    return out


def fetch_detail(seq: str) -> dict[str, str] | None:
    root = _get("detail2", {"seq": seq}, timeout=25)
    if root is None:
        return None
    item = next(root.iter("item"), None)
    return _fields(item) if item is not None else {}


def province_of(it: dict[str, str], det: dict[str, str]) -> tuple[str, str]:
    """(시·도 짧은 이름, 시·군·구). 장소 주소가 있으면 그것으로, 없으면 목록의 area·sigungu 로."""
    addr = det.get("placeAddr", "")
    if addr:
        d1, d2 = parse_korean_address(addr)
        prov = normalize_province_short(d1, d2) if d1 else ""
        if prov in PROVINCES:
            return prov, (d2.split(" ")[0] if d2 else it.get("sigungu", ""))
    area, sigungu = it.get("area", ""), it.get("sigungu", "")
    if not area:
        return "", ""
    prov = normalize_province_short(area, sigungu)
    return (prov if prov in PROVINCES else ""), sigungu


def _ymd_dot(s: str) -> str:
    return f"{s[:4]}.{s[4:6]}.{s[6:8]}" if re.fullmatch(r"\d{8}", s or "") else s


def build_culture_doc(it: dict[str, str], det: dict[str, str]) -> dict[str, Any] | None:
    seq = it.get("seq", "")
    ctype = it.get("serviceName", "")
    title = clean_text(it.get("title", ""))
    img = _https(det.get("imgUrl") or it.get("thumbnail", ""))
    try:
        lng, lat = float(it.get("gpsX") or det.get("gpsX") or 0), float(it.get("gpsY") or det.get("gpsY") or 0)
    except ValueError:
        return None
    if not seq or ctype not in KEEP_TYPES or not title or not img or not (32.0 <= lat <= 39.5 and 124.0 <= lng <= 132.0):
        return None
    prov, city = province_of(it, det)
    if not prov:
        return None
    sd, ed = it.get("startDate", ""), it.get("endDate", "")
    place = clean_text(det.get("place") or it.get("place", ""))
    realm = it.get("realmName", "") or ctype
    price = clean_text(det.get("price", ""))[:80]
    phone = clean_text(det.get("phone", ""))[:60]
    url = det.get("url", "").replace("&amp;", "&").strip()
    rows = [{"label": "기간", "value": f"{_ymd_dot(sd)} ~ {_ymd_dot(ed)}"}]
    if place:
        rows.append({"label": "장소", "value": place})
    if price:
        rows.append({"label": "요금", "value": price})
    rows.append({"label": "분야", "value": realm})
    if phone:
        rows.append({"label": "문의", "value": phone})
    addr = clean_text(det.get("placeAddr", ""))
    region_label = f"{prov} {city}".strip()
    summary = f"{region_label} {place}에서 {'열리는' if ctype == '공연' else '진행되는'} {realm}{'' if realm == ctype else ' ' + ctype}. " \
              f"{_ymd_dot(sd)}부터 {_ymd_dot(ed)}까지" + (f" · {price}" if price else "") + "."
    doc: dict[str, Any] = {
        "id": f"spot_cu_{seq}",
        "kind": "culture",
        "culture_type": ctype,
        "realm": realm,
        "title": title,
        "province": prov,
        "region_label": region_label,
        "city": city,
        "addr": addr or place,
        "lat": lat,
        "lng": lng,
        "image_url": img,
        "images": [img],
        "tel": phone,
        "start_date": sd,
        "end_date": ed,
        "place": place,
        "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {place or title}'.strip())}",
        "overview": summary[:220],
        "pull_quote": f"{realm} · {place}" if place else realm,
        "practical_header": "관람 전 확인 · 기간 · 장소 · 요금 · 예매",
        "practical_info": rows,
    }
    if url.startswith("http"):
        doc["url"] = url
    if price:
        doc["price_text"] = price
    return doc


# ---------------------------------------------------------------------------
# KOPIS (지방 공연 보강)
# ---------------------------------------------------------------------------

def _kopis_key() -> str:
    import os

    return os.environ.get("KOPIS_API_KEY", "").strip()


def _kopis_get(path: str, params: dict[str, Any] | None = None) -> ET.Element | None:
    url = f"{KOPIS_API}/{path}?" + urllib.parse.urlencode({"service": _kopis_key(), **(params or {})})
    for attempt in range(3):
        try:
            return ET.fromstring(urllib.request.urlopen(url, timeout=30).read())
        except Exception as exc:  # noqa: BLE001
            if attempt == 2:
                print(f"[kopis] {path} 실패: {exc}", file=sys.stderr)
                return None
            time.sleep(2.0 * (attempt + 1))
    return None


def _norm_title(s: str) -> str:
    return re.sub(r"[\s\[\]()<>〈〉《》「」'\"“”‘’:：\-·,.!?~]", "", clean_text(s)).lower()


def kopis_selected(rows: list[dict[str, str]], today: dt.date, culture_docs: list[dict[str, Any]]) -> list[dict[str, str]]:
    """절충안 기준으로 넣을 공연만 고른다."""
    week = (today + dt.timedelta(days=KOPIS_WEEK_DAYS - 1)).strftime("%Y%m%d")
    long_ = (today + dt.timedelta(days=KOPIS_LONG_DAYS - 1)).strftime("%Y%m%d")
    known = [(_norm_title(d["title"]), d.get("start_date", ""), d.get("end_date", "")) for d in culture_docs if d.get("culture_type") == "공연"]
    out = []
    for r in rows:
        sd, ed = r.get("prfpdfrom", "").replace(".", ""), r.get("prfpdto", "").replace(".", "")
        if not r.get("mt20id") or r.get("area") in ("서울특별시", "해외", ""):
            continue
        if KOPIS_AMATEUR_RE.search(r.get("prfnm", "")) or KOPIS_AMATEUR_RE.search(r.get("fcltynm", "")):
            continue
        if not (sd <= week or (sd != ed and sd <= long_)):
            continue
        t = _norm_title(r.get("prfnm", ""))
        if any(len(t) >= 4 and (t in a or a in t) and not (ce < sd or cs > ed) for a, cs, ce in known):
            continue  # 문화정보원에 이미 있는 공연
        out.append(r)
    return out


def build_kopis_doc(perf: dict[str, Any], venue: dict[str, str]) -> dict[str, Any] | None:
    pid = perf.get("mt20id", "")
    title = clean_text(perf.get("prfnm", ""))
    img = _https(perf.get("poster", ""))
    try:
        lat, lng = float(venue.get("la") or 0), float(venue.get("lo") or 0)
    except ValueError:
        return None
    if not pid or not title or not img or not (32.0 <= lat <= 39.5 and 124.0 <= lng <= 132.0):
        return None
    addr = clean_text(venue.get("adres", ""))
    d1, d2 = parse_korean_address(addr) if addr else ("", "")
    prov = normalize_province_short(d1, d2) if d1 else ""
    if prov not in PROVINCES:
        return None
    city = d2.split(" ")[0] if d2 else ""
    sd, ed = perf.get("prfpdfrom", "").replace(".", ""), perf.get("prfpdto", "").replace(".", "")
    place = clean_text(perf.get("fcltynm", "")) or clean_text(venue.get("fcltynm", ""))
    realm = perf.get("genrenm", "") or "공연"
    price = clean_text(perf.get("pcseguidance", ""))[:80]
    rows = [{"label": "기간", "value": f"{_ymd_dot(sd)} ~ {_ymd_dot(ed)}"}]
    if perf.get("dtguidance", "").strip():
        rows.append({"label": "공연 시간", "value": clean_text(perf["dtguidance"])[:70]})
    if place:
        rows.append({"label": "장소", "value": place})
    if price:
        rows.append({"label": "요금", "value": price})
    for key, label in (("prfruntime", "러닝타임"), ("prfage", "관람 연령")):
        v = clean_text(perf.get(key, ""))
        if v:
            rows.append({"label": label, "value": v[:40]})
    rows.append({"label": "분야", "value": realm})
    if venue.get("parkinglot") == "Y":
        rows.append({"label": "주차", "value": "가능"})
    tel = clean_text(venue.get("telno", ""))[:40]
    if tel:
        rows.append({"label": "문의", "value": tel})
    region_label = f"{prov} {city}".strip()
    cast = clean_text(perf.get("prfcast", ""))
    summary = f"{region_label} {place}에서 열리는 {realm} 공연. {_ymd_dot(sd)}부터 {_ymd_dot(ed)}까지" + (f" · {price}" if price else "") + "."
    doc: dict[str, Any] = {
        "id": f"spot_cu_{pid}",
        "kind": "culture",
        "culture_type": "공연",
        "realm": realm,
        "source": "kopis",
        "title": title,
        "province": prov,
        "region_label": region_label,
        "city": city,
        "addr": addr or place,
        "lat": lat,
        "lng": lng,
        "image_url": img,
        "images": [img],
        "tel": tel,
        "start_date": sd,
        "end_date": ed,
        "place": place,
        "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {place or title}'.strip())}",
        "overview": summary[:220],
        "pull_quote": f"{realm} · {place}" + (f" · {cast[:40]}" if cast else ""),
        "practical_header": "관람 전 확인 · 기간 · 시간 · 장소 · 요금 · 예매",
        "practical_info": rows[:9],
    }
    ticket = next((u for u in perf.get("relates", []) if u.startswith("http")), "") or venue.get("relateurl", "")
    if ticket.startswith("http"):
        doc["url"] = ticket
    if price:
        doc["price_text"] = price
    return doc


def collect_kopis(today: dt.date, culture_docs: list[dict[str, Any]], dry_run: bool) -> list[dict[str, Any]]:
    st = today.strftime("%Y%m%d")
    ed = (today + dt.timedelta(days=KOPIS_LONG_DAYS - 1)).strftime("%Y%m%d")
    rows: list[dict[str, str]] = []
    page = 1
    while True:
        root = _kopis_get("pblprfr", {"stdate": st, "eddate": ed, "cpage": page, "rows": 100})
        if root is None:
            print("[kopis] 목록 조회 실패 — KOPIS 보강 없이 진행")
            return []
        batch = [{c.tag: (c.text or "").strip() for c in db} for db in root.iter("db")]
        rows += batch
        if len(batch) < 100:
            break
        page += 1
    picked = kopis_selected(rows, today, culture_docs)
    print(f"[kopis] 목록 {len(rows)}건 → 지방·이번 주/4주 장기·중복 제외 {len(picked)}건")
    if dry_run:
        return []

    cache: dict[str, Any] = json.loads(KOPIS_CACHE_PATH.read_text(encoding="utf-8")) if KOPIS_CACHE_PATH.exists() else {}
    perfs: dict[str, Any] = cache.get("perf", {})
    venues: dict[str, Any] = cache.get("venue", {})
    today_ymd = today.strftime("%Y%m%d")
    perfs = {k: v for k, v in perfs.items() if str(v.get("prfpdto", "")).replace(".", "") >= today_ymd}
    new = 0
    for r in picked:
        pid = r["mt20id"]
        if pid not in perfs:
            root = _kopis_get(f"pblprfr/{pid}")
            time.sleep(KOPIS_GAP_SEC)
            db = root.find("db") if root is not None else None
            if db is None:
                continue
            perf = {c.tag: (c.text or "").strip() for c in db if len(c) == 0}
            perf["relates"] = [(x.findtext("relateurl") or "").strip() for x in db.iter("relate")]
            perfs[pid] = perf
            new += 1
        vid = perfs[pid].get("mt10id", "")
        if vid and vid not in venues:
            root = _kopis_get(f"prfplc/{vid}")
            time.sleep(KOPIS_GAP_SEC)
            db = root.find("db") if root is not None else None
            if db is not None:
                venues[vid] = {c.tag: (c.text or "").strip() for c in db if len(c) == 0}
    KOPIS_CACHE_PATH.write_text(json.dumps({"perf": perfs, "venue": venues}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    docs = []
    for r in picked:
        perf = perfs.get(r["mt20id"])
        venue = venues.get((perf or {}).get("mt10id", ""), {})
        doc = build_kopis_doc(perf, venue) if perf else None
        if doc:
            docs.append(doc)
    print(f"[kopis] 상세 새로 {new}건 · 공연장 {len(venues)}곳 · 넣은 공연 {len(docs)}건")
    return docs


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="공연·전시 갱신")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-firestore", action="store_true")
    args = ap.parse_args()
    _load_env()
    if not _key():
        print("[culture] DATA_GO_KR_SERVICE_KEY 없음 — 변경 없이 종료")
        return

    today = dt.date.today()
    listed = fetch_list(today)
    if listed is None:
        print("[culture] 목록 조회 실패 (키·활용신청·호출 한도 확인) — 변경 없이 종료")
        return
    today_ymd = today.strftime("%Y%m%d")
    cand = [it for it in listed if it.get("serviceName") in KEEP_TYPES and it.get("seq") and it.get("endDate", "") >= today_ymd]
    print(f"[culture] 목록 {len(listed)}건 → 공연·전시 {len(cand)}건 "
          f"(공연 {sum(1 for i in cand if i['serviceName'] == '공연')} · 전시 {sum(1 for i in cand if i['serviceName'] == '전시')})")

    cache: dict[str, Any] = json.loads(CACHE_PATH.read_text(encoding="utf-8")) if CACHE_PATH.exists() else {}
    # 끝난 항목은 캐시에서 지운다
    cache = {k: v for k, v in cache.items() if str(v.get("endDate", "99999999")) >= today_ymd}
    todo = [it for it in cand if it["seq"] not in cache]
    print(f"[culture] 상세 캐시 {len(cand) - len(todo)}건 · 새로 받을 곳 {len(todo)}건")
    if todo and not args.dry_run:
        fails = 0
        for n, it in enumerate(todo, 1):
            det = fetch_detail(it["seq"])
            time.sleep(DETAIL_GAP_SEC)
            if det is None:
                fails += 1
                if fails >= MAX_CONSECUTIVE_FAILS:
                    print(f"[culture] 상세 호출 {fails}번 연속 실패 — 여기서 멈춤 (남은 곳은 다음 실행에서)")
                    break
                continue
            fails = 0
            det["endDate"] = it.get("endDate", "")
            cache[it["seq"]] = det
            if n % 50 == 0 or n == len(todo):
                CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
                print(f"  상세 {n}/{len(todo)}", flush=True)
        CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    docs: list[dict[str, Any]] = []
    seen: set[str] = set()
    for it in cand:
        det = cache.get(it["seq"])
        if det is None or it["seq"] in seen:
            continue
        doc = build_culture_doc(it, det)
        if doc:
            seen.add(it["seq"])
            docs.append(doc)
    if _kopis_key():
        docs += collect_kopis(today, docs, args.dry_run)
    docs.sort(key=lambda d: (d["start_date"], d["title"]))
    by_prov: dict[str, int] = {}
    for d in docs:
        by_prov[d["province"]] = by_prov.get(d["province"], 0) + 1
    print(f"[culture] 결과 {len(docs)}건 (공연 {sum(1 for d in docs if d['culture_type'] == '공연')} · "
          f"전시 {sum(1 for d in docs if d['culture_type'] == '전시')}) · 시·도 {len(by_prov)}곳")
    if args.dry_run:
        return
    if not docs:
        print("[culture] 결과가 비어 있어 저장하지 않음")
        return

    if not args.no_firestore:
        upload_spots_to_firestore(docs)

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    hub["culture"] = docs
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[culture] 저장: {HUB_PATH.name} ({HUB_PATH.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
