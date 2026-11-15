"""Firebase Firestore Emulator 기반 종단 간(E2E) 파이프라인 테스트 (공공API 선별 + 사용자 별점·후기 + 관리자 모더레이션).

호스트 수동 신청·승인 절차 폐지 이후의 핵심 운영 흐름을 검증한다:
  1. 공공 인허가 CSV 기반 숙소 선별 및 Firestore 업서트 (curate_public_stays)
  2. 방문자 별점(1~5점) 및 후기 원자적 등록 시뮬레이션
  3. 공공숙소 재수집 업서트 시 기존 클릭수·별점 합산(review_count, score_sum) 보존 확인
  4. 관리자 웹(/listing/<id>) 조회 및 악성 후기 삭제 시 평점 자동 차감 확인
  5. CPC 크레딧 충전 및 폐업 확인 시 노출 중지(suspended) 전환 확인

실행:
  cd firebase && npm run test:e2e
"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import firebase_admin  # noqa: E402
from firebase_admin import credentials, firestore  # noqa: E402
from google.auth.credentials import AnonymousCredentials  # noqa: E402

import firebase_client  # noqa: E402

# 테스트 중 외부 API 키 영향을 배제해 순수 오프라인/에뮬레이터 결정성을 보장한다.
os.environ.pop("TOUR_API_KEY", None)


class _EmulatorCred(credentials.Base):
    def get_credential(self):
        return AnonymousCredentials()


PROJECT_ID = "jikstay-e2e"
firebase_client._app = firebase_admin.initialize_app(_EmulatorCred(), {"projectId": PROJECT_ID})

import admin_app  # noqa: E402
import curate_public_stays  # noqa: E402
from firebase_client import db  # noqa: E402

tmp = tempfile.mkdtemp(prefix="jikstay_e2e_")
try:
    csv_path = os.path.join(tmp, "rural.csv")
    with open(csv_path, "w", encoding="utf-8-sig") as f:
        f.write("BPLC_NM,ROAD_NM_ADDR,SALS_STTS_NM,MNG_NO\n")
        f.write("애월돌담스테이,제주특별자치도 제주시 애월읍 애월해안로 100,영업/정상,MNG-JEJU-01\n")

    # 1. 공공 인허가 데이터 기반 큐레이션 + Firestore 업서트
    docs = curate_public_stays.run_curation(
        regions=["제주"],
        categories=["농어촌민박업"],
        per_bucket=5,
        enable_naver=False,
        csv_map={"농어촌민박업": csv_path},
        out_json=os.path.join(tmp, "curated.json"),
        index_json=os.path.join(tmp, "index.json"),
        upload=True,
    )
    assert len(docs) >= 1
    listing_id = docs[0]["listing_id"]
    print(f"[1/5] 공공데이터 숙소 선별 및 Firestore 등록 완료 ({listing_id})")

    # 2. 방문자 별점(5점, 3점) + 후기 2건 원자적 배치 등록
    l_ref = db().collection("listings").document(listing_id)
    for rid, nick, sc, msg in [
        ("rev_good_1", "제주여행자", 5, "조용하고 깨끗해서 다시 오고 싶어요!"),
        ("rev_spam_2", "광고계정", 1, "스팸성 후기 테스트"),
    ]:
        b = db().batch()
        b.set(
            l_ref.collection("reviews").document(rid),
            {
                "listing_id": listing_id,
                "nickname": nick,
                "score": sc,
                "comment": msg,
                "lang": "ko",
                "created_at": firestore.SERVER_TIMESTAMP,
            },
        )
        b.update(
            l_ref,
            {
                "review_count": firestore.Increment(1),
                "score_sum": firestore.Increment(sc),
                "last_review_id": rid,
                "outbound_clicks": firestore.Increment(2),
            },
        )
        b.commit()
    snap = l_ref.get().to_dict()
    assert snap["review_count"] == 2 and snap["score_sum"] == 6 and snap["outbound_clicks"] == 4
    print("[2/5] 사용자 별점·후기 2건 등록 확인 (review_count=2, score_sum=6)")

    # 3. 재수집 업서트 실행 시 사용자 별점 및 누적 클릭 보존 검증
    curate_public_stays.upload_curated_to_firestore(docs)
    after_reupsert = l_ref.get().to_dict()
    assert after_reupsert["review_count"] == 2
    assert after_reupsert["score_sum"] == 6
    assert after_reupsert["outbound_clicks"] == 4
    print("[3/5] 공공데이터 재업서트 후 별점·클릭 보존 확인")

    # 4. 관리자 웹 화면 조회 및 스팸 후기 삭제 모더레이션
    client = admin_app.app.test_client()
    assert client.get(f"/listing/{listing_id}").status_code == 200
    r = client.post(f"/listing/{listing_id}/review/rev_spam_2/delete", data={"csrf": admin_app.CSRF})
    assert r.status_code == 302
    after_del = l_ref.get().to_dict()
    assert after_del["review_count"] == 1 and after_del["score_sum"] == 5
    print("[4/5] 관리자 스팸 후기 삭제 및 평점(5.0) 자동 보정 완료")

    # 5. CPC 크레딧 충전 및 노출 중지 처리 검증
    r = client.post(f"/listing/{listing_id}/credit", data={"csrf": admin_app.CSRF, "add_krw": "30000", "cpc_rate": "300"})
    assert r.status_code == 302
    assert l_ref.get().to_dict()["is_sponsored"] is True

    r = client.post(
        f"/listing/{listing_id}/status",
        data={"csrf": admin_app.CSRF, "next_status": "suspended", "reason": "폐업 확인 테스트"},
    )
    assert r.status_code == 302
    assert l_ref.get().to_dict()["status"] == "suspended"
    print("[5/5] CPC 크레딧 반영 및 노출 중지(suspended) 전환 완료")
    print("E2E ALL OK")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
