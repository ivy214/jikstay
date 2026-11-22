"""notify_indexnow: 바뀐 페이지만 고르는 규칙 단위 테스트."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from notify_indexnow import SITE, collect_changed_urls  # noqa: E402

prev = {
    "festivals": [
        {"id": "spot_ev_same", "title": "그대로", "province": "전북", "end_date": "20261230"},
        {"id": "spot_ev_edit", "title": "수정 전", "province": "전북", "end_date": "20261230"},
        {"id": "spot_ev_gone", "title": "빠짐", "province": "전북", "end_date": "20261230"},
    ],
    "daily_stories": [{"id": "spot_story_a", "title": "스토리"}],
}
cur = {
    "festivals": [
        {"id": "spot_ev_same", "title": "그대로", "province": "전북", "end_date": "20261230"},
        {"id": "spot_ev_edit", "title": "수정 후", "province": "전북", "end_date": "20261230"},
        {"id": "spot_ev_new", "title": "새 축제", "province": "부산", "end_date": "20261230"},
        {"id": "spot_ev_old", "title": "끝남", "province": "부산", "end_date": "20261101"},
    ],
    "daily_stories": [{"id": "spot_story_a", "title": "스토리"}],
}

urls = collect_changed_urls(cur, prev, today="20261122")
assert urls[0] == f"{SITE}/", urls
assert f"{SITE}/?topic=festival" in urls
assert f"{SITE}/?topic=festival&region=%EB%B6%80%EC%82%B0" in urls  # 부산
for i in ("spot_ev_edit", "spot_ev_new", "spot_ev_gone", "spot_ev_old"):
    assert f"{SITE}/?spot={i}" in urls, i
assert f"{SITE}/?spot=spot_ev_same" not in urls
assert not any("story=" in u for u in urls)
assert len(urls) == len(set(urls))

# 바뀐 것이 없으면 아무것도 제출하지 않는다
assert collect_changed_urls(cur, cur, today="20261122") == []

# 이전 허브가 없으면 진행 중 행사·스토리 전체 (끝난 행사 제외)
full = collect_changed_urls(cur, None, today="20261122")
assert f"{SITE}/?spot=spot_ev_new" in full and f"{SITE}/?story=spot_story_a" in full
assert f"{SITE}/?spot=spot_ev_old" not in full

print("indexnow_test OK")
