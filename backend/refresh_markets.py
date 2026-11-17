# -*- coding: utf-8 -*-
"""
전국 전통시장·5일장 갱신 (한국관광공사 TourAPI 쇼핑 분류).

  - SH060100 5일장, SH060200 상설·전통시장 목록을 받아 시장마다 상세(개요·장날·판매 품목·주차·사진)와
    네이버 방문기를 붙여 허브 JSON 의 markets 섹션에 저장한다 (상세 페이지·검색·후기·찜용).
  - 장날이 확인된 곳은 traditional_markets(달력·장날 페이지용 경량 목록)에도 넣는다.
    손으로 정리한 대표 5일장(build_travel_hub.TRADITIONAL_5DAY_MARKETS)은 같은 시장이 있으면 특산물 설명만 살려 합친다.
  - 상세 응답은 backend/market_detail_cache.json 에 저장해 다음부터는 새 시장만 호출한다.
    TourAPI 호출이 연달아 실패하면(일일 한도 등) 그 자리에서 멈추고, 상세를 받은 시장까지만 반영한다.
  - Firebase 자격 증명이 있으면 Firestore spots 문서를 만들고(후기·찜·사이트맵), 목록에서 사라진 시장은 closed 로 바꾼다.

  python backend/refresh_markets.py               # 전체
  python backend/refresh_markets.py --dry-run     # 호출·집계만, 저장 안 함
  python backend/refresh_markets.py --no-firestore
  python backend/refresh_markets.py --max-new 300 # 이번 실행에서 새로 상세를 받을 최대 시장 수
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    TRADITIONAL_5DAY_MARKETS,
    _fetch_naver_place_blog_snippets,
    _https,
    _parse_wgs84,
    _split_editorial_paragraphs,
    _strip_overview_html,
    _tour_get,
    classify_region_group,
    normalize_place_name,
    normalize_province_short,
    parse_korean_address,
    upload_spots_to_firestore,
)
from collect_half_price_spots import HUB_PATH, _items, _load_env  # noqa: E402

CACHE_PATH = ROOT / "backend" / "market_detail_cache.json"
CATEGORIES = {"SH060100": "5일장", "SH060200": "상설시장"}
MAX_CONSECUTIVE_FAILS = 5
MAX_REMOVE_RATIO = 0.10

# 이름 끝의 장날 표기 "(3, 8일)" "(1, 6일" 은 장날 칸에 따로 보여 주므로 뗀다
TITLE_DAYS_RE = re.compile(r"\s*\(\s*\d{1,2}\s*일?\s*[,·/]\s*\d{1,2}\s*일?\s*\)?\s*$")


# ---------------------------------------------------------------------------
# 장날 해석
# ---------------------------------------------------------------------------

def parse_market_days(*texts: str) -> list[int]:
    """'매월 2, 7, 12 …일' '4일 / 9일' '(3, 8일)' → 장날 끝자리 [2, 7] (10·20·30일은 0).

    5일장은 5일 간격이라 날짜를 5로 나눈 나머지가 같다. 나머지별로 [r, r+5] 끝자리를 만든다.
    연도(1956년)·시간(06:00)·월 같은 숫자는 빼고, 1~31 사이 '일' 날짜만 본다.
    """
    residues: list[int] = []
    for text in texts:
        s = str(text or "")
        if not s:
            continue
        s = re.sub(r"\d{3,}", " ", s)            # 연도·전화번호
        s = re.sub(r"\d{1,2}\s*:\s*\d{2}", " ", s)  # 시각
        s = re.sub(r"\d{1,2}\s*(월|시|개|km|분|층|호|번)", " ", s)
        nums = [int(n) for n in re.findall(r"\d{1,2}", s)]
        nums = [n for n in nums if 1 <= n <= 31]
        if len(nums) < 2:
            continue  # 숫자 하나로는 5일장인지 알 수 없다
        for n in nums:
            r = n % 5
            if r not in residues:
                residues.append(r)
        if residues:
            break  # 앞 텍스트(상세 장날)에서 찾으면 이름은 보지 않는다
    if not residues or len(residues) > 2:
        return []  # 세 가지 이상이면 5일장 표기로 보기 어렵다
    days: list[int] = []
    for r in sorted(residues, key=lambda x: x if x else 5):
        a = r if r else 5
        days += [a % 10, (a + 5) % 10]
    return days


def market_days_label(days: list[int]) -> str:
    """[2, 7] → '매월 2·7·12·17·22·27일' (31일 제외)"""
    res = {d % 5 for d in days}
    dates = [n for n in range(1, 31) if n % 5 in res]
    return "매월 " + "·".join(str(n) for n in dates) + "일" if dates else ""


# ---------------------------------------------------------------------------
# TourAPI
# ---------------------------------------------------------------------------

def fetch_market_list() -> list[tuple[str, dict[str, Any]]] | None:
    """[(분류코드, 목록 항목)]. 한 분류라도 실패하면 None (일부만 받은 목록으로 지우지 않도록)."""
    out: list[tuple[str, dict[str, Any]]] = []
    for code in CATEGORIES:
        page = 1
        while True:
            body = _tour_get(
                "areaBasedList2",
                {"contentTypeId": 38, "lclsSystm1": "SH", "lclsSystm2": code[:4], "lclsSystm3": code,
                 "numOfRows": 1000, "pageNo": page, "arrange": "A"},
                timeout=40,
            )
            if body is None:
                return None
            items = _items(body)
            out += [(code, it) for it in items]
            if len(items) < 1000:
                break
            page += 1
    return out


def _first_item(body: Any) -> dict[str, Any]:
    items = _items(body)
    return items[0] if items and isinstance(items[0], dict) else {}


def fetch_detail(cid: str) -> dict[str, Any] | None:
    """개요·홈페이지·소개(장날 등)·사진. 공통 정보 호출이 실패하면 None."""
    com_body = _tour_get("detailCommon2", {"contentId": cid}, timeout=12)
    if com_body is None:
        return None
    com = _first_item(com_body)
    intro_body = _tour_get("detailIntro2", {"contentId": cid, "contentTypeId": 38}, timeout=12)
    if intro_body is None:
        return None
    intro = {k: _strip_overview_html(str(v)) for k, v in _first_item(intro_body).items() if v}
    images: list[str] = []
    img_body = _tour_get("detailImage2", {"contentId": cid, "imageYN": "Y", "numOfRows": 4}, timeout=12)
    for im in _items(img_body):
        u = _https(str(im.get("originimgurl") or im.get("smallimageurl") or ""))
        if u and u not in images:
            images.append(u)
    hp = re.search(r'https?://[^\s"<>\']+', str(com.get("homepage") or ""))
    return {
        "fetched": dt.date.today().strftime("%Y%m%d"),
        "overview": _strip_overview_html(str(com.get("overview") or ""))[:700],
        "homepage": hp.group(0) if hp else "",
        "intro": intro,
        "images": images[:4],
    }


# ---------------------------------------------------------------------------
# 문서 만들기
# ---------------------------------------------------------------------------

def _clean_title(title: str) -> str:
    t = normalize_place_name(title)
    t2 = TITLE_DAYS_RE.sub("", t).strip()
    return t2 or t


def build_market_doc(code: str, it: dict[str, Any], detail: dict[str, Any]) -> dict[str, Any] | None:
    cid = str(it.get("contentid") or "").strip()
    raw_title = str(it.get("title") or "")
    title = _clean_title(raw_title)
    img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
    if not cid or not title or not img:
        return None
    addr1 = str(it.get("addr1") or "").strip()
    d1, d2 = parse_korean_address(addr1)
    prov = normalize_province_short(d1, d2)
    if not prov:
        return None
    lat, lng = _parse_wgs84(it, prov)
    intro: dict[str, str] = detail.get("intro") or {}
    fairday = intro.get("fairday", "")
    days = parse_market_days(fairday, raw_title)
    kind_label = CATEGORIES[code]
    if code == "SH060200" and days:
        kind_label = "상설·5일장"
    saleitem = intro.get("saleitem", "")[:120]

    rows: list[dict[str, str]] = []
    if days:
        rows.append({"label": "장날", "value": market_days_label(days)})
    elif fairday:
        rows.append({"label": "장날", "value": fairday[:60]})
    if saleitem:
        rows.append({"label": "판매 품목", "value": saleitem})
    for key, label in (("opentime", "영업 시간"), ("restdateshopping", "쉬는 날"), ("parkingshopping", "주차"),
                       ("chkcreditcardshopping", "카드 결제"), ("restroom", "화장실"), ("opendateshopping", "개설"),
                       ("infocentershopping", "문의")):
        v = intro.get(key, "").strip()
        if v:
            rows.append({"label": label, "value": v[:70]})
    if not rows and addr1:
        rows.append({"label": "위치 주소", "value": addr1})

    overview = str(detail.get("overview") or "").strip()
    paragraphs = _split_editorial_paragraphs(overview) if overview else []
    gallery = [img] + [u for u in (detail.get("images") or []) if u and u != img]
    city = (d2.split(" ")[0] if d2 else "") or prov
    doc: dict[str, Any] = {
        "id": f"spot_mk_{cid}",
        "kind": "market",
        "market_type": kind_label,
        "content_id": cid,
        "title": title,
        "province": prov,
        "region_group": classify_region_group(d1) or "전체",
        "region_label": f"{prov} {d2}".strip(),
        "city": city,
        "addr": addr1,
        "lat": lat,
        "lng": lng,
        "image_url": img,
        "images": gallery[:4],
        "tel": str(it.get("tel") or intro.get("infocentershopping") or "").strip()[:40],
        "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
        "practical_header": "장보기 전 확인 · 장날 · 판매 품목 · 주차 · 편의",
        "practical_info": rows[:8],
    }
    if days:
        doc["days"] = days
    if saleitem:
        doc["specialty"] = saleitem
    if overview:
        doc["overview"] = overview[:220]
    if paragraphs:
        doc["paragraphs"] = paragraphs[:3]
    pull = f"{kind_label} · {market_days_label(days)}" if days else ""
    if saleitem:
        pull = f"{pull} · {saleitem}" if pull else f"{kind_label} · {saleitem}"
    if pull:
        doc["pull_quote"] = pull[:130]
    if detail.get("homepage"):
        doc["url"] = detail["homepage"]
    if detail.get("naver_reviews"):
        doc["naver_reviews"] = detail["naver_reviews"]
    return doc


def _km(a_lat: float, a_lng: float, b_lat: float, b_lng: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = p2 - p1, math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def build_traditional_list(docs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """달력·장날 페이지용 경량 목록: 장날이 있는 시장 + 짝이 없는 수작업 대표 5일장."""
    out: list[dict[str, Any]] = []
    used_manual: set[str] = set()
    for d in docs:
        if not d.get("days"):
            continue
        specialty = str(d.get("specialty") or "")
        for m in TRADITIONAL_5DAY_MARKETS:
            if m["id"] in used_manual or m.get("province") != d["province"]:
                continue
            dist = _km(float(m["lat"]), float(m["lng"]), float(d["lat"]), float(d["lng"]))
            # 같은 동네에 시장이 여럿일 수 있어(순천 웃장·아랫장) 이름 앞부분까지 같아야 같은 시장으로 본다
            a = re.sub(r"\s|5일장|오일장|전통시장|시장|장터", "", str(m.get("title") or ""))
            b = re.sub(r"\s|5일장|오일장|전통시장|시장|장터", "", str(d.get("title") or ""))
            same_name = len(a) >= 2 and len(b) >= 2 and (a in b or b in a or a[:3] == b[:3])
            if dist <= 3.0 and same_name:
                used_manual.add(m["id"])
                specialty = str(m.get("specialty") or "") or specialty  # 손으로 정리한 먹거리 설명이 더 읽기 좋다
                break
        out.append({
            "id": d["id"], "province": d["province"], "city": d.get("city", ""), "title": d["title"],
            "days": d["days"], "lat": d["lat"], "lng": d["lng"], "specialty": specialty[:80],
        })
    out += [m for m in TRADITIONAL_5DAY_MARKETS if m["id"] not in used_manual]
    return out


# ---------------------------------------------------------------------------

def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="전국 전통시장·5일장 갱신")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-firestore", action="store_true")
    ap.add_argument("--max-new", type=int, default=400, help="이번 실행에서 새로 상세를 받을 최대 시장 수")
    args = ap.parse_args()
    _load_env()

    listed = fetch_market_list()
    if listed is None:
        print("[markets] TourAPI 목록 조회 실패 (키 오류 또는 호출 한도) — 변경 없이 종료")
        return
    print(f"[markets] 목록: 5일장 {sum(1 for c, _ in listed if c == 'SH060100')} · 상설시장 {sum(1 for c, _ in listed if c == 'SH060200')}")

    cache: dict[str, Any] = json.loads(CACHE_PATH.read_text(encoding="utf-8")) if CACHE_PATH.exists() else {}
    with_img = [(c, it) for c, it in listed if str(it.get("contentid") or "") and (it.get("firstimage") or it.get("firstimage2"))]
    todo = [it for _, it in with_img if str(it["contentid"]) not in cache][: max(0, args.max_new)]
    print(f"[markets] 사진 있는 시장 {len(with_img)}곳 · 상세 캐시 {sum(1 for _, it in with_img if str(it['contentid']) in cache)}곳 · 이번에 받을 곳 {len(todo)}곳")

    if todo and not args.dry_run:
        fails = 0
        stop = False
        for i in range(0, len(todo), 10):
            if stop:
                break
            chunk = todo[i : i + 10]
            with ThreadPoolExecutor(max_workers=5) as pool:
                results = list(pool.map(lambda it: fetch_detail(str(it["contentid"])), chunk))
            for it, det in zip(chunk, results):
                if det is None:
                    fails += 1
                    if fails >= MAX_CONSECUTIVE_FAILS:
                        print(f"[markets] TourAPI 상세 호출이 {fails}번 연속 실패 — 여기서 멈춤 (남은 곳은 다음 실행에서)")
                        stop = True
                        break
                    continue
                fails = 0
                prov_guess = normalize_province_short(*parse_korean_address(str(it.get("addr1") or "")))
                det["naver_reviews"] = _fetch_naver_place_blog_snippets(
                    f"{prov_guess} {_clean_title(str(it.get('title') or ''))} 시장 후기".strip(),
                    max_items=2, place_title=_clean_title(str(it.get("title") or "")),
                    region_label=prov_guess, province=prov_guess,
                )
                cache[str(it["contentid"])] = det
            CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
            print(f"  상세 {min(i + 10, len(todo))}/{len(todo)}")

    docs: list[dict[str, Any]] = []
    seen: set[str] = set()
    for code, it in with_img:
        cid = str(it["contentid"])
        if cid not in cache or cid in seen:
            continue
        doc = build_market_doc(code, it, cache[cid])
        if doc:
            seen.add(cid)
            docs.append(doc)
    docs.sort(key=lambda d: (d["province"], d["title"]))
    trad = build_traditional_list(docs)
    print(f"[markets] 결과: 시장 {len(docs)}곳 (장날 확인 {sum(1 for d in docs if d.get('days'))}곳) · 장날 목록 {len(trad)}곳")
    if args.dry_run:
        return

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    prev_ids = {str(m.get("id")) for m in hub.get("markets") or [] if m.get("id")}
    listed_ids = {f"spot_mk_{it.get('contentid')}" for _, it in listed}
    closed = [m for m in hub.get("markets") or [] if m.get("id") not in listed_ids]
    if prev_ids and len(closed) > len(prev_ids) * MAX_REMOVE_RATIO:
        print(f"[markets] 사라진 시장 {len(closed)}곳이 10%를 넘어 API 이상으로 보고 닫지 않음")
        closed = []

    use_fs = not args.no_firestore
    if use_fs:
        upload_spots_to_firestore(docs)
        if closed:
            from firebase_admin import firestore

            from firebase_client import db

            col = db().collection("spots")
            for m in closed:
                ref = col.document(str(m["id"]))
                if ref.get().exists:
                    ref.update({"status": "closed", "closed_reason": "한국관광공사 TourAPI 목록에서 삭제됨",
                                "closed_at": firestore.SERVER_TIMESTAMP})
            print(f"[markets] 목록에서 사라진 시장 {len(closed)}곳 closed")

    hub["markets"] = docs
    hub["traditional_markets"] = trad
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[markets] 저장: {HUB_PATH.name} ({HUB_PATH.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
