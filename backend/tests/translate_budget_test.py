"""translate_hub: Azure 월 무료 한도 안에서 순서대로 번역하고, 넘치면 다음 달로 미루는지 (API 호출 없음)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import translate_hub as th  # noqa: E402

calls: list[int] = []


def fake_request(texts):
    calls.append(sum(len(t) for t in texts))
    return [{"en": f"EN{t}", "ja": f"JA{t}", "zh": f"ZH{t}"} for t in texts]


th._azure_request = fake_request
month = th._kst_month()

# 1) 지난달 기록은 무시하고 이번 달 0부터
cache = {th.AZURE_USAGE_KEY: {"month": "1999-01", "billed": th.AZURE_MONTHLY_BUDGET}}
th.init_azure_budget(cache)
assert th._AZURE["budget_left"] == th.AZURE_MONTHLY_BUDGET

# 2) 이번 달 남은 한도가 두 묶음치만 있으면 앞에서부터 두 묶음만 번역하고 나머지는 남긴다
payload = {"title": "가" * 1000}  # 1,000자 × 3개 언어 = 3,000자
records = [(f"spot_cp_{i}", payload) for i in range(10)]
cache = {th.AZURE_USAGE_KEY: {"month": month, "billed": th.AZURE_MONTHLY_BUDGET - 6500}}
th.init_azure_budget(cache)
th._AZURE["enabled"] = True
th.AZURE_MAX_CHARS = 1000  # 묶음 하나 = 항목 하나
left = th.azure_translate_records("camp", records, cache)
assert len(calls) == 2, calls
assert [i for i, _ in left] == [f"spot_cp_{i}" for i in range(2, 10)]  # 순서 유지 → 다음 달 같은 자리부터
assert cache["camp:spot_cp_0"]["langs"]["en"]["title"].startswith("EN")
assert th._AZURE["enabled"] is False
th.record_azure_usage(cache)
assert cache[th.AZURE_USAGE_KEY] == {"month": month, "billed": th.AZURE_MONTHLY_BUDGET - 500}

# 3) 무료 전용 섹션은 남은 것을 유료 번역으로 넘기지 않는다
calls.clear()
out = th.process_section(None, None, "camp", records, cache, batch_size=8, max_workers=1)
assert len(calls) == 0
assert set(out["en"]) == {"spot_cp_0", "spot_cp_1"}

# 4) 이미 번역된 것은 다시 보내지 않는다 (필요한 것만)
cache2 = dict(cache)
th.init_azure_budget(cache2)
th._AZURE["budget_left"] = 10**9
th._AZURE["enabled"] = True
calls.clear()
th.process_section(None, None, "camp", records[:2], cache2, batch_size=8, max_workers=1)
assert calls == []

print("translate_budget_test OK")
