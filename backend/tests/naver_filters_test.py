"""네이버 지역 검색 매칭·블로그 방문기 관련성 필터 단위 테스트 (네트워크·키 불필요)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from build_travel_hub import is_relevant_place_snippet  # noqa: E402
from enrich_naver_local import _query_title, _road_token, category_ok, clean_link, is_facility_of  # noqa: E402


def snip(title: str, summary: str = "") -> dict:
    return {"title": title, "summary": summary}


# 1. 블로그 방문기 관련성
ok = is_relevant_place_snippet
assert ok("성남 중앙공원", "경기 성남시", "경기", snip("[경기성남]가을이 깊어가는 분당중앙공원 풍경 모음"))
assert not ok("성남 중앙공원", "경기 성남시", "경기", snip("ep.135 성남 분당동 지명 뜻과 이름이 시작된 유래", "분당 중앙공원과 이어진"))
assert not ok("성남 중앙공원", "경기 성남시", "경기", snip("서현동어린이집추천", "분당구 중앙공원로 17"))
assert not ok("파리공원", "서울 양천구", "서울", snip("목동 라멘 맛집 목동광장 면식당 목동파리공원점"))
assert ok("얼음나라화천 산천어축제", "강원 화천군", "강원", snip("2027 화천 산천어축제 총정리"))
assert ok("2026 단단단페스티벌", "강원 강릉시", "강원", snip("2026 강릉 단단단페스티벌｜안예은 공연"))
# 짧고 흔한 이름은 지역명이 함께 있어야 한다
assert not ok("중앙공원", "대구 중구", "대구", snip("김포 걸포중앙공원 물놀이터 방문 후기"))
print("[OK] 블로그 방문기 관련성 필터")

# 2. 지역 검색 매칭 보조 함수
assert _query_title("큐브스테이 | CUBE STAY") == "큐브스테이"
assert _query_title("용암사(장수)") == "용암사"
assert _road_token("제주특별자치도 제주시 애월읍 애원로 587-1") == "애원로"
assert clean_link("https://abnb.me/Xt2uleEIXjb") == ""
assert clean_link("https://www.airbnb.co.kr/rooms/1") == ""
assert clean_link("javascript:alert(1)") == ""
assert clean_link("http://www.pensionsea.com/") == "http://www.pensionsea.com/"
assert category_ok("stay", "숙박>펜션")
assert not category_ok("stay", "연애,결혼>예식장")
assert category_ok("attraction", "여행,명소>근린공원")
assert not category_ok("attraction", "음식점>카페,디저트")
assert not category_ok("attraction", "스포츠,오락>체육관")
assert category_ok("food", "한식>감자탕")
assert is_facility_of("동백공원", "동백공원산정화장실")
assert not is_facility_of("동백공원", "동백공원")
print("[OK] 네이버 지역 검색 매칭 규칙")
# '{시·도} 축제' 네이버 검색 결과: 세종 검색에 섞여 나온 다른 시·도 행사는 빼고, 시·도 없이 쓴 세종 주소는 받는다
from weekly_hub_refresh import naver_result_in_province  # noqa: E402

assert naver_result_in_province("세종", "세종특별자치시 조치원읍 새내로 1", "세종")
assert naver_result_in_province("세종", "조치원읍 새내로", "서울")          # 시·도 없는 세종 주소 → 해석은 서울이지만 받는다
assert not naver_result_in_province("세종", "부산광역시 해운대구 BEXCO", "부산")
assert not naver_result_in_province("세종", "경기도 파주시 운정호수공원", "경기")
assert naver_result_in_province("부산", "부산광역시 해운대구 BEXCO", "부산")
assert not naver_result_in_province("부산", "조치원읍 새내로", "서울")      # 세종이 아니면 예외 없음
print("[OK] 네이버 시·도 축제 검색 결과 지역 판정")
print("ALL OK")
