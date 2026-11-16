"""license_check: 바뀐 숙소만 쓰기(plan_update) · 정적 색인 제외/복원(plan_index_sync) 단위 테스트 (Firestore·API 불필요)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from firebase_admin import firestore  # noqa: E402

import datetime as dt  # noqa: E402

from license_check import (  # noqa: E402
    check_kto_listing,
    current_rotation,
    is_kto,
    plan_index_sync,
    plan_update,
    rotation_bucket,
)

DEL = firestore.DELETE_FIELD

# --- plan_update ---
# 정상 + 표시 없음 → 쓰지 않음 (매주 전체 쓰기 방지)
assert plan_update({"status": "active"}, {"result": "match"}) is None
# 정상 + 이전 표시 → 해제
upd = plan_update({"needs_review": True, "needs_review_reason": "not_found"}, {"result": "match"})
assert upd["needs_review"] is False and upd["needs_review_reason"] is DEL and upd["needs_review_detail"] is DEL
# 정상 + 예전 형식(사유만 남은 문서)도 정리
assert plan_update({"needs_review": False, "needs_review_reason": "x"}, {"result": "match"}) is not None

# 폐업 → 노출 중지
upd = plan_update({"status": "active"}, {"result": "closed", "matched_status": "폐업"})
assert upd["status"] == "suspended" and "폐업" in upd["suspended_reason"]

# 판단 불가: 새로 표시
upd = plan_update({}, {"result": "not_found"})
assert upd == {"needs_review": True, "needs_review_reason": "not_found", "needs_review_detail": DEL}
# 같은 분류로 이미 표시돼 있으면 쓰지 않음
assert plan_update({"needs_review": True, "needs_review_reason": "uncertain"}, {"result": "uncertain"}) is None
# 오류 문구가 매주 달라도 분류(error)가 같으면 쓰지 않음
assert plan_update({"needs_review": True, "needs_review_reason": "error", "needs_review_detail": "timeout A"},
                   {"result": "error", "error": "timeout B"}) is None
# 분류가 바뀌면 다시 씀, 오류 상세는 detail 로
upd = plan_update({"needs_review": True, "needs_review_reason": "not_found"}, {"result": "error", "error": "API 응답 오류 500"})
assert upd["needs_review_reason"] == "error" and upd["needs_review_detail"].startswith("API 응답 오류")
# 예전 형식(사유에 오류 문구 전체) → 한 번은 새 형식으로 다시 씀
assert plan_update({"needs_review": True, "needs_review_reason": "API 응답 오류 500"}, {"result": "error", "error": "x"}) is not None


# --- 노출 중지 숙소 ---
SUS = {"status": "suspended"}
# 다시 영업으로 확인 → 자동 재공개 없이 '재개 검토' 표시만
upd = plan_update(SUS, {"result": "match", "matched_status": "영업/정상"})
assert upd["needs_review_reason"] == "reopened" and "status" not in upd
assert plan_update({**SUS, "needs_review": True, "needs_review_reason": "reopened"}, {"result": "match"}) is None
# 여전히 폐업이면 아무것도 안 씀 / 재개 검토 표시였는데 다시 폐업이면 표시 해제
assert plan_update(SUS, {"result": "closed"}) is None
assert plan_update({**SUS, "needs_review": True, "needs_review_reason": "reopened"}, {"result": "closed"})["needs_review"] is False
# 판단 불가·오류는 노출 중지 숙소에 표시하지 않음
assert plan_update(SUS, {"result": "not_found"}) is None and plan_update(SUS, {"result": "error", "error": "x"}) is None

# --- 관광공사 출처 ---
K = {"status": "active", "public_mng_no": "KTO-12345"}
assert is_kto(K) and not is_kto({"public_mng_no": "CDFI123"})
assert check_kto_listing(K, {"12345"})["result"] == "match"
miss = check_kto_listing(K, {"999"})
assert miss["result"] == "kto_missing"
assert plan_update(K, miss)["needs_review_reason"] == "kto_missing"
# 관광공사 목록에 있으면 예전 인허가 대조(not_found)·kto_missing 표시는 풀고
assert plan_update({**K, "needs_review": True, "needs_review_reason": "not_found"}, {"result": "match", "source": "tourapi"})["needs_review"] is False
# 다른 업종에서 폐업으로 확인된 표시(license_closed)는 관광공사 목록만으로 풀지 않음
assert plan_update({**K, "needs_review": True, "needs_review_reason": "license_closed"}, {"result": "match", "source": "tourapi"}) is None

# --- 주소로 찾기 (관광공사 이름 ≠ 등록 상호) ---
from license_check import names_match_loosely, pick_address_match, road_key  # noqa: E402

assert road_key("경상북도 경주시 내남면 귀계길 17-25") == "귀계길 17-25"
assert road_key("제주특별자치도 제주시 조천읍 함덕14길 20-2") == "함덕14길 20-2"
assert road_key("경기도 양평군 강상면 강남로 1544") == "강남로 1544"
assert road_key("서울특별시 송파구 방이동 88") == ""  # 지번 주소는 주소 검색 안 함
assert names_match_loosely("구토란펜션", "경주 한옥펜션 구토란")
assert names_match_loosely("한옥펜션 나비의 꿈", "나비의꿈")
assert not names_match_loosely("바다펜션", "산속민박")
assert not names_match_loosely("펜션", "호텔")  # 일반어만 같으면 다른 업소
row = lambda name, addr, st="영업/정상": {"BPLC_NM": name, "ROAD_NM_ADDR": addr, "SALS_STTS_NM": st}
A = "경상북도 경주시 내남면 귀계길 17-25"
assert pick_address_match("구토란펜션", A, [row("경주 한옥펜션 구토란", A)])["BPLC_NM"] == "경주 한옥펜션 구토란"
# 다른 번지(17-251)·다른 시·군의 같은 도로명·다른 상호는 연결 안 함
assert pick_address_match("구토란펜션", A, [row("구토란", "경상북도 경주시 내남면 귀계길 17-251")]) is None
assert pick_address_match("구토란펜션", A, [row("구토란", "전라남도 여수시 귀계길 17-25")]) is None
assert pick_address_match("구토란펜션", A, [row("햇살민박", A)]) is None
# 같은 주소에 폐업한 예전 등록과 영업 중인 등록이 있으면 영업 중인 쪽
assert pick_address_match("구토란펜션", A, [row("구토란펜션", A, "폐업"), row("구토란 한옥", A)])["BPLC_NM"] == "구토란 한옥"


# --- 4주 순환 ---
assert rotation_bucket("stay_pub_abc", 4) == rotation_bucket("stay_pub_abc", 4)  # 고정
buckets = [rotation_bucket(f"stay_pub_{i}", 4) for i in range(400)]
assert set(buckets) == {0, 1, 2, 3} and min(buckets.count(b) for b in range(4)) > 60  # 고르게 나뉨
weeks = {current_rotation(4, dt.date(2026, 11, 16) + dt.timedelta(weeks=w)) for w in range(4)}
assert weeks == {0, 1, 2, 3}  # 연속 4주면 모든 그룹을 한 번씩
assert rotation_bucket("x", 1) == 0 == current_rotation(1)


# --- plan_index_sync ---
def it(i):
    return {"listing_id": i, "title": i}


items = [it("a"), it("b"), it("c"), it("d")]
held = [it("x"), it("y"), it("c")]
status = {"a": "active", "b": "suspended", "c": "active", "x": "active", "y": "suspended"}
# d: Firestore 문서 없음 → 색인에 그대로 / b: 노출 중지 → 제외·보류 / x: 재개 → 복원
# y: 여전히 중지 → 보류 유지 / c: 색인을 새로 만들어 이미 색인에 있음 → 보류에서 정리
new_items, new_held, removed, restored = plan_index_sync(items, held, status)
assert [x["listing_id"] for x in new_items] == ["a", "c", "d", "x"], new_items
assert sorted(x["listing_id"] for x in new_held) == ["b", "y"], new_held
assert (removed, restored) == (1, 1)

# 보류 중인데 Firestore 문서가 사라진 숙소는 되살리지 않음
new_items, new_held, removed, restored = plan_index_sync([], [it("z")], {})
assert new_items == [] and [x["listing_id"] for x in new_held] == ["z"] and restored == 0

# 다시 돌려도 결과가 같음 (변화 없음)
n2, h2, r2, s2 = plan_index_sync([it("a")], [it("b")], {"a": "active", "b": "suspended"})
assert (r2, s2) == (0, 0) and h2 == [it("b")]

print("license_recheck_test OK")
