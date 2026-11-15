"""공공데이터포털 숙박업 API 실제 호출 대조 테스트 (DATA_GO_KR_SERVICE_KEY, LICENSE_API_LODGING 필요).

  backend\\.venv\\Scripts\\python backend\\tests\\license_live_test.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import env  # noqa: E402,F401
from license_check import evaluate, query_api  # noqa: E402

rows = query_api("일반/생활숙박업", "제주유안")
print("조회 건수:", len(rows))
cases = [
    ("영업 중, 도로명주소", "제주유안아르보호텔2", "제주특별자치도 제주시 제원1길 12", "match"),
    ("영업 중, 지번주소", "제주유안아르보호텔2", "제주특별자치도 제주시 연동 261-26", "match"),
    ("폐업", "제주유안호텔3-2", "제주특별자치도 제주시 제원1길 12", "closed"),
    ("없는 상호", "바다집없음", "강원특별자치도 강릉시 어딘가", "not_found"),
]
ok_all = True
for label, name, addr, expected in cases:
    r = evaluate(name, addr, rows if expected != "not_found" else [])
    ok = r["result"] == expected
    ok_all &= ok
    print(f"[{'OK' if ok else 'FAIL'}] {label}: {r['result']} (기대 {expected}) score={r.get('score')} "
          f"{r.get('matched_name', '')} / {r.get('matched_status', '')} / 폐업일 {r.get('matched_closed_date', '')}")
print("ALL OK" if ok_all else "SOME FAILED")
