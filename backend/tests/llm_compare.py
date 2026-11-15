"""Gemini vs OpenAI: 같은 입력으로 속도·정확도 비교 (실제 API 호출, 크롤링 없음).

  backend\\.venv\\Scripts\\python backend\\tests\\llm_compare.py <smoke_test 출력 폴더> [회수=2]

입력: 가상 호스트 글(한달 120만 원만 기재, 기준 2/최대 4인, 반려동물 불가, 바다 언급 없음)
     + 숙소가 아닌 단색 도형 이미지 5장 (→ 사진은 하나도 고르지 않아야 정답)
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from PIL import Image  # noqa: E402

from blog_to_listing import analyze_with_gemini, analyze_with_openai  # noqa: E402

img_dir = os.path.join(sys.argv[1], "images")
rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 2
images = []
for i, name in enumerate(sorted(os.listdir(img_dir))[:5]):
    p = os.path.join(img_dir, name)
    images.append({"index": i, "source_url": f"test://{name}", "local_path": p,
                   "pil_image": Image.open(p).convert("RGB")})

TEXT = """[예약안내] 애월 돌담집 한달살기 안내드립니다
제주시 애월읍 중산간 마을에 있는 돌집 독채입니다. 농어촌민박 신고 숙소입니다.
기준 2인, 최대 4인까지 머무실 수 있어요.
마당이 넓고, 거실에 워케이션용 큰 책상이 있습니다. 세탁기, 무료 주차 가능.
한달살기 요금: 120만 원 (공과금 별도, 보증금 20만 원)
입실 15시 / 퇴실 11시. 반려동물은 받지 않습니다.
예약 문의는 네이버 예약으로 부탁드립니다."""


def checks(r: dict) -> dict:
    p = r["pricing"]
    words = r["options"] + r["summary_points"]
    return {
        "한달 120만": p["monthly_price"] == 1200000,
        "1박·주간 요금 미생성": p["nightly_min"] is None and p["weekly_price"] is None,
        "오션뷰 미생성": not any("오션" in w or "바다" in w for w in words),
        "반려동물 동반 미생성": not any("반려" in w and "불가" not in w for w in r["options"]),
        "인원 2/4": (r["capacity_standard"], r["capacity_max"]) == (2, 4),
        "비숙소 이미지 제외": len(r["selected_images"]) == 0,
        "컷 수=사진 수": len(r["shorts_data"]["cut_scripts"]) == len(r["selected_images"]),
    }


providers = {
    f"gemini ({os.environ.get('GEMINI_MODEL', 'gemini-3.8-flash')})": analyze_with_gemini,
    f"openai ({os.environ.get('OPENAI_MODEL', 'gpt-5.4-mini')})": analyze_with_openai,
}
only = sys.argv[3] if len(sys.argv) > 3 else ""  # 'openai' 또는 'gemini' 만 실행
providers = {k: v for k, v in providers.items() if only in k}
results = {name: [] for name in providers}
for rnd in range(rounds):
    for name, fn in providers.items():  # 번갈아 호출해 시간대 영향 줄임
        t0 = time.perf_counter()
        try:
            r = fn({"mobile_url": "test://", "text": TEXT, "images": images})
            dt = time.perf_counter() - t0
            c = checks(r)
            failed = [k for k, ok in c.items() if not ok]
            results[name].append((dt, len(c) - len(failed), len(c), failed, r["shorts_data"]["hook_banner"]))
            print(f"[{rnd + 1}] {name}: {dt:.1f}초, 검사 {len(c) - len(failed)}/{len(c)} {failed or ''}")
        except Exception as e:  # noqa: BLE001
            dt = time.perf_counter() - t0
            results[name].append((dt, 0, 0, [f"오류: {str(e)[:120]}"], ""))
            print(f"[{rnd + 1}] {name}: {dt:.1f}초, 오류 {str(e)[:160]}")

print("\n=== 요약 ===")
for name, rows in results.items():
    ok_rows = [r for r in rows if r[2]]
    times = [r[0] for r in ok_rows]
    avg = sum(times) / len(times) if times else float("nan")
    print(f"{name}: 성공 {len(ok_rows)}/{len(rows)}, 평균 {avg:.1f}초, "
          f"검사 통과 {sum(r[1] for r in ok_rows)}/{sum(r[2] for r in ok_rows)}")
    for r in rows:
        if r[4]:
            print(f"   후킹 문구 예: {r[4]}")
            break
