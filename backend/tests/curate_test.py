"""공공 인허가 큐레이션·스코어링·다국어 생성 단위 테스트 (네트워크·키 불필요).

  backend\\.venv\\Scripts\\python backend\\tests\\curate_test.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from curate_public_stays import (  # noqa: E402
    ExternalEnricher,
    build_curated_listing_doc,
    build_lightweight_index_entry,
    classify_region_group,
    curate_bucket,
    is_active_row,
    make_public_listing_id,
    normalize_place_name,
    parse_korean_address,
)

# 1. 영업/정상 필터링 및 상호 변경 화살표 정제
assert is_active_row({"SALS_STTS_NM": "영업/정상", "CLSBIZ_YMD": ""}) is True
assert is_active_row({"SALS_STTS_NM": "영업/정상", "CLSBIZ_YMD": "20250101"}) is False
assert is_active_row({"SALS_STTS_NM": "폐업"}) is False
assert normalize_place_name("가평재 -> 한옥풀빌라 가평재") == "한옥풀빌라 가평재"
assert normalize_place_name("구상호→신상호 스테이") == "신상호 스테이"
print("[OK] 영업상태 필터링 및 상호 정제")

# 2. 주소 파싱 및 5대 권역 분류
d1, d2 = parse_korean_address("제주특별자치도 제주시 애월읍 애월해안로 123")
assert d1 == "제주특별자치도" and d2 == "제주시 애월읍"
assert classify_region_group(d1) == "제주"
assert classify_region_group("경상북도") == "부산/경상"
assert classify_region_group("전북특별자치도") == "전라/충청"
assert classify_region_group("서울특별시") == "서울/경기"
print("[OK] 주소 파싱 및 5대 권역 매핑")

# 3. 결정적(Idempotent) 문서 ID 및 상세 문서·다국어 생성
lid1 = make_public_listing_id("농어촌민박업", "MNG-001", "애월 돌담집", "제주특별자치도 제주시 애월읍 1")
lid2 = make_public_listing_id("농어촌민박업", "MNG-001", "애월 돌담집", "제주특별자치도 제주시 애월읍 1")
assert lid1 == lid2 and lid1.startswith("stay_pub_")

sample_row = {
    "BPLC_NM": "애월 돌담 스테이",
    "ROAD_NM_ADDR": "제주특별자치도 제주시 애월읍 애월로 10",
    "SALS_STTS_NM": "영업/정상",
    "MNG_NO": "JEJU-2025-001",
    "LCPMT_YMD": "20250301",
    "TELNO": "064-799-0000",
    "GSRM_CNT": "2",
    "RSTRM_CNT": "2",
    "BRFT_PVSN_YN": "Y",
    "FIEX_NUM": "2",
    "SNGL_ALRMTYP_SENSO_NUM": "2",
}
sample_enrich = {
    "images": [{"url": "https://tong.visitkorea.or.kr/cms/resource/sample.jpg", "space_tag": "외관", "caption": "대표사진"}],
    "naver_blog_total": 42,
    "naver_reviews": [
        {
            "title": "제주 애월 돌담 스테이 2박 3일 방문기",
            "summary": "조용하고 마당이 예쁜 합법 농어촌민박이었습니다.",
            "blogger_name": "제주여행자",
            "postdate": "20261012",
            "link": "https://blog.naver.com/test/123",
        }
    ],
    "host_blog_url": "https://blog.naver.com/host/999",
}
doc = build_curated_listing_doc(sample_row, "농어촌민박업", "제주", sample_enrich, 95.0)
assert "listing_tier" not in doc and "cpc_balance" not in doc  # 주인 등록·CPC 과금 폐지
assert doc["room_specs"]["bedrooms"] == 2
assert "조식 제공 가능" in doc["options"]
assert len(doc["images"]) == 1 and "path" not in doc["images"][0]
assert len(doc["naver_reviews"]) == 1
assert "Jeju Island" in doc["i18n"]["en"]["title"]
assert "済州島" in doc["i18n"]["ja"]["title"]
assert "濟州島" in doc["i18n"]["zh"]["title"]

idx_entry = build_lightweight_index_entry(doc)
assert idx_entry["listing_id"] == doc["listing_id"]
assert idx_entry["title"] == doc["title"]
# 경량 색인은 상세 전용 필드(후기 수 등)를 싣지 않는다 (초기 로딩 용량 절감)
assert "naver_blog_total" not in idx_entry
print("[OK] 외부 사진 링크·네이버 후기·다국어(영/일/중) 스키마 생성")

# 4. 버킷 상위 N개 선별 검증
with tempfile.TemporaryDirectory() as tmpdir:
    fake_enricher = ExternalEnricher(cache_dir=tmpdir, enable_naver=False)
    fake_enricher.tour_key = ""
    rows = [
        dict(sample_row, MNG_NO=f"M-{i}", BPLC_NM=f"애월 독채 스테이 {i}호")
        for i in range(6)
    ] + [{"BPLC_NM": "폐업민박", "ROAD_NM_ADDR": "제주특별자치도 제주시 애월읍 9", "SALS_STTS_NM": "폐업", "MNG_NO": "CLOSED-1"}]
    picked = curate_bucket(rows, "제주", "농어촌민박업", per_bucket=3, enricher=fake_enricher)
assert len(picked) == 3
assert all(d["title"] != "폐업민박" for d in picked)
print("[OK] 버킷 상위 N개 선별 및 폐업 자동 제외")


# 5. 관리번호가 전국에서 겹치는 업종(한옥체험업 등): 서로 다른 숙소가 같은 ID를 받지 않아야 한다
from curate_public_stays import assign_unique_listing_ids, make_public_listing_id  # noqa: E402

base = make_public_listing_id("한옥체험업", "CDFI2262222026000001", "해곁", "제주 구좌읍 한동로6길 139")
docs = [
    {"listing_id": base, "license_type": "한옥체험업", "public_mng_no": "CDFI2262222026000001", "title": "해곁",
     "location_info": {"display_address": "제주 구좌읍 한동로6길 139"}},
    {"listing_id": base, "license_type": "한옥체험업", "public_mng_no": "CDFI2262222026000001", "title": "상상한옥",
     "location_info": {"display_address": "서울 중구 중림로9길 15"}},
    {"listing_id": "stay_pub_unique0001", "license_type": "농어촌민박업", "public_mng_no": "M-1", "title": "단독",
     "location_info": {"display_address": "강원 어딘가"}},
]
assert assign_unique_listing_ids(docs) == 2
assert len({d["listing_id"] for d in docs}) == 3
assert docs[2]["listing_id"] == "stay_pub_unique0001"  # 겹치지 않는 숙소는 ID 유지
again = [dict(d, listing_id=base) for d in docs[:2]]
assign_unique_listing_ids(again)
assert [d["listing_id"] for d in again] == [d["listing_id"] for d in docs[:2]]  # 재실행해도 같은 ID
print("[OK] 관리번호 중복 숙소 ID 분리 (재실행 시 동일)")
print("ALL OK")
