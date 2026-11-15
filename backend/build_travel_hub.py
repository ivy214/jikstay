"""한국관광공사 TourAPI(KorService2) + 공공 매거진 + 반값여행·외국인 혜택 통합 허브 빌더 및 숙소 상세 보강기.

활용 공공 API (모두 이미 승인된 키만 사용, 일일 트래픽 1,000건 한도 안전 준수):
1. KorService2/searchFestival2    : 현재 진행중·예정인 전국 지역 축제·행사 포스터 및 일정
2. KorService2/areaBasedList2(25) : 한국관광공사 공식 추천 여행코스 매거진
3. KorService2/detailCommon2      : 여행코스 개요 및 상위 숙소 공식 에디토리얼 소개글·홈페이지
4. KorService2/detailInfo2(25)    : 여행코스 세부 경유지(1코스 → 2코스 → 3코스)
5. KorService2/detailIntro2(32)   : 상위 숙소 실제 체크인/아웃 시간·취사·주차·부대시설
6. KorService2/locationBasedList2 : 상위 숙소 반경 5km 내 공식 관광명소·맛집·체험 추천
7. 네이버 블로그 검색 Open API    : 반값여행·지자체 숙박할인·체류지원 최신 신청 가이드 링크

실행:
  backend\\.venv\\Scripts\\python -u backend\\build_travel_hub.py --enrich-stays --upload
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
import html
import json
import os
import re
import threading
import time
from typing import Any
from urllib.parse import quote

import requests

import env  # noqa: F401
from curate_public_stays import (
    NAVER_BLOG_HUB_URL,
    NAVER_BLOG_LEGACY_URL,
    PROVINCE_17_ORDER,
    PROVINCE_CENTROIDS,
    build_lightweight_index_entry,
    classify_region_group,
    clean_html_text,
    normalize_place_name,
    normalize_province_short,
    parse_korean_address,
)

CONTENT_TYPE_LABELS: dict[str, str] = {
    "12": "관광명소",
    "14": "문화·전시",
    "15": "축제·행사",
    "25": "여행코스",
    "28": "레포츠·체험",
    "38": "전통시장·쇼핑",
    "39": "맛집·카페",
}

# 2026 문체부·한국관광공사·지자체 '대한민국 반값여행(지역사랑 휴가지원 50% 환급)' 25개 대상 지역
HALF_PRICE_REGIONS: list[dict[str, Any]] = [
    {
        "region_group": "강원",
        "cities": ["평창", "영월", "횡성", "화천"],
        "benefit_ko": "여행경비 50% 지역화폐 환급 (1인 최대 10만원 · 2인 이상 최대 20만원)",
        "benefit_en": "50% Travel Expense Cashback (Local Voucher) + Digital Tourist ID up to 50% instant discount",
    },
    {
        "region_group": "전라/충청",
        "cities": ["강진", "해남", "완도", "고흥", "영광", "영암", "장흥", "고창", "제천", "태안", "서천"],
        "benefit_ko": "여행경비 50% 환급 (청년 일부 지역 최대 70%) · 합법 숙소 영수증 필수",
        "benefit_en": "50% Local Stay & Dining Cashback + K-Tourism Digital Pass partner discounts",
    },
    {
        "region_group": "부산/경상",
        "cities": ["남해", "하동", "밀양", "합천", "거창", "고성", "산청", "함양", "안동", "영천"],
        "benefit_ko": "여행 전 사전신청 필수 · 숙박·식비·체험 영수증 정산 후 모바일 상품권 지급",
        "benefit_en": "Pre-registration Local Travel Subsidy + Historic Hanok & Countryside Stay Perks",
    },
]

# 외국인 관광객 & 내국인 공통 공공 혜택 카드 (4개 국어)
GLOBAL_BENEFIT_CARDS: list[dict[str, Any]] = [
    {
        "id": "k_digital_pass",
        "badge": "FOREIGNER & LOCAL · 최대 50% 즉시할인",
        "official_url": "https://korean.visitkorea.or.kr/digtCard/digt_card_intro.do",
        "ko": {
            "title": "디지털 관광주민증 (한국관광공사 공식)",
            "desc": "인구감소지역 35개+ 시·군 방문 시 숙박·관람·케이블카·체험 최대 10~50% 현장 즉시 할인! 내·외국인 모두 모바일로 무료 발급 가능합니다.",
        },
        "en": {
            "title": "K-Tourism Digital Resident Card (Official KTO Pass)",
            "desc": "Free mobile pass for international & local travelers! Get 10–50% instant discounts on stays, cable cars, museums & cafes across 35+ scenic Korean towns.",
        },
        "ja": {
            "title": "デジタル観光住民証（韓国観光公社公式パス）",
            "desc": "外国人旅行者もアプリ・Webで無料発行可能！韓国地方35以上の市・郡で宿泊・ケーブルカー・体験・カフェが最大50%即時割引になります。",
        },
        "zh": {
            "title": "數位觀光居民證（韓國觀光公社官方通行證）",
            "desc": "外國旅客亦可免費申辦！走訪韓國35個以上特色市郡，享住宿、纜車、景點門票與咖啡廳最高50%現場折扣。",
        },
    },
    {
        "id": "half_price_korea",
        "badge": "2026 정부·지자체 지원 · 50% 환급",
        "official_url": "https://korean.visitkorea.or.kr",
        "ko": {
            "title": "2026 대한민국 반값여행 (지역사랑 휴가지원 25개 지역)",
            "desc": "여행 출발 전 사전신청 후 합법 등록 숙소·식당 영수증을 제출하면 지출액의 50%(2인 최대 20만원)를 모바일 지역화폐로 돌려받습니다. (※ 미신고 불법숙소 영수증은 환급 불가!)",
        },
        "en": {
            "title": "2026 Half-Price Regional Travel & Foreigner Stay Incentives",
            "desc": "25 rural municipalities refund 50% of travel spend for pre-registered residents, while international FIT travelers enjoy regional stay vouchers & Korea Grand Sale perks. Always book licensed stays for valid receipts!",
        },
        "ja": {
            "title": "2026 半額旅行支援＆外国人自治体ステイ特典",
            "desc": "25自治体で事前申請による旅費50%還元を実施中。外国人個人旅行客(FIT)向けにも自治体宿泊クーポン・Korea Grand Sale特典が提供されます（※公認宿の領収書が必須）。",
        },
        "zh": {
            "title": "2026 韓國半價旅遊補助＆外國旅客地方住宿優惠",
            "desc": "韓國25個地方政府推出旅費50%回饋計畫，同時針對外國自由行旅客提供地方住宿券與Korea Grand Sale優惠（須入住政府合法認證民宿以取得正式收據）。",
        },
    },
    {
        "id": "tax_free_direct",
        "badge": "0% 수수료 + 외국인 면세·안심",
        "official_url": "https://english.visitkorea.or.kr",
        "ko": {
            "title": "수수료 0원 합법 한옥·농어촌민박 직거래 꿀팁",
            "desc": "해외 OTA 중개수수료(약 14~17%) 없이 호스트 공식 예약창구로 직결됩니다. 지자체 영업신고가 확인된 숙소만 선별해 바가지요금·불법숙소 걱정이 없습니다.",
        },
        "en": {
            "title": "Save ~15% OTA Fees + Verified Legal Hanok & City Homestays",
            "desc": "Connect directly with government-licensed Hanok stays and Foreigner City Homestays (외국인관광도시민박업) with 0% platform commission and pre-written Korean/English inquiry templates.",
        },
        "ja": {
            "title": "仲介手数料0%・自治体認可済みの韓屋＆都市民泊直取引",
            "desc": "予約サイトの手数料（約15%）を節約し、韓国語＋日本語自動翻訳テンプレートでオーナー公式窓口へそのまま問い合わせできます。",
        },
        "zh": {
            "title": "省下約15%平台手續費・合法韓屋與外國人都市民泊直訂",
            "desc": "免除訂房網站高額手續費，內建韓文＋繁體中文雙語自動詢問範本，一鍵複製即可直接聯繫韓國民宿主人。",
        },
    },
]

# 정부·공공기관·광역지자체 공식 발행 매거진/웹진 열람 디렉토리 (공공누리 공개 웹진)
PUBLIC_MAGAZINES: list[dict[str, str]] = [
    {
        "publisher": "문화체육관광부",
        "title": "대한민국 정책주간지 《K-공감》 e-Book·웹진",
        "region_group": "전체",
        "desc": "정부가 매주 발행하는 공식 시사·생활정책·로컬 여행 교양잡지 무료 열람",
        "url": "https://gonggam.korea.kr",
        "lang_badge": "KO",
    },
    {
        "publisher": "한국관광공사",
        "title": "대한민국 구석구석 《여행기사 & 월간 테마매거진》",
        "region_group": "전체",
        "desc": "전국 숨은 로컬 명소, 계절별 축제, 반값여행·디지털 관광주민증 공식 특집호",
        "url": "https://korean.visitkorea.or.kr/list/travelinfo.do?service=ms",
        "lang_badge": "KO",
    },
    {
        "publisher": "Korea Tourism Organization",
        "title": "VisitKorea Global Travel Magazine & Travel News",
        "region_group": "전체",
        "desc": "Official multilingual travel articles, seasonal guides, K-food & Hanok stay stories for international visitors",
        "url": "https://english.visitkorea.or.kr",
        "lang_badge": "EN · JA · ZH",
    },
    {
        "publisher": "제주관광공사",
        "title": "비짓제주 《제주 테마여행 매거진 & 마을여행》",
        "region_group": "제주",
        "desc": "제주특별자치도 공식 발행 계절별 로컬 마을 체류·오름·해안도로 큐레이션 웹진",
        "url": "https://www.visitjeju.net/kr/thememap",
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "publisher": "강원관광재단",
        "title": "강원관광 《이달의 추천 여행지 & 워케이션 가이드》",
        "region_group": "강원",
        "desc": "강원특별자치도 18개 시·군 계절 명소·전통시장·체류형 관광 공식 소식지",
        "url": "https://www.visitgangwon.or.kr",
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "publisher": "부산관광공사",
        "title": "비짓부산 《테마여행 & 미식 매거진》",
        "region_group": "부산/경상",
        "desc": "해운대·송정·영도·기장 로컬 여행기 및 비짓부산패스 외국인 혜택 안내",
        "url": "https://www.visitbusan.net",
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "publisher": "전라남도·전남관광재단",
        "title": "남도여행길잡이 《남도 여행 e-북·가이드북 열람관》",
        "region_group": "전라/충청",
        "desc": "강진 반값여행·여수·순천·해남·완도 공식 관광 안내책자 PDF/e-Book 무료 열람",
        "url": "https://www.namdokorea.com",
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "publisher": "서울관광재단",
        "title": "Visit Seoul 《서울 공식 관광 e-가이드북 & 한옥·동네 매거진》",
        "region_group": "서울/경기",
        "desc": "북촌·서촌 한옥체험, 서울 외곽 근교 여행 및 다국어 공식 가이드북 열람",
        "url": "https://korean.visitseoul.net/map-guide-book",
        "lang_badge": "KO · EN · JA · ZH",
    },
]

# 전국 17개 시·도 균등 공식 관광안내도·가이드북(PDF / E-book) 디렉토리 (회원가입 없이 즉시 열람)
MUNICIPAL_EBOOKS: list[dict[str, Any]] = [
    {
        "id": "ebook_seoul",
        "province": "서울",
        "city": "서울 전역",
        "title": "Visit Seoul 공식 관광안내지도 & 테마 e-가이드북",
        "materials": "서울 종합 관광지도 PDF · 북촌/서촌 한옥 도보지도 · 미식 가이드북",
        "url": "https://korean.visitseoul.net/map-guide-book",
        "lat": 37.5665,
        "lng": 126.9780,
        "themes": ["도보여행", "미식", "역사·한옥"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_busan",
        "province": "부산",
        "city": "부산 전역",
        "title": "비짓부산 공식 관광지도 & 로컬 미식·해안열차 가이드북",
        "materials": "부산 종합 관광안내도 PDF · 미식 가이드북 · 갈맷길 트레킹 지도",
        "url": "https://www.visitbusan.net/index.do?menuCd=DOM_000000204009000000",
        "lat": 35.1796,
        "lng": 129.0756,
        "themes": ["오션뷰·해변", "로컬맛집", "트레킹"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_daegu",
        "province": "대구",
        "city": "대구 전역",
        "title": "대구트립로드 공식 관광안내지도 & 근대골목 E-book",
        "materials": "대구 종합 관광지도 PDF · 근대골목 투어 리플릿 · 팔공산 산행지도",
        "url": "https://tour.daegu.go.kr/index.do?menu_id=00002942",
        "lat": 35.8714,
        "lng": 128.6014,
        "themes": ["근대골목", "먹거리골목", "산행"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_incheon",
        "province": "인천",
        "city": "인천·강화·옹진",
        "title": "인천투어 공식 가이드북 & 강화·섬여행 관광안내도",
        "materials": "인천 종합 관광지도 PDF · 개항장 도보지도 · 인천 섬여행 가이드북",
        "url": "https://itour.incheon.go.kr/NTK_10000/main.do",
        "lat": 37.4563,
        "lng": 126.7052,
        "themes": ["섬·바다", "개항장", "캠핑"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_gwangju",
        "province": "광주",
        "city": "광주 전역",
        "title": "오매광주 문화관광 가이드북 & 양림동·미식 안내도",
        "materials": "광주 종합 관광지도 PDF · 예술·양림동 골목지도 · 남도미식 책자",
        "url": "https://tour.gwangju.go.kr/home/sub.cs?m=69",
        "lat": 35.1595,
        "lng": 126.8526,
        "themes": ["예술·전시", "남도미식", "도보코스"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_daejeon",
        "province": "대전",
        "city": "대전 전역",
        "title": "대전관광 공식 관광안내지도 & 빵지순례·과학여행 리플릿",
        "materials": "대전 종합 관광안내도 PDF · 빵집 지도 · 대청호 오백리길 가이드",
        "url": "https://www.daejeontour.co.kr/ko/page.do?menuIdx=159",
        "lat": 36.3504,
        "lng": 127.3845,
        "themes": ["빵지순례", "호수둘레길", "온천"],
        "lang_badge": "KO · EN",
    },
    {
        "id": "ebook_ulsan",
        "province": "울산",
        "city": "울산·울주",
        "title": "울산관광 가이드북 & 영남알프스·태화강 관광안내도 E-book",
        "materials": "울산 종합 관광지도 PDF · 영남알프스 등산지도 · 해안 드라이브 책자",
        "url": "https://tour.ulsan.go.kr/index.ulsan?menuCd=DOM_000000105002000000",
        "lat": 35.5384,
        "lng": 129.3114,
        "themes": ["등산·트레킹", "국가정원", "해안드라이브"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_sejong",
        "province": "세종",
        "city": "세종 전역",
        "title": "세종시 공식 관광안내지도 & 수목원·호수공원 나들이 책자",
        "materials": "세종 관광안내지도 PDF · 국립세종수목원·금강보행교 코스 가이드",
        "url": "https://www.sejong.go.kr/tour/sub04_02.do",
        "lat": 36.4800,
        "lng": 127.2890,
        "themes": ["수목원·정원", "가족나들이", "자전거길"],
        "lang_badge": "KO",
    },
    {
        "id": "ebook_gyeonggi",
        "province": "경기",
        "city": "가평·양평·수원·파주 등 31개 시군",
        "title": "경기관광포털 시·군별 공식 가이드북 & 경기둘레길 지도",
        "materials": "경기도 종합 관광지도 PDF · 경기둘레길 60코스북 · 캠핑·계곡 리플릿",
        "url": "https://ggtour.or.kr/travel-info/guidebook",
        "lat": 37.4138,
        "lng": 127.5183,
        "themes": ["둘레길", "캠핑·차박", "근교여행"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_gangwon",
        "province": "강원",
        "city": "강릉·속초·평창·영월 등 18개 시군",
        "title": "강원관광 18개 시·군 공식 관광지도 & 트레킹·해변 E-book",
        "materials": "강원 종합 관광안내도 PDF · 바우길/해파랑길 지도 · 반값여행 안내서",
        "url": "https://www.visitgangwon.or.kr/kor/guide/bookList.do",
        "lat": 37.8228,
        "lng": 128.1555,
        "themes": ["동해바다", "숲길·트레킹", "워케이션"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_chungbuk",
        "province": "충북",
        "city": "단양·제천·청주·충주 등 11개 시군",
        "title": "충북나드리 공식 관광지도 & 청풍호·소백산 여행 E-book",
        "materials": "충북 종합 관광안내도 PDF · 단양·제천 호수길 코스북 · 맛집 가이드",
        "url": "https://tour.chungbuk.go.kr/www/selectBbsNttList.do?bbsNo=34&key=213",
        "lat": 36.6357,
        "lng": 127.4914,
        "themes": ["호수·계곡", "단풍·산행", "치유여행"],
        "lang_badge": "KO · EN",
    },
    {
        "id": "ebook_chungnam",
        "province": "충남",
        "city": "태안·보령·공주·부여·서천 등 15개 시군",
        "title": "충남문화관광 공식 관광안내도 & 서해랑길·백제역사 가이드북",
        "materials": "충남 종합 관광지도 PDF · 태안 해변길 지도 · 백제문화권 E-book",
        "url": "https://tour.chungnam.go.kr/html/kr/guide/guide_04.html",
        "lat": 36.6588,
        "lng": 126.6728,
        "themes": ["서해낙조", "백제역사", "갯벌·캠핑"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_jeonbuk_eco",
        "province": "전북",
        "city": "전주·무주·진안·장수 등 14개 시군",
        "title": "전북생태관광 · 천리길 공식 가이드북 E-Book & 종합지도",
        "materials": "전북생태관광_가이드북.pdf · 전북 천리길 44개 노선도 · 생태명소 리플릿",
        "url": "https://www.jb-ecotour.org/bbs/board1/3271",
        "pdf_links": [
            {"label": "📖 생태관광 가이드북 E-Book", "label_en": "📖 Eco-Tour Guide PDF", "url": "https://www.jb-ecotour.org/bbs/board1/3271"},
            {"label": "🥾 전북 천리길 노선 안내", "label_en": "🥾 Jeonbuk Trail Portal", "url": "https://www.jb-ecotour.org/"},
        ],
        "lat": 35.8203,
        "lng": 127.1088,
        "themes": ["생태관광", "천리길트레킹", "한옥·미식"],
        "lang_badge": "KO",
    },
    {
        "id": "ebook_jeonbuk_muju",
        "province": "전북",
        "city": "무주군",
        "title": "자연특별시 무주군 공식 관광안내도 & 구천동·덕유산 트레킹 지도",
        "materials": "무주군 종합 관광안내도 고화질 PDF · 구천동 어사길 트레킹 지도 · 명소 리플릿",
        "url": "https://tour.muju.go.kr/tour/contents.do?key=109",
        "pdf_links": [
            {"label": "🗺️ 무주 관광안내도 PDF", "label_en": "🗺️ Muju Tourist Map PDF", "url": "https://tour.muju.go.kr/tour/contents.do?key=109"},
            {"label": "🏛️ 자연특별시 무주 문화관광", "label_en": "🏛️ Muju Tour Portal", "url": "https://tour.muju.go.kr/"},
        ],
        "lat": 36.0068,
        "lng": 127.6608,
        "themes": ["덕유산트레킹", "구천동계곡", "반딧불생태"],
        "lang_badge": "KO",
    },
    {
        "id": "ebook_jeonbuk_jinan",
        "province": "전북",
        "city": "진안군",
        "title": "진안군 종합 가이드북 《진안고원여행》 E-book & 관광지도",
        "materials": "《진안고원여행》 12개 테마 E-book · 마이산·용담호·홍삼스파 관광지도 PDF",
        "url": "https://tour.jinan.go.kr/index.jinan?menuCd=DOM_000000205003000000",
        "pdf_links": [
            {"label": "📖 《진안고원여행》 E-book·지도", "label_en": "📖 Jinan Guidebook & Map", "url": "https://tour.jinan.go.kr/index.jinan?menuCd=DOM_000000205003000000"},
            {"label": "🏛️ 진안군 문화관광 포털", "label_en": "🏛️ Jinan Tour Portal", "url": "https://tour.jinan.go.kr/"},
        ],
        "lat": 35.7917,
        "lng": 127.4248,
        "themes": ["마이산", "진안고원길", "홍삼·치유"],
        "lang_badge": "KO",
    },
    {
        "id": "ebook_jeonbuk_jangsu",
        "province": "전북",
        "city": "장수군",
        "title": "장수군청 공식 관광안내도 & 종합 안내책자 《장수여행》 PDF",
        "materials": "고화질 관광안내지도(tour_guide.pdf) · 종합 안내책자(tourist.pdf) 원본 직링크 즉시 열람",
        "url": "https://www.jangsu.go.kr/images/tour/tour_guide.pdf",
        "pdf_links": [
            {"label": "🗺️ 관광안내지도 PDF 원본", "label_en": "🗺️ Direct Tourist Map PDF", "url": "https://www.jangsu.go.kr/images/tour/tour_guide.pdf"},
            {"label": "📖 《장수여행》 안내책자 PDF", "label_en": "📖 Direct Guidebook PDF", "url": "https://www.jangsu.go.kr/images/tour/content/sub05/tourist.pdf"},
            {"label": "🏛️ 장수군 문화관광 포털", "label_en": "🏛️ Jangsu Tour Portal", "url": "https://www.jangsu.go.kr/tour/index.jangsu"},
        ],
        "lat": 35.6473,
        "lng": 127.5215,
        "themes": ["장안산·방화동", "한우·사과특산", "걷기여행"],
        "lang_badge": "KO",
    },
    {
        "id": "ebook_jeonnam",
        "province": "전남",
        "city": "여수·순천·담양·강진·해남 등 22개 시군",
        "title": "남도여행길잡이 22개 시·군 e-북 열람관 & 남도미식·섬 지도",
        "materials": "전남 권역별 관광안내지도 PDF · 남도한바퀴 코스북 · 반값여행 안내",
        "url": "https://www.namdokorea.com/site/jeonnam/tour/ebookList.do",
        "lat": 34.8161,
        "lng": 126.7629,
        "themes": ["남도맛집", "다도해·섬", "정원·사찰"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_gyeongbuk",
        "province": "경북",
        "city": "경주·안동·포항·영주·울릉 등 22개 시군",
        "title": "경북나드리 공식 관광안내지도 & 세계유산·동해안 가이드북",
        "materials": "경북 종합 관광지도 PDF · 경주·안동 한옥·서원 가이드북 · 해파랑길 지도",
        "url": "https://tour.gb.go.kr/page.do?mnu_uid=216",
        "lat": 36.4919,
        "lng": 128.8889,
        "themes": ["세계문화유산", "전통한옥", "동해안일출"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_gyeongnam",
        "province": "경남",
        "city": "남해·통영·거제·하동·산청 등 18개 시군",
        "title": "경남관광길잡이 공식 관광홍보물 & 남해안 아일랜드 하이웨이 지도",
        "materials": "경남 종합 관광안내도 PDF · 지리산 둘레길/남파랑길 책자 · 반값여행 가이드",
        "url": "https://tour.gyeongnam.go.kr/index.gyeong?menuCd=DOM_000000105004000000",
        "lat": 35.2383,
        "lng": 128.4922,
        "themes": ["남해바다", "지리산차문화", "섬트레킹"],
        "lang_badge": "KO · EN · JA · ZH",
    },
    {
        "id": "ebook_jeju",
        "province": "제주",
        "city": "제주시·서귀포시 전역",
        "title": "비짓제주 공식 제주 관광지도 PDF & 오름·올레·마을여행 가이드북",
        "materials": "제주 종합 관광안내지도 고화질 PDF · 오름·올레길 트레킹북 · 로컬 마을여행",
        "url": "https://www.visitjeju.net/kr/tourInfo/guideBook",
        "lat": 33.3846,
        "lng": 126.5535,
        "themes": ["올레·오름", "해안도로", "마을체류"],
        "lang_badge": "KO · EN · JA · ZH",
    },
]

# 전국 대표 전통 5일장 (날짜 끝자리 1·6 / 2·7 / 3·8 / 4·9 / 5·0 기준 매일 동적 장날 브리핑에 활용)
TRADITIONAL_5DAY_MARKETS: list[dict[str, Any]] = [
    {"id": "mkt_muju", "province": "전북", "city": "무주군", "title": "무주반딧불시장 5일장", "days": [1, 6], "lat": 36.0072, "lng": 127.6615, "specialty": "산채비빔밥·머루·어죽·표고버섯"},
    {"id": "mkt_danyang", "province": "충북", "city": "단양군", "title": "단양구경시장 5일장", "days": [1, 6], "lat": 36.9839, "lng": 128.3653, "specialty": "흑마늘닭강정·마늘순대·산나물"},
    {"id": "mkt_pohang_heunghae", "province": "경북", "city": "포항시", "title": "포항 흥해5일장", "days": [1, 6], "lat": 36.1095, "lng": 129.3456, "specialty": "동해 자연산 활어·시금치·국수"},
    {"id": "mkt_jeju_hallim", "province": "제주", "city": "제주시", "title": "제주 세화·대정 오일장권", "days": [1, 6], "lat": 33.2241, "lng": 126.2512, "specialty": "제주 흑돼지순대·빙떡·제철 감귤"},
    {"id": "mkt_jeongseon", "province": "강원", "city": "정선군", "title": "정선아리랑시장 5일장", "days": [2, 7], "lat": 37.3812, "lng": 128.6631, "specialty": "곤드레밥·콧등치기국수·메밀전병"},
    {"id": "mkt_jeju_folk", "province": "제주", "city": "제주시", "title": "제주민속오일시장", "days": [2, 7], "lat": 33.4979, "lng": 126.4754, "specialty": "제주 빙떡·몸국·한라봉·활어회"},
    {"id": "mkt_damyang", "province": "전남", "city": "담양군", "title": "담양 창평·담양 5일장", "days": [2, 7], "lat": 35.3211, "lng": 126.9881, "specialty": "창평국밥·대통밥·수제 찹쌀순대"},
    {"id": "mkt_hadong", "province": "경남", "city": "하동군", "title": "하동 공설·화개장터권 5일장", "days": [2, 7], "lat": 35.0674, "lng": 127.7513, "specialty": "섬진강 재첩국·참게탕·야생녹차"},
    {"id": "mkt_yangpyeong", "province": "경기", "city": "양평군", "title": "양평물맑은시장 5일장", "days": [3, 8], "lat": 37.4897, "lng": 127.4915, "specialty": "양평해장국·수제전·유기농 로컬푸드"},
    {"id": "mkt_gochang", "province": "전북", "city": "고창군", "title": "고창전통시장 5일장", "days": [3, 8], "lat": 35.4357, "lng": 126.7019, "specialty": "풍천장어·복분자·서해 갯벌 바지락"},
    {"id": "mkt_boryeong", "province": "충남", "city": "보령시", "title": "보령중앙·한내 5일장", "days": [3, 8], "lat": 36.3492, "lng": 126.5976, "specialty": "대천 김·서해 건어물·칼국수"},
    {"id": "mkt_changnyeong", "province": "경남", "city": "창녕군", "title": "창녕전통시장 5일장", "days": [3, 8], "lat": 35.5416, "lng": 128.4962, "specialty": "수구레국밥·창녕 마늘·양파전"},
    {"id": "mkt_moran", "province": "경기", "city": "성남시", "title": "성남 모란민속5일장", "days": [4, 9], "lat": 37.4310, "lng": 127.1292, "specialty": "손칼국수·수수부꾸미·전통 약초"},
    {"id": "mkt_jinan", "province": "전북", "city": "진안군", "title": "진안고원시장 5일장", "days": [4, 9], "lat": 35.7908, "lng": 127.4285, "specialty": "진안 홍삼·흑돼지국밥·고원 산나물"},
    {"id": "mkt_seogwipo", "province": "제주", "city": "서귀포시", "title": "서귀포향토오일시장", "days": [4, 9], "lat": 33.2591, "lng": 126.5754, "specialty": "모닥치기·흑돼지꼬치·천혜향"},
    {"id": "mkt_gangjin", "province": "전남", "city": "강진군", "title": "강진오일시장 (반값여행 성지)", "days": [4, 9], "lat": 34.6391, "lng": 126.7684, "specialty": "남도 한정식·병어·회춘탕·매생이"},
    {"id": "mkt_jangsu", "province": "전북", "city": "장수군", "title": "장수전통시장 5일장", "days": [5, 0], "lat": 35.6484, "lng": 127.5205, "specialty": "장수 한우국밥·장수사과·오미자"},
    {"id": "mkt_pyeongchang", "province": "강원", "city": "평창군", "title": "평창올림픽시장 5일장", "days": [5, 0], "lat": 37.3702, "lng": 128.3924, "specialty": "메밀부치기·올챙이국수·감자옹심이"},
    {"id": "mkt_suncheon_ut", "province": "전남", "city": "순천시", "title": "순천 웃장 5일장", "days": [5, 0], "lat": 34.9598, "lng": 127.4841, "specialty": "순천 웃장 국밥골목·남도 젓갈·꼬막"},
    {"id": "mkt_sehwa", "province": "제주", "city": "제주시 구좌읍", "title": "제주 세화민속오일시장", "days": [5, 0], "lat": 33.5252, "lng": 126.8569, "specialty": "구좌 당근주스·해녀 해산물·호떡"},
]

# 지자체 발행 공식 가이드북(PDF)·문화관광 누리집 원문 기반 '하루 한 편 오늘의 로컬 스토리' (계절·테마 큐레이션)
DAILY_MUNICIPAL_STORIES: list[dict[str, Any]] = [
    {
        "id": "spot_story_tteunbongsaem",
        "province": "전북",
        "city": "장수군",
        "season_badge": "🍂 가을·초겨울 생태숲길 테마",
        "source_book": "장수군청 공식 가이드북 《장수여행》 p.9 수록",
        "months": [9, 10, 11, 4, 5],
        "title": "금강첫물, 뜬봉샘 발원지",
        "subtitle": "장수군 물뿌랭이길 10-18 (금강사랑물체험관)",
        "address": "전북특별자치도 장수군 장수읍 물뿌랭이길 10-18",
        "lat": 35.59214,
        "lng": 127.50133,
        "phone": "063-350-2550",
        "pull_quote": "조선 개국조 이성계가 봉황새가 오색 무지개를 타고 하늘로 뜬 것을 보고 개국의 계시를 받은 곳 — 서해바다까지 397.25km를 흐르는 금강의 첫물",
        "paragraphs": [
            "수분마을에 위치한 신무산은 계곡을 따라 1.5km 올라가면 금강의 발원천이 되는 뜬봉샘이 있다. 뜬봉샘은 금강의 발원지이며 조선 개국조 이성계가 봉황새가 무지개를 타고 하늘로 뜬 것을 보고 천지신명으로부터 개국의 계시를 받았다는 설화가 있는 곳이다.",
            "뜬봉샘부터 시작한 물줄기는 서해바다 하구까지 397.25km로 흐른다. 특히 뜬봉샘생태공원은 금강사랑물 체험관, 자생 야생화 군락지, 생태놀이터, 생태온실, 생태숲길 등 다양한 공간과 멸종위기 종을 비롯한 동물들과 양서 파충류 등을 전시하여 관광객들에게 다양한 볼거리를 제공하고, 생태체험과 교육의 장을 제공한다.",
        ],
        "images": [
            "https://tong.visitkorea.or.kr/cms/resource/69/4098569_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/68/4098568_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/67/4098567_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/70/4098570_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/65/4098565_image2_1.jpg",
        ],
        "practical_header": "생태관광해설사와 함께 하는 생태관광 프로그램 · 3~11월 사전예약 필수",
        "practical_info": [
            {"label": "트레킹 코스", "value": "뜬봉샘 탐방로 코스 (1시간 코스, 왕복 3km)"},
            {"label": "해설 시간", "value": "10:00 ~ 16:00 (생태프로그램 진행 시 해설 불가)"},
            {"label": "문의 전화", "value": "063-350-2550 / 063-353-7002"},
            {"label": "무장애 편의시설", "value": "촉지·음성 종합안내도, 장애인 전용 주차구역, 접근가능한 화장실·휴게시설·체험시설, 장애인동선"},
        ],
        "pdf_links": [
            {
                "label": "📖 《장수여행》 가이드북 원본 열람 (p.9)",
                "label_en": "📖 Open Jangsu Guidebook PDF (p.9)",
                "url": "https://www.jangsu.go.kr/images/tour/content/sub05/tourist.pdf#page=9",
            },
            {
                "label": "🗺️ 장수 관광안내지도 PDF",
                "label_en": "🗺️ Jangsu Tourist Map PDF",
                "url": "https://www.jangsu.go.kr/images/tour/tour_guide.pdf",
            },
        ],
        "en_summary": "Tteunbongsaem Eco Park in Jangsu-gun is the sacred headwater of the 397.25km Geumgang River, featuring a gentle 3km (1-hour) forest boardwalk trail and Joseon Dynasty founding legend.",
    },
    {
        "id": "spot_story_deogyusan",
        "province": "전북",
        "city": "무주군",
        "season_badge": "🌲 고원 산림휴양 · 가문비나무 숲",
        "source_book": "무주군 문화관광 《자연특별시 무주》 수록",
        "months": [10, 11, 12, 1, 2, 6, 7, 8],
        "title": "국립 덕유산자연휴양림, 아름드리 독일 가문비나무 숲길",
        "subtitle": "무주군 무풍면 구천동로 530-62",
        "address": "전북특별자치도 무주군 무풍면 구천동로 530-62",
        "lat": 35.90660,
        "lng": 127.81440,
        "phone": "063-322-1097",
        "pull_quote": "하늘을 찌를 듯 솟은 아름드리 독일 가문비나무 군락 아래, 사계절 고요한 깊은 숲의 호흡을 만나는 시간",
        "paragraphs": [
            "덕유산 자연휴양림은 덕유산국립공원과 구천동 계곡 인접지에 자리해 봄에는 철쭉군락, 여름에는 구천동 청류, 가을에는 적상산의 붉은 단풍, 겨울에는 덕유산 설경과 상고대까지 사계절 내내 깊은 산림 휴양을 선사한다.",
            "특히 휴양림 경내에는 낙엽송과 잣나무가 울창한 숲을 이루고 있으며, 1931년 조림되어 하늘 높이 뻗은 대표 명물 '아름드리 독일 가문비나무 숲'이 이국적이면서도 웅장한 자태를 뽐내 누구나 완만하게 걸으며 피톤치드 산책을 즐길 수 있다.",
        ],
        "images": [
            "https://tong.visitkorea.or.kr/cms/resource/42/3064442_image2_1.JPG",
            "https://tong.visitkorea.or.kr/cms/resource/44/3064444_image2_1.JPG",
            "https://tong.visitkorea.or.kr/cms/resource/43/3064443_image2_1.JPG",
            "https://tong.visitkorea.or.kr/cms/resource/40/3064440_image2_1.JPG",
        ],
        "practical_header": "국립자연휴양림 일일 입장 · 가문비나무 산책로 연중 개방 (화요일 휴무 확인)",
        "practical_info": [
            {"label": "추천 산책코스", "value": "독일 가문비나무 숲 순환 산책로 (약 40~50분, 완만한 숲길)"},
            {"label": "이용 시간", "value": "일일 입장 09:00 ~ 18:00"},
            {"label": "문의 전화", "value": "063-322-1097"},
            {"label": "연계 볼거리", "value": "구천동 어사길 · 덕유산 관광곤도라 · 머루와인동굴 차량 15~20분"},
        ],
        "pdf_links": [
            {
                "label": "🗺️ 무주군 공식 관광안내도 다운로드",
                "label_en": "🗺️ Muju Official Tourist Map",
                "url": "https://tour.muju.go.kr/tour/contents.do?key=109",
            },
        ],
        "en_summary": "Deogyusan National Recreation Forest in Muju offers majestic giant Norway spruce groves planted in 1931 and serene four-season mountain walks near Gucheondong Valley.",
    },
    {
        "id": "spot_story_baengnyeonsa",
        "province": "전남",
        "city": "강진군",
        "season_badge": "🌺 초겨울~봄 동백숲 · 사색의 오솔길",
        "source_book": "전남·강진 공식 가이드북 《남도여행길잡이》 수록",
        "months": [11, 12, 1, 2, 3, 4],
        "title": "강진 만덕산 백련사 동백나무 숲과 다산 오솔길",
        "subtitle": "강진군 도암면 백련사길 145 (천연기념물 제151호)",
        "address": "전라남도 강진군 도암면 백련사길 145",
        "lat": 34.58764,
        "lng": 126.74859,
        "phone": "061-432-0837",
        "pull_quote": "다산 정약용과 혜장선사가 차와 학문을 나누러 오가던 800m 비밀의 숲길, 천연기념물 토종 동백 1,500그루의 군락",
        "paragraphs": [
            "고려 시대 원묘국사가 백련결사를 일으켰던 유서 깊은 사찰 백련사 주변으로는 천연기념물 제151호로 지정된 약 1,500여 그루의 토종 동백나무가 울창한 푸른 숲을 이루고 있다. 찬 바람이 불기 시작하는 늦가을과 초겨울부터 봉오리를 맺어 이른 봄까지 선홍빛 꽃송이를 숲길 위에 수놓는다.",
            "약 7m 높이의 동백나무 터널을 지나 다산초당으로 이어지는 호젓한 산허리 오솔길은 유배 시절 다산 정약용 선생이 백련사의 혜장선사를 만나기 위해 날마다 걸었던 사색의 길로, 남도 강진만의 잔잔한 바다 풍경까지 한눈에 내려다보인다.",
        ],
        "images": [
            "https://tong.visitkorea.or.kr/cms/resource/36/4065236_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/39/4065239_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/37/4065237_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/41/4065241_image2_1.jpg",
        ],
        "practical_header": "백련사 ~ 다산초당 연결 사색 산책로 · 강진 반값여행(50% 환급) 대표 코스",
        "practical_info": [
            {"label": "탐방 코스", "value": "백련사 동백숲 ~ 다산초당 오솔길 (편도 약 800m, 도보 30분)"},
            {"label": "입장 및 관람", "value": "상시 개방 · 입장료 무료 (사찰 정숙 관람)"},
            {"label": "문의 전화", "value": "061-432-0837 (백련사) / 061-430-3314 (강진군 문화관광과)"},
            {"label": "여행자 혜택", "value": "강진군 반값여행 사전신청 시 숙박·식비 50% 모바일 강진사랑상품권 환급"},
        ],
        "pdf_links": [
            {
                "label": "📖 남도여행 공식 e-가이드북 열람",
                "label_en": "📖 Open Namdo Official Travel E-book",
                "url": "https://www.namdokorea.com",
            },
        ],
        "en_summary": "A Natural Monument camellia forest of 1,500 native trees surrounding historic Baengnyeonsa Temple in Gangjin, connected by the scenic 800m forest trail walked by scholar Dasan Jeong Yak-yong.",
    },
    {
        "id": "spot_story_cheongnyeongpo",
        "province": "강원",
        "city": "영월군",
        "season_badge": "🚣 나룻배 역사기행 · 천년 소나무 숲",
        "source_book": "강원·영월 공식 관광가이드 《영월 기행》 수록",
        "months": [9, 10, 11, 3, 4, 5],
        "title": "영월 청령포, 삼면이 강물로 둘러싸인 단종의 숲",
        "subtitle": "강원 영월군 남면 광천리 (명승 제50호)",
        "address": "강원특별자치도 영월군 남면 청령포로 133",
        "lat": 37.17527,
        "lng": 128.44461,
        "phone": "033-372-1240",
        "pull_quote": "배가 아니면 닿을 수 없는 육지 속의 작은 섬, 어린 왕의 시간을 묵묵히 지켜본 아름드리 관음송과 솔숲",
        "paragraphs": [
            "영월 남한강 상류 서강이 굽이쳐 흐르는 청령포는 동·남·북 삼면이 깊은 강물로 둘러싸이고 서쪽으로는 험준한 육육봉 암벽이 솟아 있어 배를 타지 않고는 출입할 수 없는 천혜의 지형이다. 조선 제6대 임금 단종이 왕위를 잃고 노산군으로 강봉되어 머물렀던 역사의 현장이다.",
            "짧은 나룻배 도선을 건너 발을 딛는 순간 수백 년 세월을 품은 빽빽한 소나무 숲과 천연기념물 제349호 관음송이 방문객을 맞이하며, 망향탑과 노산대에 오르면 고요히 흐르는 서강의 물결과 단풍·솔향기가 깊은 여운을 남긴다.",
        ],
        "images": [
            "https://tong.visitkorea.or.kr/cms/resource/65/4041365_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/69/4041369_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/64/4041364_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/60/4041360_image2_1.jpg",
        ],
        "practical_header": "왕복 나룻배 탑승 포함 탐방 · 영월 디지털 관광주민증 할인 연계",
        "practical_info": [
            {"label": "탐방 소요시간", "value": "나룻배 왕복 승선(각 3분) + 솔숲·노산대 산책 약 1시간"},
            {"label": "운영 시간", "value": "09:00 ~ 18:00 (매표 마감 17:00 · 월요일 휴무 여부 사전 확인)"},
            {"label": "문의 전화", "value": "033-372-1240"},
            {"label": "주변 연계", "value": "영월 서부시장(메밀전병) · 장릉 · 선돌 전망대 차량 10분 거리"},
        ],
        "pdf_links": [
            {
                "label": "📖 강원관광 공식 가이드 열람",
                "label_en": "📖 Open Gangwon Official Travel Guide",
                "url": "https://www.visitgangwon.or.kr",
            },
        ],
        "en_summary": "Cheongnyeongpo in Yeongwol is a river-wrapped pine forest peninsula reachable only by a brief ferry ride, preserving the poignant history of King Danjong and a 600-year-old pine tree.",
    },
    {
        "id": "spot_story_suncheonman",
        "province": "전남",
        "city": "순천시",
        "season_badge": "🌾 황금빛 갈대밭 · 낙조 생태산책",
        "source_book": "순천시 생태관광 가이드북 수록",
        "months": [10, 11, 12, 1, 2],
        "title": "순천만습지, 바람에 일렁이는 황금 갈대숲과 저녁노을",
        "subtitle": "순천시 순천만길 513-25 (유네스코 세계자연유산)",
        "address": "전라남도 순천시 순천만길 513-25",
        "lat": 34.88580,
        "lng": 127.50928,
        "phone": "061-749-6052",
        "pull_quote": "끝없이 펼쳐진 황금빛 갈대 물결 위로 흑두루미가 날아오르고, S자 갯골이 붉은 노을로 물드는 대한민국 대표 생태정원",
        "paragraphs": [
            "고흥반도와 여수반도가 포근히 감싸 안은 순천만은 총면적 75㎢가 넘는 광활한 연안습지로, 가을부터 겨울까지 키를 훌쩍 넘는 황금빛 갈대 군락이 은빛 파도처럼 일렁이며 장관을 연출한다.",
            "유모차와 휠체어도 편안히 오갈 수 있는 평탄한 무장애 나무데크 길을 따라 걸으며 게와 짱뚱어가 살아 숨 쉬는 갯벌을 가까이서 만날 수 있고, 완만한 산길을 올라 용산전망대에 서면 순천만의 S자 수로 위로 떨어지는 잊지 못할 일몰이 펼쳐진다.",
        ],
        "images": [
            "https://tong.visitkorea.or.kr/cms/resource/14/4088614_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/10/4088610_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/13/4088613_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/11/4088611_image2_1.jpg",
        ],
        "practical_header": "평지 갈대데크 무장애 산책 · 일몰 1시간 전 방문 추천",
        "practical_info": [
            {"label": "탐방 코스", "value": "갈대데크 평지 산책(왕복 40분) / 용산전망대 일몰 코스(왕복 1시간 30분)"},
            {"label": "운영 시간", "value": "08:00 ~ 일몰 시까지 (계절별 매표 마감 상이)"},
            {"label": "문의 전화", "value": "061-749-6052"},
            {"label": "무장애 편의시설", "value": "전 구간 무장애 평지 갈대데크, 장애인 주차장·화장실, 생태체험선"},
        ],
        "pdf_links": [
            {
                "label": "📖 남도 생태관광 e-가이드북 열람",
                "label_en": "📖 Open Namdo Eco-Travel E-book",
                "url": "https://www.namdokorea.com",
            },
        ],
        "en_summary": "Suncheonman Wetland is a UNESCO World Natural Heritage coastal marsh famed for golden reed boardwalks, wintering hooded cranes, and breathtaking S-channel sunsets.",
    },
    {
        "id": "spot_story_jusanji",
        "province": "경북",
        "city": "청송군",
        "season_badge": "🌫️ 새벽 물안개 · 왕버들 지질명소",
        "source_book": "청송 유네스코 세계지질공원 가이드북 수록",
        "months": [10, 11, 4, 5],
        "title": "청송 주산지, 300년 물 위를 지키는 고목 왕버들의 아침",
        "subtitle": "경북 청송군 주왕산면 주산지리 (명승 제105호)",
        "address": "경상북도 청송군 주왕산면 주산지리 73",
        "lat": 36.36272,
        "lng": 129.18982,
        "phone": "054-873-0019",
        "pull_quote": "1721년 축조된 이래 단 한 번도 바닥을 드러낸 적 없는 신비의 못, 물속에서 뿌리내린 왕버들과 고요한 물안개의 수채화",
        "paragraphs": [
            "조선 경종 원년(1721년)에 준공된 주산지는 치밀한 화산재가 굳어 만들어진 '용결응회암' 지층 위에 자리해, 300년 넘는 세월 동안 아무리 극심한 가뭄이 찾아와도 단 한 번도 물이 말라 밑바닥을 드러낸 적이 없는 신비로운 산중 호수다.",
            "특히 수면 위로 낮게 물안개가 피어오르는 이른 아침, 물속에 깊이 뿌리를 내린 채 가지를 드리운 수령 수백 년의 왕버들 스무여 그루가 거울 같은 수면에 반영을 드리워 사계절 사진가와 여행자들의 발길을 조용히 불러 모은다.",
        ],
        "images": [
            "https://tong.visitkorea.or.kr/cms/resource/71/3526071_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/72/3526072_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/69/3526069_image2_1.jpg",
            "https://tong.visitkorea.or.kr/cms/resource/68/3526068_image2_1.jpg",
        ],
        "practical_header": "완만한 숲길 도보 20분 · 입장료 및 주차 무료",
        "practical_info": [
            {"label": "산책 코스", "value": "주산지 입구 주차장 ~ 호수 전망대 (편도 약 1km, 완만한 숲길 20분)"},
            {"label": "추천 시간대", "value": "일출 직후 ~ 오전 9시 물안개 시간대 및 늦가을 단풍·초록 신록기"},
            {"label": "문의 전화", "value": "054-873-0019 (주왕산국립공원 주산지분소)"},
            {"label": "주변 연계", "value": "주왕산 용추폭포 무장애 탐방로 · 달기약수 백숙거리 · 청송사과 직판장"},
        ],
        "pdf_links": [
            {
                "label": "📖 경북나드리 공식 가이드북 열람",
                "label_en": "📖 Open Gyeongbuk Official Guidebook",
                "url": "https://tour.gb.go.kr/page.do?mnu_uid=2199&",
            },
        ],
        "en_summary": "Built in 1721 atop volcanic welded tuff, Jusanji Pond in Cheongsong UNESCO Global Geopark has never dried up, famous for ancient willow trees growing straight out of misty mirror waters.",
    },
]

# KorService2 17개 시·도 균등 조회 파라미터 매핑 (2026 행정구역 코드 반영)
PROVINCE_17_TOUR_PARAMS: list[tuple[str, list[dict[str, str]]]] = [
    ("서울", [{"lDongRegnCd": "11"}]),
    ("부산", [{"lDongRegnCd": "26"}]),
    ("대구", [{"lDongRegnCd": "27"}]),
    ("인천", [{"lDongRegnCd": "28"}]),
    ("광주", [{"lDongRegnCd": "12", "lDongSignguCd": "210"}, {"lDongRegnCd": "12", "lDongSignguCd": "240"}, {"lDongRegnCd": "12", "lDongSignguCd": "300"}]),
    ("대전", [{"lDongRegnCd": "30"}]),
    ("울산", [{"lDongRegnCd": "31"}]),
    ("세종", [{"lDongRegnCd": "36110"}]),
    ("경기", [{"lDongRegnCd": "41"}]),
    ("강원", [{"lDongRegnCd": "51"}]),
    ("충북", [{"lDongRegnCd": "43"}]),
    ("충남", [{"lDongRegnCd": "44"}]),
    ("전북", [{"lDongRegnCd": "52"}, {"lDongRegnCd": "52", "lDongSignguCd": "730"}, {"lDongRegnCd": "52", "lDongSignguCd": "720"}, {"lDongRegnCd": "52", "lDongSignguCd": "740"}]),
    ("전남", [{"lDongRegnCd": "12"}]),
    ("경북", [{"lDongRegnCd": "47"}]),
    ("경남", [{"lDongRegnCd": "48"}]),
    ("제주", [{"lDongRegnCd": "50"}]),
]


def _https(url: str) -> str:
    u = (url or "").strip()
    if u.startswith("http://"):
        return "https://" + u[len("http://"):]
    return u if u.startswith("https://") else ""


def _strip_overview_html(raw: str) -> str:
    if not raw:
        return ""
    s = re.sub(r"<br\s*/?>", " ", str(raw), flags=re.IGNORECASE)
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s+", " ", html.unescape(s)).strip()


def _tour_get(endpoint: str, params: dict[str, Any], timeout: int = 12) -> Any:
    key = os.environ.get("TOUR_API_KEY") or os.environ.get("DATA_GO_KR_SERVICE_KEY") or ""
    if not key:
        return None
    full_params = {
        "serviceKey": key,
        "MobileOS": "ETC",
        "MobileApp": "jikstay",
        "_type": "json",
        **params,
    }
    url = f"https://apis.data.go.kr/B551011/KorService2/{endpoint}"
    try:
        r = requests.get(url, params=full_params, timeout=timeout)
        if r.status_code != 200 or "LIMITED_NUMBER_OF_SERVICE_REQUESTS" in r.text:
            return None
        return r.json().get("response", {}).get("body", {})
    except Exception:  # noqa: BLE001
        return None


def _parse_wgs84(it: dict[str, Any], prov: str) -> tuple[float, float]:
    try:
        lng = float(str(it.get("mapx") or "").strip())
        lat = float(str(it.get("mapy") or "").strip())
        if 32.5 <= lat <= 39.0 and 124.0 <= lng <= 132.0:
            return (round(lat, 5), round(lng, 5))
    except ValueError:
        pass
    clat, clng = PROVINCE_CENTROIDS.get(prov, (36.5, 127.8))
    return (clat, clng)


def fetch_festivals(limit: int = 36) -> list[dict[str, Any]]:
    """KorService2/searchFestival2로 현재 진행중이거나 다가오는 전국 축제를 시·도 균형 있게 가져온다."""
    today_str = date.today().strftime("%Y%m%d")
    start_from = (date.today() - timedelta(days=21)).strftime("%Y%m%d")
    body = _tour_get(
        "searchFestival2",
        {"numOfRows": 120, "pageNo": 1, "eventStartDate": start_from, "arrange": "Q"},
        timeout=18,
    )
    if not body:
        return []
    raw_items = (body.get("items") or {}).get("item") or []
    if isinstance(raw_items, dict):
        raw_items = [raw_items]

    out: list[dict[str, Any]] = []
    per_prov: dict[str, int] = {}
    for it in raw_items:
        end_d = str(it.get("eventenddate") or "").strip()
        if end_d and end_d < today_str:
            continue
        img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
        if not img:
            continue
        addr1 = str(it.get("addr1") or "").strip()
        d1, d2 = parse_korean_address(addr1)
        prov = normalize_province_short(d1, d2)
        if per_prov.get(prov, 0) >= 4:
            continue
        per_prov[prov] = per_prov.get(prov, 0) + 1
        rg = classify_region_group(d1) or "전체"
        title = normalize_place_name(str(it.get("title") or ""))
        start_d = str(it.get("eventstartdate") or "").strip()
        cid = str(it.get("contentid") or "")
        lat, lng = _parse_wgs84(it, prov)
        out.append({
            "id": f"spot_ev_{cid}" if cid else f"spot_ev_{len(out)}",
            "kind": "event",
            "content_id": cid,
            "title": title,
            "province": prov,
            "region_group": rg,
            "region_label": f"{prov} {d2}".strip(),
            "search_city": (d2.split(" ")[0] if d2 else prov).replace("시", "").replace("군", "").replace("구", ""),
            "addr": addr1,
            "lat": lat,
            "lng": lng,
            "start_date": start_d,
            "end_date": end_d,
            "image_url": img,
            "tel": str(it.get("tel") or "").strip(),
            "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
        })
        if len(out) >= limit:
            break
    return out


def fetch_17_provinces_spots(
    per_province_attractions: int = 8,
    per_province_foods: int = 8,
    cache_path: str = "output/curated_stays_cache/local_discovery_17prov_cache.json",
) -> list[dict[str, Any]]:
    """전국 17개 시·도에서 볼거리(contentTypeId=12)와 먹거리(contentTypeId=39)를 균등하게 수집한다."""
    if os.path.exists(cache_path):
        try:
            with open(cache_path, encoding="utf-8") as f:
                cached = json.load(f)
            if isinstance(cached, list) and len(cached) >= 100:
                print(f"  → 로컬 캐시 재사용: 전국 17개 시도 명소·먹거리 {len(cached)}건")
                return cached
        except Exception:  # noqa: BLE001
            pass

    gwangju_gu_names = ("동구", "서구", "남구", "북구", "광산구")
    all_spots: list[dict[str, Any]] = []
    seen_cids: set[str] = set()
    lock = threading.Lock()

    def _collect_province(prov_and_queries: tuple[str, list[dict[str, str]]]) -> list[dict[str, Any]]:
        prov, q_list = prov_and_queries
        prov_spots: list[dict[str, Any]] = []
        for content_type, kind_key, target_cnt in (
            ("12", "attraction", per_province_attractions),
            ("39", "food", per_province_foods),
        ):
            picked_for_type: list[dict[str, Any]] = []
            per_q_rows = max(25, target_cnt * 3)
            for idx_q, q_params in enumerate(q_list):
                if len(picked_for_type) >= target_cnt and idx_q == 0 and len(q_list) == 1:
                    break
                body = _tour_get(
                    "areaBasedList2",
                    {**q_params, "contentTypeId": content_type, "numOfRows": per_q_rows, "pageNo": 1, "arrange": "Q"},
                    timeout=14,
                )
                if not body:
                    continue
                items = (body.get("items") or {}).get("item") or []
                if isinstance(items, dict):
                    items = [items]
                # 전북 무주·진안·장수 보조 쿼리에서는 각 시군 대표 2건씩 우선 확보
                sub_quota = 2 if idx_q > 0 and prov == "전북" else target_cnt
                sub_added = 0
                for it in items:
                    cid = str(it.get("contentid") or "").strip()
                    if not cid:
                        continue
                    with lock:
                        if cid in seen_cids:
                            continue
                    img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
                    if not img:
                        continue
                    addr1 = str(it.get("addr1") or "").strip()
                    d1, d2 = parse_korean_address(addr1)
                    # 전남 쿼리(lDongRegnCd=12)에서 광주 5개 구는 광주 몫으로 분리
                    if prov == "전남" and any(d2.startswith(g) for g in gwangju_gu_names):
                        continue
                    lat, lng = _parse_wgs84(it, prov)
                    title = normalize_place_name(str(it.get("title") or ""))
                    if not title:
                        continue
                    with lock:
                        seen_cids.add(cid)
                    rg = classify_region_group(d1) or "전체"
                    spot_idx = len(picked_for_type)
                    # 시·도별 대표 먹거리·볼거리 상단 2곳에 방문 혜택 쿠폰 / 스폰서 추천(CPC 모델) 메타데이터 부여
                    is_sponsored = spot_idx < 2
                    coupon_title = ""
                    if is_sponsored:
                        coupon_title = (
                            "직스테이 방문 혜택 · 화면 제시 시 음료/사이드 서비스"
                            if kind_key == "food"
                            else "로컬 추천 파트너 · 주변 맛집·안심숙소 연계 코스"
                        )
                    spot_doc: dict[str, Any] = {
                        "id": f"spot_{kind_key[:2]}_{cid}",
                        "kind": kind_key,
                        "content_id": cid,
                        "title": title,
                        "province": prov,
                        "region_group": rg,
                        "region_label": f"{prov} {d2}".strip(),
                        "addr": addr1,
                        "lat": lat,
                        "lng": lng,
                        "image_url": img,
                        "tel": str(it.get("tel") or "").strip(),
                        "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
                    }
                    if is_sponsored:
                        spot_doc["is_sponsored"] = True
                        spot_doc["coupon_title"] = coupon_title
                        spot_doc["cpc_rate"] = 500
                    picked_for_type.append(spot_doc)
                    sub_added += 1
                    if sub_added >= sub_quota:
                        break
            # 보조 시군 쿼리로 초과 수집된 경우 시·도당 균등 상한(target_cnt + 2)으로 정돈하되 무진장 항목 보존
            if len(picked_for_type) > target_cnt + 2:
                head = picked_for_type[: max(4, target_cnt - 3)]
                tail = picked_for_type[-(target_cnt + 2 - len(head)) :]
                picked_for_type = head + tail
            prov_spots.extend(picked_for_type)
        return prov_spots

    with ThreadPoolExecutor(max_workers=5) as pool:
        for chunk in pool.map(_collect_province, PROVINCE_17_TOUR_PARAMS):
            all_spots.extend(chunk)

    if all_spots:
        os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(all_spots, f, ensure_ascii=False, indent=2)
    return all_spots


def fetch_travel_courses(limit: int = 12) -> list[dict[str, Any]]:
    """KorService2/areaBasedList2(contentTypeId=25) + detailCommon2 + detailInfo2로 공식 여행코스 매거진을 생성한다."""
    body = _tour_get(
        "areaBasedList2",
        {"contentTypeId": "25", "numOfRows": 40, "pageNo": 1, "arrange": "Q"},
        timeout=18,
    )
    if not body:
        return []
    raw_items = (body.get("items") or {}).get("item") or []
    if isinstance(raw_items, dict):
        raw_items = [raw_items]

    # 권역별로 골고루 안배
    picked: list[dict[str, Any]] = []
    per_rg: dict[str, int] = {}
    for it in raw_items:
        img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
        if not img:
            continue
        addr1 = str(it.get("addr1") or "").strip()
        title = normalize_place_name(str(it.get("title") or ""))
        d1, d2 = parse_korean_address(addr1)
        rg = classify_region_group(d1)
        if not rg:
            for kw, grp in (("제주", "제주"), ("강원", "강원"), ("강릉", "강원"), ("속초", "강원"), ("부산", "부산/경상"), ("경주", "부산/경상"), ("남해", "부산/경상"), ("전주", "전라/충청"), ("여수", "전라/충청"), ("목포", "전라/충청"), ("태안", "전라/충청"), ("서울", "서울/경기"), ("인천", "서울/경기"), ("수원", "서울/경기")):
                if kw in title:
                    rg = grp
                    break
        rg = rg or "전체"
        if per_rg.get(rg, 0) >= 3:
            continue
        per_rg[rg] = per_rg.get(rg, 0) + 1
        picked.append({**it, "_rg": rg, "_d1": d1, "_d2": d2, "_img": img, "_title": title})
        if len(picked) >= limit:
            break

    courses: list[dict[str, Any]] = []
    for it in picked:
        cid = str(it.get("contentid") or "")
        com_body = _tour_get("detailCommon2", {"contentId": cid}, timeout=10)
        overview = ""
        if com_body:
            c_items = (com_body.get("items") or {}).get("item") or []
            if isinstance(c_items, dict):
                c_items = [c_items]
            if c_items:
                overview = _strip_overview_html(c_items[0].get("overview", ""))[:260]

        inf_body = _tour_get("detailInfo2", {"contentId": cid, "contentTypeId": "25"}, timeout=10)
        stops: list[str] = []
        if inf_body:
            s_items = (inf_body.get("items") or {}).get("item") or []
            if isinstance(s_items, dict):
                s_items = [s_items]
            for s in s_items[:6]:
                sname = str(s.get("subname") or "").strip()
                if sname and sname not in stops:
                    stops.append(sname)

        courses.append({
            "content_id": cid,
            "title": it["_title"],
            "region_group": it["_rg"],
            "region_label": f"{it['_d1']} {it['_d2']}".strip() or it["_rg"],
            "image_url": it["_img"],
            "overview": overview or "한국관광공사가 엄선한 지역 대표 테마 여행코스입니다.",
            "stops": stops,
            "article_url": f"https://korean.visitkorea.or.kr/detail/cs_detail_cos.do?cotid={cid}" if cid else "https://korean.visitkorea.or.kr",
        })
    return courses


def fetch_naver_subsidy_guides() -> list[dict[str, str]]:
    """네이버 오픈 API로 반값여행·지자체 숙박비 지원·디지털 관광주민증 최신 실전 가이드 링크를 수집한다."""
    nid = os.environ.get("NAVER_CLIENT_ID") or ""
    nsec = os.environ.get("NAVER_CLIENT_SECRET") or ""
    if not nid or not nsec:
        return []
    use_hub = len(nsec) >= 20 or os.environ.get("NAVER_API_MODE", "").lower() == "hub"
    headers = (
        {"X-NCP-APIGW-API-KEY-ID": nid, "X-NCP-APIGW-API-KEY": nsec}
        if use_hub
        else {"X-Naver-Client-Id": nid, "X-Naver-Client-Secret": nsec}
    )
    api_url = NAVER_BLOG_HUB_URL if use_hub else NAVER_BLOG_LEGACY_URL

    queries = [
        ("반값여행 가이드", "반값여행 대상 지역 사전 신청 가이드"),
        ("지자체 체류지원", "지자체 한달살기 일주일살기 숙박비 지원 신청"),
        ("관광주민증 혜택", "디지털 관광주민증 발급 숙박 할인 혜택"),
    ]
    guides: list[dict[str, str]] = []
    seen_links: set[str] = set()
    spam = ("매매", "분양", "대출", "보험", "부동산")

    for tag, q in queries:
        params: dict[str, Any] = {"query": q, "display": 4, "start": 1, "sort": "sim"}
        if use_hub:
            params["format"] = "json"
        try:
            r = requests.get(api_url, headers=headers, params=params, timeout=8)
            if r.status_code != 200:
                continue
            for item in r.json().get("items") or []:
                link = str(item.get("link") or "").strip()
                title = clean_html_text(item.get("title", ""))
                desc = clean_html_text(item.get("description", ""))
                if not link.startswith("http") or link in seen_links:
                    continue
                if any(w in title for w in spam):
                    continue
                seen_links.add(link)
                guides.append({
                    "tag": tag,
                    "title": title[:85],
                    "summary": desc[:150],
                    "blogger": clean_html_text(item.get("bloggername", ""))[:30],
                    "postdate": str(item.get("postdate") or ""),
                    "link": link,
                })
                if len(guides) >= 6:
                    break
        except Exception:  # noqa: BLE001
            continue
    return guides[:6]


def enrich_top_stays_with_tour_details(
    curated_path: str = "output/curated_stays.json",
    catalog_path: str = "output/curated_stays_cache/tour_stays_catalog.json",
    cache_path: str = "output/curated_stays_cache/stay_deep_tour_cache.json",
    per_bucket_top: int = 5,
    upload: bool = False,
) -> int:
    """각 버킷 상위 숙소에 KorService2 detailCommon2·detailIntro2·locationBasedList2(주변 5km 명소·맛집)를 보강한다."""
    if not os.path.exists(curated_path) or not os.path.exists(catalog_path):
        print("[건너뜀] curated_stays.json 또는 tour_stays_catalog.json 파일이 없습니다.")
        return 0

    with open(curated_path, encoding="utf-8") as f:
        docs: list[dict[str, Any]] = json.load(f)
    with open(catalog_path, encoding="utf-8") as f:
        catalog: list[dict[str, Any]] = json.load(f)

    by_cid: dict[str, dict[str, Any]] = {}
    by_prov_title: dict[tuple[str, str], dict[str, Any]] = {}
    for it in catalog:
        cid = str(it.get("contentid") or "").strip()
        if cid:
            by_cid[cid] = it
        d1, _ = parse_korean_address(str(it.get("addr1") or ""))
        t = re.sub(r"[^\w가-힣]", "", normalize_place_name(str(it.get("title") or ""))).lower()
        if d1[:2] and t:
            by_prov_title.setdefault((d1[:2], t), it)

    deep_cache: dict[str, dict[str, Any]] = {}
    if os.path.exists(cache_path):
        try:
            with open(cache_path, encoding="utf-8") as f:
                deep_cache = json.load(f)
        except Exception:  # noqa: BLE001
            deep_cache = {}
    lock = threading.Lock()

    # 1) 모든 TourAPI 매칭 숙소에 좌표(lat/lng) 보강 및 버킷별 상위 N개 선정
    bucket_counts: dict[tuple[str, str], int] = {}
    targets: list[tuple[dict[str, Any], dict[str, Any]]] = []

    for d in docs:
        mng = str(d.get("public_mng_no") or "")
        t_item: dict[str, Any] | None = None
        if mng.startswith("KTO-"):
            t_item = by_cid.get(mng[4:])
        if not t_item:
            p2 = str(d.get("region_depth1") or "")[:2]
            tk = re.sub(r"[^\w가-힣]", "", str(d.get("title") or "")).lower()
            t_item = by_prov_title.get((p2, tk))
        if not t_item:
            continue

        mx = t_item.get("mapx")
        my = t_item.get("mapy")
        try:
            if mx and my:
                loc = d.setdefault("location_info", {})
                loc["lng"] = round(float(mx), 6)
                loc["lat"] = round(float(my), 6)
        except ValueError:
            pass

        bkey = (str(d.get("region_group") or ""), str(d.get("license_type") or ""))
        if bucket_counts.get(bkey, 0) < per_bucket_top:
            bucket_counts[bkey] = bucket_counts.get(bkey, 0) + 1
            targets.append((d, t_item))

    def _fetch_deep(pair: tuple[dict[str, Any], dict[str, Any]]) -> dict[str, Any] | None:
        doc, t_item = pair
        cid = str(t_item.get("contentid") or "").strip()
        if not cid:
            return None
        with lock:
            info = deep_cache.get(cid)

        if info is None:
            info = {}
            com = _tour_get("detailCommon2", {"contentId": cid}, timeout=10)
            if com:
                c_list = (com.get("items") or {}).get("item") or []
                if isinstance(c_list, dict):
                    c_list = [c_list]
                if c_list:
                    info["overview"] = _strip_overview_html(c_list[0].get("overview", ""))[:420]
                    hp_raw = str(c_list[0].get("homepage") or "")
                    m_hp = re.search(r'https?://[^\s"<>\']+', hp_raw)
                    if m_hp:
                        info["homepage"] = m_hp.group(0)

            intro = _tour_get("detailIntro2", {"contentId": cid, "contentTypeId": "32"}, timeout=10)
            if intro:
                i_list = (intro.get("items") or {}).get("item") or []
                if isinstance(i_list, dict):
                    i_list = [i_list]
                if i_list:
                    it0 = i_list[0]
                    info["checkintime"] = _strip_overview_html(it0.get("checkintime", ""))[:30]
                    info["checkouttime"] = _strip_overview_html(it0.get("checkouttime", ""))[:30]
                    info["parking"] = _strip_overview_html(it0.get("parkinglodging", ""))[:40]
                    info["cooking"] = _strip_overview_html(it0.get("chkcooking", ""))[:30]
                    info["subfacility"] = _strip_overview_html(it0.get("subfacility", ""))[:80]
                    info["roomcount"] = _strip_overview_html(it0.get("roomcount", ""))[:15]

            mx = str(t_item.get("mapx") or "").strip()
            my = str(t_item.get("mapy") or "").strip()
            nearby: list[dict[str, Any]] = []
            if mx and my:
                near_body = _tour_get(
                    "locationBasedList2",
                    {"mapX": mx, "mapY": my, "radius": "5000", "numOfRows": 10, "pageNo": 1, "arrange": "Q"},
                    timeout=10,
                )
                if near_body:
                    n_list = (near_body.get("items") or {}).get("item") or []
                    if isinstance(n_list, dict):
                        n_list = [n_list]
                    for n_it in n_list:
                        ctype = str(n_it.get("contenttypeid") or "")
                        if ctype == "32":  # 다른 숙박업소는 제외하고 명소·맛집·체험만 추천
                            continue
                        n_title = normalize_place_name(str(n_it.get("title") or ""))
                        n_img = _https(str(n_it.get("firstimage") or n_it.get("firstimage2") or ""))
                        try:
                            dist_m = int(float(n_it.get("dist") or 0))
                        except ValueError:
                            dist_m = 0
                        n_addr = str(n_it.get("addr1") or "").strip()
                        nearby.append({
                            "title": n_title,
                            "category": CONTENT_TYPE_LABELS.get(ctype, "주변 명소"),
                            "distance_m": dist_m,
                            "image_url": n_img,
                            "addr": n_addr,
                            "map_url": f"https://map.naver.com/p/search/{quote(f'{n_addr[:10]} {n_title}'.strip())}",
                        })
                        if len(nearby) >= 4:
                            break
            info["nearby"] = nearby
            with lock:
                deep_cache[cid] = info

        # 문서에 반영
        if info.get("overview"):
            doc["editorial_story"] = info["overview"]
        if info.get("homepage") and not doc.get("source_blog_url"):
            doc["official_homepage_url"] = info["homepage"]
            doc["direct_booking_url"] = info["homepage"]
        hr = doc.setdefault("house_rules", {})
        if info.get("checkintime"):
            hr["check_in_time"] = info["checkintime"]
        if info.get("checkouttime"):
            hr["check_out_time"] = info["checkouttime"]
        loc = doc.setdefault("location_info", {})
        if info.get("parking"):
            loc["parking_note"] = f"주차 안내(한국관광공사): {info['parking']}"
        opts: list[str] = list(doc.get("options") or [])
        if info.get("cooking") and "가능" in info["cooking"] and "객실 취사 가능" not in opts:
            opts.insert(0, "객실 취사 가능")
        if info.get("subfacility"):
            for sf in re.split(r"[,/·]", info["subfacility"]):
                sf_clean = sf.strip()
                if 2 <= len(sf_clean) <= 12 and sf_clean not in opts:
                    opts.append(sf_clean)
        doc["options"] = opts[:8]
        if info.get("nearby"):
            doc["nearby_places"] = info["nearby"]
            names_preview = ", ".join(p["title"] for p in info["nearby"][:3])
            loc["nearby_spots"] = f"반경 5km 추천 명소·맛집: {names_preview}"
        return doc

    with ThreadPoolExecutor(max_workers=5) as pool:
        enriched_docs = [d for d in pool.map(_fetch_deep, targets) if d is not None]

    os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(deep_cache, f, ensure_ascii=False, indent=2)

    with open(curated_path, "w", encoding="utf-8") as f:
        json.dump(docs, f, ensure_ascii=False, indent=2)

    # 초경량 웹 색인 재생성
    index_path = "app/web/data/public_stays_index.json"
    os.makedirs(os.path.dirname(os.path.abspath(index_path)), exist_ok=True)
    lightweight = [build_lightweight_index_entry(d) for d in docs]
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump({"updated_at": int(time.time() * 1000), "items": lightweight}, f, ensure_ascii=False, separators=(",", ":"))
    size_kb = os.path.getsize(index_path) / 1024
    print(f"[경량 색인 갱신] {index_path}: {len(lightweight)}곳 ({size_kb:.1f} KB)")

    if upload and enriched_docs:
        from firebase_client import db

        col = db().collection("listings")
        batch = db().batch()
        ops = 0
        for d in enriched_docs:
            snap = col.document(d["listing_id"]).get()
            if snap.exists and snap.to_dict().get("listing_tier") == "claimed":
                continue
            batch.set(
                col.document(d["listing_id"]),
                {
                    "editorial_story": d.get("editorial_story", ""),
                    "official_homepage_url": d.get("official_homepage_url", ""),
                    "direct_booking_url": d.get("direct_booking_url", ""),
                    "house_rules": d.get("house_rules", {}),
                    "location_info": d.get("location_info", {}),
                    "options": d.get("options", []),
                    "nearby_places": d.get("nearby_places", []),
                },
                merge=True,
            )
            ops += 1
            if ops >= 180:
                batch.commit()
                batch = db().batch()
                ops = 0
        if ops > 0:
            batch.commit()
        print(f"[Firestore 상세 보강] 상위 숙소 {len(enriched_docs)}곳 (개요·체크인·반경 5km 주변명소) 업데이트 완료")

    return len(enriched_docs)


def refresh_stays_lightweight_index(
    curated_path: str = "output/curated_stays.json",
    index_path: str = "app/web/data/public_stays_index.json",
) -> int:
    """curated_stays.json에서 위경도(lat/lng)·17개 시도(province)가 포함된 초경량 웹 색인을 재생성한다."""
    if not os.path.exists(curated_path):
        return 0
    with open(curated_path, encoding="utf-8") as f:
        docs: list[dict[str, Any]] = json.load(f)
    os.makedirs(os.path.dirname(os.path.abspath(index_path)), exist_ok=True)
    lightweight = [build_lightweight_index_entry(d) for d in docs]
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(
            {"updated_at": int(time.time() * 1000), "items": lightweight},
            f,
            ensure_ascii=False,
            separators=(",", ":"),
        )
    size_kb = os.path.getsize(index_path) / 1024
    print(f"[지도용 숙소 색인 갱신] {index_path}: {len(lightweight)}곳 ({size_kb:.1f} KB)")
    return len(lightweight)


def _split_editorial_paragraphs(text: str, max_chars: int = 520) -> list[str]:
    clean = (text or "").strip()
    if not clean:
        return []
    clean = clean[:max_chars].strip()
    sentences = [s.strip() for s in re.split(r"(?<=[.!?다요음함])\s+", clean) if s.strip()]
    if len(sentences) <= 2 or len(clean) < 180:
        return [clean]
    mid = len(sentences) // 2
    p1 = " ".join(sentences[:mid]).strip()
    p2 = " ".join(sentences[mid:]).strip()
    return [p for p in (p1, p2) if p]


def _fetch_naver_place_blog_snippets(query: str, max_items: int = 2) -> list[dict[str, str]]:
    nid = os.environ.get("NAVER_CLIENT_ID") or ""
    nsec = os.environ.get("NAVER_CLIENT_SECRET") or ""
    if not nid or not nsec or not query.strip():
        return []
    use_hub = len(nsec) >= 20 or os.environ.get("NAVER_API_MODE", "").lower() == "hub"
    headers = (
        {"X-NCP-APIGW-API-KEY-ID": nid, "X-NCP-APIGW-API-KEY": nsec}
        if use_hub
        else {"X-Naver-Client-Id": nid, "X-Naver-Client-Secret": nsec}
    )
    api_url = NAVER_BLOG_HUB_URL if use_hub else NAVER_BLOG_LEGACY_URL
    params: dict[str, Any] = {"query": query, "display": 5, "start": 1, "sort": "sim"}
    if use_hub:
        params["format"] = "json"
    spam_words = ("분양", "대출", "매매", "보험", "부동산", "원고료", "소정의 수수료")
    out: list[dict[str, str]] = []
    seen: set[str] = set()
    try:
        r = requests.get(api_url, headers=headers, params=params, timeout=7)
        if r.status_code != 200:
            return []
        for it in r.json().get("items") or []:
            link = str(it.get("link") or "").strip()
            title = clean_html_text(it.get("title", ""))
            desc = clean_html_text(it.get("description", ""))
            if not link.startswith("http") or link in seen:
                continue
            if any(w in title or w in desc for w in spam_words):
                continue
            seen.add(link)
            out.append({
                "title": title[:72],
                "summary": desc[:135],
                "blogger": clean_html_text(it.get("bloggername", ""))[:24],
                "postdate": str(it.get("postdate") or ""),
                "link": link,
            })
            if len(out) >= max_items:
                break
    except Exception:  # noqa: BLE001
        return []
    return out


def enrich_spots_and_festivals_details(
    items: list[dict[str, Any]],
    cache_path: str = "output/curated_stays_cache/spot_editorial_detail_cache.json",
) -> None:
    """전국 축제·먹거리·볼거리에 TourAPI 상세(개요·대표메뉴·영업시간·갤러리) + 네이버 방문 후기를 보강한다."""
    cache: dict[str, dict[str, Any]] = {}
    if os.path.exists(cache_path):
        try:
            with open(cache_path, encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                cache = loaded
        except Exception:  # noqa: BLE001
            cache = {}

    lock = threading.Lock()
    dirty = False

    def _fmt_ymd(raw: str) -> str:
        s = (raw or "").strip()
        return f"{s[:4]}.{s[4:6]}.{s[6:8]}" if len(s) == 8 else s

    def _enrich_one(d: dict[str, Any]) -> None:
        nonlocal dirty
        cid = str(d.get("content_id") or "").strip()
        kind = str(d.get("kind") or "attraction").strip()
        title = str(d.get("title") or "").strip()
        prov = str(d.get("province") or "").strip()
        reg_label = str(d.get("region_label") or prov).strip()
        cache_key = f"{kind}:{cid or title}"

        with lock:
            info = cache.get(cache_key)

        if info is None:
            info = {}
            ctype = {"event": "15", "food": "39", "attraction": "12"}.get(kind, "12")
            overview = ""
            homepage = ""
            if cid:
                com = _tour_get("detailCommon2", {"contentId": cid}, timeout=9)
                if com:
                    c_items = (com.get("items") or {}).get("item") or []
                    if isinstance(c_items, dict):
                        c_items = [c_items]
                    if c_items:
                        overview = _strip_overview_html(c_items[0].get("overview", ""))
                        hp_raw = str(c_items[0].get("homepage") or "")
                        m_hp = re.search(r'https?://[^\s"<>\']+', hp_raw)
                        if m_hp:
                            homepage = m_hp.group(0)

                intro_map: dict[str, str] = {}
                intro = _tour_get("detailIntro2", {"contentId": cid, "contentTypeId": ctype}, timeout=9)
                if intro:
                    i_items = (intro.get("items") or {}).get("item") or []
                    if isinstance(i_items, dict):
                        i_items = [i_items]
                    if i_items and isinstance(i_items[0], dict):
                        for k, v in i_items[0].items():
                            if v:
                                intro_map[k] = _strip_overview_html(str(v))

                extra_imgs: list[str] = []
                img_body = _tour_get("detailImage2", {"contentId": cid, "imageYN": "Y", "numOfRows": 4}, timeout=8)
                if img_body:
                    im_items = (img_body.get("items") or {}).get("item") or []
                    if isinstance(im_items, dict):
                        im_items = [im_items]
                    for im in im_items:
                        u = _https(str(im.get("originimgurl") or im.get("smallimageurl") or ""))
                        if u and u not in extra_imgs:
                            extra_imgs.append(u)
                        if len(extra_imgs) >= 4:
                            break
                info["extra_images"] = extra_imgs
                info["overview"] = overview[:560]
                if homepage:
                    info["homepage"] = homepage
                info["intro"] = intro_map

            q_suffix = "후기" if kind in ("food", "attraction") else "일정 후기"
            q_region = reg_label if reg_label else prov
            info["naver_reviews"] = _fetch_naver_place_blog_snippets(f"{q_region} {title} {q_suffix}".strip(), max_items=2)

            with lock:
                cache[cache_key] = info
                dirty = True

        # 항목에 스토리형 필드 조합·주입
        primary_img = str(d.get("image_url") or "").strip()
        gallery = [primary_img] if primary_img else []
        for u in info.get("extra_images") or []:
            if u and u not in gallery:
                gallery.append(u)
            if len(gallery) >= 4:
                break
        if gallery:
            d["images"] = gallery

        intro_m: dict[str, str] = info.get("intro") or {}
        overview_txt = str(info.get("overview") or "").strip()
        paragraphs = _split_editorial_paragraphs(overview_txt)

        p_rows: list[dict[str, str]] = []
        pull_quote = ""

        if kind == "food":
            p_header = "방문 전 필수 확인 · 대표 메뉴 · 영업시간 · 편의안내"
            first_m = intro_m.get("firstmenu", "")[:60]
            treat_m = intro_m.get("treatmenu", "")[:90]
            open_t = intro_m.get("opentimefood", "")[:70]
            rest_d = intro_m.get("restdatefood", "")[:50]
            park_f = intro_m.get("parkingfood", "")[:50]
            pack_f = intro_m.get("packing", "")[:35]
            tel_f = intro_m.get("infocenterfood", "")[:40] or str(d.get("tel") or "")
            if first_m:
                p_rows.append({"label": "대표 메뉴", "value": first_m})
                pull_quote = f"대표 별미: {first_m}" + (f" · {treat_m}" if treat_m and treat_m != first_m else "")
            if treat_m and treat_m != first_m:
                p_rows.append({"label": "취급 메뉴", "value": treat_m})
            if open_t:
                p_rows.append({"label": "영업 시간", "value": open_t})
            if rest_d:
                p_rows.append({"label": "쉬는 날", "value": rest_d})
            if park_f:
                p_rows.append({"label": "주차 안내", "value": park_f})
            if pack_f:
                p_rows.append({"label": "포장 안내", "value": pack_f})
            if tel_f:
                p_rows.append({"label": "문의 전화", "value": tel_f})
        elif kind == "event":
            p_header = "행사 관람 필수 확인 · 일정 · 장소 · 프로그램 안내"
            sd, ed = _fmt_ymd(str(d.get("start_date") or "")), _fmt_ymd(str(d.get("end_date") or ""))
            if sd or ed:
                p_rows.append({"label": "행사 기간", "value": f"{sd} ~ {ed}".strip(" ~")})
            ev_place = intro_m.get("eventplace", "")[:70] or str(d.get("addr") or "")
            play_t = intro_m.get("playtime", "")[:70]
            fee = intro_m.get("usetimefestival", "")[:70]
            spon = intro_m.get("sponsor1", "")[:40]
            tel_e = intro_m.get("sponsor1tel", "")[:40] or str(d.get("tel") or "")
            prog = intro_m.get("program", "")[:240]
            if ev_place:
                p_rows.append({"label": "행사 장소", "value": ev_place})
            if play_t:
                p_rows.append({"label": "운영 시간", "value": play_t})
            if fee:
                p_rows.append({"label": "이용 요금", "value": fee})
            if spon or tel_e:
                p_rows.append({"label": "주최·문의", "value": " · ".join(x for x in (spon, tel_e) if x)})
            if prog and len(paragraphs) < 2:
                paragraphs.append(f"주요 프로그램: {prog}")
            if ev_place:
                pull_quote = f"{reg_label} 계절 추천 축제 · {ev_place}" + (f" ({sd} ~ {ed})" if sd else "")
        else:
            p_header = "탐방 전 필수 확인 · 관람시간 · 주차 · 편의안내"
            use_t = intro_m.get("usetime", "")[:70]
            rest_a = intro_m.get("restdate", "")[:50]
            exp_g = intro_m.get("expguide", "")[:90]
            park_a = intro_m.get("parking", "")[:50]
            tel_a = intro_m.get("infocenter", "")[:50] or str(d.get("tel") or "")
            if use_t:
                p_rows.append({"label": "이용 시간", "value": use_t})
            if rest_a:
                p_rows.append({"label": "쉬는 날", "value": rest_a})
            if exp_g:
                p_rows.append({"label": "체험 안내", "value": exp_g})
            if park_a:
                p_rows.append({"label": "주차 안내", "value": park_a})
            if tel_a:
                p_rows.append({"label": "문의 안내", "value": tel_a})

        if not p_rows and d.get("addr"):
            p_rows.append({"label": "위치 주소", "value": str(d["addr"])})
        if not pull_quote:
            if d.get("coupon_title"):
                pull_quote = str(d["coupon_title"])
            elif paragraphs:
                pull_quote = paragraphs[0][:95] + ("…" if len(paragraphs[0]) > 95 else "")

        if overview_txt:
            d["overview"] = overview_txt[:220]
        if paragraphs:
            d["paragraphs"] = paragraphs[:3]
        if pull_quote:
            d["pull_quote"] = pull_quote[:130]
        if p_rows:
            d["practical_header"] = p_header
            d["practical_info"] = p_rows[:6]
        if info.get("homepage") and not d.get("url"):
            d["url"] = info["homepage"]
        if info.get("naver_reviews"):
            d["naver_reviews"] = info["naver_reviews"]

    with ThreadPoolExecutor(max_workers=10) as pool:
        list(pool.map(_enrich_one, items))

    if dirty:
        os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(cache, f, ensure_ascii=False, indent=2)


def upload_spots_to_firestore(spots_and_events: list[dict[str, Any]]) -> int:
    """전국 로컬 스팟(축제·볼거리·먹거리)을 Firestore spots 컬렉션에 업서트한다 (클릭수·평점·쿠폰 설정 보존)."""
    from firebase_client import db

    col = db().collection("spots")
    upserted = 0
    chunk_size = 200
    for i in range(0, len(spots_and_events), chunk_size):
        chunk = spots_and_events[i : i + chunk_size]
        refs = [col.document(str(d["id"])) for d in chunk if d.get("id")]
        existing_snaps = db().get_all(refs)
        existing_map = {s.id: (s.to_dict() or {}) for s in existing_snaps if s.exists}

        batch = db().batch()
        ops = 0
        for d in chunk:
            sid = str(d.get("id") or "").strip()
            if not sid:
                continue
            prev = existing_map.get(sid)
            payload: dict[str, Any] = {
                **d,
                "status": prev.get("status", "active") if prev else "active",
                "outbound_clicks": prev.get("outbound_clicks", 0) if prev else 0,
                "review_count": prev.get("review_count", 0) if prev else 0,
                "score_sum": prev.get("score_sum", 0) if prev else 0,
            }
            if prev:
                if "last_review_id" in prev:
                    payload["last_review_id"] = prev["last_review_id"]
                if "admin_override_sponsor" in prev:
                    payload["is_sponsored"] = bool(prev.get("is_sponsored", False))
                    payload["coupon_title"] = prev.get("coupon_title", "")
                    payload["cpc_rate"] = prev.get("cpc_rate", 500)
                    payload["admin_override_sponsor"] = True
            batch.set(col.document(sid), payload)
            ops += 1
            upserted += 1
        if ops > 0:
            batch.commit()
    print(f"[Firestore 스팟 동기화] 전국 축제·볼거리·먹거리 {upserted}곳 업서트 완료")
    return upserted


def build_hub_json(
    out_path: str = "app/web/data/public_travel_hub.json",
    upload_spots: bool = False,
) -> dict[str, Any]:
    print("[1/5] 한국관광공사 전국 축제·행사(searchFestival2) 조회 중...")
    festivals = fetch_festivals(limit=36)
    print(f"  → 진행·예정 축제 {len(festivals)}건 수집")

    print("[2/5] 전국 17개 시·도 볼거리(12) & 먹거리(39) 균등 수집 중...")
    spots = fetch_17_provinces_spots(per_province_attractions=8, per_province_foods=8)
    prov_counts = {p: sum(1 for s in spots if s.get("province") == p) for p in PROVINCE_17_ORDER}
    print(f"  → 전국 17개 시도 명소·맛집 총 {len(spots)}건 수집: {prov_counts}")

    print("[2.5/5] 전국 축제·먹거리·볼거리 매거진 상세정보(TourAPI + 네이버 방문기) 보강 중...")
    enrich_spots_and_festivals_details([*festivals, *spots])
    enriched_cnt = sum(1 for x in [*festivals, *spots] if x.get("paragraphs") or x.get("naver_reviews"))
    print(f"  → 매거진 상세·방문기 보강 완료: {enriched_cnt}/{len(festivals) + len(spots)}건")

    print("[3/5] 한국관광공사 공식 추천 여행코스(contentTypeId=25) 조회 중...")
    courses = fetch_travel_courses(limit=12)
    print(f"  → 추천 여행코스 매거진 {len(courses)}건 수집")

    print("[4/5] 반값여행·지자체 지원 가이드(네이버 오픈 API) 조회 중...")
    subsidy_guides = fetch_naver_subsidy_guides()
    print(f"  → 실전 신청 가이드 {len(subsidy_guides)}건 수집")

    print("[5/5] 지도 연동 숙소 경량 색인(lat/lng/province) 동기화 중...")
    refresh_stays_lightweight_index()

    story_spot_docs: list[dict[str, Any]] = []
    for st in DAILY_MUNICIPAL_STORIES:
        imgs = st.get("images") or []
        story_spot_docs.append({
            "id": st["id"],
            "category": "attraction",
            "is_story": True,
            "title": st["title"],
            "province": st["province"],
            "city": st.get("city", ""),
            "address": st.get("address", ""),
            "lat": st["lat"],
            "lng": st["lng"],
            "image": imgs[0] if imgs else "",
            "images": imgs,
            "tel": st.get("phone", ""),
            "summary": st.get("pull_quote", ""),
            "season_badge": st.get("season_badge", ""),
            "source_book": st.get("source_book", ""),
            "paragraphs": st.get("paragraphs", []),
            "practical_header": st.get("practical_header", ""),
            "practical_info": st.get("practical_info", []),
            "pdf_links": st.get("pdf_links", []),
            "en_summary": st.get("en_summary", ""),
            "naver_map_url": f"https://map.naver.com/p/search/{quote(st['province'] + ' ' + st['title'])}",
        })

    payload = {
        "updated_at": int(time.time() * 1000),
        "provinces": PROVINCE_17_ORDER,
        "daily_stories": DAILY_MUNICIPAL_STORIES,
        "municipal_ebooks": MUNICIPAL_EBOOKS,
        "traditional_markets": TRADITIONAL_5DAY_MARKETS,
        "spots": spots,
        "festivals": festivals,
        "courses": courses,
        "half_price_regions": HALF_PRICE_REGIONS,
        "global_benefits": GLOBAL_BENEFIT_CARDS,
        "public_magazines": PUBLIC_MAGAZINES,
        "subsidy_guides": subsidy_guides,
    }
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
    print(f"[완료] 전국 17개 시도 통합 로컬 허브 저장: {out_path} ({os.path.getsize(out_path)/1024:.1f} KB)")

    if upload_spots:
        upload_spots_to_firestore([*story_spot_docs, *festivals, *spots])
    return payload


def main() -> None:
    ap = argparse.ArgumentParser(description="전국 17개 시도 지자체 E-book·볼거리·먹거리·축제 통합 허브 빌더")
    ap.add_argument("--out", default="app/web/data/public_travel_hub.json")
    ap.add_argument("--enrich-stays", action="store_true", help="버킷별 상위 숙소에 체크인·개요·주변 5km 명소 보강")
    ap.add_argument("--top-per-bucket", type=int, default=5)
    ap.add_argument("--upload", action="store_true", help="보강된 상위 숙소 정보를 Firestore에 반영")
    ap.add_argument("--upload-spots", action="store_true", help="수집된 전국 축제·볼거리·먹거리 스팟을 Firestore spots에 동기화")
    args = ap.parse_args()

    build_hub_json(args.out, upload_spots=args.upload_spots)
    if args.enrich_stays:
        enrich_top_stays_with_tour_details(per_bucket_top=args.top_per_bucket, upload=args.upload)


if __name__ == "__main__":
    main()
