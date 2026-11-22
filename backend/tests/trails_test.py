"""refresh_trails: 두루누비 코스 → 걷기길 문서 (API 호출 없음)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from collect_outdoor_spots import is_excluded  # noqa: E402
from refresh_trails import (  # noqa: E402
    COURSE_PAGE,
    _duration,
    build_trail_doc,
    course_key,
    decode_polyline,
    dist_to_route_km,
    encode_polyline,
    gpx_endpoints,
    simplify_to,
    tour_names,
)

# 같은 길·같은 코스 번호면 표기가 달라도 같은 코스
assert course_key("해파랑길 39코스 바우길 05구간") == ("해파랑길", 39)
assert course_key("[해파랑길] 39코스(바우길 05구간)") == ("해파랑길", 39)
assert course_key("DMZ 평화의 길 12코스") == ("DMZ평화의길", 12)
assert course_key("[강화 나들길 2코스] 호국돈대길") is None
# 코리아둘레길 코스는 레포츠 수집에서 빼고 두루누비가 맡는다
assert is_excluded("[해파랑길] 8코스") and not is_excluded("금오도 비렁길")

assert _duration(420) == "약 7시간" and _duration(390) == "약 6시간 30분" and _duration(50) == "약 50분"

gpx = '<gpx><trk><trkseg><trkpt lat="35.1" lon="129.1"></trkpt><trkpt lat="35.2" lon="129.0"></trkpt></trkseg></trk></gpx>'
assert gpx_endpoints(gpx) == (35.1, 129.1, 35.2, 129.0)
assert gpx_endpoints("<gpx></gpx>") is None

course = {
    "crsIdx": "T_CRS_MNG0000005116", "crsKorNm": "남파랑길 1코스", "crsDstnc": "19", "crsTotlRqrmHour": "420",
    "crsLevel": "2", "crsCycle": "비순환형", "sigun": "부산 남구",
    "crsSummary": "- 오륙도 해맞이 공원에서 부산대교까지<br>- 부산항 파노라마",
    "crsContents": "오륙도 해맞이 공원에서부터 부산대교까지 이어지는 구간이다.",
    "crsTourInfo": "- 부산의 상징 '오륙도' <br>- '신선대'", "travelerinfo": "- 시점 : 오륙도해맞이공원<br>교통편) 24번 버스",
    "gpxpath": "http://www.durunubi.kr/x.gpx",
}
doc = build_trail_doc(course, "남파랑길", [35.1, 129.1, 35.2, 129.0])
assert doc and doc["id"] == "spot_tr_NG0000005116" and doc["kind"] == "outdoor" and doc["sub"] == "trail"
assert doc["province"] == "부산" and doc["region_group"] == "부산/경상"
assert doc["url"] == COURSE_PAGE + "T_CRS_MNG0000005116" and doc["gpx_url"].startswith("https://")
rows = {r["label"]: r["value"] for r in doc["practical_info"]}
assert rows == {"거리": "19km", "걷는 시간": "약 7시간", "난이도": "보통", "코스 형태": "비순환형", "길 이름": "코리아둘레길 남파랑길"}
assert doc["image_url"] == ""  # 맞는 사진이 없으면 비워 둔다
assert any(p.startswith("찾아가는 길:") and "24번 버스" in p for p in doc["paragraphs"])
assert "<br>" not in doc["overview"]
# 값이 없는 칸은 만들지 않는다
bare = build_trail_doc({**course, "crsLevel": "", "crsTotlRqrmHour": "", "crsCycle": ""}, "", [35.1, 129.1, 35.2, 129.0])
assert [r["label"] for r in bare["practical_info"]] == ["거리"]
# 좌표(GPX)·시·도가 없으면 만들지 않는다
assert build_trail_doc(course, "남파랑길", None) is None
assert build_trail_doc({**course, "sigun": ""}, "남파랑길", [35.1, 129.1, 35.2, 129.0]) is None

# 경로: Google encoded polyline 왕복 (앱 lib/trail_route.dart decodePolyline 과 같은 규칙)
pts = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)]
assert encode_polyline(pts) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"  # 구글 문서의 예시
assert decode_polyline(encode_polyline(pts)) == pts
# 그림용 경로는 점 수 상한 안으로 줄이되 시작·끝은 그대로
line = [(35.0 + i * 0.001, 129.0 + (i % 7) * 0.0004) for i in range(500)]
small = simplify_to(line, 32)
assert len(small) <= 32 and small[0] == line[0] and small[-1] == line[-1]
# 경로까지 거리 (km): 경로 위 ≈ 0, 1도 위도 차 ≈ 110km
assert dist_to_route_km(35.1, 129.0, [(35.0, 129.0), (35.2, 129.0)]) < 0.01
assert 109 < dist_to_route_km(36.1, 129.0, [(35.0, 129.0), (35.1, 129.0)]) < 112

# 코스 설명 '주요 볼거리'의 따옴표 속 이름
assert tour_names("- 부산의 상징 '오륙도' <br>- 한눈에 볼 수 있는 '신선대' <br>- ‘유엔공원’") == ["오륙도", "신선대", "유엔공원"]

# 코스 위 볼거리 사진이면 장소 이름을 남겨 앱이 밝히게 한다, 같은 코스 사진이면 남기지 않는다
on = build_trail_doc(course, "남파랑길", [35.1, 129.1, 35.2, 129.0], "https://a/b.jpg", encode_polyline(pts), "신선대")
assert on["image_place"] == "신선대" and on["route"] == encode_polyline(pts)
same = build_trail_doc(course, "남파랑길", [35.1, 129.1, 35.2, 129.0], "https://a/b.jpg")
assert "image_place" not in same and "route" not in same

print("trails_test OK")
