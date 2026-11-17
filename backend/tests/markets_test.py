"""refresh_markets: 장날 해석·이름 정리·문서 만들기 단위 테스트 (API 호출 없음)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from refresh_markets import _clean_title, build_market_doc, market_days_label, parse_market_days  # noqa: E402

# 상세 장날 표기 여러 형식 → 끝자리
assert parse_market_days("매월 3, 8, 13, 18, 23, 28일") == [3, 8]
assert parse_market_days("4일 / 9일 / 14일 / 19일 / 24일 / 29일") == [4, 9]
assert parse_market_days("새벽시장, 오일장 (2일, 7일, 12일, 17일, 22일, 27일)") == [2, 7]
assert parse_market_days("상설시장 / 오일장 매월 2일·7일") == [2, 7]
assert parse_market_days("5일 / 10일 / 15일 / 20일 / 25일 / 30일") == [5, 0]
# 장날이 아닌 숫자는 무시
assert parse_market_days("매일") == []
assert parse_market_days("1956년대") == []
assert parse_market_days("1, 3, 5주 일요일") == []
# 상세에 없으면 이름의 (3, 8일) 로
assert parse_market_days("", "곡성기차마을전통시장 (3, 8일)") == [3, 8]
assert parse_market_days("", "영덕시장") == []

# 31일은 장이 서지 않는다
assert market_days_label([1, 6]) == "매월 1·6·11·16·21·26일"
assert market_days_label([5, 0]) == "매월 5·10·15·20·25·30일"

# 이름 끝 장날 표기 정리
assert _clean_title("곡성기차마을전통시장 (3, 8일)") == "곡성기차마을전통시장"
assert _clean_title("도일시장(3일,8일)") == "도일시장"
assert _clean_title("운봉장 / 운봉공설시장  (1, 6일") == "운봉장 / 운봉공설시장"

# 문서: 상설시장인데 장날이 있으면 '상설·5일장', 장날·판매 품목이 이용 안내 앞에
item = {
    "contentid": "123", "title": "경주 중앙시장", "addr1": "경상북도 경주시 금성로 295",
    "firstimage": "http://tong.visitkorea.or.kr/a.jpg", "mapx": "129.21", "mapy": "35.84",
}
detail = {"overview": "경주의 대표 시장이다.", "intro": {"fairday": "상설시장 / 오일장 매월 2일·7일", "saleitem": "농산물·한우", "parkingshopping": "가능"}, "images": []}
doc = build_market_doc("SH060200", item, detail)
assert doc and doc["id"] == "spot_mk_123" and doc["kind"] == "market"
assert doc["market_type"] == "상설·5일장" and doc["days"] == [2, 7]
assert doc["practical_info"][0] == {"label": "장날", "value": "매월 2·7·12·17·22·27일"}
assert doc["practical_info"][1]["label"] == "판매 품목"
assert doc["image_url"].startswith("https://")
# 사진이 없으면 만들지 않는다 (카드·상세가 비어 보이지 않게)
assert build_market_doc("SH060100", {**item, "firstimage": ""}, detail) is None

print("markets_test OK")
