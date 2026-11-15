"""Firebase·API 키 없이 돌릴 수 있는 공공 인허가 대조 스모크 테스트.

  backend\\.venv\\Scripts\\python backend\\tests\\smoke_test.py

1) license_check.evaluate: 일치 / 폐업 / 불확실 판정
2) license_check.check_listing: 숙소 문서 기준 대조 (관리번호 정확 일치 우선, KTO 콘텐츠 ID 제외)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import license_check  # noqa: E402
from license_check import check_listing, evaluate  # noqa: E402

# ---------- 1. evaluate ----------
rows = [
    {"BPLC_NM": "바다집", "ROAD_NM_ADDR": "제주특별자치도 제주시 애월읍 애월해안로 100", "SALS_STTS_NM": "영업/정상"},
    {"BPLC_NM": "바다집2호", "ROAD_NM_ADDR": "제주특별자치도 서귀포시 성산읍", "SALS_STTS_NM": "폐업"},
]
r = evaluate("바다집", "제주특별자치도 제주시 애월읍 애월해안로 100", rows)
assert r["result"] == "match", r
r = evaluate("바다집2호", "제주특별자치도 서귀포시 성산읍 일출로 1", rows)
assert r["result"] == "closed", r
r = evaluate("산집", "강원특별자치도 강릉시", rows)
assert r["result"] in ("uncertain", "not_found"), r
r = evaluate("바다집", "제주특별자치도 제주시 조천읍 조천로 50", rows)
assert r["result"] == "uncertain", r
assert evaluate("x", "y", [])["result"] == "not_found"
print("[OK] license_check.evaluate: match / closed / uncertain 판정")

# ---------- 2. check_listing (공공 API 호출은 가짜로 대체) ----------
api_rows = [
    {"BPLC_NM": "돌담집", "ROAD_NM_ADDR": "제주특별자치도 제주시 한림읍 금능9길 10", "SALS_STTS_NM": "휴업", "MNG_NO": "M-001"},
    {"BPLC_NM": "돌담집", "ROAD_NM_ADDR": "강원특별자치도 강릉시 어딘가 1", "SALS_STTS_NM": "영업/정상", "MNG_NO": "M-002"},
]
license_check.query_api = lambda license_type, name, max_pages=5: list(api_rows)
doc = {
    "title": "돌담집",
    "license_type": "농어촌민박업",
    "location_info": {"display_address": "강원특별자치도 강릉시 어딘가 1"},
}
# 관리번호가 같으면 주소가 달라도 그 행의 영업상태로 판정
r = check_listing({**doc, "public_mng_no": "M-001"})
assert r["result"] == "closed" and r["matched_by"] == "mng_no", r
# KTO 콘텐츠 ID는 관리번호로 쓰지 않고 상호·주소로 판정
r = check_listing({**doc, "public_mng_no": "KTO-2556500"})
assert r["result"] == "match" and r["matched_by"] == "name_address", r
# 상호·업종이 없으면 오류
assert check_listing({"title": ""})["result"] == "error"
print("[OK] license_check.check_listing: 관리번호 우선 대조 · KTO ID 제외")
print("ALL OK")
