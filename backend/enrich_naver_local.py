#!/usr/bin/env python3
"""
네이버 지역 검색(Naver API Hub `search/v1/local`)으로 숙소·볼거리·먹거리 상세 정보를 보강한다.

채우는 필드 (비어 있을 때만, 원본 데이터는 덮어쓰지 않음)
  - lat/lng         근사 좌표(approx_coord) 숙소만: 이름 완전 일치 + 도로명 일치 결과의 좌표로 교체
  - naver_link      공식 홈페이지 / 인스타그램 / 네이버 톡톡 등 (OTA·단축 링크 제외)
  - naver_category  네이버 업종 분류 (예: "한식>감자탕", "숙박>펜션")

전화번호는 이 API가 빈 값만 돌려주므로 다루지 않는다.

대상 파일
  - app/web/data/public_travel_hub.json   spots (food / attraction)
  - app/web/data/public_stays_index.json  items (숙소)

매칭 기준 (오매칭 방지 우선)
  1. 이름: 정규화한 이름이 서로 포함 관계
  2. 위치: 좌표가 정확한 항목은 거리 이내(먹거리 0.5km, 볼거리·숙소 1.5km),
          근사 좌표(approx_coord) 숙소는 이름 완전 일치 + 도로명(…로/…길) 일치
  3. 업종: 숙소는 '숙박' 계열만, 볼거리·먹거리는 서로 섞이거나 도로시설·부속시설인 결과 제외

API 응답은 output/curated_stays_cache/naver_local_cache.json 에 캐시한다.
build_travel_hub.py / curate_public_stays.py 로 JSON을 다시 만들면 이 필드가 사라지므로,
그 뒤에 이 스크립트를 다시 실행하면 된다(캐시 덕분에 API 호출 없이 즉시 복원).

사용법
  python backend/enrich_naver_local.py              # 전체 보강 후 저장
  python backend/enrich_naver_local.py --dry-run    # 저장하지 않고 매칭 결과만 확인
  python backend/enrich_naver_local.py --limit 50   # 섹션별 앞 N건만
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import os
import re
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import requests

import env  # noqa: F401  (.env 자동 로드)

ROOT = Path(__file__).resolve().parent.parent
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
STAYS_PATH = ROOT / "app" / "web" / "data" / "public_stays_index.json"
CACHE_PATH = ROOT / "output" / "curated_stays_cache" / "naver_local_cache.json"
REPORT_PATH = ROOT / "output" / "naver_local_matches.csv"
# 접속 점검에서 404·도메인 없음으로 확인된 링크 (재실행 시 다시 붙지 않게)
DEAD_LINKS_PATH = ROOT / "backend" / "naver_dead_links.json"
DEAD_LINKS: set[str] = set(json.loads(DEAD_LINKS_PATH.read_text(encoding="utf-8"))) if DEAD_LINKS_PATH.exists() else set()

API_URL = "https://naverapihub.apigw.ntruss.com/search/v1/local"

# 직거래 취지에 맞지 않거나 출처가 불분명한 링크
BLOCKED_LINK_HOSTS = (
    "airbnb.", "abnb.me", "yanolja.", "goodchoice.", "yeogi.", "booking.com", "agoda.",
    "expedia.", "hotels.com", "trip.com", "interpark.", "tripadvisor.", "share.google",
    "goo.gl", "bit.ly", "naver.me", "kko.to",
)

STAY_CATEGORY_WORDS = ("숙박", "펜션", "민박", "게스트하우스", "호텔", "모텔", "리조트", "콘도", "한옥", "캠핑", "글램핑", "호스텔")
FOOD_EXCLUDE_WORDS = ("숙박", "여행,명소", "도로시설", "교통", "주차", "부동산", "병원", "학교", "관리,안내", "공공기관")
# 볼거리는 이름이 겹치는 주변 시설(공원 화장실·체육관·카페 등)이 많아 허용 목록으로 판정한다.
ATTRACTION_ALLOW_WORDS = (
    "여행,명소", "자연명소", "지명", "문화,예술", "문화,유적", "박물관", "미술관", "전시", "기념관",
    "공원", "휴양림", "산림욕장", "해수욕장", "해변", "섬", "산", "계곡", "폭포", "사찰", "절", "성당", "교회",
    "테마파크", "유원지", "수목원", "식물원", "동물원", "아쿠아리움", "전망대", "체험",
)
ATTRACTION_EXCLUDE_WORDS = ("음식점", "카페", "디저트", "숙박", "부속시설", "도로시설", "방면정보", "주차", "화장실")
# 원래 이름에 없는데 검색 결과 이름에만 붙어 있으면 본체가 아닌 부속 시설로 본다.
FACILITY_SUFFIX_WORDS = ("화장실", "주차장", "매표소", "입구", "부속", "체육관", "관리사무소", "정류장", "방면", "관리동")

_cache_lock = threading.Lock()


# ---------------------------------------------------------------------------
# 유틸
# ---------------------------------------------------------------------------

def _strip_tags(s: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", s or "")).strip()


def _norm(s: str) -> str:
    return re.sub(r"[\s()\[\]·,.\-_|&'\"]", "", _strip_tags(s)).lower()


def _query_title(title: str) -> str:
    """검색용 이름: '큐브스테이 | CUBE STAY' → '큐브스테이', '용암사(장수)' → '용암사'."""
    t = title.split("|")[0]
    t = re.sub(r"\([^)]*\)", " ", t)
    return re.sub(r"\s+", " ", t).strip() or title.strip()


def _km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = math.radians
    dlat, dlng = r(lat2 - lat1), r(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(r(lat1)) * math.cos(r(lat2)) * math.sin(dlng / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(a))


def _road_token(addr: str) -> str:
    """주소에서 도로명 토큰(…로, …길)을 뽑는다. 예: '애월읍 애원로 587-1' → '애원로'."""
    for tok in (addr or "").split():
        if re.fullmatch(r"[가-힣0-9]+(로|길)", tok):
            return tok
    return ""


def clean_link(url: str) -> str:
    url = (url or "").strip()
    if not re.match(r"^https?://", url, re.I) or url in DEAD_LINKS:
        return ""
    host = (urlparse(url).hostname or "").lower()
    if not host or any(b in host for b in BLOCKED_LINK_HOSTS):
        return ""
    return url


def category_ok(kind: str, category: str) -> bool:
    if kind == "stay":
        return any(w in category for w in STAY_CATEGORY_WORDS)
    if kind == "food":
        return not any(w in category for w in FOOD_EXCLUDE_WORDS)
    if any(w in category for w in ATTRACTION_EXCLUDE_WORDS):
        return False
    return any(w in category for w in ATTRACTION_ALLOW_WORDS)


def is_facility_of(original: str, found: str) -> bool:
    """'동백공원' → '동백공원산정화장실' 처럼 결과가 본체가 아닌 부속 시설인지."""
    return any(w in found and w not in original for w in FACILITY_SUFFIX_WORDS)


# ---------------------------------------------------------------------------
# API + 캐시
# ---------------------------------------------------------------------------

def _headers() -> dict[str, str]:
    nid = os.environ.get("NAVER_CLIENT_ID", "")
    sec = os.environ.get("NAVER_CLIENT_SECRET", "")
    if not nid or not sec:
        raise SystemExit("NAVER_CLIENT_ID / NAVER_CLIENT_SECRET 이 .env 에 필요합니다.")
    return {"X-NCP-APIGW-API-KEY-ID": nid, "X-NCP-APIGW-API-KEY": sec}


def load_cache() -> dict[str, list[dict[str, Any]]]:
    if CACHE_PATH.exists():
        try:
            return json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {}


def save_cache(cache: dict[str, Any]) -> None:
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _cache_lock:
        CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")


class LocalSearch:
    def __init__(self, cache: dict[str, Any]):
        self.cache = cache
        self.headers = _headers()
        self.api_calls = 0
        self.errors = 0

    def search(self, query: str) -> list[dict[str, Any]]:
        with _cache_lock:
            if query in self.cache:
                return self.cache[query]
        params = {"query": query, "display": 5, "start": 1, "sort": "random", "format": "json"}
        for attempt in range(3):
            try:
                r = requests.get(API_URL, headers=self.headers, params=params, timeout=8)
                if r.status_code == 429:
                    time.sleep(1.5 * (attempt + 1))
                    continue
                if r.status_code != 200:
                    self.errors += 1
                    return []
                items = r.json().get("items") or []
                with _cache_lock:
                    self.cache[query] = items
                    self.api_calls += 1
                return items
            except requests.RequestException:
                time.sleep(1.0 * (attempt + 1))
        self.errors += 1
        return []


# ---------------------------------------------------------------------------
# 매칭
# ---------------------------------------------------------------------------

def find_match(
    searcher: LocalSearch,
    *,
    kind: str,
    title: str,
    region: str,
    lat: float,
    lng: float,
    trust_coord: bool,
    addr_hint: str,
) -> tuple[dict[str, Any], float] | None:
    qtitle = _query_title(title)
    items = searcher.search(f"{region} {qtitle}".strip())
    want = _norm(qtitle)
    if len(want) < 2:
        return None
    road = _road_token(addr_hint)
    max_km = 0.5 if kind == "food" else 1.5

    best: tuple[dict[str, Any], float] | None = None
    for it in items:
        got = _norm(it.get("title", ""))
        if not got or not (want in got or got in want):
            continue
        if not category_ok(kind, str(it.get("category") or "")):
            continue
        if is_facility_of(qtitle, _strip_tags(it.get("title", ""))):
            continue
        try:
            ilat, ilng = int(it["mapy"]) / 1e7, int(it["mapx"]) / 1e7
        except (KeyError, TypeError, ValueError):
            continue
        dist = _km(lat, lng, ilat, ilng)
        if trust_coord:
            if dist > max_km:
                continue
        else:
            addr = f"{it.get('roadAddress') or ''} {it.get('address') or ''}"
            if got != want or not road or road not in addr:
                continue
        if best is None or dist < best[1]:
            best = (it, dist)
    return best


def _record_targets(hub: dict, stays: dict, limit: int | None) -> list[tuple[str, dict[str, Any]]]:
    spots = [s for s in hub.get("spots", []) if s.get("kind") in ("food", "attraction")]
    stay_items = list(stays.get("items", []))
    if limit:
        foods = [s for s in spots if s["kind"] == "food"][:limit]
        attrs = [s for s in spots if s["kind"] == "attraction"][:limit]
        spots = foods + attrs
        stay_items = stay_items[:limit]
    return [(s["kind"], s) for s in spots] + [("stay", s) for s in stay_items]


def _match_args(kind: str, rec: dict[str, Any]) -> dict[str, Any]:
    if kind == "stay":
        pts = rec.get("summary_points") or []
        loc = next((p.replace("위치:", "").strip() for p in pts if isinstance(p, str) and p.startswith("위치")), "")
        return {
            "kind": "stay",
            "title": rec.get("title", ""),
            "region": rec.get("region_depth2") or rec.get("region_depth1") or rec.get("province", ""),
            "lat": float(rec.get("lat") or 0),
            "lng": float(rec.get("lng") or 0),
            "trust_coord": not rec.get("approx_coord"),
            "addr_hint": loc,
        }
    return {
        "kind": kind,
        "title": rec.get("title", ""),
        "region": rec.get("region_label") or rec.get("province", ""),
        "lat": float(rec.get("lat") or 0),
        "lng": float(rec.get("lng") or 0),
        "trust_coord": True,
        "addr_hint": rec.get("addr", ""),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="JSON을 저장하지 않고 매칭 결과만 출력")
    ap.add_argument("--limit", type=int, default=None, help="섹션별 앞 N건만 처리")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    stays = json.loads(STAYS_PATH.read_text(encoding="utf-8"))
    cache = load_cache()
    searcher = LocalSearch(cache)
    targets = _record_targets(hub, stays, args.limit)
    print(f"[naver-local] 대상 {len(targets)}건 (캐시 {len(cache)}건)", flush=True)

    results: list[tuple[str, dict[str, Any], tuple[dict[str, Any], float] | None]] = [None] * len(targets)  # type: ignore[list-item]
    done = [0]

    def work(idx: int) -> None:
        kind, rec = targets[idx]
        m = find_match(searcher, **_match_args(kind, rec))
        results[idx] = (kind, rec, m)
        with _cache_lock:
            done[0] += 1
            n = done[0]
        if n % 200 == 0:
            save_cache(cache)
            print(f"  … {n}/{len(targets)} (API 호출 {searcher.api_calls}회)", flush=True)

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
        list(ex.map(work, range(len(targets))))
    save_cache(cache)

    stats: dict[str, dict[str, int]] = {}
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with REPORT_PATH.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kind", "id", "title", "naver_title", "naver_category", "distance_km", "naver_link", "applied"])
        for kind, rec, m in results:
            st = stats.setdefault(kind, {"total": 0, "matched": 0, "link": 0, "category": 0})
            st["total"] += 1
            if not m:
                continue
            it, dist = m
            st["matched"] += 1
            link = clean_link(str(it.get("link") or ""))
            category = str(it.get("category") or "").strip()
            applied = []
            if link and not rec.get("naver_link") and not rec.get("url") and not rec.get("direct_booking_url"):
                applied.append("link")
                st["link"] += 1
                if not args.dry_run:
                    rec["naver_link"] = link
            if category and not rec.get("naver_category"):
                applied.append("category")
                st["category"] += 1
                if not args.dry_run:
                    rec["naver_category"] = category
            # 근사 좌표(시·군 중심 + 무작위 오프셋) 숙소는 이름 완전 일치 + 도로명 일치로 찾은 네이버 좌표로 교체
            if kind == "stay" and rec.get("approx_coord"):
                applied.append("coord")
                st["coord"] = st.get("coord", 0) + 1
                if not args.dry_run:
                    rec["lat"] = round(int(it["mapy"]) / 1e7, 5)
                    rec["lng"] = round(int(it["mapx"]) / 1e7, 5)
                    rec.pop("approx_coord", None)
            w.writerow([
                kind, rec.get("id") or rec.get("listing_id"), rec.get("title"), _strip_tags(it.get("title", "")),
                category, f"{dist:.2f}", link, "+".join(applied),
            ])

    labels = {"food": "먹거리", "attraction": "볼거리", "stay": "숙소"}
    for kind, st in stats.items():
        print(
            f"[{labels.get(kind, kind)}] 매칭 {st['matched']}/{st['total']} "
            f"· 링크 추가 {st['link']} · 업종 추가 {st['category']}"
            + (f" · 좌표 보정 {st['coord']}" if st.get("coord") else "")
        )
    print(f"API 호출 {searcher.api_calls}회 · 오류 {searcher.errors}회 · 검토용 CSV: {REPORT_PATH}")

    if args.dry_run:
        print("--dry-run: JSON 파일은 저장하지 않았습니다.")
        return
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    STAYS_PATH.write_text(json.dumps(stays, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("저장 완료:", HUB_PATH.name, STAYS_PATH.name)


if __name__ == "__main__":
    main()
