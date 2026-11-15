"""공공 인허가 API(행안부 4종) + TourAPI(선택) + 네이버 검색 오픈 API 결합 숙소 큐레이션 파이프라인.

목적:
- 호스트가 직접 입력하기 전이라도 행정안전부 지방인허가 공공데이터에서 '영업/정상' 합법 숙소를 조회하고,
  권역(5개) × 인허가 카테고리(4개)별로 알짜 숙소를 최대 100개씩 자동 선별(Scoring)한다.
- 이미지 파일은 서버(Firebase Storage)에 다운로드·재업로드하지 않고 외부 공식 이미지 URL 링크만 연결한다.
- 부족한 실사용 후기·주변 정보는 네이버 블로그 검색 오픈 API 메타데이터(제목·요약·블로거명·원문 링크)로만
  합법적으로 보완한다(본문·이미지 무단 스크래핑 없음).
- 해외 게스트 유입 및 다국어 SEO를 위해 영문(en)·일문(ja)·중문 번체(zh) 요약 메타데이터를 함께 생성한다.

사용 예:
  # 1) 로컬 JSON 생성 점검 (권역×업종별 상위 100개 선별, 네이버 블로그 API 보완 포함)
  backend\\.venv\\Scripts\\python backend\\curate_public_stays.py --per-bucket 100

  # 2) 특정 지역 빠른 테스트 (예: 제주 × 4개 업종 각 5개씩)
  backend\\.venv\\Scripts\\python backend\\curate_public_stays.py --regions 제주 --per-bucket 5

  # 3) 선별 결과를 Firestore listings 컬렉션에 일괄 반영 (이미 호스트가 클레임한 숙소는 보존)
  backend\\.venv\\Scripts\\python backend\\curate_public_stays.py --per-bucket 100 --upload
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import csv
import hashlib
import html
import json
import os
import re
import threading
import time
from typing import Any
from urllib.parse import quote

import requests

import env  # noqa: F401  (.env 자동 로드)
from license_check import (
    ADDR_KEYS,
    BAD_WORDS,
    DATE_KEYS,
    NAME_KEYS,
    OK_WORDS,
    STATUS_KEYS,
    _api_url,
    _find_rows,
    _first,
)

# 앱(app/lib/main.dart)의 5대 권역과 동일한 분류 및 검색용 시/도 키워드
REGION_GROUPS: dict[str, list[str]] = {
    "제주": ["제주특별자치도"],
    "강원": ["강원특별자치도"],
    "부산/경상": ["부산광역시", "경상남도", "경상북도", "대구광역시", "울산광역시"],
    "전라/충청": ["전북특별자치도", "전라남도", "광주광역시", "충청남도", "충청북도", "대전광역시", "세종특별자치시"],
    "서울/경기": ["서울특별시", "경기도", "인천광역시"],
}

LICENSE_CATEGORIES: list[str] = [
    "농어촌민박업",
    "일반/생활숙박업",
    "한옥체험업",
    "외국인관광도시민박업",
]

# 다국어(영·일·중 번체) 자동 번역 매핑 테이블 (LLM 비용 0원으로 즉시 글로벌 노출)
PROVINCE_I18N: dict[str, dict[str, str]] = {
    "제주특별자치도": {"en": "Jeju Island", "ja": "済州島", "zh": "濟州島"},
    "강원특별자치도": {"en": "Gangwon-do", "ja": "江原道", "zh": "江原道"},
    "부산광역시": {"en": "Busan", "ja": "釜山", "zh": "釜山"},
    "경상남도": {"en": "Gyeongsangnam-do", "ja": "慶尚南道", "zh": "慶尚南道"},
    "경상북도": {"en": "Gyeongsangbuk-do", "ja": "慶尚北道", "zh": "慶尚北道"},
    "대구광역시": {"en": "Daegu", "ja": "大邱", "zh": "大邱"},
    "울산광역시": {"en": "Ulsan", "ja": "蔚山", "zh": "蔚山"},
    "전북특별자치도": {"en": "Jeonbuk-do", "ja": "全北特別自治道", "zh": "全羅北道"},
    "전라남도": {"en": "Jeollanam-do", "ja": "全羅南道", "zh": "全羅南道"},
    "광주광역시": {"en": "Gwangju", "ja": "光州", "zh": "光州"},
    "충청남도": {"en": "Chungcheongnam-do", "ja": "忠清南道", "zh": "忠清南道"},
    "충청북도": {"en": "Chungcheongbuk-do", "ja": "忠清北道", "zh": "忠清北道"},
    "대전광역시": {"en": "Daejeon", "ja": "大田", "zh": "大田"},
    "세종특별자치시": {"en": "Sejong", "ja": "世宗", "zh": "世宗"},
    "서울특별시": {"en": "Seoul", "ja": "ソウル", "zh": "首爾"},
    "경기도": {"en": "Gyeonggi-do", "ja": "京畿道", "zh": "京畿道"},
    "인천광역시": {"en": "Incheon", "ja": "仁川", "zh": "仁川"},
}

CATEGORY_I18N: dict[str, dict[str, str]] = {
    "농어촌민박업": {
        "ko_type": "감성 농어촌민박",
        "en": "Korean Countryside Homestay (Gov-Licensed)",
        "ja": "韓国ローカル農漁村民宿（自治体認可済）",
        "zh": "韓國在地農漁村民宿（政府合法認證）",
    },
    "일반/생활숙박업": {
        "ko_type": "합법 숙박·레지던스",
        "en": "Licensed Stay & Residence",
        "ja": "公認ステイ・レジデンス（営業申告済）",
        "zh": "合法認證住宿・公寓式酒店",
    },
    "한옥체험업": {
        "ko_type": "전통 한옥스테이",
        "en": "Traditional Korean Hanok Stay (Gov-Verified)",
        "ja": "韓国伝統韓屋ステイ（自治体認証）",
        "zh": "韓國傳統韓屋體驗住宿（政府認證）",
    },
    "외국인관광도시민박업": {
        "ko_type": "외국인 전용 도시민박",
        "en": "Foreigner-Exclusive City Homestay (Gov-Licensed)",
        "ja": "外国人専用・都市型ゲストハウス（政府公認）",
        "zh": "外國旅客專屬都市民宿（政府合法認證）",
    },
}

# 무관한 대형 프랜차이즈 모텔·여관 노이즈 완화 키워드 및 감성·독채 가산 키워드
NEGATIVE_NAME_WORDS = ("무인텔", "성인", "여인숙")
POSITIVE_NAME_WORDS = (
    "독채", "스테이", "한옥", "민박", "펜션", "하우스", "빌라", "게스트", "별장", "정원",
    "바다", "오션", "숲", "돌담", "마당", "자쿠지", "풀빌라", "감성", "호스텔", "호텔", "리조트",
)

NAVER_BLOG_LEGACY_URL = "https://openapi.naver.com/v1/search/blog.json"
NAVER_BLOG_HUB_URL = "https://naverapihub.apigw.ntruss.com/search/v1/blog"
NAVER_IMAGE_LEGACY_URL = "https://openapi.naver.com/v1/search/image.json"
NAVER_IMAGE_HUB_URL = "https://naverapihub.apigw.ntruss.com/search/v1/image"

# 한국관광공사 TourAPI(KorService2) 숙박 분류체계(lclsSystm3) → 직스테이 4대 합법 인허가 업종 매핑
TOUR_LCLS_TO_LICENSE: dict[str, str] = {
    "AC030100": "농어촌민박업",          # 펜션
    "AC030300": "농어촌민박업",          # 농어촌민박
    "AC010100": "일반/생활숙박업",       # 관광호텔
    "AC040100": "일반/생활숙박업",       # 일반숙박·부티크호텔
    "AC020100": "일반/생활숙박업",       # 가족호텔·콘도·생활숙박
    "AC020200": "일반/생활숙박업",       # 레지던스·생활숙박
    "AC030200": "한옥체험업",            # 한옥스테이
    "AC060200": "외국인관광도시민박업",  # 게스트하우스
    "AC030400": "외국인관광도시민박업",  # 외국인관광도시민박업
    "AC060100": "외국인관광도시민박업",  # 호스텔
}


def _norm_match_name(raw: str) -> str:
    """상호 대조용 정규화 키 (괄호 부제·공백·특수문자 제거)."""
    s = normalize_place_name(raw)
    s = re.sub(r"\([^)]*\)", "", s)
    s = re.sub(r"\[[^\]]*\]", "", s)
    return re.sub(r"[^\w가-힣]", "", s).lower()


def _norm_addr_key(addr: str) -> str:
    """도로명+건물번호 정밀 대조 키 (예: '제주|애월해안로|490'). 건물번호까지 정확히 일치할 때만 매칭한다."""
    cleaned = re.sub(r"\([^)]*\)", " ", addr or "").strip()
    tokens = cleaned.split()
    if len(tokens) < 3:
        return ""
    prov2 = tokens[0][:2]
    m = re.search(r"([가-힣A-Za-z0-9]+(?:로|길))\s*(\d+(?:-\d+)?)\b", cleaned)
    if not m:
        return ""
    return f"{prov2}|{m.group(1)}|{m.group(2)}"


def clean_html_text(raw: str) -> str:
    if not raw:
        return ""
    stripped = re.sub(r"<[^>]+>", "", str(raw))
    return html.unescape(stripped).strip()


def normalize_place_name(raw: str) -> str:
    """공공 인허가 상호 변경 이력 표기('구상호 -> 현상호', '구상호→현상호')에서 최신 상호만 정제한다."""
    s = re.sub(r"\s+", " ", (raw or "").strip())
    if not s:
        return ""
    for arrow in ("->", "→", "=>"):
        if arrow in s:
            parts = [p.strip() for p in s.split(arrow) if p.strip()]
            if parts:
                s = parts[-1]
    return s


def _safe_int(val: Any) -> int | None:
    if val is None:
        return None
    s = re.sub(r"[^\d]", "", str(val).strip())
    if not s:
        return None
    try:
        n = int(s)
        return n if n > 0 else None
    except ValueError:
        return None


def _safe_float(val: Any) -> float | None:
    if val is None:
        return None
    try:
        return float(str(val).strip())
    except ValueError:
        return None


def is_active_row(row: dict[str, Any]) -> bool:
    """공공 인허가 행이 현재 정상 영업 중인지 판별한다."""
    status = _first(row, STATUS_KEYS)
    cls_ymd = str(row.get("CLSBIZ_YMD") or row.get("dcbYmd") or row.get("폐업일자") or "").strip()
    if cls_ymd:
        return False
    if any(b in status for b in BAD_WORDS):
        return False
    return any(g in status for g in OK_WORDS)


def parse_korean_address(addr: str) -> tuple[str, str]:
    """주소 문자열에서 (시/도, 시/군/구 + 읍/면/동)을 분리한다."""
    cleaned = re.sub(r"\s+", " ", (addr or "").strip())
    if not cleaned:
        return ("", "")
    tokens = cleaned.split(" ")
    depth1 = tokens[0]
    # 제주시 애월읍 / 부산광역시 해운대구 송정동 등 2~3토큰 추출
    sub_tokens: list[str] = []
    for tok in tokens[1:4]:
        if re.search(r"(시|군|구|읍|면|동|가)$", tok):
            sub_tokens.append(tok)
        elif len(sub_tokens) < 1:
            sub_tokens.append(tok)
        else:
            break
    depth2 = " ".join(sub_tokens[:2]).strip()
    return (depth1, depth2)


def classify_region_group(depth1: str) -> str | None:
    if "전남광주" in depth1:
        return "전라/충청"
    for group, provinces in REGION_GROUPS.items():
        if any(p[:2] in depth1 or depth1 in p for p in provinces):
            return group
    # 약칭 대응 (예: 제주도, 강원도, 경남, 경북, 전남, 전북, 충남, 충북)
    short_map = {
        "제주": "제주",
        "강원": "강원",
        "부산": "부산/경상", "대구": "부산/경상", "울산": "부산/경상", "경남": "부산/경상", "경북": "부산/경상", "경상": "부산/경상",
        "광주": "전라/충청", "전남": "전라/충청", "전북": "전라/충청", "전라": "전라/충청",
        "대전": "전라/충청", "세종": "전라/충청", "충남": "전라/충청", "충북": "전라/충청", "충청": "전라/충청",
        "서울": "서울/경기", "경기": "서울/경기", "인천": "서울/경기",
    }
    for prefix, grp in short_map.items():
        if depth1.startswith(prefix):
            return grp
    return None


PROVINCE_17_ORDER: list[str] = [
    "서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
    "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주",
]

PROVINCE_CENTROIDS: dict[str, tuple[float, float]] = {
    "서울": (37.5665, 126.9780),
    "부산": (35.1796, 129.0756),
    "대구": (35.8714, 128.6014),
    "인천": (37.4563, 126.7052),
    "광주": (35.1595, 126.8526),
    "대전": (36.3504, 127.3845),
    "울산": (35.5384, 129.3114),
    "세종": (36.4800, 127.2890),
    "경기": (37.4138, 127.5183),
    "강원": (37.8228, 128.1555),
    "충북": (36.6357, 127.4914),
    "충남": (36.6588, 126.6728),
    "전북": (35.8203, 127.1088),
    "전남": (34.8161, 126.4629),
    "경북": (36.4919, 128.8889),
    "경남": (35.2383, 128.6922),
    "제주": (33.3846, 126.5535),
}

CITY_CENTROID_HINTS: dict[str, tuple[float, float]] = {
    "제주시": (33.4996, 126.5312), "서귀포": (33.2541, 126.5601),
    "강릉": (37.7519, 128.8761), "속초": (38.2070, 128.5918), "양양": (38.0754, 128.6189),
    "춘천": (37.8813, 127.7298), "평창": (37.3708, 128.3906), "홍천": (37.6972, 127.8887),
    "정선": (37.3806, 128.6608), "영월": (37.1836, 128.4618), "고성": (38.3806, 128.4678),
    "해운대": (35.1631, 129.1636), "수영": (35.1456, 129.1132), "기장": (35.2446, 129.2223),
    "경주": (35.8562, 129.2247), "안동": (36.5684, 128.7294), "포항": (36.0190, 129.3435),
    "통영": (34.8544, 128.4332), "거제": (34.8806, 128.6211), "남해": (34.8377, 127.8924),
    "하동": (35.0673, 127.7513), "산청": (35.4156, 127.8735), "밀양": (35.5038, 128.7464),
    "전주": (35.8242, 127.1480), "군산": (35.9677, 126.7366), "남원": (35.4164, 127.3904),
    "무주": (36.0068, 127.6608), "진안": (35.7917, 127.4248), "장수": (35.6473, 127.5215),
    "부안": (35.7318, 126.7332), "고창": (35.4358, 126.7020),
    "여수": (34.7604, 127.6622), "순천": (34.9506, 127.4872), "목포": (34.8118, 126.3922),
    "담양": (35.3211, 126.9882), "강진": (34.6421, 126.7672), "해남": (34.5733, 126.5989),
    "완도": (34.3111, 126.7551), "보성": (34.7715, 127.0799), "구례": (35.2025, 127.4628),
    "태안": (36.7456, 126.2981), "보령": (36.3334, 126.6129), "공주": (36.4465, 127.1190),
    "부여": (36.2758, 126.9098), "서천": (36.0803, 126.6914), "아산": (36.7898, 127.0018),
    "단양": (36.9845, 128.3656), "제천": (37.1326, 128.1910), "청주": (36.6424, 127.4890),
    "충주": (36.9910, 127.9259),
    "가평": (37.8315, 127.5095), "양평": (37.4912, 127.4876), "포천": (37.8949, 127.2003),
    "파주": (37.7599, 126.7802), "수원": (37.2636, 127.0286), "용인": (37.2411, 127.1776),
    "강화": (37.7465, 126.4881), "옹진": (37.2500, 126.3100), "중구": (37.5636, 126.9975),
    "종로": (37.5730, 126.9794), "마포": (37.5563, 126.9220), "용산": (37.5326, 126.9900),
}


def normalize_province_short(depth1: str, depth2: str = "") -> str:
    """17개 시·도 표준 2글자 약칭으로 정규화한다 (전남광주통합특별시 시군구 분리 포함)."""
    d1 = (depth1 or "").strip()
    d2 = (depth2 or "").strip()
    if "전남광주" in d1:
        gwangju_gu = ("동구", "서구", "남구", "북구", "광산구", "광주")
        if any(d2.startswith(g) for g in gwangju_gu):
            return "광주"
        return "전남"
    mapping = [
        ("서울", "서울"), ("부산", "부산"), ("대구", "대구"), ("인천", "인천"),
        ("광주", "광주"), ("대전", "대전"), ("울산", "울산"), ("세종", "세종"),
        ("경기", "경기"), ("강원", "강원"),
        ("충청북", "충북"), ("충북", "충북"),
        ("충청남", "충남"), ("충남", "충남"),
        ("전북", "전북"), ("전라북", "전북"),
        ("전남", "전남"), ("전라남", "전남"),
        ("경상북", "경북"), ("경북", "경북"),
        ("경상남", "경남"), ("경남", "경남"),
        ("제주", "제주"),
    ]
    for prefix, short in mapping:
        if prefix in d1:
            return short
    return "서울"


def infer_stay_coords(doc: dict[str, Any]) -> tuple[float, float, bool]:
    """정확한 WGS84 좌표가 있으면 그대로 반환하고, 없으면 시군구 중심점 기반 근사 좌표를 반환한다."""
    loc = doc.get("location_info") or {}
    lat = _safe_float(loc.get("lat"))
    lng = _safe_float(loc.get("lng"))
    if lat and lng and 32.5 <= lat <= 39.0 and 124.0 <= lng <= 132.0:
        return (round(lat, 5), round(lng, 5), False)
    prov = normalize_province_short(str(doc.get("region_depth1") or ""), str(doc.get("region_depth2") or ""))
    d2 = str(doc.get("region_depth2") or "")
    base_lat, base_lng = PROVINCE_CENTROIDS.get(prov, (36.5, 127.8))
    for city_key, (clat, clng) in CITY_CENTROID_HINTS.items():
        if city_key in d2:
            base_lat, base_lng = clat, clng
            break
    seed_hex = hashlib.md5(str(doc.get("listing_id") or doc.get("title") or "").encode("utf-8")).hexdigest()
    off_lat = ((int(seed_hex[:4], 16) / 65535.0) - 0.5) * 0.036
    off_lng = ((int(seed_hex[4:8], 16) / 65535.0) - 0.5) * 0.036
    return (round(base_lat + off_lat, 5), round(base_lng + off_lng, 5), True)


def make_public_listing_id(license_type: str, mng_no: str, name: str, addr: str) -> str:
    """재실행 시에도 동일한 문서 ID를 유지해 호스트 클레임·클릭 통계를 보존한다."""
    seed = f"{license_type}|{mng_no.strip()}" if mng_no.strip() else f"{license_type}|{name.strip()}|{addr.strip()}"
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()[:10]
    return f"stay_pub_{digest}"


def extract_public_amenities_and_specs(
    row: dict[str, Any],
    license_type: str,
    addr: str,
) -> tuple[dict[str, Any], list[dict[str, Any]], list[str]]:
    """행안부 공공 API의 실제 물리·안전 필드에서 객실 스펙과 표준 편의시설 목록을 추출한다."""
    gsrm = _safe_int(row.get("GSRM_CNT"))
    ksrm = _safe_int(row.get("KSRM_CNT"))
    wsrm = _safe_int(row.get("WSRM_CNT"))
    room_cnt = gsrm or ((ksrm or 0) + (wsrm or 0) if (ksrm or wsrm) else None)
    bath_cnt = _safe_int(row.get("RSTRM_CNT"))
    ground_flr = _safe_int(row.get("BLDG_GRND_FLR_CNT"))
    bldg_shape = str(row.get("BLDG_SHP_SE_NM") or row.get("SNTTN_BZSTAT_NM") or "").strip()
    area_sqm = _safe_float(row.get("HSAR") or row.get("LCTN_AREA"))

    floor_parts: list[str] = []
    if bldg_shape:
        floor_parts.append(bldg_shape)
    if ground_flr:
        floor_parts.append(f"지상 {ground_flr}층")
    if area_sqm and area_sqm >= 15:
        floor_parts.append(f"연면적 약 {round(area_sqm)}㎡")

    room_specs: dict[str, Any] = {}
    if room_cnt:
        room_specs["bedrooms"] = min(room_cnt, 20)
    if bath_cnt:
        room_specs["bathrooms"] = min(bath_cnt, 20)
    if floor_parts:
        room_specs["floor_info"] = " · ".join(floor_parts)

    loc_items: list[str] = []
    if any(w in addr for w in ("해변", "해안", "바다", "해수욕장", "송정", "해운대", "광안", "애월", "협재", "구좌", "성산", "강문", "경포", "주문진", "양양")):
        loc_items.append("해변·바다 인접 권역")
    if any(w in addr for w in ("산", "숲", "계곡", "리 ", "읍 ", "면 ")):
        loc_items.append("한적한 로컬·자연 인접")
    if license_type == "한옥체험업":
        loc_items.append("전통 한옥 공간 체험")

    safety_items: list[str] = ["지자체 영업신고 적법 업소"]
    if _safe_int(row.get("FIEX_NUM")) or _safe_int(row.get("AUTO_DIFSI_FIEX_CNTOM")):
        safety_items.append("소화기 비치 확인(공공데이터)")
    if _safe_int(row.get("SNGL_ALRMTYP_SENSO_NUM")):
        safety_items.append("화재경보기(단독경보형감지기)")
    if _safe_int(row.get("CBMX_SENSO_CNTOM")):
        safety_items.append("일산화탄소 경보기")
    if _safe_int(row.get("GAS_LKGE_ALARM_CNTOM")):
        safety_items.append("가스누출 경보기")
    if _safe_int(row.get("PRTB_EMRGC_LGTS_CNTOM")):
        safety_items.append("휴대용 비상조명등")

    dining_items: list[str] = []
    if str(row.get("BRFT_PVSN_YN") or "").strip().upper() == "Y":
        dining_items.append("조식 제공 가능")

    parking_items: list[str] = ["장기·단기 숙박 문의 가능"]
    if license_type in ("농어촌민박업", "한옥체험업"):
        parking_items.insert(0, "독채/개별실 여부 호스트 확인")

    amenity_groups: list[dict[str, Any]] = []
    if loc_items:
        amenity_groups.append({"category": "전망 및 입지", "items": loc_items})
    if dining_items:
        amenity_groups.append({"category": "주방 및 다이닝", "items": dining_items})
    if parking_items:
        amenity_groups.append({"category": "주차 및 출입", "items": parking_items})
    amenity_groups.append({"category": "냉난방 및 안전", "items": safety_items})

    flat_options: list[str] = []
    for grp in amenity_groups:
        for it in grp["items"]:
            if it not in flat_options:
                flat_options.append(it)

    return room_specs, amenity_groups, flat_options[:8]


def base_quality_score(row: dict[str, Any], name: str, addr: str, license_type: str) -> float:
    """외부 API 호출 전 공공 인허가 데이터 충실도로 1차 후보 점수를 매긴다."""
    score = 10.0
    if any(bad in name for bad in NEGATIVE_NAME_WORDS):
        return -100.0
    if len(name.strip()) < 2:
        return -50.0

    # 감성·여행 친화 상호 가산점
    for kw in POSITIVE_NAME_WORDS:
        if kw in name:
            score += 6.0

    # 도로명주소, 전화번호, 객실/안전시설 정보 보유 가산점
    if row.get("ROAD_NM_ADDR"):
        score += 8.0
    if str(row.get("TELNO") or "").strip():
        score += 5.0
    if _safe_int(row.get("GSRM_CNT")) or _safe_int(row.get("KSRM_CNT")) or _safe_int(row.get("WSRM_CNT")):
        score += 6.0
    if _safe_int(row.get("FIEX_NUM")) or _safe_int(row.get("SNGL_ALRMTYP_SENSO_NUM")):
        score += 5.0

    # 최근 인허가/갱신 숙소 우대 (현업 운영 확률이 훨씬 높음)
    lic_ymd = re.sub(r"[^\d]", "", _first(row, DATE_KEYS))
    if len(lic_ymd) >= 4:
        yr = int(lic_ymd[:4])
        if yr >= 2022:
            score += 12.0
        elif yr >= 2018:
            score += 7.0

    if license_type in ("한옥체험업", "외국인관광도시민박업"):
        score += 5.0
    return score


class ExternalEnricher:
    """TourAPI(KorService2) 공식 사진 링크 + 네이버 검색 오픈 API 후기 링크 보완기 (디스크 캐시 내장)."""

    def __init__(
        self,
        cache_dir: str = "output/curated_stays_cache",
        enable_naver: bool = True,
        tour_gallery_budget: int = 240,
    ):
        self.cache_dir = cache_dir
        os.makedirs(self.cache_dir, exist_ok=True)
        self.cache_path = os.path.join(self.cache_dir, "enrichment_cache.json")
        self.gallery_cache_path = os.path.join(self.cache_dir, "tour_gallery_cache.json")
        self.catalog_path = os.path.join(self.cache_dir, "tour_stays_catalog.json")
        self._lock = threading.Lock()

        self.cache: dict[str, dict[str, Any]] = {}
        if os.path.exists(self.cache_path):
            try:
                with open(self.cache_path, encoding="utf-8") as f:
                    self.cache = json.load(f)
            except Exception:  # noqa: BLE001
                self.cache = {}

        self.tour_gallery_cache: dict[str, list[dict[str, str]]] = {}
        if os.path.exists(self.gallery_cache_path):
            try:
                with open(self.gallery_cache_path, encoding="utf-8") as f:
                    self.tour_gallery_cache = json.load(f)
            except Exception:  # noqa: BLE001
                self.tour_gallery_cache = {}

        self.tour_key = os.environ.get("TOUR_API_KEY") or os.environ.get("DATA_GO_KR_SERVICE_KEY") or ""
        self.tour_gallery_budget = tour_gallery_budget
        self.tour_gallery_calls = 0
        self._tour_quota_exhausted = False
        self._catalog_loaded = False
        self._tour_by_name: dict[tuple[str, str], dict[str, Any]] = {}
        self._tour_by_addr: dict[str, dict[str, Any]] = {}
        self._tour_by_bucket: dict[tuple[str, str], list[dict[str, Any]]] = {}

        self.naver_id = os.environ.get("NAVER_CLIENT_ID") or ""
        self.naver_secret = os.environ.get("NAVER_CLIENT_SECRET") or ""
        self.enable_naver = enable_naver and bool(self.naver_id and self.naver_secret)
        self.naver_use_hub = len(self.naver_secret) >= 20 or os.environ.get("NAVER_API_MODE", "").lower() == "hub"
        self.naver_image_enabled: bool | None = None  # 첫 호출 시 자동 감지
        self._dirty = 0
        self._gallery_dirty = 0

    def save_cache(self) -> None:
        with self._lock:
            if self._dirty:
                tmp = self.cache_path + ".tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(self.cache, f, ensure_ascii=False, indent=2)
                os.replace(tmp, self.cache_path)
                self._dirty = 0
            if self._gallery_dirty:
                gtmp = self.gallery_cache_path + ".tmp"
                with open(gtmp, "w", encoding="utf-8") as f:
                    json.dump(self.tour_gallery_cache, f, ensure_ascii=False, indent=2)
                os.replace(gtmp, self.gallery_cache_path)
                self._gallery_dirty = 0

    def ensure_tour_catalog(self) -> None:
        """한국관광공사 KorService2/searchStay2 사진 보유 숙소 전체 카탈로그를 일괄 로드·캐싱한다 (최초 7회 호출)."""
        if self._catalog_loaded or not self.tour_key:
            return
        self._catalog_loaded = True
        items: list[dict[str, Any]] = []
        if os.path.exists(self.catalog_path):
            try:
                with open(self.catalog_path, encoding="utf-8") as f:
                    cached = json.load(f)
                if isinstance(cached, list) and cached:
                    items = cached
            except Exception:  # noqa: BLE001
                items = []

        if not items:
            url = "https://apis.data.go.kr/B551011/KorService2/searchStay2"
            for page in range(1, 12):
                params = {
                    "serviceKey": self.tour_key,
                    "numOfRows": 500,
                    "pageNo": page,
                    "MobileOS": "ETC",
                    "MobileApp": "jikstay",
                    "_type": "json",
                    "arrange": "Q",  # 대표이미지 반드시 보유한 숙소만 조회
                }
                try:
                    resp = requests.get(url, params=params, timeout=25)
                    if resp.status_code != 200:
                        break
                    body = resp.json().get("response", {}).get("body", {})
                    raw = body.get("items", {})
                    batch = (raw.get("item") if isinstance(raw, dict) else []) or []
                    if isinstance(batch, dict):
                        batch = [batch]
                    if not batch:
                        break
                    items.extend(batch)
                    if len(batch) < 500:
                        break
                except Exception:  # noqa: BLE001
                    break
            if items:
                with open(self.catalog_path, "w", encoding="utf-8") as f:
                    json.dump(items, f, ensure_ascii=False)
                print(f"[TourAPI] 한국관광공사 사진 보유 숙소 {len(items):,}개 카탈로그 캐싱 완료")

        for it in items:
            first_img = str(it.get("firstimage") or it.get("firstimage2") or "").strip()
            if not first_img.startswith("http"):
                continue
            addr1 = str(it.get("addr1") or "").strip()
            title = normalize_place_name(str(it.get("title") or ""))
            if not addr1 or not title:
                continue
            d1, _ = parse_korean_address(addr1)
            rg = classify_region_group(d1)
            prov2 = d1[:2]
            nkey = _norm_match_name(title)
            if prov2 and nkey:
                self._tour_by_name.setdefault((prov2, nkey), it)
            akey = _norm_addr_key(addr1)
            if akey:
                self._tour_by_addr.setdefault(akey, it)
            lt = TOUR_LCLS_TO_LICENSE.get(str(it.get("lclsSystm3") or "").strip())
            if rg and lt:
                self._tour_by_bucket.setdefault((rg, lt), []).append(it)

    def find_tour_match(self, name: str, addr: str, license_type: str = "") -> dict[str, Any] | None:
        self.ensure_tour_catalog()
        if not self._tour_by_name and not self._tour_by_addr:
            return None
        d1, _ = parse_korean_address(addr)
        prov2 = d1[:2]
        nkey = _norm_match_name(name)
        if prov2 and nkey and len(nkey) >= 2 and (prov2, nkey) in self._tour_by_name:
            return self._tour_by_name[(prov2, nkey)]
        akey = _norm_addr_key(addr)
        if akey and akey in self._tour_by_addr and nkey:
            cand = self._tour_by_addr[akey]
            cand_nkey = _norm_match_name(str(cand.get("title") or ""))
            # 동일 건물이라도 상호 변경(구상호 사진 오매칭)을 막기 위해 상호 핵심어가 겹칠 때만 허용
            if cand_nkey and (nkey in cand_nkey or cand_nkey in nkey):
                cand_lt = TOUR_LCLS_TO_LICENSE.get(str(cand.get("lclsSystm3") or "").strip(), "")
                if not license_type or not cand_lt or cand_lt == license_type:
                    return cand
        return None

    def get_tour_bucket_items(self, region_group: str, license_type: str) -> list[dict[str, Any]]:
        self.ensure_tour_catalog()
        return list(self._tour_by_bucket.get((region_group, license_type), []))

    def fetch_tour_detail_images(self, content_id: str, name: str) -> list[dict[str, str]]:
        """KorService2/detailImage2로 객실·내부 추가 갤러리 사진 링크를 최대 4장 더 가져온다 (캐시·일일쿼터 보호)."""
        if not content_id or not self.tour_key:
            return []
        with self._lock:
            if content_id in self.tour_gallery_cache:
                return self.tour_gallery_cache[content_id]
            if self._tour_quota_exhausted or self.tour_gallery_calls >= self.tour_gallery_budget:
                return []
            self.tour_gallery_calls += 1

        url = "https://apis.data.go.kr/B551011/KorService2/detailImage2"
        params = {
            "serviceKey": self.tour_key,
            "MobileOS": "ETC",
            "MobileApp": "jikstay",
            "_type": "json",
            "contentId": content_id,
            "imageYN": "Y",
            "numOfRows": 6,
            "pageNo": 1,
        }
        try:
            resp = requests.get(url, params=params, timeout=10)
            if resp.status_code in (403, 429) or "LIMITED_NUMBER_OF_SERVICE_REQUESTS" in resp.text:
                self._tour_quota_exhausted = True
                return []
            if resp.status_code != 200:
                return []
            items = resp.json().get("response", {}).get("body", {}).get("items", {})
            raw_list = (items.get("item") if isinstance(items, dict) else []) or []
            if isinstance(raw_list, dict):
                raw_list = [raw_list]
            extras: list[dict[str, str]] = []
            for it in raw_list:
                img_url = str(it.get("originimgurl") or it.get("smallimageurl") or "").strip()
                if not img_url.startswith("http"):
                    continue
                if img_url.startswith("http://"):
                    img_url = "https://" + img_url[len("http://"):]
                raw_caption = re.sub(r"\.[a-zA-Z0-9]{3,4}$", "", str(it.get("imgname") or "").strip())
                extras.append({
                    "url": img_url,
                    "space_tag": "객실·공간 사진",
                    "caption": raw_caption or f"{name} 상세 사진 (한국관광공사)",
                    "source": "tourapi",
                })
                if len(extras) >= 4:
                    break
            with self._lock:
                self.tour_gallery_cache[content_id] = extras
                self._gallery_dirty += 1
            return extras
        except Exception:  # noqa: BLE001
            return []

    def images_from_tour_item(
        self,
        tour_item: dict[str, Any],
        name: str,
        fetch_gallery: bool = False,
    ) -> list[dict[str, str]]:
        out: list[dict[str, str]] = []
        seen_urls: set[str] = set()
        for key in ("firstimage", "firstimage2"):
            u = str(tour_item.get(key) or "").strip()
            if u.startswith("http"):
                if u.startswith("http://"):
                    u = "https://" + u[len("http://"):]
                out.append({
                    "url": u,
                    "space_tag": "공식 대표사진",
                    "caption": f"{name} (한국관광공사 공공누리 제공)",
                    "source": "tourapi",
                })
                seen_urls.add(u)
                break
        cid = str(tour_item.get("contentid") or "").strip()
        if cid and (fetch_gallery or cid in self.tour_gallery_cache):
            for extra in self.fetch_tour_detail_images(cid, name):
                if extra["url"] not in seen_urls:
                    seen_urls.add(extra["url"])
                    out.append(extra)
                if len(out) >= 5:
                    break
        return out

    def _naver_headers(self) -> dict[str, str]:
        if self.naver_use_hub:
            return {
                "X-NCP-APIGW-API-KEY-ID": self.naver_id,
                "X-NCP-APIGW-API-KEY": self.naver_secret,
            }
        return {
            "X-Naver-Client-Id": self.naver_id,
            "X-Naver-Client-Secret": self.naver_secret,
        }

    def query_tour_images(self, name: str, depth1: str) -> list[dict[str, str]]:
        """한국관광공사 TourAPI 키가 활성화된 경우 공식 숙박 사진 URL 링크만 조회한다."""
        if not self.tour_key:
            return []
        url = "https://apis.data.go.kr/B551011/KorService2/searchKeyword2"
        params = {
            "serviceKey": self.tour_key,
            "numOfRows": 5,
            "pageNo": 1,
            "MobileOS": "ETC",
            "MobileApp": "jikstay",
            "_type": "json",
            "contentTypeId": "32",  # 숙박
            "keyword": name,
        }
        try:
            r = requests.get(url, params=params, timeout=10)
            if r.status_code != 200:
                return []
            items = (
                r.json()
                .get("response", {})
                .get("body", {})
                .get("items", {})
            )
            if not isinstance(items, dict):
                return []
            raw_list = items.get("item") or []
            if isinstance(raw_list, dict):
                raw_list = [raw_list]
            out: list[dict[str, str]] = []
            for it in raw_list:
                addr = str(it.get("addr1") or "")
                if depth1[:2] not in addr and name not in str(it.get("title") or ""):
                    continue
                for img_key in ("firstimage", "firstimage2"):
                    img_url = str(it.get(img_key) or "").strip()
                    if img_url.startswith("http"):
                        if img_url.startswith("http://"):
                            img_url = "https://" + img_url[len("http://"):]
                        out.append({
                            "url": img_url,
                            "space_tag": "공식 대표사진",
                            "caption": f"{name} (한국관광공사 공공누리 제공)",
                            "source": "tourapi",
                        })
                        break
            return out[:3]
        except Exception:  # noqa: BLE001
            return []

    def query_naver_blog(self, name: str, depth1: str, depth2: str) -> dict[str, Any]:
        """네이버 블로그 검색 오픈 API로 후기 건수·원문 아웃링크 최대 4건을 가져온다."""
        if not self.enable_naver:
            return {"total": 0, "reviews": [], "host_blog_url": ""}

        region_hint = (depth2.split(" ")[0] if depth2 else depth1[:2]).strip()
        compact_name = re.sub(r"\s+", "", name)
        stay_suffix = " 숙소" if len(compact_name) <= 4 and not any(w in name for w in ("펜션", "스테이", "호텔", "민박", "한옥", "하우스", "리조트")) else ""
        query = f'"{name}" {region_hint}{stay_suffix}'.strip()
        api_url = NAVER_BLOG_HUB_URL if self.naver_use_hub else NAVER_BLOG_LEGACY_URL
        params: dict[str, Any] = {"query": query, "display": 7, "start": 1, "sort": "sim"}
        if self.naver_use_hub:
            params["format"] = "json"

        spam_words = ("매매", "분양", "급매", "경매", "공인중개", "부동산", "원룸임대", "전세", "월세")
        try:
            resp = requests.get(api_url, headers=self._naver_headers(), params=params, timeout=8)
            if resp.status_code != 200:
                return {"total": 0, "reviews": [], "host_blog_url": ""}
            payload = resp.json()
            total = int(payload.get("total") or 0)
            reviews: list[dict[str, str]] = []
            host_blog_url = ""
            for item in payload.get("items") or []:
                title = clean_html_text(item.get("title", ""))
                desc = clean_html_text(item.get("description", ""))
                link = str(item.get("link") or "").strip()
                blogger = clean_html_text(item.get("bloggername", ""))
                postdate = str(item.get("postdate") or "").strip()
                if not link.startswith("http"):
                    continue
                if any(sw in (title + blogger) for sw in spam_words):
                    continue
                # 상호가 실제 제목·요약·블로거명에 포함되는 후기만 채택
                merged_compact = re.sub(r"\s+", "", title + desc + blogger).lower()
                if compact_name.lower() not in merged_compact:
                    continue
                if not host_blog_url and any(w in (title + desc) for w in ("예약안내", "공식", "입실", "요금안내")):
                    if name[:2] in blogger or name in title:
                        host_blog_url = link
                reviews.append({
                    "title": title[:90],
                    "summary": desc[:160],
                    "blogger_name": blogger[:40],
                    "postdate": postdate,
                    "link": link,
                })
                if len(reviews) >= 4:
                    break
            time.sleep(0.08)
            effective_total = total if reviews else 0
            return {"total": effective_total, "reviews": reviews, "host_blog_url": host_blog_url}
        except Exception:  # noqa: BLE001
            return {"total": 0, "reviews": [], "host_blog_url": ""}

    def query_naver_image_links(self, name: str, depth1: str, depth2: str) -> list[dict[str, str]]:
        """네이버 이미지 검색 오픈 API가 활성화된 앱인 경우 공개 썸네일 링크만 참조한다."""
        if not self.enable_naver or self.naver_image_enabled is False:
            return []
        region_hint = (depth2.split(" ")[0] if depth2 else depth1[:2]).strip()
        api_url = NAVER_IMAGE_HUB_URL if self.naver_use_hub else NAVER_IMAGE_LEGACY_URL
        params: dict[str, Any] = {"query": f"{region_hint} {name} 숙소", "display": 4, "sort": "sim"}
        if self.naver_use_hub:
            params["format"] = "json"
        try:
            resp = requests.get(api_url, headers=self._naver_headers(), params=params, timeout=8)
            if resp.status_code in (401, 403):
                self.naver_image_enabled = False
                return []
            if resp.status_code != 200:
                return []
            self.naver_image_enabled = True
            out: list[dict[str, str]] = []
            for it in resp.json().get("items") or []:
                # 핫링킹 차단이 적은 공식 썸네일 URL 우선, 링크만 기록
                thumb = str(it.get("thumbnail") or it.get("link") or "").strip()
                title = clean_html_text(it.get("title") or name)
                if thumb.startswith("https://"):
                    out.append({
                        "url": thumb,
                        "space_tag": "외부 검색 사진",
                        "caption": title[:60],
                        "source": "naver_image_api",
                    })
            return out[:4]
        except Exception:  # noqa: BLE001
            return []

    def enrich(
        self,
        listing_id: str,
        name: str,
        depth1: str,
        depth2: str,
        tour_item: dict[str, Any] | None = None,
        fetch_gallery: bool = False,
    ) -> dict[str, Any]:
        with self._lock:
            cached = self.cache.get(listing_id)

        if cached is not None:
            if tour_item and (not cached.get("images") or (fetch_gallery and len(cached.get("images") or []) < 2)):
                upgraded_imgs = self.images_from_tour_item(tour_item, name, fetch_gallery=fetch_gallery)
                if upgraded_imgs:
                    with self._lock:
                        cached = dict(cached, images=upgraded_imgs)
                        self.cache[listing_id] = cached
                        self._dirty += 1
            return cached

        if tour_item:
            tour_imgs = self.images_from_tour_item(tour_item, name, fetch_gallery=fetch_gallery)
        else:
            matched = self.find_tour_match(name, f"{depth1} {depth2}")
            tour_imgs = (
                self.images_from_tour_item(matched, name, fetch_gallery=fetch_gallery)
                if matched
                else []
            )

        blog_info = self.query_naver_blog(name, depth1, depth2)
        imgs = tour_imgs or self.query_naver_image_links(name, depth1, depth2)

        result = {
            "images": imgs,
            "naver_blog_total": blog_info["total"],
            "naver_reviews": blog_info["reviews"],
            "host_blog_url": blog_info["host_blog_url"],
        }
        with self._lock:
            self.cache[listing_id] = result
            self._dirty += 1
            should_flush = self._dirty >= 40
        if should_flush:
            self.save_cache()
        return result


def build_multilingual_meta(
    name: str,
    depth1: str,
    depth2: str,
    license_type: str,
    room_specs: dict[str, Any],
) -> dict[str, dict[str, str]]:
    """글로벌 게스트 및 다국어 구글 SEO를 위한 영문·일문·중문(번체) 요약 메타데이터 생성."""
    prov = PROVINCE_I18N.get(depth1, {"en": depth1, "ja": depth1, "zh": depth1})
    cat = CATEGORY_I18N.get(
        license_type,
        {
            "en": "Government-Licensed Stay",
            "ja": "政府公認宿泊施設",
            "zh": "政府合法認證住宿",
        },
    )
    rooms = room_specs.get("bedrooms")
    room_en = f" · {rooms} Rooms" if rooms else ""
    room_ja = f"・客室{rooms}室" if rooms else ""
    room_zh = f"・{rooms}間客房" if rooms else ""

    return {
        "en": {
            "title": f"{name} ({prov['en']})",
            "subtitle": f"{cat['en']}{room_en} · 0% Booking Fee Direct Stay",
            "summary": (
                f"Verified legal stay registered with local Korean authorities in {prov['en']} ({depth2}). "
                "Zero platform commission — connect directly with the property or view local reviews."
            ),
        },
        "ja": {
            "title": f"{name}（{prov['ja']}）",
            "subtitle": f"{cat['ja']}{room_ja}・仲介手数料0ウォン直取引",
            "summary": (
                f"韓国自治体の営業申告が確認された{prov['ja']}（{depth2}）の合法宿泊施設です。"
                "予約サイトの仲介手数料なしで公式窓口・現地レビューをご確認いただけます。"
            ),
        },
        "zh": {
            "title": f"{name}（{prov['zh']}）",
            "subtitle": f"{cat['zh']}{room_zh}・0%平台手續費直訂",
            "summary": (
                f"經韓國地方政府營業申報核實的{prov['zh']}（{depth2}）合法住宿。"
                "免除平台高額仲介費，可直接查看在地評價並聯繫住宿方。"
            ),
        },
    }


def build_curated_listing_doc(
    row: dict[str, Any],
    license_type: str,
    region_group: str,
    enrichment: dict[str, Any],
    curated_score: float,
) -> dict[str, Any]:
    """공공 API 행 + 외부 보완 메타데이터를 직스테이 표준 상세페이지 문서 스키마로 변환한다."""
    name = normalize_place_name(_first(row, NAME_KEYS))
    road_addr = str(row.get("ROAD_NM_ADDR") or row.get("RDN_WHL_ADDR") or "").strip()
    lot_addr = str(row.get("LOTNO_ADDR") or row.get("SITE_WHL_ADDR") or "").strip()
    primary_addr = road_addr or lot_addr or _first(row, ADDR_KEYS)
    depth1, depth2 = parse_korean_address(primary_addr)
    mng_no = str(row.get("MNG_NO") or "").strip()
    kto_cid = str(row.get("KTO_CONTENT_ID") or "").strip()
    lic_date = _first(row, DATE_KEYS)
    tel = str(row.get("TELNO") or "").strip()
    tour_item = row.get("_tour_item") if isinstance(row.get("_tour_item"), dict) else None
    if not tel and tour_item:
        tel = str(tour_item.get("tel") or "").strip()

    listing_id = make_public_listing_id(license_type, mng_no, name, primary_addr)
    room_specs, amenity_groups, flat_options = extract_public_amenities_and_specs(row, license_type, primary_addr)
    cat_meta = CATEGORY_I18N.get(license_type, {"ko_type": license_type})
    acc_type = cat_meta.get("ko_type", license_type)

    search_q = f"{depth1} {depth2} {name}".strip()
    naver_map_url = f"https://map.naver.com/p/search/{quote(f'{depth2} {name}'.strip())}"
    naver_search_url = f"https://search.naver.com/search.naver?query={quote(search_q)}"

    reviews: list[dict[str, str]] = enrichment.get("naver_reviews") or []
    blog_total = int(enrichment.get("naver_blog_total") or 0)
    images: list[dict[str, str]] = enrichment.get("images") or []
    host_blog_url = str(enrichment.get("host_blog_url") or "").strip()

    if kto_cid:
        verify_summary = f"한국관광공사(TourAPI) 등록 합법 '{license_type}' 숙박시설 (콘텐츠 #{kto_cid})"
        verify_subtitle = f"한국관광공사 국문 관광정보(콘텐츠 #{kto_cid})에 등록·검증된 합법 숙소입니다."
        license_badge_text = f"한국관광공사 등록 (#{kto_cid})"
    else:
        verify_summary = f"행정안전부 지방인허가 데이터 기준 '{license_type}' 영업/정상 확인 업소"
        has_tour_photo = any(img.get("source") == "tourapi" for img in images)
        verify_subtitle = (
            f"지자체 인허가(관리번호 {mng_no or '확인됨'}) 및 한국관광공사 공식 사진이 확인된 숙소입니다."
            if has_tour_photo
            else f"지자체 인허가 데이터(관리번호 {mng_no or '확인됨'})에서 정상 영업 상태가 확인된 숙소입니다."
        )
        license_badge_text = f"공공데이터 확인 ({mng_no[:18]})" if mng_no else "공공 인허가 영업중"

    summary_points: list[str] = [
        verify_summary,
        f"위치: {primary_addr}",
    ]
    if blog_total > 0:
        summary_points.append(f"네이버 블로그 언급·후기 {blog_total:,}건 검색됨 (원문 링크 바로가기 지원)")
    elif tel:
        summary_points.append(f"공공데이터 등록 안내 전화: {tel}")

    highlights = [
        {
            "icon_key": "verified",
            "title": f"{license_type} 공공 인허가 확인",
            "subtitle": verify_subtitle,
        },
        {
            "icon_key": "location",
            "title": f"{depth1} {depth2} 로컬 스테이",
            "subtitle": primary_addr,
        },
    ]
    if reviews:
        highlights.append({
            "icon_key": "review",
            "title": "네이버 블로그 방문 후기·소개 연결",
            "subtitle": f"실제 여행객 후기 및 안내글 {len(reviews)}건을 상세페이지에서 바로 열어볼 수 있습니다.",
        })

    editorial = (
        f"{depth1} {depth2}에 위치한 합법 등록 {license_type} '{name}'입니다. "
        "행정안전부 공공 인허가 데이터를 기반으로 선별된 숙소이며, 아래 네이버 블로그 후기 링크와 지도 바로가기를 통해 "
        "생생한 방문기와 실시간 예약 창구를 수수료 부담 없이 확인하실 수 있습니다."
    )

    i18n = build_multilingual_meta(name, depth1, depth2, license_type, room_specs)

    return {
        "listing_id": listing_id,
        "listing_tier": "public",  # 'public'(공공DB 자동선별) vs 'claimed'(호스트 직접 인증·CPC 연결)
        "is_sponsored": False,
        "cpc_balance": 0,
        "cpc_rate": 300,
        "cpc_charged_clicks": 0,
        "curated_score": round(curated_score, 1),
        "region_group": region_group,
        "status": "active",
        "title": name,
        "region_depth1": depth1,
        "region_depth2": depth2,
        "accommodation_type": acc_type,
        "capacity_standard": None,
        "capacity_max": None,
        "room_specs": room_specs,
        "editorial_story": editorial,
        "summary_points": summary_points,
        "highlights": highlights,
        "options": flat_options,
        "amenities_by_category": amenity_groups,
        "unavailable_amenities": [],
        "house_rules": {
            "check_in_time": "호스트 예약창구 확인",
            "check_out_time": "호스트 예약창구 확인",
            "smoking_policy": "객실 내 금연 권장 (숙소별 규정 확인)",
            "pet_policy": "동반 가능 여부 사전 문의 필수",
            "extra_rules": [
                "본 숙소 정보는 행정안전부 공공데이터 및 네이버 검색 공개 링크를 바탕으로 자동 구성되었습니다.",
                "이 숙소의 호스트이시라면 하단 [내 숙소 주인 등록]을 통해 공식 사진·요금·직거래 예약 링크를 무료로 직접 연결하실 수 있습니다.",
            ],
        },
        "location_info": {
            "display_address": primary_addr,
            "lot_address": lot_addr,
            "public_phone": tel,
            "nearby_spots": f"{depth1} {depth2} 일대 · 네이버 지도에서 주변 맛집·해변·교통편을 확인하세요.",
            "parking_note": "숙소별 주차 가능 여부는 네이버 플레이스 또는 호스트 문의 시 확인해 주세요.",
        },
        "pricing": {},
        "promo_title": "",
        "promo_detail": "",
        "images": images,  # Storage 파일 저장 없이 외부 URL 링크만 보관
        "naver_reviews": reviews,
        "naver_blog_total": blog_total,
        "naver_map_url": naver_map_url,
        "naver_search_url": naver_search_url,
        "source_blog_url": host_blog_url,
        "direct_booking_url": naver_map_url,  # 미인증 상태에서는 네이버 지도/플레이스 검색으로 안전 연결
        "license_type": license_type,
        "license_number": license_badge_text,
        "public_mng_no": mng_no,
        "public_licensed_at": lic_date,
        "i18n": i18n,
        "outbound_clicks": 0,
        "created_at": int(time.time() * 1000),
    }


def fetch_public_api_rows_for_province(
    license_type: str,
    province: str,
    max_pages: int = 3,
    per_page: int = 100,
    cache_dir: str = "output/curated_stays_cache",
) -> list[dict[str, Any]]:
    """행안부 공공 API에서 특정 시/도의 인허가 목록을 가져온다 (재시도 및 로컬 캐시 지원)."""
    os.makedirs(cache_dir, exist_ok=True)
    safe_key = re.sub(r"[^\w가-힣]", "_", f"{license_type}_{province}")
    cache_file = os.path.join(cache_dir, f"raw_{safe_key}.json")
    if os.path.exists(cache_file):
        try:
            with open(cache_file, encoding="utf-8") as f:
                cached = json.load(f)
            if isinstance(cached, list) and cached:
                return cached
        except Exception:  # noqa: BLE001
            pass

    base_url = _api_url(license_type)
    service_key = os.environ.get("DATA_GO_KR_SERVICE_KEY")
    if not base_url or not service_key:
        raise RuntimeError(f"{license_type}: API URL 또는 DATA_GO_KR_SERVICE_KEY 환경변수가 없습니다.")

    endpoint = base_url.rstrip("/").removesuffix("/info") + "/info"
    # '제주특별자치도' 대신 앞 2글자('제주', '강원', '부산' 등)로 조회하면 도로명 변경/약칭 행도 빠짐없이 검색됨
    addr_prefix = province[:2]
    collected: list[dict[str, Any]] = []

    for page in range(1, max_pages + 1):
        params = {
            "serviceKey": service_key,
            "pageNo": page,
            "numOfRows": per_page,
            "returnType": "json",
            "cond[ROAD_NM_ADDR::LIKE]": addr_prefix,
        }
        batch: list[dict[str, Any]] | None = None
        for attempt in range(3):
            try:
                resp = requests.get(endpoint, params=params, timeout=35)
                if resp.status_code == 200:
                    batch = _find_rows(resp.json())
                    break
            except requests.RequestException as exc:
                if attempt == 2:
                    print(f"  [경고] {license_type} / {province} p{page} 시간초과·연결실패: {str(exc)[:90]}")
                else:
                    time.sleep(1.5 * (attempt + 1))
        if not batch:
            break
        collected.extend(batch)
        if len(batch) < per_page:
            break
        time.sleep(0.15)

    if collected:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(collected, f, ensure_ascii=False)
    return collected


def load_csv_rows(csv_path: str) -> list[dict[str, Any]]:
    for enc in ("utf-8-sig", "cp949", "utf-8"):
        try:
            with open(csv_path, encoding=enc, newline="") as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    return []


def curate_bucket(
    raw_rows: list[dict[str, Any]],
    region_group: str,
    license_type: str,
    per_bucket: int,
    enricher: ExternalEnricher,
) -> list[dict[str, Any]]:
    """단일 (권역 × 업종) 버킷에서 중복·폐업을 제거하고 점수 상위 N개 숙소를 완성한다."""
    seen: set[str] = set()
    seen_norm_names: set[str] = set()
    matched_tour_cids: set[str] = set()
    preliminary: list[tuple[float, dict[str, Any], str, str]] = []

    for row in raw_rows:
        if not is_active_row(row):
            continue
        name = normalize_place_name(_first(row, NAME_KEYS))
        addr = str(row.get("ROAD_NM_ADDR") or row.get("LOTNO_ADDR") or _first(row, ADDR_KEYS)).strip()
        if not name or not addr:
            continue
        depth1, _ = parse_korean_address(addr)
        if classify_region_group(depth1) != region_group:
            continue

        mng_no = str(row.get("MNG_NO") or "").strip()
        dedup_key = mng_no or f"{name}|{addr}"
        if dedup_key in seen:
            continue
        seen.add(dedup_key)

        b_score = base_quality_score(row, name, addr, license_type)
        if b_score < 0:
            continue

        tour_match = enricher.find_tour_match(name, addr, license_type)
        row_copy = dict(row)
        if tour_match:
            row_copy["_tour_item"] = tour_match
            b_score += 65.0  # 행안부 인허가 + 한국관광공사 공식 사진 동시 보유 최우선
            cid = str(tour_match.get("contentid") or "").strip()
            if cid:
                matched_tour_cids.add(cid)

        seen_norm_names.add(f"{depth1[:2]}|{_norm_match_name(name)}")
        preliminary.append((b_score, row_copy, name, addr))

    # 행안부 샘플 페이지(시/도별 앞 페이지) 밖의 한국관광공사 공식 사진 보유 합법 숙소 보강
    for t_item in enricher.get_tour_bucket_items(region_group, license_type):
        cid = str(t_item.get("contentid") or "").strip()
        if cid and cid in matched_tour_cids:
            continue
        t_name = normalize_place_name(str(t_item.get("title") or ""))
        t_addr = f"{str(t_item.get('addr1') or '').strip()} {str(t_item.get('addr2') or '').strip()}".strip()
        if not t_name or not t_addr:
            continue
        t_d1, _ = parse_korean_address(t_addr)
        norm_pair = f"{t_d1[:2]}|{_norm_match_name(t_name)}"
        if norm_pair in seen_norm_names:
            continue
        t_row: dict[str, Any] = {
            "BPLC_NM": t_name,
            "ROAD_NM_ADDR": t_addr,
            "TELNO": str(t_item.get("tel") or "").strip(),
            "SALS_STTS_NM": "영업/정상",
            "MNG_NO": f"KTO-{cid}" if cid else "",
            "KTO_CONTENT_ID": cid,
            "LCPMT_YMD": str(t_item.get("modifiedtime") or "")[:8],
            "_tour_item": t_item,
        }
        b_score = base_quality_score(t_row, t_name, t_addr, license_type)
        if b_score < 0:
            continue
        seen_norm_names.add(norm_pair)
        preliminary.append((b_score + 50.0, t_row, t_name, t_addr))

    # 1차 공공데이터·공식사진 충실도 상위 (per_bucket * 1.25)개만 외부 검색 보완하여 API 호출량을 아낀다.
    preliminary.sort(key=lambda x: x[0], reverse=True)
    shortlist = preliminary[: max(per_bucket, int(per_bucket * 1.25))]

    def _enrich_candidate(idx_and_cand: tuple[int, tuple[float, dict[str, Any], str, str]]) -> tuple[float, dict[str, Any]]:
        rank_idx, (b_score, row_item, name, addr) = idx_and_cand
        depth1, depth2 = parse_korean_address(addr)
        mng_no = str(row_item.get("MNG_NO") or "").strip()
        lid = make_public_listing_id(license_type, mng_no, name, addr)
        tour_item = row_item.get("_tour_item") if isinstance(row_item.get("_tour_item"), dict) else None
        enrichment = enricher.enrich(
            lid,
            name,
            depth1,
            depth2,
            tour_item=tour_item,
            fetch_gallery=(rank_idx < 12),
        )

        final_score = b_score
        if enrichment.get("images"):
            final_score += 50.0
            if len(enrichment.get("images") or []) >= 2:
                final_score += 10.0
        blog_total = int(enrichment.get("naver_blog_total") or 0)
        if blog_total >= 20:
            final_score += 30.0
        elif blog_total >= 5:
            final_score += 20.0
        elif blog_total >= 1:
            final_score += 10.0
        if enrichment.get("host_blog_url"):
            final_score += 20.0

        doc = build_curated_listing_doc(row_item, license_type, region_group, enrichment, final_score)
        return (final_score, doc)

    with ThreadPoolExecutor(max_workers=4) as pool:
        scored_docs = list(pool.map(_enrich_candidate, enumerate(shortlist)))

    enricher.save_cache()
    scored_docs.sort(key=lambda x: x[0], reverse=True)
    return [doc for _, doc in scored_docs[:per_bucket]]


def build_lightweight_index_entry(doc: dict[str, Any]) -> dict[str, Any]:
    """웹앱 초기 목록·지도 탐색용 초경량 색인 항목 (~80% 용량 절감: 상세 필드는 상세페이지 진입 시 단건 조회)."""
    imgs = doc.get("images") or []
    first_img = [{"url": imgs[0]["url"]}] if imgs and imgs[0].get("url") else []
    specs = doc.get("room_specs") or {}
    compact_specs = {"bedrooms": specs["bedrooms"]} if specs.get("bedrooms") else {}
    points = doc.get("summary_points") or []
    short_point = [points[1] if len(points) > 1 else points[0]] if points else []
    lat, lng, approx = infer_stay_coords(doc)
    prov = normalize_province_short(str(doc.get("region_depth1") or ""), str(doc.get("region_depth2") or ""))

    entry: dict[str, Any] = {
        "listing_id": doc["listing_id"],
        "title": doc["title"],
        "province": prov,
        "region_depth1": doc["region_depth1"],
        "region_depth2": doc["region_depth2"],
        "lat": round(lat, 5),
        "lng": round(lng, 5),
        "license_type": doc["license_type"],
        "curated_score": doc.get("curated_score", 0),
    }
    if doc.get("listing_tier") and doc.get("listing_tier") != "public":
        entry["listing_tier"] = doc["listing_tier"]
    if doc.get("accommodation_type"):
        entry["accommodation_type"] = doc["accommodation_type"]
    if short_point:
        entry["summary_points"] = short_point
    if first_img:
        entry["images"] = first_img
    if approx:
        entry["approx_coord"] = True
    if compact_specs:
        entry["room_specs"] = compact_specs
    if doc.get("pricing"):
        entry["pricing"] = doc["pricing"]
    if doc.get("is_sponsored"):
        entry["is_sponsored"] = True
    if doc.get("promo_title"):
        entry["promo_title"] = doc["promo_title"]
    direct_url = str(doc.get("direct_booking_url") or "")
    if direct_url and not direct_url.startswith("https://map.naver.com/p/search/"):
        entry["direct_booking_url"] = direct_url
    naver_url = str(doc.get("naver_map_url") or "")
    if naver_url and not naver_url.startswith("https://map.naver.com/p/search/"):
        entry["naver_map_url"] = naver_url
    if doc.get("outbound_clicks"):
        entry["outbound_clicks"] = doc["outbound_clicks"]
    if doc.get("review_count"):
        entry["review_count"] = doc["review_count"]
        entry["score_sum"] = doc.get("score_sum", 0)
    return entry


def upload_curated_to_firestore(docs: list[dict[str, Any]]) -> tuple[int, int]:
    """선별된 공공 숙소를 Firestore listings에 업서트한다. 누적 클릭·사용자 별점 집계는 기존 값을 보존한다."""
    from firebase_admin import firestore

    from firebase_client import db

    col = db().collection("listings")
    upserted = 0
    skipped_claimed = 0

    # 배치 단위(최대 400개) 처리
    chunk_size = 200
    for i in range(0, len(docs), chunk_size):
        chunk = docs[i : i + chunk_size]
        refs = [col.document(d["listing_id"]) for d in chunk]
        existing_snaps = db().get_all(refs)
        existing_map = {s.id: s.to_dict() for s in existing_snaps if s.exists}

        batch = db().batch()
        ops = 0
        for d in chunk:
            lid = d["listing_id"]
            prev = existing_map.get(lid)
            if prev and (prev.get("listing_tier") == "claimed" or prev.get("application_id")):
                skipped_claimed += 1
                continue
            payload = dict(d)
            if prev:
                # 누적 클릭수·사용자 별점 합산·생성일시는 기존 값 유지
                payload["outbound_clicks"] = prev.get("outbound_clicks", 0)
                if prev.get("review_count") is not None:
                    payload["review_count"] = prev.get("review_count", 0)
                if prev.get("score_sum") is not None:
                    payload["score_sum"] = prev.get("score_sum", 0)
                if prev.get("last_review_id"):
                    payload["last_review_id"] = prev["last_review_id"]
                payload["created_at"] = prev.get("created_at", firestore.SERVER_TIMESTAMP)
            else:
                payload["created_at"] = firestore.SERVER_TIMESTAMP
            batch.set(col.document(lid), payload, merge=True)
            ops += 1
            upserted += 1
        if ops > 0:
            batch.commit()

    return upserted, skipped_claimed


def run_curation(
    regions: list[str] | None = None,
    categories: list[str] | None = None,
    per_bucket: int = 100,
    max_pages_per_province: int = 3,
    enable_naver: bool = True,
    csv_map: dict[str, str] | None = None,
    out_json: str = "output/curated_stays.json",
    index_json: str = "app/web/data/public_stays_index.json",
    upload: bool = False,
) -> list[dict[str, Any]]:
    target_regions = regions or list(REGION_GROUPS.keys())
    target_categories = categories or list(LICENSE_CATEGORIES)
    enricher = ExternalEnricher(enable_naver=enable_naver)

    all_curated: list[dict[str, Any]] = []
    csv_cache: dict[str, list[dict[str, Any]]] = {}

    for cat in target_categories:
        if csv_map and csv_map.get(cat) and os.path.exists(csv_map[cat]):
            print(f"[CSV 로드] {cat}: {csv_map[cat]}")
            csv_cache[cat] = load_csv_rows(csv_map[cat])

        for reg in target_regions:
            provinces = REGION_GROUPS.get(reg, [])
            if not provinces:
                continue

            if cat in csv_cache:
                raw_rows = csv_cache[cat]
            else:
                raw_rows = []
                pages_each = max(1, max_pages_per_province if len(provinces) <= 2 else min(max_pages_per_province, 2))
                with ThreadPoolExecutor(max_workers=3) as prov_pool:
                    prov_batches = list(
                        prov_pool.map(
                            lambda p: fetch_public_api_rows_for_province(cat, p, max_pages=pages_each),
                            provinces,
                        )
                    )
                for rows in prov_batches:
                    raw_rows.extend(rows)

            selected = curate_bucket(raw_rows, reg, cat, per_bucket, enricher)
            photo_cnt = sum(1 for d in selected if d.get("images"))
            print(
                f"[선별 완료] {reg} × {cat}: 행안부 {len(raw_rows)}건+TourAPI 결합 → "
                f"정예 {len(selected)}곳 확정 (공식사진 링크 {photo_cnt}곳)"
            )
            all_curated.extend(selected)

    os.makedirs(os.path.dirname(os.path.abspath(out_json)), exist_ok=True)
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(all_curated, f, ensure_ascii=False, indent=2)
    print(f"\n상세 결과 저장: {out_json} (총 {len(all_curated)}곳)")

    if index_json:
        os.makedirs(os.path.dirname(os.path.abspath(index_json)), exist_ok=True)
        lightweight = [build_lightweight_index_entry(d) for d in all_curated]
        with open(index_json, "w", encoding="utf-8") as f:
            json.dump({"updated_at": int(time.time() * 1000), "items": lightweight}, f, ensure_ascii=False)
        print(f"웹 경량 색인 저장: {index_json} ({len(lightweight)}곳)")

    if upload and all_curated:
        upserted, skipped = upload_curated_to_firestore(all_curated)
        print(f"Firestore 반영 완료: 업서트 {upserted}곳 (호스트 클레임 보존 {skipped}곳)")

    return all_curated


def main() -> None:
    parser = argparse.ArgumentParser(description="공공 인허가 API + 네이버 검색 보완 지역·업종별 100선 큐레이션")
    parser.add_argument("--regions", default="", help="쉼표 구분 권역 (예: 제주,강원). 비우면 5대 권역 전체")
    parser.add_argument("--categories", default="", help="쉼표 구분 업종. 비우면 4대 업종 전체")
    parser.add_argument("--per-bucket", type=int, default=100, help="권역×업종당 최대 선별 수 (기본 100)")
    parser.add_argument("--max-pages", type=int, default=3, help="시/도당 공공 API 조회 최대 페이지 수")
    parser.add_argument("--skip-naver", action="store_true", help="네이버 검색 오픈 API 보완 생략")
    parser.add_argument("--out", default="output/curated_stays.json", help="상세 결과 JSON 경로")
    parser.add_argument("--index-out", default="app/web/data/public_stays_index.json", help="웹 경량 색인 JSON 경로")
    parser.add_argument("--upload", action="store_true", help="선별 결과를 Firestore listings에 일괄 반영")
    args = parser.parse_args()

    regions = [r.strip() for r in args.regions.split(",") if r.strip()] or None
    categories = [c.strip() for c in args.categories.split(",") if c.strip()] or None

    run_curation(
        regions=regions,
        categories=categories,
        per_bucket=args.per_bucket,
        max_pages_per_province=args.max_pages,
        enable_naver=not args.skip_naver,
        out_json=args.out,
        index_json=args.index_out,
        upload=args.upload,
    )


if __name__ == "__main__":
    main()
