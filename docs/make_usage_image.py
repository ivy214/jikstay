"""공공데이터포털 활용신청 첨부용 '데이터 활용 계획' 이미지 생성 (1600x900 PNG)."""
import os

from PIL import Image, ImageDraw, ImageFont

W, H = 1600, 900
BOLD, REG = "C:/Windows/Fonts/malgunbd.ttf", "C:/Windows/Fonts/malgun.ttf"
BG, INK, QUIET, LINE = (255, 255, 255), (33, 37, 41), (90, 98, 110), (173, 181, 189)
ACCENT, ACCENT_BG = (255, 90, 54), (255, 238, 233)


def f(path, size):
    return ImageFont.truetype(path, size)


im = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(im)

d.text((70, 55), "직스테이 · 공공 인허가 데이터 활용 계획", font=f(BOLD, 44), fill=INK)
d.text((70, 120), "적법하게 영업신고된 숙박업소만 노출하기 위해 인허가 정보를 대조·재확인합니다",
       font=f(REG, 26), fill=QUIET)

boxes = [
    ("1. 호스트 입점 신청", ["업종, 영업신고번호", "상호, 소재지 주소", "신고증 사본 제출"]),
    ("2. 공공데이터 대조", ["사업장명·소재지 일치", "영업상태 '영업' 확인", "(오픈API 조회)"]),
    ("3. 승인 후 노출", ["신고증 사본 육안 확인", "확인 기록 보관", "미확인 숙소는 비노출"]),
    ("4. 정기 재확인", ["공개 숙소 전체 재조회", "폐업·휴업 확인 시", "즉시 노출 중지"]),
]
bw, bh, gap, y0 = 330, 300, 46, 230
for i, (title, lines) in enumerate(boxes):
    x = 70 + i * (bw + gap)
    main = i == 1
    d.rounded_rectangle([x, y0, x + bw, y0 + bh], radius=18,
                        fill=ACCENT_BG if main else BG, outline=ACCENT if main else LINE, width=4 if main else 2)
    d.text((x + 28, y0 + 32), title, font=f(BOLD, 30), fill=INK)
    for j, line in enumerate(lines):
        d.text((x + 28, y0 + 110 + j * 50), "· " + line, font=f(REG, 26), fill=INK)
    if i < len(boxes) - 1:
        ax, ay = x + bw + 6, y0 + bh // 2
        d.line([ax, ay, ax + gap - 14, ay], fill=LINE, width=4)
        d.polygon([(ax + gap - 6, ay), (ax + gap - 20, ay - 10), (ax + gap - 20, ay + 10)], fill=LINE)

d.rounded_rectangle([70, 590, W - 70, 790], radius=14, fill=(248, 249, 250), outline=LINE, width=2)
d.text((100, 615), "활용 데이터", font=f(BOLD, 28), fill=INK)
d.text((100, 665), "행정안전부 문화 농어촌민박업 · 숙박업 · 한옥체험업 · 외국인관광도시민박업 조회서비스",
       font=f(REG, 26), fill=INK)
d.text((100, 712), "활용 항목: 사업장명, 소재지 주소, 영업상태, 인허가일자  (개인정보 미수집 · 재배포 없음)",
       font=f(REG, 26), fill=QUIET)

d.text((70, 825), "근거: 개정 「공중위생관리법」(2026.11.12 시행) — 온라인 중개 시 숙박업 영업신고증 확인 의무",
       font=f(REG, 24), fill=QUIET)

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data_go_kr_usage_plan.png")
im.save(out)
print(out)
