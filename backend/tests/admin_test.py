"""관리자 화면 렌더링 및 사용자 후기 모더레이션 테스트 (가짜 Firestore 사용, Firebase 불필요).

  backend\\.venv\\Scripts\\python backend\\tests\\admin_test.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

DATA = {
    "listings": {
        "stay_0000abcd": {
            "status": "active",
            "title": "<b>바다집</b>",
            "region_depth1": "제주특별자치도",
            "region_depth2": "제주시 애월읍",
            "license_type": "농어촌민박업",
            "license_number": "제2026-001호",
            "pricing": {"monthly_price": 1500000},
            "images": [],
            "summary_points": ["a"],
            "options": ["독채"],
            "outbound_clicks": 4,
            "review_count": 2,
            "score_sum": 9,
        },
    },
    "listings/stay_0000abcd/reviews": {
        "rev_1": {
            "listing_id": "stay_0000abcd",
            "nickname": "<script>x</script>여행자",
            "score": 5,
            "comment": "정말 깨끗한 숙소였어요!",
            "visit_tag": "가족여행",
            "lang": "ko",
            "created_at": "2026-11-15",
        },
        "rev_2": {
            "listing_id": "stay_0000abcd",
            "nickname": "스팸계정",
            "score": 4,
            "comment": "광고성 후기 테스트",
            "lang": "ko",
            "created_at": "2026-11-15",
        },
    },
    "notifications": {"n1": {"kind": "curated", "result": "ok", "detail": "", "text": "t", "created_at": "x"}},
    "spots": {
        "spot_fo_1": {
            "status": "active",
            "province": "전북",
            "kind": "food",
            "title": "장수 한우명가",
            "addr": "전북 장수군 장수읍",
            "is_sponsored": True,
            "coupon_title": "음료 서비스",
            "outbound_clicks": 12,
            "review_count": 3,
            "score_sum": 15,
        },
    },
}


class Snap:
    def __init__(self, cid, did):
        self.id, self._d = did, DATA.get(cid, {}).get(did)
        self.exists = self._d is not None
        self.reference = self

    def to_dict(self):
        return dict(self._d) if self._d is not None else None


class Query:
    def __init__(self, cid, filt=None):
        self.cid, self.filt = cid, filt

    def where(self, field, op, value):
        return Query(self.cid, (field, value))

    def order_by(self, *a, **k):
        return self

    def limit(self, n):
        return self

    def stream(self):
        for did, d in list(DATA.get(self.cid, {}).items()):
            if self.filt is None or d.get(self.filt[0]) == self.filt[1]:
                yield Snap(self.cid, did)

    def document(self, did):
        return Doc(self.cid, did)


class Doc:
    def __init__(self, cid, did):
        self.cid, self.did = cid, did

    def get(self):
        return Snap(self.cid, self.did)

    def update(self, fields):
        DATA[self.cid][self.did].update(fields)

    def delete(self):
        DATA[self.cid].pop(self.did, None)

    def collection(self, sub):
        return Query(f"{self.cid}/{self.did}/{sub}")


class FakeDB:
    def collection(self, cid):
        return Query(cid)


import admin_app  # noqa: E402

admin_app.db = lambda: FakeDB()
client = admin_app.app.test_client()

assert client.get("/").status_code == 302
for url in ["/listings", "/listings?reviewed=1", "/listing/stay_0000abcd", "/spots", "/analytics", "/curate", "/review", "/jobs"]:
    r = client.get(url)
    assert r.status_code == 200, (url, r.status_code, r.data[:500])
    print(f"[OK] GET {url}")

html = client.get("/listing/stay_0000abcd").get_data(as_text=True)
assert "&lt;b&gt;바다집&lt;/b&gt;" in html, "제목이 HTML 이스케이프되지 않음"
assert "&lt;script&gt;x&lt;/script&gt;여행자" in html, "후기 닉네임이 HTML 이스케이프되지 않음"
assert "★ 4.50" in html
print("[OK] 사용자 입력(숙소명·후기 닉네임) HTML 이스케이프 및 평점 표시")

# 폐지된 구 호스트 신청서 경로 404 확인
assert client.get("/application/app_1").status_code == 404
assert client.get("/notifications").status_code == 404
assert client.post("/listing/stay_0000abcd/credit", data={"csrf": admin_app.CSRF}).status_code == 404
assert "CPC" not in html and "cpc_balance" not in html
print("[OK] 폐지된 호스트 신청서·알림 기록·CPC 크레딧 라우트 제거 확인")

# CSRF 차단
r = client.post("/listing/stay_0000abcd/review/rev_2/delete", data={"csrf": "wrong"})
assert r.status_code == 403
print("[OK] CSRF 토큰 없는 POST 차단")

# 악성 후기 삭제 및 숙소 평점 자동 차감 보정 검증
r = client.post("/listing/stay_0000abcd/review/rev_2/delete", data={"csrf": admin_app.CSRF})
assert r.status_code == 302
assert "rev_2" not in DATA["listings/stay_0000abcd/reviews"]
assert DATA["listings"]["stay_0000abcd"]["review_count"] == 1
assert DATA["listings"]["stay_0000abcd"]["score_sum"] == 5
print("[OK] 관리자 후기 삭제 및 review_count/score_sum 자동 보정 완료")

# 노출 중지 시 사유 필수 검증
r = client.post("/listing/stay_0000abcd/status", data={"csrf": admin_app.CSRF, "next_status": "suspended", "reason": ""})
assert r.status_code == 400
r = client.post("/listing/stay_0000abcd/status", data={"csrf": admin_app.CSRF, "next_status": "suspended", "reason": "폐업 확인"})
assert r.status_code == 302
assert DATA["listings"]["stay_0000abcd"]["status"] == "suspended"
print("[OK] 노출 상태 변경(suspended) 정상 동작")
print("ALL OK")
