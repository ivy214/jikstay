"""Gemini 실제 호출 테스트 (GEMINI_API_KEY 필요, 블로그 크롤링 없음).

가상의 호스트 글 + 테스트 이미지로 analyze_with_gemini 를 호출해
  - 응답이 스키마대로 오는지
  - 본문에 없는 정보(1박·일주일 요금, 오션뷰)를 지어내지 않는지
를 확인한다.

  backend\\.venv\\Scripts\\python backend\\tests\\gemini_test.py <smoke_test 출력 폴더>
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from PIL import Image  # noqa: E402

from blog_to_listing import analyze_with_gemini  # noqa: E402

img_dir = os.path.join(sys.argv[1], "images")
images = []
for i, name in enumerate(sorted(os.listdir(img_dir))[:5]):
    p = os.path.join(img_dir, name)
    images.append({"index": i, "source_url": f"test://{name}", "local_path": p, "pil_image": Image.open(p).convert("RGB")})

text = """[예약안내] 애월 돌담집 한달살기 안내드립니다
제주시 애월읍 중산간 마을에 있는 돌집 독채입니다. 농어촌민박 신고 숙소입니다.
기준 2인, 최대 4인까지 머무실 수 있어요.
마당이 넓고, 거실에 워케이션용 큰 책상이 있습니다. 세탁기, 무료 주차 가능.
한달살기 요금: 120만 원 (공과금 별도, 보증금 20만 원)
입실 15시 / 퇴실 11시. 반려동물은 받지 않습니다.
예약 문의는 네이버 예약으로 부탁드립니다."""

result = analyze_with_gemini({"mobile_url": "test://", "text": text, "images": images})
print(json.dumps({k: v for k, v in result.items() if k != "selected_images"}, ensure_ascii=False, indent=2))
print("selected_images:", [(s["image_index"], s["space_tag"]) for s in result["selected_images"]])

p = result["pricing"]
checks = {
    "한달 요금 120만 원 추출": p["monthly_price"] == 1200000,
    "1박 요금 지어내지 않음": p["nightly_min"] is None,
    "일주일 요금 지어내지 않음": p["weekly_price"] is None,
    "오션뷰 지어내지 않음": not any("오션" in o or "바다" in o for o in result["options"] + result["summary_points"]),
    "반려동물 동반 옵션 없음": not any("반려" in o and "불가" not in o for o in result["options"]),
    "인원 2/4": (result["capacity_standard"], result["capacity_max"]) == (2, 4),
    "컷 대본 수 = 선택 사진 수": len(result["shorts_data"]["cut_scripts"]) == len(result["selected_images"]),
    "나레이션 존재": len(result["shorts_data"]["narration_full"]) > 20,
    # 테스트 이미지는 단색 도형이라 숙소 사진으로 고르면 안 된다
    "숙소가 아닌 이미지는 선택하지 않음": len(result["selected_images"]) == 0,
}
for k, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + k)
print("ALL OK" if all(checks.values()) else "SOME CHECKS FAILED")
