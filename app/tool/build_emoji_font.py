"""앱 내장 이모지 폰트(assets/fonts/AppEmoji.ttf) 생성기.

Flutter 웹(CanvasKit)은 OS 이모지를 쓰지 못해, 화면에 이모지가 나오면 fonts.gstatic.com 에서
Noto Color Emoji 조각(10개, 합계 약 2MB)을 런타임에 받는다. lib/ 에서 실제로 쓰는 이모지만 담은
작은 서브셋을 앱에 넣고 테마의 fontFamilyFallback 으로 지정하면 그 다운로드가 사라진다.

lib/ 코드와 홈 화면이 읽는 데이터(web/data/hub/core·markets·culture.json)의 이모지를 담는다.
lib/ 에 새 이모지를 넣었으면 다시 실행한다 (없는 이모지는 지금처럼 gstatic 에서 받으므로 깨지지는 않는다):
    pip install fonttools brotli
    python tool/build_emoji_font.py            # 생성
    python tool/build_emoji_font.py --check    # lib/ 이모지가 모두 폰트에 있는지 확인 (없으면 exit 1)

폰트: Noto Color Emoji (SIL Open Font License 1.1, assets/fonts/OFL.txt). Google Fonts 의 text= 서브셋 API 사용.
"""
import io
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph

APP = Path(__file__).resolve().parent.parent
OUT = APP / "assets" / "fonts" / "AppEmoji.ttf"
# 이모지(그림 문자) 범위. ★ ✓ → 같은 일반 기호는 한글 폰트 쪽에서 처리되므로 넣지 않는다.
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿⌀-⏿←-⇿]")
TEXT_SYMBOLS = {0x2192, 0x2605, 0x2713}
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36")


# 홈 화면이 처음에 읽는 데이터. 주간 갱신으로 새 이모지가 생기면 그 글자만 gstatic 에서 받는다.
DATA_FILES = [APP / "web" / "data" / "hub" / f"{n}.json" for n in ("core", "markets", "culture")]


def _emoji_in(paths) -> set[int]:
    text = "".join(p.read_text(encoding="utf-8") for p in paths if p.exists())
    return {ord(c) for c in EMOJI.findall(text)} - TEXT_SYMBOLS


def used_codepoints(include_data: bool = False) -> list[int]:
    cps = _emoji_in((APP / "lib").rglob("*.dart"))
    if include_data:
        cps |= _emoji_in(DATA_FILES)
    return sorted(cps)


def check() -> int:
    cmap = TTFont(OUT).getBestCmap()
    missing = [cp for cp in used_codepoints() if cp not in cmap]
    if missing:
        print("AppEmoji.ttf 에 없는 이모지:", " ".join(chr(c) for c in missing), "→ 이 스크립트를 다시 실행하세요")
        return 1
    print(f"OK: lib/ 이모지 {len(used_codepoints())}종 모두 포함")
    return 0


def build() -> None:
    cps = used_codepoints(include_data=True)
    url = "https://fonts.googleapis.com/css2?family=Noto+Color+Emoji&text=" + urllib.parse.quote("".join(map(chr, cps)))
    css = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA})).read().decode()
    font_url = re.search(r"url\((https://[^)]+)\)", css).group(1)
    font = TTFont(io.BytesIO(urllib.request.urlopen(font_url).read()))
    font.flavor = None  # woff2 → ttf (Flutter 웹 CanvasKit 은 woff2 를 읽지 못한다)

    # 서브셋에 딸려 오는 공백(U+0020, 너비 1.25em) 등 이모지가 아닌 문자는 매핑에서 뺀다.
    # 남겨 두면 한글 문장 속 공백이 이 폰트로 그려져 단어 사이가 크게 벌어진다.
    keep = set(cps)
    for table in font["cmap"].tables:
        table.cmap = {cp: g for cp, g in table.cmap.items() if cp in keep}

    # 변형 선택자 VS16(U+FE0F, 🏞️ 의 뒤 글자)을 너비 0 빈 글리프로 넣어 대체 폰트 검사에 걸리지 않게 한다
    name = "uniFE0F"
    if name not in font.getGlyphOrder():
        font.setGlyphOrder(font.getGlyphOrder() + [name])
        font["glyf"].glyphs[name] = Glyph()
        font["glyf"].glyphOrder = font.getGlyphOrder()
        font["hmtx"].metrics[name] = (0, 0)
        font["maxp"].numGlyphs = len(font.getGlyphOrder())
        for table in font["cmap"].tables:
            if table.isUnicode():
                table.cmap[0xFE0F] = name

    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    cmap = font.getBestCmap()
    missing = [cp for cp in cps if cp not in cmap]
    print(f"{OUT.relative_to(APP)}: {OUT.stat().st_size:,} bytes, 이모지 {len(cps) - len(missing)}/{len(cps)}종")
    if missing:
        print("Noto Color Emoji 에 없는 문자:", " ".join(chr(c) for c in missing))


if __name__ == "__main__":
    sys.exit(check() if "--check" in sys.argv else build())
