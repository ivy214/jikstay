"""license_check: 바뀐 숙소만 쓰기(plan_update) · 정적 색인 제외/복원(plan_index_sync) 단위 테스트 (Firestore·API 불필요)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from firebase_admin import firestore  # noqa: E402

from license_check import plan_index_sync, plan_update  # noqa: E402

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
