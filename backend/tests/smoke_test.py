"""Firebase·API 키 없이 돌릴 수 있는 핵심 모듈 스모크 테스트.

  backend\\.venv\\Scripts\\python backend\\tests\\smoke_test.py

1) blog_to_listing: 에어비앤비형 상세 스키마(ListingExtractionResult) 검증 및 이미지·편의시설 후처리
2) license_check.evaluate: 일치 / 폐업 / 불확실 판정
3) notify.render: 알림 문구 생성
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# ---------- 1. blog_to_listing 스키마 & 다중 URL 파서 후처리 ----------
from blog_to_listing import (  # noqa: E402
    ListingExtractionResult,
    _attach_images,
    normalize_intro_url,
    parse_general_or_airbnb_html,
)

# 에어비앤비·네이버플레이스·일반 홈페이지 HTML 파싱 검증
assert normalize_intro_url("https://map.naver.com/p/entry/place/12345678") == "https://m.place.naver.com/place/12345678/home"
mock_airbnb_html = """<!doctype html><html><head>
<title>5층 오션뷰 해운대 레지던스</title>
<meta property="og:description" content="송정해변 도보 10초 오션뷰 숙소">
<script id="data-deferred-state-0" type="application/json">
{"niobeMinimalClientData": {"sections": [
  {"title": "대형 욕조", "subtitle": "선착순 온수 무료"},
  {"photo": "https://a0.muscache.com/im/pictures/hosting/Hosting-1581/original/room1.jpeg?im_w=720"},
  {"avatar": "https://a0.muscache.com/im/pictures/user/host_avatar.jpg"}
]}}
</script></head><body><main><p>체크인 15:00 이후</p><img src="https://mystay.kr/photos/living.jpg"></main></body></html>"""
ext_text, ext_imgs = parse_general_or_airbnb_html(mock_airbnb_html, "https://www.airbnb.co.kr/rooms/1581")
assert "선착순 온수 무료" in ext_text and "체크인 15:00 이후" in ext_text, ext_text
assert "https://a0.muscache.com/im/pictures/hosting/Hosting-1581/original/room1.jpeg" in ext_imgs, ext_imgs
assert all("host_avatar" not in u for u in ext_imgs), ext_imgs
assert "https://mystay.kr/photos/living.jpg" in ext_imgs, ext_imgs

sample_payload = {
    "title": "5층 오션뷰 | 송정해변 도보 1분 자쿠지 레지던스",
    "region_depth1": "부산광역시",
    "region_depth2": "해운대구 송정동",
    "accommodation_type": "오션뷰 레지던스",
    "capacity_standard": 4,
    "capacity_max": 7,
    "room_specs": {
        "bedrooms": 1,
        "beds": 2,
        "bed_summary": "저상형 퀸베드 2개 + 미끄럼틀 복층침대",
        "bathrooms": 1,
        "floor_info": "5층 / 엘리베이터 있음",
    },
    "editorial_story": "통유리 창 가득 송정 바다가 펼쳐지는 5층 오션뷰 레지던스입니다.",
    "summary_points": ["송정해변 백사장 도보 1분", "통창 바다전망 대형 자쿠지", "어린이 미끄럼틀 & 식기 구비"],
    "highlights": [
        {"icon_key": "beach", "title": "송정해변 도보 1분", "subtitle": "해변 산책로와 카페거리가 바로 앞에 펼쳐집니다."},
        {"icon_key": "jacuzzi", "title": "바다 전망 자쿠지 & 미끄럼틀", "subtitle": "아이 동반 가족과 커플 모두 만족하는 힐링 공간입니다."},
    ],
    "options": ["오션뷰", "대형 욕조"],
    "amenities_by_category": [
        {"category": "전망 및 입지", "items": ["오션뷰", "해변 인접(워터프런트)", "1층 편의점"]},
        {"category": "주방 및 다이닝", "items": ["취사 가능 주방", "냉장고", "전자레인지", "어린이 식기"]},
        {"category": "주차 및 출입", "items": ["건물 내 무료 주차", "엘리베이터", "셀프 체크인"]},
    ],
    "unavailable_amenities": ["세탁기 없음", "건조기 없음", "반려동물 동반 불가"],
    "house_rules": {
        "check_in_time": "15:00 이후",
        "check_out_time": "11:00 이전",
        "self_check_in": "스마트 도어록 키패드",
        "quiet_hours": "22:00 ~ 08:00",
        "smoking_policy": "실내 절대 금연",
        "pet_policy": "반려동물 동반 불가",
        "extra_rules": ["미성년자 단독 투숙 불가"],
    },
    "location_info": {
        "display_address": "부산광역시 해운대구 송정해변 앞",
        "nearby_spots": "송정해수욕장 도보 1분 · 1층 이마트24 · 해운대 차량 10분",
        "parking_note": "건물 부지 내 무료 주차 가능",
    },
    "promo_title": "선착순 온수욕조 무료 이벤트",
    "promo_detail": "직거래 문의 시 대형 욕조 온수 무료 제공 (정상가 3만 원)",
    "pricing": {"nightly_min": 249600, "weekly_price": None, "monthly_price": None, "price_note": "주말·성수기 별도"},
    "selected_images": [
        {"image_index": 0, "space_tag": "외관/뷰", "caption": "파노라마 오션뷰 거실"},
        {"image_index": 99, "space_tag": "침실", "caption": "범위 밖 인덱스"},
    ],
}

parsed = ListingExtractionResult.model_validate(sample_payload)
attached = _attach_images(
    parsed.model_dump(),
    {"images": [{"local_path": "raw_00.jpg", "source_url": "https://example.com/0.jpg"}]},
)
assert len(attached["selected_images"]) == 1, attached["selected_images"]
assert "건물 내 무료 주차" in attached["options"], attached["options"]
print("[OK] blog_to_listing: 상세 스키마 검증 및 편의시설·이미지 후처리")

# ---------- 2. license_check.evaluate ----------
from license_check import evaluate  # noqa: E402

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

# ---------- 3. notify.render ----------
from notify import TEMPLATES, render  # noqa: E402

samples = dict(title="테스트 돌집", listing_id="stay_0000abcd", reason="신고번호 불일치",
               clicks=3, clicks_total=15, status="폐업")
for k in TEMPLATES:
    assert render(k, **samples)
print("[OK] notify.render: 템플릿", len(TEMPLATES), "종")
print("ALL OK")
