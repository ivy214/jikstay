"""업종별 공공데이터 API 연결 확인: 호출 성공 여부, 건수, 핵심 필드 존재 여부.

  backend\\.venv\\Scripts\\python backend\\tests\\license_probe_all.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import env  # noqa: E402,F401
from license_check import ADDR_KEYS, NAME_KEYS, STATUS_KEYS, _first, query_api  # noqa: E402

SAMPLES = {"농어촌민박업": "민박", "일반/생활숙박업": "호텔", "한옥체험업": "한옥", "외국인관광도시민박업": "게스트"}

for license_type, word in SAMPLES.items():
    try:
        rows = query_api(license_type, word)
        r0 = rows[0] if rows else {}
        print(f"[OK] {license_type}: '{word}' 검색 {len(rows)}건 | 예: {_first(r0, NAME_KEYS)} / "
              f"{_first(r0, ADDR_KEYS)[:30]} / {_first(r0, STATUS_KEYS)}")
        if rows:
            missing = [n for n, keys in (("사업장명", NAME_KEYS), ("주소", ADDR_KEYS), ("영업상태", STATUS_KEYS))
                       if not _first(r0, keys)]
            if missing:
                print(f"     ! 필드 못 찾음: {missing} — 실제 키: {list(r0)[:20]}")
    except Exception as e:  # noqa: BLE001
        print(f"[--] {license_type}: {str(e)[:150]}")
