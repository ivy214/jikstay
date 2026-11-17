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
    assert.match(koHtml, /애월 돌담 스테이 \| 직스테이/);
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
