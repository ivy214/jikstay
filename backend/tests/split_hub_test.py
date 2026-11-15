"""split_hub: 첫 화면 core / 시·도별 상세 분할 규칙 단위 테스트."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from split_hub import OVERVIEW_PREVIEW_CHARS, _default_map_url, split  # noqa: E402

long_overview = "가" * 150 + " 밤이면 야경이 아름답다."
hub = {
    "updated_at": 1,
    "daily_stories": [{"id": "st1", "paragraphs": ["본문"]}],
    "spots": [
        {
            "id": "spot_a",
            "kind": "attraction",
            "title": "수성못",
            "province": "대구",
            "overview": long_overview,
            "paragraphs": ["p1", "p2"],
            "naver_reviews": [{"title": "t"}],
            "practical_info": [{"label": "a", "value": "b"}],
            "images": ["https://tong.visitkorea.or.kr/x.jpg"],
            "map_url": _default_map_url("대구", "수성못"),
            "lat": 35.8,
            "lng": 128.6,
        },
        {"id": "spot_b", "kind": "food", "title": "짧은집", "province": "세종", "overview": "짧다", "map_url": "https://custom"},
    ],
    "festivals": [],
}

core, details = split(hub)
a, b = core["spots"]

# 상세 전용 필드는 core에서 빠지고 해당 시·도 상세 파일로
for f in ("paragraphs", "naver_reviews", "practical_info", "images"):
    assert f not in a, f
    assert f in details["daegu"]["spot_a"], f
assert a["has_details"] is True
assert a["lat"] == 35.8 and a["title"] == "수성못"

# 긴 개요는 미리보기만 core에, 전체는 상세에. 잘려 나간 여행 키워드는 kw 로 보존
assert len(a["overview"]) == OVERVIEW_PREVIEW_CHARS + 1 and a["overview"].endswith("…")
assert details["daegu"]["spot_a"]["overview"] == long_overview
assert a["kw"] == ["야경"]

# 앱이 똑같이 만들 수 있는 기본 지도 URL은 생략, 사용자 지정 URL은 유지
assert "map_url" not in a
assert b["map_url"] == "https://custom"

# 상세가 없는 항목은 표시 없음
assert "has_details" not in b and "sejong" not in details

# 스토리 등 다른 섹션은 그대로
assert core["daily_stories"] == hub["daily_stories"]
# 원본은 변경하지 않음
assert "paragraphs" in hub["spots"][0]
print("[OK] 허브 core / 시·도별 상세 분할")
print("ALL OK")
