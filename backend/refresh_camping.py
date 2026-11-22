# -*- coding: utf-8 -*-
"""
전국 캠핑장·야영장 + 자연휴양림 갱신 → 허브 JSON 의 camping 섹션 (앱은 data/hub/camping.json 을 2단계에서 받음).

  - 캠핑장: 한국관광공사 고캠핑(GoCamping) basedList 전체(약 3,100곳). 목록 응답에 시설 정보가 모두 들어 있어
    상세 호출 없이 문서를 만든다. 운영 상태(manageSttus)가 '운영'이고 대표 사진·좌표가 있는 곳만 넣는다.
    이용 안내 칸은 고캠핑 값이 있는 것만 보여 주고, 값이 없으면 칸을 만들지 않는다(시설·요금을 추정하지 않음).
  - 자연휴양림·치유의숲: TourAPI searchKeyword2 ("휴양림", "치유의숲"). 상세(개요·이용 안내·사진)·네이버 방문기는
    spot_editorial_detail_cache.json 캐시로 새 곳만 받는다. 휴양림 안 캠핑장은 고캠핑 쪽에 있으므로 여기서 빼고,
    이미 볼거리(spots)에 있는 휴양림은 그대로 둔다(같은 곳이 두 번 나오지 않게).
  - 모두 kind="outdoor" 이고 sub 는 camping / forest.
  - Firebase 자격 증명이 있으면 Firestore spots 문서를 만들고(후기·찜·사이트맵·SEO 페이지),
    목록에서 사라졌거나 운영 상태가 바뀐 곳은 closed 로 바꾼다 (사라진 곳이 10%를 넘으면 API 이상으로 보고 닫지 않음).

  python backend/refresh_camping.py               # 전체
  python backend/refresh_camping.py --dry-run     # 호출·집계만, 저장 안 함
  python backend/refresh_camping.py --no-firestore
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

import requests

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    _https,
    _split_editorial_paragraphs,
    _strip_overview_html,
    _tour_get,
    enrich_spots_and_festivals_details,
    upload_spots_to_firestore,
)
from collect_half_price_spots import DETAIL_CACHE, HUB_PATH, _items, _load_env, _spot_doc  # noqa: E402
from curate_public_stays import classify_region_group, normalize_province_short, parse_korean_address  # noqa: E402

GOCAMPING_URL = "https://apis.data.go.kr/B551011/GoCamping/basedList"
MAX_REMOVE_RATIO = 0.10
FOREST_KEYWORDS = ("휴양림", "치유의숲")
FOREST_TITLE_RE = re.compile(r"(휴양림|치유의\s?숲)")
CAMP_TITLE_RE = re.compile(r"(캠핑|캠프|글램핑|카라반|야영|오토캠)")


# ── 캠핑장 (고캠핑) ──────────────────────────────────────────────

def fetch_gocamping_all() -> list[dict[str, Any]] | None:
    """고캠핑 전체 목록. 한 페이지라도 실패하면 None (일부만 받은 목록으로 닫지 않도록)."""
    key = os.environ.get("TOUR_API_KEY") or os.environ.get("DATA_GO_KR_SERVICE_KEY") or ""
    if not key:
        return None
    rows: list[dict[str, Any]] = []
    page = 1
    while True:
        try:
            r = requests.get(GOCAMPING_URL, params={
                "serviceKey": key, "MobileOS": "ETC", "MobileApp": "jikstay", "_type": "json",
                "numOfRows": 1000, "pageNo": page,
            }, timeout=60)
            if r.status_code != 200:
                print(f"  [고캠핑] HTTP {r.status_code} (p{page})")
                return None
            body = r.json().get("response", {}).get("body", {})
        except Exception as exc:  # noqa: BLE001
            print(f"  [고캠핑] 조회 실패 (p{page}): {str(exc)[:120]}")
            return None
        got = _items(body)
        rows += got
        total = int(body.get("totalCount") or 0)
        if not got or page * 1000 >= total:
            break
        page += 1
    return rows


def _num(v: Any) -> int:
    try:
        return int(str(v or "0").strip() or 0)
    except ValueError:
        return 0


def _url(raw: str) -> str:
    u = (raw or "").strip()
    if not u:
        return ""
    if not re.match(r"https?://", u):
        u = "https://" + u.lstrip("/")
    return _https(u) if re.match(r"https?://[^\s/]+\.[^\s]+", u) else ""


def build_camp_doc(it: dict[str, Any]) -> dict[str, Any] | None:
    cid = str(it.get("contentId") or "").strip()
    title = re.sub(r"\s+", " ", str(it.get("facltNm") or "")).strip()
    img = _https(str(it.get("firstImageUrl") or "").strip())
    if not cid or not title or not img:
        return None
    if str(it.get("manageSttus") or "").strip() != "운영":
        return None
    try:
        lat, lng = float(it.get("mapY") or 0), float(it.get("mapX") or 0)
    except ValueError:
        return None
    if not (32.0 <= lat <= 39.5 and 124.0 <= lng <= 132.0):
        return None
    addr1 = str(it.get("addr1") or "").strip()
    d1, d2 = parse_korean_address(addr1)
    prov = normalize_province_short(d1 or str(it.get("doNm") or ""), d2)
    if not prov:
        return None
    city = (d2.split(" ")[0] if d2 else str(it.get("sigunguNm") or "")) or prov

    induty = str(it.get("induty") or "").strip()
    rows: list[dict[str, str]] = []

    def add(label: str, value: Any, n: int = 70) -> None:
        v = re.sub(r"\s+", " ", str(value or "")).strip()
        if v:
            rows.append({"label": label, "value": v[:n]})

    add("야영장 종류", induty.replace(",", " · "))
    sites = [(lbl, _num(it.get(k))) for lbl, k in (("일반", "gnrlSiteCo"), ("자동차", "autoSiteCo"),
                                                  ("글램핑", "glampSiteCo"), ("카라반", "caravSiteCo"),
                                                  ("개인 카라반", "indvdlCaravSiteCo"))]
    add("사이트 수", " · ".join(f"{lbl} {n}" for lbl, n in sites if n > 0))
    add("입지", str(it.get("lctCl") or "").replace(",", " · "))
    add("운영 기간", " · ".join(x for x in (str(it.get("operPdCl") or "").replace(",", " · "),
                                            str(it.get("operDeCl") or "")) if x.strip()))
    add("부대시설", str(it.get("sbrsCl") or "").replace(",", " · "), 90)
    add("반려동물 동반", it.get("animalCmgCl"))
    add("예약", str(it.get("resveCl") or "").replace(",", " · "))
    add("문의 전화", it.get("tel"), 40)

    intro = _strip_overview_html(str(it.get("intro") or ""))
    line = re.sub(r"\s+", " ", str(it.get("lineIntro") or "")).strip()
    feature = _strip_overview_html(str(it.get("featureNm") or ""))
    overview = intro or feature or line
    paragraphs = _split_editorial_paragraphs(overview) if overview else []
    tip = re.sub(r"\s+", " ", str(it.get("tooltip") or "")).strip()
    if tip and len(paragraphs) < 3:
        paragraphs.append(tip[:300])

    doc: dict[str, Any] = {
        "id": f"spot_cp_{cid}",
        "kind": "outdoor",
        "sub": "camping",
        "camp_type": induty,
        "content_id": f"gocamping:{cid}",
        "title": title,
        "province": prov,
        "region_group": classify_region_group(d1) or "전체",
        "region_label": f"{prov} {d2}".strip(),
        "city": city,
        "addr": addr1,
        "lat": round(lat, 6),
        "lng": round(lng, 6),
        "image_url": img,
        "tel": str(it.get("tel") or "").strip()[:40],
        "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
        "practical_header": "캠핑 전 확인 · 종류 · 운영 기간 · 시설 · 반려동물 · 예약",
        "practical_info": rows[:8],
        "source": "한국관광공사 고캠핑",
    }
    if str(it.get("animalCmgCl") or "").startswith("가능"):
        doc["pet"] = True
    if overview:
        doc["overview"] = overview[:220]
    if paragraphs:
        doc["paragraphs"] = paragraphs[:3]
    if line:
        doc["pull_quote"] = line[:130]
    link = _url(str(it.get("resveUrl") or "")) or _url(str(it.get("homepage") or ""))
    if link:
        doc["url"] = link
    return doc


# ── 자연휴양림·치유의숲 (TourAPI) ───────────────────────────────────

def fetch_forests(existing_cids: set[str]) -> list[dict[str, Any]] | None:
    docs: dict[str, dict[str, Any]] = {}
    for kw in FOREST_KEYWORDS:
        body = _tour_get("searchKeyword2", {"keyword": kw, "numOfRows": 1000, "pageNo": 1, "arrange": "O"}, timeout=40)
        if body is None:
            print(f"  [휴양림] '{kw}' 검색 실패")
            return None
        for it in _items(body):
            ct = str(it.get("contenttypeid") or "")
            title = str(it.get("title") or "")
            if ct not in ("12", "28") or not FOREST_TITLE_RE.search(title) or CAMP_TITLE_RE.search(title):
                continue
            doc = _spot_doc(it, "outdoor")
            if not doc or doc["content_id"] in existing_cids or doc["content_id"] in docs:
                continue
            doc["id"] = f"spot_fr_{doc['content_id']}"
            doc["sub"] = "forest"
            doc["content_type"] = ct  # 상세 보강(detailIntro2)에 쓸 관광공사 분류
            docs[doc["content_id"]] = doc
    return list(docs.values())


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="전국 캠핑장·자연휴양림 갱신")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-firestore", action="store_true")
    args = ap.parse_args()
    _load_env()

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    prev = hub.get("camping") or []

    raw = fetch_gocamping_all()
    if raw is None:
        print("[camping] 고캠핑 목록 조회 실패 (키·활용신청 또는 호출 한도) — 변경 없이 종료")
        return
    camps: list[dict[str, Any]] = []
    seen: set[str] = set()
    for it in raw:
        doc = build_camp_doc(it)
        if doc and doc["id"] not in seen:
            seen.add(doc["id"])
            camps.append(doc)
    print(f"[camping] 고캠핑 {len(raw)}곳 → 운영 중·사진·좌표 있는 곳 {len(camps)}곳")

    spot_cids = {str(x.get("content_id") or "") for x in hub.get("spots") or []}
    forests = fetch_forests(spot_cids)
    if forests is None:
        forests = [x for x in prev if x.get("sub") == "forest"]
        print(f"[camping] 휴양림 검색 실패 — 지난번 {len(forests)}곳 유지")
    else:
        print(f"[camping] 자연휴양림·치유의숲 {len(forests)}곳 (이미 볼거리에 있는 곳 제외)")
    if args.dry_run:
        from collections import Counter
        print("  시·도별 캠핑장:", dict(Counter(c["province"] for c in camps).most_common()))
        for c in camps[:3]:
            print("  예시:", json.dumps({k: c[k] for k in ("title", "region_label", "camp_type", "practical_info")}, ensure_ascii=False)[:400])
        print("  휴양림 예시:", [f["title"] for f in forests[:10]])
        return

    # 지난번에 상세를 받은 휴양림은 그 내용을 그대로 쓰고(CI 에는 상세 캐시가 없다) 새 곳만 받는다
    prev_by_id = {str(x.get("id")): x for x in prev if x.get("sub") == "forest"}
    for f in forests:
        old = prev_by_id.get(f["id"])
        if old:
            for k in ("overview", "paragraphs", "pull_quote", "practical_header", "practical_info", "images", "naver_reviews", "url"):
                if old.get(k):
                    f[k] = old[k]
    new_forests = [f for f in forests if f["id"] not in prev_by_id]
    if new_forests:
        enrich_spots_and_festivals_details(new_forests, cache_path=str(DETAIL_CACHE))

    docs = sorted([*camps, *forests], key=lambda d: (d["province"], d.get("sub", ""), d["title"]))
    today = dt.date.today().strftime("%Y%m%d")
    prev_ids = {str(x.get("id")) for x in prev if x.get("id")}
    for d in docs:
        if d["id"] not in prev_ids:
            d.setdefault("added_at", today)
        else:
            old = next((x for x in prev if x.get("id") == d["id"]), {})
            if old.get("added_at"):
                d["added_at"] = old["added_at"]

    now_ids = {d["id"] for d in docs}
    closed = [x for x in prev if x.get("id") not in now_ids]
    if prev_ids and len(closed) > len(prev_ids) * MAX_REMOVE_RATIO:
        print(f"[camping] 사라진 곳 {len(closed)}곳이 10%를 넘어 API 이상으로 보고 닫지 않음 — 이번에는 지난 목록 유지")
        docs = [*docs, *closed]
        closed = []

    # 1단계(레포츠 수집)에서 spots 에 들어간 캠핑장은 이제 이 섹션이 맡는다
    moved = [s for s in hub.get("spots") or [] if s.get("kind") == "outdoor" and s.get("sub") == "camping"]

    if not args.no_firestore:
        # Firestore 를 먼저 쓴다: 실패하면 허브도 바꾸지 않는다
        upload_spots_to_firestore(docs)
        to_close = [*closed, *moved]
        if to_close:
            from firebase_admin import firestore

            from firebase_client import db

            col = db().collection("spots")
            for m in to_close:
                ref = col.document(str(m["id"]))
                if ref.get().exists:
                    ref.update({"status": "closed",
                                "closed_reason": "고캠핑·관광공사 목록에서 삭제되었거나 운영 상태 변경" if m in closed else "캠핑장 목록(고캠핑)으로 이동",
                                "closed_at": firestore.SERVER_TIMESTAMP})
            print(f"[camping] closed {len(to_close)}곳 (사라짐 {len(closed)} · 이동 {len(moved)})")

    if moved:
        moved_ids = {s["id"] for s in moved}
        hub["spots"] = [s for s in hub.get("spots") or [] if s.get("id") not in moved_ids]
        print(f"[camping] spots 에 있던 캠핑장 {len(moved)}곳 제거 (고캠핑 목록으로 대체)")
    hub["camping"] = docs
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[camping] 저장: 캠핑장 {len(camps)} · 휴양림 {len(forests)} → {HUB_PATH.name} ({HUB_PATH.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
