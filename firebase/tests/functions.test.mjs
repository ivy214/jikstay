import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const fn = require("../functions/index.js");

const SAMPLE_TPL = `<!DOCTYPE html>
<html>
<head>
  <title>직스테이</title>
  <meta name="description" content="기본 설명">
  <meta property="og:title" content="기본 제목">
  <meta property="og:description" content="기본 OG 설명">
</head>
<body>
</body>
</html>`;

describe("Cloud Functions 다국어 SEO 및 스키마 생성", () => {
  const sampleListing = {
    title: "애월 돌담 스테이",
    region_depth1: "제주특별자치도",
    region_depth2: "제주시 애월읍",
    license_type: "농어촌민박업",
    images: [{ url: "https://tong.visitkorea.or.kr/cms/sample.jpg" }],
    location_info: { display_address: "제주특별자치도 제주시 애월읍 10", public_phone: "064-000-0000" },
    naver_reviews: [{ title: "제주 애월 방문기", summary: "조용하고 깨끗한 합법 민박" }],
    review_count: 4,
    score_sum: 19,
    i18n: {
      en: { title: "Aewol Stone Stay (Jeju Island)", summary: "Verified legal homestay in Jeju." },
      ja: { title: "涯月石垣ステイ（済州島）", summary: "自治体認可済の合法民宿。" },
      zh: { title: "涯月石牆民宿（濟州島）", summary: "政府合法認證民宿。" },
    },
  };

  it("한국어·영어·일본어·번체중국어 OG, hreflang, JSON-LD, noscript 요약 주입", () => {
    const koHtml = fn.buildOgHtml(SAMPLE_TPL, sampleListing, "stay_pub_abc123", "https://jikstay.kr", "ko");
    assert.match(koHtml, /<html lang="ko">/);
    assert.match(koHtml, /애월 돌담 스테이 \(제주 펜션·민박\) \| 직스테이/);
    assert.match(koHtml, /"@type":"LodgingBusiness"/);
    assert.match(koHtml, /"@type":"AggregateRating"/);
    assert.match(koHtml, /"ratingValue":4\.75/);
    assert.match(koHtml, /hreflang="zh-Hant"/);
    assert.match(koHtml, /제주 애월 방문기/);

    const enHtml = fn.buildOgHtml(SAMPLE_TPL, sampleListing, "stay_pub_abc123", "https://jikstay.kr", "en");
    assert.match(enHtml, /<html lang="en">/);
    assert.match(enHtml, /Aewol Stone Stay \(Jeju Island\)/);
    assert.match(enHtml, /Verified legal homestay in Jeju\./);

    const jaHtml = fn.buildOgHtml(SAMPLE_TPL, sampleListing, "stay_pub_abc123", "https://jikstay.kr", "ja");
    assert.match(jaHtml, /<html lang="ja">/);
    assert.match(jaHtml, /涯月石垣ステイ/);
  });

  it("JSON-LD 내부 </script> 문자열 탈출 차단", () => {
    const xssListing = { ...sampleListing, title: "</script><script>alert(1)</script>" };
    const html = fn.buildOgHtml(SAMPLE_TPL, xssListing, "stay_pub_xss123", "https://jikstay.kr", "ko");
    assert.ok(!html.includes("</script><script>alert(1)"));
  });

  it("로컬 축제·맛집 스팟(?spot=...) 및 17개 시도 랜딩(?region=...) Programmatic SEO 메타·JSON-LD 생성", () => {
    const evSpot = {
      kind: "event",
      province: "전북",
      title: "장수 한우랑사과랑 축제",
      addr: "전북특별자치도 장수군 장수읍",
      lat: 35.6473,
      lng: 127.5215,
      start_date: "20261110",
      end_date: "20261120",
      review_count: 2,
      score_sum: 10,
    };
    const evHtml = fn.buildSpotOgHtml(SAMPLE_TPL, evSpot, "spot_event_999", "https://jikstay.kr", "ko");
    assert.match(evHtml, /"@type":"Festival"/);
    assert.match(evHtml, /"startDate":"2026-11-10"/);
    assert.match(evHtml, /"@type":"GeoCoordinates"/);
    assert.match(evHtml, /"ratingValue":5/);

    const regHtml = fn.buildRegionOgHtml(SAMPLE_TPL, "전북", "https://jikstay.kr", "en");
    assert.match(regHtml, /<html lang="en">/);
    assert.match(regHtml, /Things to Do in Jeonbuk, Korea/);
    assert.match(regHtml, /"@type":"TouristDestination"/);
  });
});

describe("검색엔진용 본문 (<main id=jikstay-seo>) — 번역·주변 링크", () => {
  // serveApp 이 호스팅의 정적 파일에서 받아 넘기는 데이터와 같은 모양
  const seoData = {
    hub: {
      spots: [
        { id: "spot_at_1", kind: "attraction", title: "경복궁", province: "서울", lat: 37.5796, lng: 126.977 },
        { id: "spot_at_2", kind: "attraction", title: "창덕궁", province: "서울", lat: 37.5794, lng: 126.991 },
        { id: "spot_fo_3", kind: "food", title: "광장시장", province: "서울", lat: 37.57, lng: 126.999 },
        { id: "spot_at_9", kind: "attraction", title: "해운대", province: "부산", lat: 35.16, lng: 129.16 },
      ],
      festivals: [{ id: "spot_ev_5", kind: "event", title: "서울빛초롱축제", province: "서울", end_date: "20991231" }],
    },
    i18nCore: {
      items: {
        spot_at_1: { title: "Gyeongbokgung Palace", addr: "161 Sajik-ro, Jongno-gu, Seoul", overview: "The main royal palace of the Joseon dynasty." },
        spot_at_2: { title: "Changdeokgung Palace" },
      },
      stays: { stay_pub_abc123: { title: "Aewol Stonewall Stay", region: "Aewol-eup, Jeju-si", summary: "['Location: 10 Aewol', 'Parking: 2 cars']" } },
    },
    i18nDetail: { spot_at_1: { paragraphs: ["Built in 1395."], practical_info: [{ label: "Closed", value: "Tuesdays" }] } },
  };
  const gyeongbok = {
    kind: "attraction", province: "서울", title: "경복궁", addr: "서울특별시 종로구 사직로 161",
    overview: "조선의 법궁", paragraphs: ["1395년 창건"], lat: 37.5796, lng: 126.977,
  };

  it("영어 볼거리 페이지: 번역된 이름·설명·본문, 한국어 이름은 alternateName, 가까운 곳 링크", () => {
    const html = fn.buildSpotOgHtml(SAMPLE_TPL, gyeongbok, "spot_at_1", "https://jikstay.kr", "en", seoData);
    assert.match(html, /<title>Gyeongbokgung Palace \(Seoul\) \| Jikstay Korea<\/title>/);
    assert.match(html, /The main royal palace of the Joseon dynasty\./);
    assert.match(html, /"alternateName":"경복궁"/);
    assert.match(html, /<main id="jikstay-seo" lang="en">/);
    assert.match(html, /<p>Built in 1395\.<\/p>/);
    assert.match(html, /Closed: Tuesdays/);
    assert.ok(!html.includes("<noscript"), "본문은 JS 실행 후에도 남도록 noscript 가 아닌 실제 요소");
    // 가까운 순: 창덕궁(번역 이름) 이 광장시장보다 앞, 다른 시·도(해운대)는 없음, 자기 자신도 없음
    assert.ok(html.indexOf("Changdeokgung Palace") < html.indexOf("광장시장"));
    const main = html.slice(html.indexOf('<main id="jikstay-seo"'));
    assert.ok(!main.includes("해운대") && !main.includes("?spot=spot_at_1&amp;lang=en\">"));
    assert.match(html, /href="https:\/\/jikstay\.kr\/\?spot=spot_at_2&amp;lang=en"/);
  });

  it("번역이 없으면 한국어 원문으로 (데이터를 못 받아도 페이지는 나감)", () => {
    const html = fn.buildSpotOgHtml(SAMPLE_TPL, gyeongbok, "spot_at_1", "https://jikstay.kr", "ja", null);
    assert.match(html, /<html lang="ja">/);
    assert.match(html, /경복궁（ソウル）/);
    assert.match(html, /1395년 창건/);
  });

  it("숙소 페이지: 번역 번들의 제목 우선(문서 i18n 이 한국어 상호면), 목록 문자열 요약 정리", () => {
    const listing = {
      title: "애월 돌담 스테이", region_depth1: "제주특별자치도", region_depth2: "제주시 애월읍", license_type: "농어촌민박업",
      location_info: { display_address: "제주특별자치도 제주시 애월읍 10" },
      i18n: { en: { title: "애월 돌담 스테이 (Jeju)", summary: "A stay in Jeju." } },
    };
    const html = fn.buildOgHtml(SAMPLE_TPL, listing, "stay_pub_abc123", "https://jikstay.kr", "en", seoData);
    assert.match(html, /<title>Aewol Stonewall Stay \| JikStay Korea<\/title>/);
    assert.match(html, /Location: 10 Aewol · Parking: 2 cars/);
    assert.match(html, /Aewol-eup, Jeju-si/);
    assert.match(html, /href="https:\/\/jikstay\.kr\/\?region=%EC%A0%9C%EC%A3%BC&amp;lang=en">Jeju</);
  });

  it("지역 페이지: 축제·볼거리·먹거리 링크 목록(번역 이름)과 숙소", () => {
    const stays = { items: [{ listing_id: "stay_pub_s1", title: "서울 한옥", province: "서울", curated_score: 9 }] };
    const html = fn.buildRegionOgHtml(SAMPLE_TPL, "서울", "https://jikstay.kr", "en", seoData, stays);
    assert.match(html, /Seoul · Festivals &amp; events<\/h2><ul><li><a [^>]+>서울빛초롱축제/);
    assert.match(html, /Seoul · Things to do<\/h2><ul><li><a [^>]+>Gyeongbokgung Palace/);
    assert.match(html, /Seoul · Local food<\/h2><ul><li><a [^>]+>광장시장/);
    assert.match(html, /href="https:\/\/jikstay\.kr\/\?id=stay_pub_s1&amp;lang=en">서울 한옥/);
    assert.ok(!html.includes("해운대"));
  });

  it("보조 함수: 시·도 줄임, 목록 문자열 요약, 사이트맵 lastmod", () => {
    assert.equal(fn.shortProvince("서울특별시"), "서울");
    assert.equal(fn.shortProvince("충청북도"), "충북");
    assert.equal(fn.shortProvince("전북특별자치도"), "전북");
    assert.equal(fn.shortProvince("전남광주통합특별시"), "전남");
    assert.equal(fn.cleanListSummary("['A', 'B']"), "A · B");
    assert.equal(fn.cleanListSummary("plain"), "plain");
    assert.equal(fn.lastmodTag({ updateTime: { toDate: () => new Date("2026-11-16T03:00:00Z") } }), "\n    <lastmod>2026-11-16</lastmod>");
    assert.equal(fn.lastmodTag({}), "");
  });
});

describe("숙소 외부 연결(/go) 이동 대상", () => {
  it("운영자 직거래 링크가 있으면 그 링크로 이동", () => {
    assert.equal(fn.directBookingUrl({ direct_booking_url: " https://pension.example.com/book " }), "https://pension.example.com/book");
  });

  it("네이버 지도 URL·잘못된 스킴·빈 값은 직거래 링크로 보지 않음 (네이버 지도 검색으로 대체)", () => {
    assert.equal(fn.directBookingUrl({ direct_booking_url: "https://map.naver.com/p/search/abc" }), "");
    assert.equal(fn.directBookingUrl({ direct_booking_url: "javascript:alert(1)" }), "");
    assert.equal(fn.directBookingUrl({}), "");
  });
});

describe("대표 도메인 이동", () => {
  it("Firebase 기본 주소만 jikstay.app 으로 보내고 경로·쿼리는 유지", () => {
    assert.equal(fn.primaryDomainRedirectUrl("jikstay-lkxu1.web.app", "/?spot=spot_at_1&lang=en"), "https://jikstay.app/?spot=spot_at_1&lang=en");
    assert.equal(fn.primaryDomainRedirectUrl("jikstay-lkxu1.firebaseapp.com", "/sitemap.xml"), "https://jikstay.app/sitemap.xml");
    assert.equal(fn.primaryDomainRedirectUrl("jikstay.app", "/"), "");
    assert.equal(fn.primaryDomainRedirectUrl("www.jikstay.app", "/"), "");
    assert.equal(fn.primaryDomainRedirectUrl("", "/"), "");
  });
});

describe("숙소 한국어 검색 제목", () => {
  it("지역(시·군 / 광역시 구)과 검색어로 쓰는 업종을 붙인다", () => {
    const q = fn.stayTitleQualifierKo;
    assert.equal(q({ region_depth1: "충청남도", region_depth2: "태안군 남면", license_type: "농어촌민박업" }), "태안 펜션·민박");
    assert.equal(q({ region_depth1: "제주특별자치도", region_depth2: "서귀포시", license_type: "한옥체험업" }), "서귀포 한옥스테이");
    assert.equal(q({ region_depth1: "부산광역시", region_depth2: "해운대구", license_type: "외국인관광도시민박업" }), "부산 해운대구 게스트하우스");
    assert.equal(q({ region_depth1: "세종특별자치시", region_depth2: "", license_type: "일반/생활숙박업" }), "세종 숙소");
    assert.equal(q({ title: "펜션이룸", region_depth1: "경기도", region_depth2: "가평군", license_type: "일반/생활숙박업" }), "가평 펜션");
  });

  it("검색 제목에는 붙이고 본문 제목(h1)은 상호만", () => {
    const listing = { title: "그림일기펜션", region_depth1: "충청남도", region_depth2: "태안군 남면", license_type: "농어촌민박업" };
    const html = fn.buildOgHtml(SAMPLE_TPL, listing, "stay_pub_abc123", "https://jikstay.app", "ko", null);
    assert.match(html, /<title>그림일기펜션 \(태안 펜션·민박\) \| 직스테이<\/title>/);
    assert.doesNotMatch(html, /<h1>[^<]*\(태안/);
  });
});

describe("주제 페이지 (축제 일정 · 5일장 장날)", () => {
  const hub = {
    festivals: [
      { id: "spot_ev_1", title: "진행축제", province: "전북", region_label: "전북 남원시", start_date: "20261101", end_date: "20261130" },
      { id: "spot_ev_2", title: "예정축제", province: "전북", region_label: "전북 전주시", start_date: "20261220", end_date: "20261225" },
      { id: "spot_ev_3", title: "끝난축제", province: "전북", start_date: "20260101", end_date: "20260102" },
    ],
    traditional_markets: [{ id: "mkt_a", province: "전북", city: "무주군", title: "무주장", days: [1, 6], specialty: "어죽" }],
  };

  it("5일장 장날과 다음 장날 (31일 제외, 다음 달로 넘어감)", () => {
    assert.deepEqual(fn.marketDaysOfMonth([1, 6]), [1, 6, 11, 16, 21, 26]);
    assert.equal(fn.nextMarketYmd([1, 6], "20261117"), "20261121");
    assert.equal(fn.nextMarketYmd([1, 6], "20261127"), "20261201");
    assert.equal(fn.nextMarketYmd([1, 6], "20261121"), "20261121");
  });

  it("지역 축제 페이지: 진행·예정만, 끝난 축제 제외, 제목에 지역·연도", () => {
    const html = fn.buildTopicOgHtml(SAMPLE_TPL, "festival", "전북", "https://jikstay.app", "ko", { hub });
    assert.match(html, /<title>전북 축제 일정 \d{4} · 지역 축제·행사 모음 \| 직스테이 로컬<\/title>/);
    assert.match(html, /진행축제/);
    assert.match(html, /예정축제/);
    assert.doesNotMatch(html, /끝난축제/);
    assert.match(html, /rel="canonical" href="https:\/\/jikstay\.app\/\?topic=festival&amp;region=%EC%A0%84%EB%B6%81"/);
  });

  it("5일장 페이지: 장날·특산물 표시", () => {
    const html = fn.buildTopicOgHtml(SAMPLE_TPL, "market", "", "https://jikstay.app", "ko", { hub });
    assert.match(html, /<title>전국 5일장 장날 일정/);
    assert.match(html, /무주장<\/strong> — 전북 무주군 · 매월 1·6·11·16·21·26일/);
    assert.match(html, /어죽/);
  });
});

describe("전통시장 상세 페이지", () => {
  it("검색 제목에 시·군과 시장 종류·장날을 붙이고 Store 스키마", () => {
    const spot = { title: "간성전통시장", kind: "market", market_type: "5일장", days: [2, 7], province: "강원", city: "고성군", region_label: "강원 고성군 간성읍", status: "active" };
    const html = fn.buildSpotOgHtml(SAMPLE_TPL, spot, "spot_mk_132783", "https://jikstay.app", "ko", null);
    assert.match(html, /<title>간성전통시장 \(고성 5일장 · 장날\) \| 직스테이 로컬<\/title>/);
    assert.match(html, /"@type":"Store"/);
  });
});

describe("공연·전시", () => {
  const culture = [
    { id: "spot_cu_1", kind: "culture", culture_type: "전시", realm: "전시", title: "개방 수장고", province: "충북", city: "청주시", place: "국립현대미술관 청주관", start_date: "20201203", end_date: "20991231", price_text: "무료" },
    { id: "spot_cu_2", kind: "culture", culture_type: "공연", realm: "연극", title: "오백에 삼십", province: "서울", city: "종로구", place: "JTN아트홀", start_date: "20200101", end_date: "20991231" },
    { id: "spot_cu_3", kind: "culture", culture_type: "공연", realm: "연극", title: "끝난공연", province: "서울", start_date: "20200101", end_date: "20200102" },
  ];

  it("전국 전시·공연 페이지: 전시·공연을 나눠 보여 주고 끝난 것은 뺀다", () => {
    const html = fn.buildTopicOgHtml(SAMPLE_TPL, "culture", "", "https://jikstay.app", "ko", { hub: {}, culture });
    assert.match(html, /<title>전국 전시회·공연 일정 \d{4}/);
    assert.match(html, /지금 볼 수 있는 전시/);
    assert.match(html, /개방 수장고 \(충북 국립현대미술관 청주관/);
    assert.match(html, /오백에 삼십/);
    assert.doesNotMatch(html, /끝난공연/);
  });

  it("상세: 검색 제목에 시·군과 종류, 구조화 데이터는 Event + 장소", () => {
    const spot = { ...culture[0], region_label: "충북 청주시", status: "active", url: "https://www.mmca.go.kr/x" };
    const html = fn.buildSpotOgHtml(SAMPLE_TPL, spot, "spot_cu_1", "https://jikstay.app", "ko", null);
    assert.match(html, /<title>개방 수장고 \(청주 전시\) \| 직스테이 로컬<\/title>/);
    assert.match(html, /"@type":"ExhibitionEvent"/);
    assert.match(html, /"location":\{"@type":"Place","name":"국립현대미술관 청주관"/);
    assert.match(html, /"startDate":"2020-12-03"/);
  });
});

describe("끝난 축제·공연·전시", () => {
  it("종료일이 지나면 종료 안내 + noindex, 같은 지역 진행 중 일정으로 연결", () => {
    const spot = { title: "지난 연극", kind: "culture", province: "부산", end_date: "20200102", status: "active" };
    assert.equal(fn.isEndedSpot(spot), true);
    assert.equal(fn.isEndedSpot({ ...spot, end_date: "20991231" }), false);
    assert.equal(fn.isEndedSpot({ ...spot, end_date: "20991231", status: "ended" }), true);
    const data = { hub: { festivals: [{ id: "spot_ev_9", title: "부산 진행축제", province: "부산", start_date: "20200101", end_date: "20991231" }] }, culture: [] };
    const html = fn.buildEndedSpotHtml(SAMPLE_TPL, spot, "spot_cu_x", "https://jikstay.app", "ko", data);
    assert.match(html, /<title>지난 연극 \(종료\) \| 직스테이 로컬<\/title>/);
    assert.match(html, /<meta name="robots" content="noindex,follow">/);
    assert.match(html, /2020\.01\.02에 종료되었습니다/);
    assert.match(html, /부산 진행축제/);
  });
});

describe("홈 오늘의 스토리 (스플래시 = 앱 첫 화면)", () => {
  const ts = require("../functions/today_story.js");
  const fs = require("node:fs");
  const path = require("node:path");
  const story = (id, months = []) => ({ id, title: `스토리 ${id}`, months, images: [`https://img/${id}.jpg`], province: "전북", city: "장수군",
    season_badge: "🍂 가을", source_book: "장수여행", subtitle: "장수군 주소", pull_quote: "" , paragraphs: ["첫 문단"] });
  const fest = (id, start, extra = {}) => ({ id, kind: "event", title: `축제 ${id}`, province: "부산", region_label: "부산 해운대구",
    image_url: `https://img/${id}.png`, start_date: start, end_date: "20261231", addr: "부산 해운대구 BEXCO", overview: "개요", ...extra });

  it("개막 0~7일 축제를 가까운 순으로 앞에 두고, 이번 달 스토리와 함께 날짜로 순환한다", () => {
    const hub = {
      daily_stories: [story("a", [11]), story("b", [6]), story("c")],
      festivals: [fest("far", "20261130"), fest("d2", "20261120"), fest("d0", "20261118"), fest("noimg", "20261119", { image_url: "" }),
        fest("ended", "20261101", { end_date: "20261117" })],
      municipal_ebooks: [{ id: "ebook_busan", province: "부산", title: "부산 관광 e북" }],
    };
    // 15~18일 모두 pool = [d0, d2, a, c] (far 는 D-7 밖, noimg·ended 제외, b 는 6월 전용) → 2026-11-15 부터 하루씩 순환
    const ids = ["20261115", "20261116", "20261117", "20261118"].map((d) => ts.pickTodayStory(hub, d).id);
    assert.deepEqual(ids, ["d0", "d2", "a", "c"]);
    const on15 = ts.pickTodayStory(hub, "20261115"); // 그날 기준 d0 개막 D-3
    assert.equal(on15.id, "d0");
    assert.equal(on15.badge, "⏳ 개막 D-3 · 임박 축제");
    assert.equal(on15.region, "부산 해운대구");
    assert.equal(on15.sourceBook, "부산 관광 e북");
    assert.equal(on15.summary, "개요");
    assert.equal(on15.addressLine, "부산 해운대구 BEXCO");
    assert.equal(ts.pickTodayStory(hub, "20261116").id, "d2");
    assert.ok(!ids.includes("noimg") && !ids.includes("ended") && !ids.includes("b"));
    assert.equal(ts.pickTodayStory({ daily_stories: [] }, "20261118"), null);
  });

  it("스토리 요약은 pull_quote → 첫 문단 → subtitle 순 (빈 pull_quote 는 건너뜀)", () => {
    const s = ts.storyFromJson(story("x"));
    assert.equal(s.summary, "첫 문단");
    assert.equal(s.region, "전북 장수군");
    assert.equal(s.image, "https://img/x.jpg");
  });

  it("실제 템플릿의 스플래시를 채우고 앱용 힌트를 심는다", () => {
    const tpl = fs.readFileSync(path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "../functions/index.html"), "utf8");
    const st = ts.pickTodayStory({ daily_stories: [story("z<1>")], festivals: [] }, "20261119");
    const html = ts.injectTodayStory(tpl, st, "20261119");
    assert.match(html, /<span class="js-badge-dark">📖 11월 19일 오늘의 로컬 스토리<\/span>/);
    assert.match(html, /<p class="js-story-title">스토리 z&lt;1&gt;<\/p>/);
    assert.match(html, /<img src="https:\/\/img\/z&lt;1&gt;\.jpg" alt="스토리 z&lt;1&gt;"/);
    assert.match(html, /<span class="js-story-addr">📍 장수군 주소<\/span>/);
    // id 의 < 는 \u003c 로 이스케이프되어 </script> 를 끊지 못한다
    assert.ok(html.includes(String.raw`<script>window.jikstayTodayStory = {"id":"z\u003c1>","badge":"🍂 가을","date":"20261119"};</script>`));
    assert.ok(html.indexOf("window.jikstayTodayStory") < html.indexOf("</head>"));
    assert.match(html, /<link rel="preload" as="image" href="https:\/\/img\/z&lt;1&gt;\.jpg" fetchpriority="high">/);
    assert.equal(ts.injectTodayStory(tpl, null, "20261119"), tpl);
    const noImg = ts.injectTodayStory(tpl, { ...st, image: "" }, "20261119");
    assert.match(noImg, /<div class="js-story-img-wrap" style="display:none">/);
  });
});
