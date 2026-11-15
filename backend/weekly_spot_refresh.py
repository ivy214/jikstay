# -*- coding: utf-8 -*-
"""
주간 볼거리·먹거리 갱신 (한국관광공사 TourAPI).

1) 폐업·삭제 확인: 전국 볼거리(12)·먹거리(39) 목록 전체를 시·도별로 받아(약 60회 호출),
   허브에 있는데 관광공사 목록에서 사라진 곳을 허브에서 빼고 Firestore spots 를 closed 로 바꾼다.
   - 목록 조회가 하나라도 실패하면 이 단계 전체를 건너뛴다(일부만 받은 목록으로 지우지 않도록).
   - 사라진 곳이 확인 대상의 10%를 넘으면 API 이상으로 보고 건너뛴다.
2) 반값여행 25개 시·군: 1)로 빠졌거나 모자란 만큼 조회순으로 다시 채운다 (collect_half_price_spots).
3) 신규 등록: 시·도마다 최근 14일 안에 관광공사에 새로 등록된 볼거리·먹거리를 종류별 최대 2곳 추가한다.
   시·도별 일반 항목이 40곳 이상이면 더 넣지 않는다(첫 화면 데이터가 끝없이 커지지 않도록).
4) 새 항목은 상세(개요·이용안내·사진)·네이버 방문기 보강 후 허브 JSON 에 저장하고,
   Firebase 자격 증명이 있으면 Firestore spots 문서를 만든다(후기·클릭 집계용).

  python backend/weekly_spot_refresh.py             # 전체 실행
  python backend/weekly_spot_refresh.py --dry-run   # 변경 내용만 출력
  python backend/weekly_spot_refresh.py --no-firestore
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    PROVINCE_17_TOUR_PARAMS,
    _tour_get,
    enrich_spots_and_festivals_details,
    upload_spots_to_firestore,
)
from collect_half_price_spots import DETAIL_CACHE, HUB_PATH, _items, _load_env, _spot_doc, collect  # noqa: E402

SPOT_KINDS = {"12": "attraction", "39": "food"}
NEW_DAYS = 14
NEW_PER_TYPE = 2
PROVINCE_CAP = 40
MAX_REMOVE_RATIO = 0.10


def fetch_live_content_ids() -> set[str] | None:
    """관광공사에 현재 등록된 전국 볼거리·먹거리 content id 전체. 하나라도 실패하면 None."""
    regions = _items(_tour_get("ldongCode2", {"numOfRows": 50, "pageNo": 1}))
    if len(regions) < 15:
        return None
    ids: set[str] = set()
    for reg in regions:
        code = str(reg.get("code") or "")
        for ctype in SPOT_KINDS:
            page = 1
            while True:
                body = _tour_get(
                    "areaBasedList2",
                    {"lDongRegnCd": code, "contentTypeId": ctype, "numOfRows": 1000, "pageNo": page, "arrange": "A"},
                    timeout=60,
                )
                if body is None:
                    print(f"  [건너뜀] 목록 조회 실패: {reg.get('name')} {ctype} p{page}")
                    return None
                rows = _items(body)
                ids.update(str(r.get("contentid") or "") for r in rows)
                total = int(body.get("totalCount") or 0)
                if not rows or page * 1000 >= total:
                    break
                page += 1
    return ids


def find_closed(hub: dict[str, Any], live: set[str]) -> list[dict[str, Any]]:
    checked = [
        s for s in hub.get("spots") or []
        if s.get("kind") in ("attraction", "food") and str(s.get("content_id") or "").isdigit()
    ]
    gone = [s for s in checked if str(s["content_id"]) not in live]
    if checked and len(gone) / len(checked) > MAX_REMOVE_RATIO:
        print(f"  [건너뜀] 사라진 곳 {len(gone)}/{len(checked)} — 비율이 너무 높아 API 이상으로 판단")
        return []
    return gone


def fetch_new_registrations(hub: dict[str, Any], existing_cids: set[str]) -> list[dict[str, Any]]:
    cutoff = (dt.date.today() - dt.timedelta(days=NEW_DAYS)).strftime("%Y%m%d")
    today = dt.date.today().strftime("%Y%m%d")
    per_prov: dict[str, int] = {}
    for s in hub.get("spots") or []:
        if not s.get("half_price_city"):
            per_prov[s.get("province", "")] = per_prov.get(s.get("province", ""), 0) + 1

    out: list[dict[str, Any]] = []
    for prov, q_list in PROVINCE_17_TOUR_PARAMS:
        if per_prov.get(prov, 0) >= PROVINCE_CAP:
            continue
        for ctype, kind in SPOT_KINDS.items():
            added = 0
            for q in q_list[:1]:
                body = _tour_get("areaBasedList2", {**q, "contentTypeId": ctype, "numOfRows": 30, "pageNo": 1, "arrange": "R"}, timeout=20)
                for it in _items(body):
                    if str(it.get("createdtime") or "")[:8] < cutoff:
                        break  # 등록일 내림차순이므로 이후는 모두 더 오래됨
                    doc = _spot_doc(it, kind)
                    if not doc or doc["content_id"] in existing_cids or doc["province"] != prov:
                        continue
                    doc["added_at"] = today
                    existing_cids.add(doc["content_id"])
                    out.append(doc)
                    added += 1
                    if added >= NEW_PER_TYPE:
                        break
    return out


def _firestore_ready() -> bool:
    try:
        from firebase_client import db

        db().collection("spots").limit(1).get()
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"  [Firestore 생략] {str(exc)[:160]}")
        return False


def mark_closed_in_firestore(spots: list[dict[str, Any]]) -> None:
    from firebase_admin import firestore

    from firebase_client import db

    col = db().collection("spots")
    for s in spots:
        ref = col.document(str(s["id"]))
        if ref.get().exists:
            ref.update({
                "status": "closed",
                "closed_reason": "한국관광공사 TourAPI 목록에서 삭제됨",
                "closed_at": firestore.SERVER_TIMESTAMP,
            })


def main() -> None:
    ap = argparse.ArgumentParser(description="주간 볼거리·먹거리 갱신")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-firestore", action="store_true")
    args = ap.parse_args()

    _load_env()
    if _tour_get("ldongCode2", {"numOfRows": 1, "pageNo": 1}) is None:
        print("[weekly-spots] TourAPI 응답 없음 (키 오류 또는 호출 한도) — 변경 없이 종료")
        return
    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))

    print("[weekly-spots] 1) 관광공사 목록에서 사라진 볼거리·먹거리 확인 중...")
    live = fetch_live_content_ids()
    closed = find_closed(hub, live) if live is not None else []
    for s in closed:
        print(f"  삭제됨: {s.get('province')} {s.get('title')} ({s.get('content_id')})")
    if closed:
        gone_ids = {s["id"] for s in closed}
        hub["spots"] = [s for s in hub.get("spots") or [] if s.get("id") not in gone_ids]

    print("[weekly-spots] 2) 반값여행 시·군 모자란 곳 채우는 중...")
    hp_spots, hp_events, _ = collect(hub)

    print("[weekly-spots] 3) 최근 등록된 볼거리·먹거리 확인 중...")
    existing = {str(x.get("content_id") or "") for x in [*(hub.get("spots") or []), *(hub.get("festivals") or []), *hp_spots, *hp_events]}
    new_regs = fetch_new_registrations(hub, existing)
    for s in new_regs:
        print(f"  신규: {s['province']} {s['kind']} {s['title']}")

    new_items = [*hp_spots, *new_regs]
    print(f"[weekly-spots] 결과: 삭제 {len(closed)} · 반값여행 시·군 보충 {len(hp_spots)} · 축제 {len(hp_events)} · 신규 등록 {len(new_regs)}")
    if args.dry_run or not (closed or new_items or hp_events):
        return

    if new_items or hp_events:
        enrich_spots_and_festivals_details([*new_items, *hp_events], cache_path=str(DETAIL_CACHE))
    hub["spots"] = [*(hub.get("spots") or []), *new_items]
    hub["festivals"] = [*(hub.get("festivals") or []), *hp_events]
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[weekly-spots] 저장: {HUB_PATH.name} ({HUB_PATH.stat().st_size / 1024:.0f} KB)")

    if not args.no_firestore and _firestore_ready():
        if new_items or hp_events:
            upload_spots_to_firestore([*new_items, *hp_events])
        if closed:
            mark_closed_in_firestore(closed)


if __name__ == "__main__":
    main()
