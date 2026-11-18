"""refresh_culture: 제목 정리·지역·문서 만들기 단위 테스트 (API 호출 없음)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from refresh_culture import build_culture_doc, clean_text  # noqa: E402

# API 제목은 두 번 이스케이프되어 온다
assert clean_text("[대학로] 대표 코미디 연극 &amp;lt;오백에 삼십&amp;gt;") == "[대학로] 대표 코미디 연극 <오백에 삼십>"

item = {"seq": "246265", "serviceName": "전시", "title": "개방 수장고 개편", "startDate": "20201203", "endDate": "20991231",
        "place": "국립현대미술관 청주관", "realmName": "전시", "area": "충북", "sigungu": "청주시",
        "thumbnail": "http://www.culture.go.kr/upload/a.jpg", "gpsX": "127.4899", "gpsY": "36.6554"}
det = {"price": "무료", "url": "https://www.mmca.go.kr/x?a=1&amp;b=2", "phone": "043-261-1400",
       "placeAddr": "충청북도 청주시 청원구 상당로 314"}
doc = build_culture_doc(item, det)
assert doc and doc["id"] == "spot_cu_246265" and doc["kind"] == "culture" and doc["culture_type"] == "전시"
assert doc["province"] == "충북" and doc["region_label"].startswith("충북 청주시")
assert doc["image_url"].startswith("https://")           # 사이트가 https 라 이미지도 https
assert doc["url"] == "https://www.mmca.go.kr/x?a=1&b=2"  # &amp; 풀기
assert doc["practical_info"][0] == {"label": "기간", "value": "2020.12.03 ~ 2099.12.31"}
assert {"label": "요금", "value": "무료"} in doc["practical_info"]

# 장소 주소가 없으면 목록의 area/sigungu 로 (전남광주통합 → 광주 구)
gw = build_culture_doc({**item, "seq": "1", "area": "전남광주통합", "sigungu": "광산구"}, {**det, "placeAddr": ""})
assert gw and gw["province"] == "광주"
# 교육/체험·좌표 없음·사진 없음은 제외
assert build_culture_doc({**item, "serviceName": "교육/체험"}, det) is None
assert build_culture_doc({**item, "gpsX": "", "gpsY": ""}, det) is None
assert build_culture_doc({**item, "thumbnail": ""}, {**det, "imgUrl": ""}) is None

# 끝난 일정 정리: 종료 7일이 지나야 ended, 삭제 예정은 종료 다음 날 + 183일
import datetime as dt  # noqa: E402

from expire_events import expire_at_for, should_end  # noqa: E402

today = dt.date(2026, 11, 18)
assert should_end("20261110", today) is True
assert should_end("20261111", today) is False   # 7일째까지는 유지
assert should_end("", today) is False
exp = expire_at_for("20261231")
assert exp is not None and exp.date() == dt.date(2027, 7, 3)

# KOPIS 중복 제외: 출처마다 지역 태그 위치가 달라도 같은 공연으로 본다 ("[인제] 아는 노래" / "아는 노래 [인제]")
from refresh_culture import kopis_selected  # noqa: E402

ku_today = dt.date(2026, 11, 18)
ku_known = [{"title": "[인제] 아는 노래", "culture_type": "공연", "start_date": "20261121", "end_date": "20261121", "province": "강원"},
            {"title": "[부산] 호두까기인형", "culture_type": "공연", "start_date": "20261201", "end_date": "20261201", "province": "부산"}]


def ku_row(title, area, sd="2026.11.21", ed="2026.11.21", pid="PF1"):
    return {"mt20id": pid, "prfnm": title, "area": area, "fcltynm": "공연장", "prfpdfrom": sd, "prfpdto": ed}


assert kopis_selected([ku_row("아는 노래 [인제]", "강원특별자치도")], ku_today, ku_known) == []
assert kopis_selected([ku_row("아는 노래", "강원특별자치도")], ku_today, ku_known) == []
# 같은 제목이라도 다른 시·도 공연은 남긴다 (태그를 빼고 비교해도 오탐하지 않게)
assert len(kopis_selected([ku_row("호두까기인형 [대구]", "대구광역시", "2026.11.20", "2026.11.20")], ku_today,
                          [{**ku_known[1], "start_date": "20261120", "end_date": "20261120"}])) == 1
# 기간이 겹치지 않으면 다른 공연
assert len(kopis_selected([ku_row("아는 노래 [인제]", "강원특별자치도", "2026.11.19", "2026.11.19")], ku_today, ku_known)) == 1

print("culture_test OK")
