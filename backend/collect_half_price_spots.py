# -*- coding: utf-8 -*-
"""
반값여행(지역사랑 휴가지원) 대상 시·군 단위 볼거리·먹거리·축제 보강 수집.

전국 수집(build_travel_hub.fetch_17_provinces_spots)은 시·도마다 22곳 안팎이라 강진·해남 같은
군 단위로는 볼거리·먹거리가 0~1곳뿐이다. 배너로 홍보하는 대상 지역은 시·군마다 TourAPI
areaBasedList2 / searchFestival2 를 시·군 코드(lDongSignguCd)로 따로 조회해 허브 JSON 의
spots · festivals 에 더한다. 기존 항목(content_id 기준)은 건드리지 않는다.

  python backend/collect_half_price_spots.py            # 수집 + 상세 보강 + 허브 JSON 저장
  python backend/collect_half_price_spots.py --upload   # 위 + Firestore spots 문서 생성(후기·클릭 집계용)
  python backend/collect_half_price_spots.py --dry-run  # 시·군 코드 확인과 수집 건수만 출력 (저장 안 함)

다시 실행하면 이미 들어간 곳은 건너뛰고 모자란 시·군만 채운다(캐시: output/curated_stays_cache/).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    _https,
    _parse_wgs84,
    _tour_get,
    classify_region_group,
    enrich_spots_and_festivals_details,
    normalize_place_name,
    normalize_province_short,
    parse_korean_address,
    upload_spots_to_firestore,
)

HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
DETAIL_CACHE = ROOT / "output" / "curated_stays_cache" / "spot_editorial_detail_cache.json"

# 시·군당 목표 건수
PER_CITY = {"attraction": 6, "food": 4}
PER_CITY_FESTIVALS = 3

# 반값여행 권역 → 후보 시·도 법정동 코드 (같은 이름의 시·군이 여러 시·도에 있을 때 권역으로 가른다: 고성=경남)
REGION_GROUP_LDONG = {
    "강원": ["51"],
    "전라/충청": ["12", "52", "43", "44"],
    "부산/경상": ["48", "47", "26", "27", "31"],
    "제주": ["50"],
    "서울/경기": ["11", "41", "28"],
}


def _load_env() -> None:
    env_path = ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _items(body: Any) -> list[dict[str, Any]]:
    if not body:
        return []
    items = (body.get("items") or {}) if isinstance(body.get("items"), dict) else {}
    raw = items.get("item") or []
    return [raw] if isinstance(raw, dict) else list(raw)


def _sigungu_table(regn_cd: str, memo: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    if regn_cd not in memo:
        memo[regn_cd] = _items(_tour_get("ldongCode2", {"lDongRegnCd": regn_cd, "numOfRows": 100, "pageNo": 1}))
    return memo[regn_cd]


def resolve_city_codes(region_group: str, city: str, memo: dict[str, list[dict[str, Any]]]) -> tuple[str, str] | None:
    """('12', '780') 처럼 (시·도 코드, 시·군 코드). 못 찾으면 None."""
    for regn in REGION_GROUP_LDONG.get(region_group, []):
        for row in _sigungu_table(regn, memo):
            name = str(row.get("name") or "")
            if name in (f"{city}군", f"{city}시", city):
                return regn, str(row.get("code") or "")
    return None


def _spot_doc(it: dict[str, Any], kind: str, city: str = "") -> dict[str, Any] | None:
    cid = str(it.get("contentid") or "").strip()
    img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
    title = normalize_place_name(str(it.get("title") or ""))
    if not cid or not img or not title:
        return None
    addr1 = str(it.get("addr1") or "").strip()
    d1, d2 = parse_korean_address(addr1)
    prov = normalize_province_short(d1, d2)
    lat, lng = _parse_wgs84(it, prov)
    prefix = {"attraction": "at", "food": "fo", "event": "ev"}[kind]
    doc: dict[str, Any] = {
        "id": f"spot_{prefix}_{cid}",
        "kind": kind,
        "content_id": cid,
        "title": title,
        "province": prov,
        "region_group": classify_region_group(d1) or "전체",
        "region_label": f"{prov} {d2}".strip(),
        "addr": addr1,
        "lat": lat,
        "lng": lng,
        "image_url": img,
        "tel": str(it.get("tel") or "").strip(),
        "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
    }
    if city:
        doc["half_price_city"] = city
    if kind == "event":
        doc["start_date"] = str(it.get("eventstartdate") or "").strip()
        doc["end_date"] = str(it.get("eventenddate") or "").strip()
        doc["search_city"] = city or (d2.split(" ")[0] if d2 else prov)
    return doc


def collect(hub: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    existing_cids = {
        str(x.get("content_id") or "")
        for x in [*(hub.get("spots") or []), *(hub.get("festivals") or [])]
        if x.get("content_id")
    }
    # 이미 시·군 보강으로 들어간 건수 (다시 실행 시 모자란 만큼만)
    have: dict[tuple[str, str], int] = {}
    for x in [*(hub.get("spots") or []), *(hub.get("festivals") or [])]:
        c = x.get("half_price_city")
        if c:
            have[(c, x.get("kind"))] = have.get((c, x.get("kind")), 0) + 1

    today = dt.date.today()
    today_ymd = today.strftime("%Y%m%d")
    end_ymd = (today + dt.timedelta(days=120)).strftime("%Y%m%d")
    start_from = (today - dt.timedelta(days=60)).strftime("%Y%m%d")
    memo: dict[str, list[dict[str, Any]]] = {}
    new_spots: list[dict[str, Any]] = []
    new_events: list[dict[str, Any]] = []
    unresolved: list[str] = []

    for grp in hub.get("half_price_regions") or []:
        rg = str(grp.get("region_group") or "")
        for city in grp.get("cities") or []:
            codes = resolve_city_codes(rg, city, memo)
            if not codes:
                unresolved.append(city)
                continue
            regn, sig = codes
            q = {"lDongRegnCd": regn, "lDongSignguCd": sig}
            counts: dict[str, int] = {}
            for ctype, kind in (("12", "attraction"), ("39", "food")):
                need = PER_CITY[kind] - have.get((city, kind), 0)
                if need <= 0:
                    continue
                body = _tour_get(
                    "areaBasedList2",
                    {**q, "contentTypeId": ctype, "numOfRows": 40, "pageNo": 1, "arrange": "P"},
                    timeout=14,
                )
                added = 0
                for it in _items(body):
                    doc = _spot_doc(it, kind, city)
                    if not doc or doc["content_id"] in existing_cids:
                        continue
                    existing_cids.add(doc["content_id"])
                    new_spots.append(doc)
                    added += 1
                    if added >= need:
                        break
                counts[kind] = added

            need_ev = PER_CITY_FESTIVALS - have.get((city, "event"), 0)
            if need_ev > 0:
                body = _tour_get(
                    "searchFestival2",
                    # 이미 시작해 진행 중인 축제도 잡도록 60일 전부터 조회하고, 끝났거나 120일 뒤 시작은 걸러 낸다
                    {**q, "eventStartDate": start_from, "numOfRows": 30, "pageNo": 1, "arrange": "A"},
                    timeout=12,
                )
                added = 0
                for it in _items(body):
                    doc = _spot_doc(it, "event", city)
                    if not doc or doc["content_id"] in existing_cids:
                        continue
                    if (doc["end_date"] and doc["end_date"] < today_ymd) or (doc["start_date"] and doc["start_date"] > end_ymd):
                        continue
                    existing_cids.add(doc["content_id"])
                    new_events.append(doc)
                    added += 1
                    if added >= need_ev:
                        break
                counts["event"] = added
            print(f"  {city} ({regn}-{sig}): 볼거리 +{counts.get('attraction', 0)} · 먹거리 +{counts.get('food', 0)} · 축제 +{counts.get('event', 0)}")
    return new_spots, new_events, unresolved


def main() -> None:
    ap = argparse.ArgumentParser(description="반값여행 대상 시·군 단위 볼거리·먹거리·축제 보강")
    ap.add_argument("--dry-run", action="store_true", help="수집 건수만 출력하고 저장하지 않음")
    ap.add_argument("--upload", action="store_true", help="새 항목을 Firestore spots 에 생성(후기·클릭 집계용)")
    args = ap.parse_args()

    _load_env()
    if not (os.environ.get("TOUR_API_KEY") or os.environ.get("DATA_GO_KR_SERVICE_KEY")):
        sys.exit("TOUR_API_KEY 가 없습니다 (.env)")
    if _tour_get("ldongCode2", {"numOfRows": 1, "pageNo": 1}) is None:
        sys.exit("TourAPI 응답 없음 (키 오류 또는 일일 호출 한도 초과) — 저장하지 않고 종료")

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    print("[반값여행 시·군 보강] 수집 중...")
    new_spots, new_events, unresolved = collect(hub)
    print(f"  → 새 볼거리·먹거리 {len(new_spots)}곳, 새 축제 {len(new_events)}건" + (f", 시·군 코드 못 찾음: {unresolved}" if unresolved else ""))
    if args.dry_run or not (new_spots or new_events):
        return

    print("[반값여행 시·군 보강] 상세(개요·이용안내·사진) + 네이버 방문기 보강 중...")
    enrich_spots_and_festivals_details([*new_spots, *new_events], cache_path=str(DETAIL_CACHE))

    hub["spots"] = [*(hub.get("spots") or []), *new_spots]
    hub["festivals"] = [*(hub.get("festivals") or []), *new_events]
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[저장] {HUB_PATH} ({HUB_PATH.stat().st_size / 1024:.0f} KB)")

    if args.upload:
        upload_spots_to_firestore([*new_spots, *new_events])


if __name__ == "__main__":
    main()
