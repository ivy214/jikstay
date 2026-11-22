"""자연·액티비티: 레포츠 선별·고캠핑 문서 만들기 단위 테스트 (API 호출 없음)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from collect_outdoor_spots import activity_type, is_excluded, outdoor_sub, pick_for_province, series_key  # noqa: E402
from refresh_camping import build_camp_doc  # noqa: E402

# 여행 액티비티로 보기 어려운 곳 · 캠핑장(고캠핑이 따로 맡음)은 레포츠에서 뺀다
for t in ("레이캐슬CC", "푸른솔GC 포천", "의창스포츠센터", "양정청소년수련관", "대구스타디움", "무주하얀나라스키샵렌탈샵", "구덕야영장", "에스글램핑"):
    assert is_excluded(t), t
for t in ("단양패러마을 패러글라이딩", "전주한옥레일바이크", "월정 투명카약", "[제주올레 1코스] 시흥-광치기 올레"):
    assert not is_excluded(t), t

assert outdoor_sub("[강화 나들길 2코스] 호국돈대길") == "trail"
assert outdoor_sub("금오도 비렁길") == "trail"
assert outdoor_sub("스카이라인 루지 부산") == "activity"
assert activity_type("부산요트투어 고고요트") == "요트" and activity_type("골든블루마리나") == "요트"
assert activity_type("용호동일대 바다낚시") == "낚시"
assert series_key("[대구올레 팔공산 2코스] 한실골 가는 길") == series_key("[대구올레 팔공산 7코스] 폭포골 가는 길")


def _c(title, region, sub="activity"):
    return {"title": title, "region_label": region, "sub": sub}


# 같은 종류는 2곳까지, 같은 길 연작은 1곳, 시·군·구를 돌아가며
cands = [_c(f"{i}낚시터", f"인천 강화군{i % 3}") for i in range(6)] + [
    _c("인천승마공원", "인천 남동구"),
    _c("[강화 나들길 1코스] 가", "인천 강화군", "trail"),
    _c("[강화 나들길 2코스] 나", "인천 강화군", "trail"),
    _c("하늘빛", "인천 옹진군"),
]
picked = pick_for_province(cands, 8)
titles = [p["title"] for p in picked]
assert sum("낚시" in t for t in titles) == 2, titles
assert sum("나들길" in t for t in titles) == 1, titles
assert "인천승마공원" in titles and "하늘빛" in titles

# 고캠핑 → camping 문서: 값이 있는 칸만 만들고, 운영 중·사진·좌표가 있는 곳만
camp = {
    "contentId": "7595", "facltNm": "풀앤밸리야영장", "lineIntro": "남대천변 글램핑&야영장", "intro": "양양 남대천변 캠핑장이다.",
    "manageSttus": "운영", "induty": "일반야영장,자동차야영장", "lctCl": "계곡", "doNm": "강원특별자치도", "sigunguNm": "양양군",
    "addr1": "강원특별자치도 양양군 현북면 남대천로 1352", "mapX": "128.6526262", "mapY": "37.9931403", "tel": "010-0000-0000",
    "homepage": "fvalley.cafe24.com", "resveUrl": "", "resveCl": "전화,온라인실시간예약", "gnrlSiteCo": "7", "autoSiteCo": "0",
    "operPdCl": "봄,여름,가을", "operDeCl": "평일+주말", "sbrsCl": "전기,무선인터넷", "animalCmgCl": "가능",
    "firstImageUrl": "http://gocamping.or.kr/upload/camp/7595/thumb.jpg",
}
doc = build_camp_doc(camp)
assert doc and doc["id"] == "spot_cp_7595" and doc["kind"] == "outdoor" and doc["sub"] == "camping"
assert doc["province"] == "강원" and doc["image_url"].startswith("https://")
assert doc["url"] == "https://fvalley.cafe24.com" and doc["pet"] is True
rows = {r["label"]: r["value"] for r in doc["practical_info"]}
assert rows["야영장 종류"] == "일반야영장 · 자동차야영장"
assert rows["사이트 수"] == "일반 7"  # 0인 종류는 쓰지 않는다
assert rows["예약"] == "전화 · 온라인실시간예약"
assert "휴장 기간" not in rows and "주차" not in rows  # 고캠핑에 없는 값은 칸을 만들지 않는다
assert build_camp_doc({**camp, "manageSttus": "휴업"}) is None
assert build_camp_doc({**camp, "firstImageUrl": ""}) is None
assert build_camp_doc({**camp, "mapY": "0", "mapX": "0"}) is None
assert "pet" not in build_camp_doc({**camp, "animalCmgCl": "불가능"})

print("outdoor_test OK")
