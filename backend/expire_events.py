# -*- coding: utf-8 -*-
"""
끝난 축제·공연·전시 정리 (Firestore spots).

  - 종료일(end_date)이 GRACE_DAYS 일보다 더 지난 active 문서 → status 'ended' + ended_at
    (사이트맵·관리 조회는 active 만 읽으므로 끝난 항목이 쌓여도 읽기 비용이 늘지 않는다)
  - expire_at = 종료일 + DELETE_AFTER_DAYS → Firestore TTL 정책(firestore.indexes.json 의 spots.expire_at)이
    그 뒤 자동 삭제한다. TTL 은 문서만 지우고 하위 후기(reviews) 문서는 남는다.
  - 상세 페이지는 종료일이 지나면 서버가 '종료' 안내 + noindex 로 내보낸다 (status 와 무관).

  python backend/expire_events.py            # 실행
  python backend/expire_events.py --dry-run  # 바꿀 대상만 출력
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))

GRACE_DAYS = 7
DELETE_AFTER_DAYS = 183  # 약 6개월

KST = dt.timezone(dt.timedelta(hours=9))


def expire_at_for(end_ymd: str) -> dt.datetime | None:
    """종료일(YYYYMMDD) 다음 날 0시(KST) + DELETE_AFTER_DAYS"""
    if not re.fullmatch(r"\d{8}", end_ymd or ""):
        return None
    end = dt.datetime.strptime(end_ymd, "%Y%m%d").replace(tzinfo=KST) + dt.timedelta(days=1)
    return end + dt.timedelta(days=DELETE_AFTER_DAYS)


def should_end(end_ymd: str, today: dt.date) -> bool:
    if not re.fullmatch(r"\d{8}", end_ymd or ""):
        return False
    return end_ymd < (today - dt.timedelta(days=GRACE_DAYS)).strftime("%Y%m%d")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="끝난 축제·공연·전시 정리")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    import env  # noqa: F401  (.env 로드)
    from firebase_admin import firestore

    from firebase_client import db

    today = dt.datetime.now(KST).date()
    col = db().collection("spots")
    targets = []
    for snap in col.where(filter=firestore.FieldFilter("status", "==", "active")).select(["end_date", "title", "kind"]).stream():
        d = snap.to_dict() or {}
        if should_end(str(d.get("end_date") or ""), today):
            targets.append((snap.id, d))
    print(f"[expire] 종료 {GRACE_DAYS}일 지난 active 문서 {len(targets)}건")
    for sid, d in targets[:5]:
        print(f"  {sid} {d.get('kind')} {d.get('title')} (종료 {d.get('end_date')})")
    if args.dry_run or not targets:
        return

    batch = db().batch()
    n = 0
    for sid, d in targets:
        payload = {"status": "ended", "ended_at": firestore.SERVER_TIMESTAMP}
        exp = expire_at_for(str(d.get("end_date") or ""))
        if exp:
            payload["expire_at"] = exp
        batch.update(col.document(sid), payload)
        n += 1
        if n % 400 == 0:
            batch.commit()
            batch = db().batch()
    batch.commit()
    print(f"[expire] {n}건 → ended (종료 {DELETE_AFTER_DAYS}일 뒤 TTL 자동 삭제)")


if __name__ == "__main__":
    main()
