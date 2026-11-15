"""주간 성과 리포트.

공개(active) 숙소마다
  - 직거래 버튼 클릭 수(outbound_clicks, 누적)를 읽고
  - 지난 리포트 때 숫자(listings.last_report)와의 차이를 '지난주 성과'로 계산해
  - stats_snapshots 에 기록하고, 연락처 동의한 호스트에게 이메일(기본)·문자(선택)로 안내한다.
첫 실행 때는 이전 값이 없으므로 누적값을 그대로 보낸다.

사용
  python weekly_report.py            # 실제 발송(발송 키 없으면 dry-run 기록)
  python weekly_report.py --no-send  # 숫자만 계산·기록
"""
import argparse
from datetime import date

from firebase_admin import firestore

from firebase_client import db


def run(send: bool = True):
    today = date.today().isoformat()
    listings = [(s.id, s.to_dict()) for s in db().collection("listings").where("status", "==", "active").stream()]

    for listing_id, d in listings:
        clicks_total = int(d.get("outbound_clicks", 0))
        prev = d.get("last_report") or {}
        clicks = clicks_total - int(prev.get("clicks_total", 0))

        db().collection("stats_snapshots").document(f"{listing_id}_{today}").set({
            "listing_id": listing_id,
            "date": today,
            "clicks_total": clicks_total,
            "clicks_week": clicks,
            "views_total": 0,
            "views_week": 0,
            "created_at": firestore.SERVER_TIMESTAMP,
        })
        db().collection("listings").document(listing_id).update({
            "last_report": {"date": today, "clicks_total": clicks_total, "views_total": 0}
        })
        print(f"{d['title']}: 지난주 직거래 클릭 {clicks}건 (누적 {clicks_total}건)")

        if send:
            from notify import notify_listing

            notify_listing(listing_id, "weekly_report", clicks=clicks, clicks_total=clicks_total)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-send", action="store_true")
    run(send=not ap.parse_args().no_send)
