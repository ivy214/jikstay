"""앱 내장 한글 폰트(assets/fonts/AppKR.ttf) 생성기.

Flutter 웹(CanvasKit)은 OS 폰트를 쓰지 못해, 한글이 나오면 fonts.gstatic.com 에서 Noto Sans KR 조각을
화면에 나온 글자에 맞춰 런타임에 받는다 (첫 화면만 18개 요청, 다른 화면으로 가면 더 받음, 글자가 늦게 뜸).
Noto Sans KR 400 굵기에서 KS X 1001 한글 2,350자 + 앱·데이터에 쓰인 글자만 담아 앱에 넣는다.
굵게는 지금처럼 엔진이 400 에서 합성하므로 화면 모양은 그대로다.

    pip install fonttools brotli
    python tool/build_korean_font.py

담는 글자: KS X 1001 한글 2,350자, 기본 라틴·문장부호·한글 자모, 그리고 lib/·첫 화면 데이터·숙소 색인에
쓰인 한글·기호. 한자·일본어·중국어는 넣지 않는다 (번역 화면에서만 쓰이고, 지금처럼 gstatic 에서 받는다).
AppEmoji.ttf 에 있는 글자(❤ ★ ↗ 등)는 빼서 컬러 이모지가 흑백 글리프로 바뀌지 않게 한다 (fontFamilyFallback 은 AppKR 이 먼저).
없는 글자는 지금처럼 gstatic 에서 받으므로 깨지지 않는다.

폰트: Noto Sans KR (SIL Open Font License 1.1, assets/fonts/OFL-NotoSansKR.txt).
"""
import io
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

APP = Path(__file__).resolve().parent.parent
OUT = APP / "assets" / "fonts" / "AppKR.ttf"
EMOJI_FONT = APP / "assets" / "fonts" / "AppEmoji.ttf"
SRC_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf"
DATA_FILES = [APP / "web" / "data" / "hub" / f"{n}.json" for n in ("core", "markets", "culture")]
DATA_FILES.append(APP / "web" / "data" / "public_stays_index.json")


def ksx1001_hangul() -> set[int]:
    out = set()
    for b1 in range(0xB0, 0xC9):
        for b2 in range(0xA1, 0xFF):
            try:
                out.add(ord(bytes([b1, b2]).decode("euc-kr")))
            except UnicodeDecodeError:
                pass
    return out


def is_cjk_non_korean(cp: int) -> bool:
    return (0x3040 <= cp <= 0x30FF or 0x3400 <= cp <= 0x4DBF or 0x4E00 <= cp <= 0x9FFF
            or 0xF900 <= cp <= 0xFAFF or 0x20000 <= cp)


def wanted_codepoints() -> set[int]:
    base = (set(range(0x20, 0x7F)) | set(range(0xA0, 0x100))     # 라틴 기본·보충
            | set(range(0x2010, 0x2070)) | set(range(0x2190, 0x2200))  # 문장부호·화살표
            | set(range(0x3000, 0x3020)) | set(range(0x3131, 0x318F))  # CJK 문장부호·한글 호환 자모
            | set(range(0xFF01, 0xFF5F)))                          # 전각 영숫자·기호
    text = "".join(p.read_text(encoding="utf-8") for p in (APP / "lib").rglob("*.dart"))
    text += "".join(p.read_text(encoding="utf-8") for p in DATA_FILES if p.exists())
    used = {ord(c) for c in text if ord(c) >= 0x80 and not is_cjk_non_korean(ord(c))}
    cps = ksx1001_hangul() | base | used
    if EMOJI_FONT.exists():
        cps -= set(TTFont(EMOJI_FONT).getBestCmap())
    return cps


def main() -> None:
    print("Noto Sans KR 가변 폰트 내려받는 중 (약 10MB)...")
    vf = TTFont(io.BytesIO(urllib.request.urlopen(SRC_URL).read()))
    font = instancer.instantiateVariableFont(vf, {"wght": 400})
    cps = wanted_codepoints() & set(font.getBestCmap())

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.hinting = False  # 웹 CanvasKit 은 힌팅을 쓰지 않는다
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(cps))
    sub.subset(font)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    hangul = sum(1 for c in cps if 0xAC00 <= c <= 0xD7A3)
    print(f"{OUT.relative_to(APP)}: {OUT.stat().st_size:,} bytes, 글자 {len(cps):,}개 (한글 음절 {hangul:,})")


if __name__ == "__main__":
    main()
