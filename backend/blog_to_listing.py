"""호스트 숙소 소개 URL(블로그·홈페이지 등) → 에어비앤비형 숙소 상세 JSON 추출.

[주요 특징]
- 동의 게이트: 호스트가 신청 폼에서 필수 4대 동의를 마친 신청서(host_applications)의
  숙소 소개 URL만 처리한다.
- 동영상(쇼츠) 대본 생성을 제거하고, 객실 물리 스펙·3대 하이라이트·카테고리별 Amenity·
  미제공 시설·이용규칙·호스트 직거래 혜택·공간별 사진(최대 15장) 추출에 집중한다.
- 개발자 본인 소유 페이지로 테스트할 때만 --own-url 을 쓴다.

사용:
  python blog_to_listing.py --application-id app_123
  python blog_to_listing.py --own-url https://blog.naver.com/내아이디/글번호
환경변수: GEMINI_API_KEY 또는 OPENAI_API_KEY (+ Firestore 조회 시 FIREBASE_CREDENTIALS, FIREBASE_BUCKET)
"""
import argparse
import json
import os
import re
from io import BytesIO
from urllib.parse import parse_qs, urljoin, urlparse, urlunparse

import env  # noqa: F401  (.env 로드)
import requests
from bs4 import BeautifulSoup
from PIL import Image
from pydantic import BaseModel, Field

REQUIRED_CONSENTS = ("consent_copyright", "consent_marketing", "consent_direct_liability", "consent_privacy")

STANDARD_AMENITY_CATEGORIES = (
    "전망 및 입지",
    "스파 및 부대시설",
    "주차 및 출입",
    "주방 및 다이닝",
    "가족 및 키즈",
    "객실 및 침구",
    "세탁 및 다림질",
    "엔터테인먼트·업무",
    "냉난방 및 안전",
)


# ---------- 출력 스키마 ----------
class PricingInfo(BaseModel):
    nightly_min: int | None = Field(description="1박 최소 요금(원). 본문에 없으면 null")
    weekly_price: int | None = Field(description="일주일 요금(원). 본문에 없으면 null")
    monthly_price: int | None = Field(description="한달살기 요금(원). 본문에 없으면 null")
    price_note: str = Field(description="성수기/주말/추가 인원 등 요금 참고사항 요약 (없으면 빈 문자열)")


class RoomSpecs(BaseModel):
    bedrooms: int | None = Field(description="침실 수 (원룸/오픈형이면 1, 본문에 근거 없으면 null)")
    beds: int | None = Field(description="침대 총 개수 (본문에 근거 없으면 null)")
    bed_summary: str = Field(description="침대 구성 요약 (예: '저상형 퀸베드 2개 + 복층 침대', 없으면 빈 문자열)")
    bathrooms: int | None = Field(description="욕실/화장실 개수 (본문에 근거 없으면 null)")
    floor_info: str = Field(description="층수 또는 건물 구조 요약 (예: '5층 단독 객실 / 엘리베이터 있음', 없으면 빈 문자열)")


class HighlightItem(BaseModel):
    icon_key: str = Field(
        description="beach, view, jacuzzi, family, checkin, kitchen, parking, private, quiet 중 가장 어울리는 키워드 1개"
    )
    title: str = Field(description="핵심 특장점 제목 (22자 이내, 예: '송정해변 도보 1분 파노라마 오션뷰')")
    subtitle: str = Field(description="근거 있는 부연 설명 1문장 (55자 이내)")


class AmenityGroup(BaseModel):
    category: str = Field(
        description=(
            "전망 및 입지, 스파 및 부대시설, 주차 및 출입, 주방 및 다이닝, "
            "가족 및 키즈, 객실 및 침구, 세탁 및 다림질, 엔터테인먼트·업무, 냉난방 및 안전 중 택1"
        )
    )
    items: list[str] = Field(description="본문이나 사진에서 명확히 확인되는 편의시설 명칭 목록")


class HouseRules(BaseModel):
    check_in_time: str = Field(description="체크인 시간 (예: '15:00 이후', 미기재 시 빈 문자열)")
    check_out_time: str = Field(description="체크아웃 시간 (예: '11:00 이전', 미기재 시 빈 문자열)")
    self_check_in: str = Field(description="체크인 방식 (예: '스마트 도어록 비대면 셀프 체크인', 미기재 시 빈 문자열)")
    quiet_hours: str = Field(description="매너타임/정숙 시간 (예: '22:00 ~ 08:00', 미기재 시 빈 문자열)")
    smoking_policy: str = Field(description="금연 규정 (예: '실내 전자담배 포함 절대 금연', 미기재 시 빈 문자열)")
    pet_policy: str = Field(description="반려동물 동반 규정 (예: '반려동물 동반 입실 불가' 또는 '소형견 가능', 미기재 시 빈 문자열)")
    extra_rules: list[str] = Field(description="기타 중요 이용규칙·주의사항 목록 (최대 5개, 없으면 빈 배열)")


class LocationInfo(BaseModel):
    display_address: str = Field(description="읍/면/동 또는 해변·랜드마크 기준 위치 요약 (예: '부산 해운대구 송정해변 앞')")
    nearby_spots: str = Field(description="본문에 언급된 도보/차량 거리 주변 편의시설·명소 (없으면 빈 문자열)")
    parking_note: str = Field(description="주차 가능 여부 및 안내 (예: '건물 내 무료 주차 가능', 없으면 빈 문자열)")


class SelectedImage(BaseModel):
    image_index: int = Field(description="입력 이미지 목록 인덱스(0부터)")
    space_tag: str = Field(
        description="외관/뷰, 거실, 침실, 주방, 욕실, 자쿠지/부대시설, 주변풍경 중 택1"
    )
    caption: str = Field(description="20자 이내 공간 설명 캡션")


class ListingExtractionResult(BaseModel):
    title: str = Field(description="숙소의 핵심 매력(뷰·위치·특화시설)이 직관적으로 드러나는 제목 (36자 이내)")
    region_depth1: str = Field(description="시/도 (예: 부산광역시, 제주특별자치도)")
    region_depth2: str = Field(description="시/군/구/읍/면 (예: 해운대구 송정동, 제주시 애월읍)")
    accommodation_type: str = Field(description="숙소 유형 (예: 오션뷰 레지던스, 독채 민박, 한옥 스테이)")
    capacity_standard: int | None = Field(description="기준 인원(명). 미기재 시 null")
    capacity_max: int | None = Field(description="최대 수용 인원(명). 미기재 시 null")
    room_specs: RoomSpecs
    editorial_story: str = Field(
        description="게스트가 이 숙소에서 머무는 하루를 상상하게 만드는 3~5문장(180~320자)의 감성 공간 소개글"
    )
    summary_points: list[str] = Field(description="핵심 매력 포인트 3가지 (본문 근거가 있는 것만)")
    highlights: list[HighlightItem] = Field(description="상세 상단 3대 핵심 특장점 블록 (최대 3개)")
    options: list[str] = Field(description="카드·검색용 대표 옵션 키워드 목록 (예: 오션뷰, 자쿠지, 무료주차, 풀옵션주방)")
    amenities_by_category: list[AmenityGroup] = Field(description="카테고리별 확인된 숙소 편의시설 목록")
    unavailable_amenities: list[str] = Field(
        description="본문에서 제공하지 않는다고 명시되었거나 주의가 필요한 미제공 시설·제한사항 (예: '세탁기 없음', '건조기 없음', '침실 독립 문 없음', 없으면 빈 배열)"
    )
    house_rules: HouseRules
    location_info: LocationInfo
    promo_title: str = Field(
        description="호스트가 본문에서 안내한 이벤트·할인·직거래 혜택 제목 (예: '선착순 온수욕조 무료 이벤트', 없으면 빈 문자열)"
    )
    promo_detail: str = Field(
        description="이벤트·직거래 혜택 상세 조건 1문장 (없으면 빈 문자열)"
    )
    pricing: PricingInfo
    selected_images: list[SelectedImage] = Field(description="실제 숙소 공간 사진 선별 (최대 15장)")


# ---------- 동의 확인 ----------
def load_consented_application(app_id: str) -> dict:
    from firebase_client import db

    snap = db().collection("host_applications").document(app_id).get()
    if not snap.exists:
        raise ValueError(f"신청서 {app_id} 가 없습니다.")
    app = snap.to_dict()
    missing = [k for k in REQUIRED_CONSENTS if app.get(k) is not True]
    if missing:
        raise PermissionError(f"동의 누락 {missing} — 처리하지 않습니다.")
    if app.get("status") in ("rejected", "withdrawn"):
        raise PermissionError(f"신청 상태가 {app['status']} 입니다 — 처리하지 않습니다.")
    return app


# ---------- 네이버 블로그 및 일반 숙소 웹페이지 파서 ----------
MOBILE_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    ),
    "Referer": "https://m.blog.naver.com/",
}

DESKTOP_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8",
}


def to_mobile_naver_url(url: str) -> str:
    parsed = urlparse(url)
    if "blog.naver.com" in parsed.netloc and not parsed.netloc.startswith("m."):
        qs = parse_qs(parsed.query)
        if "blogId" in qs and "logNo" in qs:
            return f"https://m.blog.naver.com/{qs['blogId'][0]}/{qs['logNo'][0]}"
        return urlunparse(parsed._replace(netloc="m.blog.naver.com"))
    return url


def upgrade_naver_image_res(img_url: str) -> str:
    if "pstatic.net" in img_url and "type=" in img_url:
        return re.sub(r"type=[a-zA-Z0-9_]+", "type=w966", img_url)
    return img_url


def _extract_naver_blog(url: str) -> tuple[str, str, list[str], dict]:
    mobile_url = to_mobile_naver_url(url)
    resp = requests.get(mobile_url, headers=MOBILE_HEADERS, timeout=15)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")

    container = soup.select_one("div.se-main-container") or soup.select_one("div#viewTypeSelector")
    if not container:
        raise ValueError("블로그 본문을 찾을 수 없습니다. 전체 공개 글인지 확인하세요.")

    text = re.sub(r"\n{3,}", "\n\n", container.get_text(separator="\n", strip=True))
    urls: list[str] = []
    for img in container.select("img"):
        src = img.get("data-lazy-src") or img.get("src") or ""
        if not src.startswith("http") or "storep-phinf" in src or "blogimgs.pstatic.net" in src:
            continue
        hi = upgrade_naver_image_res(src)
        if hi not in urls:
            urls.append(hi)
    return mobile_url, text, urls, MOBILE_HEADERS


def normalize_intro_url(url: str) -> str:
    """데스크톱 네이버 지도 플레이스 URL(껍데기 프레임)을 SSR 본문이 있는 모바일 플레이스 URL로 변환한다."""
    m = re.search(r"map\.naver\.com/.+?/place/(\d+)", url)
    if m:
        return f"https://m.place.naver.com/place/{m.group(1)}/home"
    return url


def _collect_json_texts_and_images(node, texts: list[str], imgs: list[str]):
    """에어비앤비(deferred-state)·네이버플레이스(Next/Apollo)·JSON-LD 내 숙소 텍스트와 원본 사진 URL을 추출한다."""
    text_keys = {
        "description", "htmlText", "title", "subtitle", "name",
        "sectionId", "checkinTime", "checkoutTime", "address", "streetAddress",
    }
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, str):
                s = v.strip()
                if not s:
                    continue
                if s.startswith("http") and (
                    ("muscache.com/im/pictures/" in s and "/user/" not in s.lower() and "avatar" not in s.lower())
                    or "ldb-phinf.pstatic.net" in s
                    or "naverbooking-phinf.pstatic.net" in s
                ):
                    clean_img = s.split("?")[0] if "muscache.com" in s else upgrade_naver_image_res(s)
                    if clean_img not in imgs:
                        imgs.append(clean_img)
                elif k in text_keys and 2 <= len(s) <= 4000 and not s.startswith("http"):
                    cleaned = BeautifulSoup(s, "html.parser").get_text(" ", strip=True)
                    if cleaned and cleaned not in texts:
                        texts.append(cleaned)
            elif isinstance(v, (dict, list)):
                _collect_json_texts_and_images(v, texts, imgs)
    elif isinstance(node, list):
        for item in node:
            if isinstance(item, (dict, list)):
                _collect_json_texts_and_images(item, texts, imgs)


def parse_general_or_airbnb_html(html: str, base_url: str) -> tuple[str, list[str]]:
    """일반 홈페이지·에어비앤비·네이버플레이스 HTML에서 메타·구조화 JSON·본문·사진 URL을 추출한다."""
    soup = BeautifulSoup(html, "html.parser")

    meta_parts: list[str] = []
    if soup.title and soup.title.string:
        meta_parts.append(soup.title.string.strip())
    for sel in ('meta[property="og:title"]', 'meta[property="og:description"]', 'meta[name="description"]'):
        tag = soup.select_one(sel)
        if tag and tag.get("content"):
            val = tag["content"].strip()
            if val and val not in meta_parts:
                meta_parts.append(val)

    json_texts: list[str] = []
    urls: list[str] = []

    og_img = soup.select_one('meta[property="og:image"]')
    if og_img and og_img.get("content"):
        og_resolved = urljoin(base_url, og_img["content"].strip())
        if og_resolved.startswith("http"):
            urls.append(og_resolved)

    # script 제거 전에 JSON-LD 및 SSR 상태(Airbnb data-deferred-state, Next.js __NEXT_DATA__ 등)를 먼저 파싱
    for sc in soup.select('script[type="application/ld+json"], script[type="application/json"]'):
        raw_json = (sc.string or sc.get_text() or "").strip()
        if not raw_json:
            continue
        try:
            parsed_json = json.loads(raw_json)
            _collect_json_texts_and_images(parsed_json, json_texts, urls)
        except Exception:  # noqa: BLE001
            continue

    for noisy in soup.select("script, style, noscript, svg, nav, footer"):
        noisy.decompose()

    root = soup.select_one("main") or soup.select_one("article") or soup.body or soup
    body_text = re.sub(r"\n{3,}", "\n\n", root.get_text(separator="\n", strip=True))
    structured_summary = "\n".join(json_texts[:160])
    full_text = "\n\n".join(p for p in [*meta_parts, body_text, structured_summary] if p).strip()
    if not full_text:
        raise ValueError("페이지 본문 텍스트를 추출할 수 없습니다.")

    for img in soup.select("img"):
        raw = img.get("data-src") or img.get("data-lazy-src") or img.get("src") or ""
        if not raw or raw.startswith("data:"):
            continue
        resolved = upgrade_naver_image_res(urljoin(base_url, raw))
        if resolved.startswith("http") and "/user/" not in resolved.lower() and resolved not in urls:
            urls.append(resolved)

    return full_text, urls


def _extract_general_page(url: str) -> tuple[str, str, list[str], dict]:
    target_url = normalize_intro_url(url)
    resp = requests.get(target_url, headers=DESKTOP_HEADERS, timeout=15, allow_redirects=True)
    resp.raise_for_status()
    final_url = normalize_intro_url(resp.url)
    if final_url != resp.url:
        resp = requests.get(final_url, headers=DESKTOP_HEADERS, timeout=15)
        resp.raise_for_status()
    full_text, urls = parse_general_or_airbnb_html(resp.text, resp.url)
    return resp.url, full_text, urls, DESKTOP_HEADERS


def scrape_single_post(url: str, out_dir: str, max_images: int = 18) -> dict:
    """권리자가 동의한 단일 숙소 소개 페이지 1건만 가져온다."""
    host = (urlparse(url).netloc or "").lower()
    if "blog.naver.com" in host:
        fetched_url, text, urls, headers = _extract_naver_blog(url)
    else:
        fetched_url, text, urls, headers = _extract_general_page(url)

    img_dir = os.path.join(out_dir, "images")
    os.makedirs(img_dir, exist_ok=True)
    images = []
    for src in urls:
        if len(images) >= max_images:
            break
        try:
            r = requests.get(src, headers=headers, timeout=10)
            r.raise_for_status()
            im = Image.open(BytesIO(r.content)).convert("RGB")
        except Exception as e:  # noqa: BLE001
            print(f"  이미지 건너뜀: {e}")
            continue
        if min(im.size) < 400:
            continue
        path = os.path.join(img_dir, f"raw_{len(images):02d}.jpg")
        im.save(path, "JPEG", quality=90)
        images.append({"index": len(images), "source_url": src, "local_path": path, "pil_image": im})

    return {"mobile_url": fetched_url, "text": text[:10000], "images": images}


# ---------- AI 분석 (Gemini / OpenAI 공용 지시문) ----------
LLM_TIMEOUT_S = int(os.environ.get("LLM_TIMEOUT_S", "120"))  # 호출 1회 시간 제한(초)
LLM_ATTEMPTS = int(os.environ.get("LLM_ATTEMPTS", "2"))  # 최초 포함 시도 횟수
SYSTEM_PROMPT = """
당신은 에어비앤비 수준의 숙소 큐레이터이자 감성 스테이 매거진 에디터입니다.
호스트의 숙소 소개 본문과 이미지를 분석하여 게스트가 숙소의 구조·편의시설(Amenity)·이용규칙을 투명하게 파악하고
호스트에게 바로 예약·문의를 신청하고 싶어지는 상세 페이지 JSON을 작성하세요.

[표시광고법 준수 규칙 — 절대 엄수]
1. 본문과 사진에 없는 가격·뷰·시설·거리·침대 수·수치를 절대 지어내거나 과장하지 마세요.
   확인되지 않는 숫자 필드는 null, 문자열 필드는 빈 문자열(""), 배열 필드는 빈 배열([])로 두세요.
2. 실제 숙소 공간(외관/뷰, 거실, 침실, 주방, 욕실, 자쿠지/부대시설, 주변풍경)이 찍힌 사진만 고르세요.
   음식·영수증·지도 캡처·텍스트 배너·인물 위주 사진·로고 그래픽은 절대 고르지 마세요.
   최대 15장까지 공간별로 골고루 선별하되, 가장 매력적인 대표 뷰/거실 사진을 첫 번째(0번)에 배치하세요.
3. 편의시설(amenities_by_category)은 본문 설명이나 사진에서 실제로 확인되는 항목만 표준 카테고리에 분류해 넣으세요.
   반대로 본문에서 '세탁기 없음', '건조기 없음', '반려동물 불가', '취사 불가', '침실 문이 없는 오픈형 구조'처럼
   미제공·제한 사항이 확인되면 unavailable_amenities 에 명확히 적어 게스트의 오해를 예방하세요.

[전환 유도 & 에디토리얼 작성 규칙]
4. editorial_story 는 게스트가 숙소에 들어와 가장 먼저 읽는 3~5문장의 감성 공간 에세이입니다.
   광고 전단지 말투 대신 공간의 채광, 창밖 풍경, 호스트의 배려, 머무는 동안의 휴식을 따뜻하게 그려내세요.
5. highlights 는 에어비앤비 상세 상단처럼 게스트의 마음을 움직이는 핵심 매력 3가지(입지/뷰, 시그니처 시설, 체크인/호스트 배려 등)를 간결하게 요약하세요.
6. 본문에 이벤트·프로모션(예: 온수욕조 무료 이벤트, 연박 할인 등)이 있다면 promo_title 과 promo_detail 에 정확히 담으세요.
"""


def analyze_with_gemini(scraped: dict) -> dict:
    from google import genai
    from google.genai import types

    if not scraped["images"]:
        raise ValueError("사용 가능한 사진이 없습니다.")

    contents: list = [f"[숙소 소개 본문]\n{scraped['text']}\n\n[이미지 목록]"]
    for item in scraped["images"]:
        contents.append(f"이미지 인덱스 #{item['index']}:")
        contents.append(item["pil_image"])

    client = genai.Client(http_options=types.HttpOptions(
        timeout=LLM_TIMEOUT_S * 1000,
        retry_options=types.HttpRetryOptions(attempts=LLM_ATTEMPTS),
    ))
    resp = client.models.generate_content(
        model=os.environ.get("GEMINI_MODEL", "gemini-3.8-flash"),
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            response_mime_type="application/json",
            response_schema=ListingExtractionResult,
            temperature=0.2,
        ),
    )
    return _attach_images(json.loads(resp.text), scraped)


def analyze_with_openai(scraped: dict) -> dict:
    """OpenAI Responses API + 구조화 출력(같은 Pydantic 스키마)."""
    import base64
    from io import BytesIO as _B

    from openai import OpenAI

    if not scraped["images"]:
        raise ValueError("사용 가능한 사진이 없습니다.")

    content: list = [{"type": "input_text", "text": f"[숙소 소개 본문]\n{scraped['text']}\n\n[이미지 목록]"}]
    for item in scraped["images"]:
        buf = _B()
        item["pil_image"].save(buf, "JPEG", quality=85)
        content.append({"type": "input_text", "text": f"이미지 인덱스 #{item['index']}:"})
        content.append({"type": "input_image",
                        "image_url": "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()})

    client = OpenAI(timeout=LLM_TIMEOUT_S, max_retries=max(LLM_ATTEMPTS - 1, 0))
    resp = client.responses.parse(
        model=os.environ.get("OPENAI_MODEL", "gpt-5.4-mini"),
        instructions=SYSTEM_PROMPT,
        input=[{"role": "user", "content": content}],
        text_format=ListingExtractionResult,
        reasoning={"effort": os.environ.get("OPENAI_REASONING_EFFORT", "low")},
    )
    return _attach_images(resp.output_parsed.model_dump(), scraped)


def analyze_listing(scraped: dict) -> dict:
    """LLM_PROVIDER(.env): gemini(기본) | openai"""
    provider = os.environ.get("LLM_PROVIDER", "gemini").lower()
    return analyze_with_openai(scraped) if provider == "openai" else analyze_with_gemini(scraped)


def _attach_images(result: dict, scraped: dict) -> dict:
    valid = []
    seen_indices: set[int] = set()
    for sel in result.get("selected_images", []):
        idx = sel["image_index"]
        if 0 <= idx < len(scraped["images"]) and idx not in seen_indices:
            seen_indices.add(idx)
            sel["local_path"] = scraped["images"][idx]["local_path"]
            sel["original_url"] = scraped["images"][idx]["source_url"]
            valid.append(sel)
    result["selected_images"] = valid[:15]

    # 검색·카드 하위 호환을 위해 options 에 주요 편의시설 키워드를 중복 없이 보강
    opts = list(dict.fromkeys(o.strip() for o in (result.get("options") or []) if o and o.strip()))
    for grp in result.get("amenities_by_category") or []:
        for item in grp.get("items") or []:
            cleaned = item.strip()
            if cleaned and cleaned not in opts and len(opts) < 20:
                opts.append(cleaned)
    result["options"] = opts
    return result


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--application-id", help="동의 완료된 host_applications 문서 ID")
    g.add_argument("--own-url", help="개발자 본인 소유 숙소 소개 페이지(테스트 전용)")
    ap.add_argument("--out", default="output")
    args = ap.parse_args()

    if args.application_id:
        app = load_consented_application(args.application_id)
        url, source = app["blog_url"], {"application_id": args.application_id}
        out_dir = os.path.join(args.out, args.application_id)
    else:
        url, source = args.own_url, {"own_test": True}
        out_dir = os.path.join(args.out, "own_test")

    print("1/2 숙소 소개 페이지 수집 중...")
    scraped = scrape_single_post(url, out_dir)
    print(f" -> 텍스트 {len(scraped['text'])}자, 사진 {len(scraped['images'])}장")

    print(f"2/2 {os.environ.get('LLM_PROVIDER', 'gemini')} 상세 데이터 분석 중...")
    listing = analyze_listing(scraped)
    listing["source_blog_url"] = url
    listing["source"] = source

    path = os.path.join(out_dir, "listing_result.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(listing, f, ensure_ascii=False, indent=2)
    print(f"완료: {path}")


if __name__ == "__main__":
    main()
