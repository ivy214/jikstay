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
    assert.match(regHtml, /Jeonbuk Official Tourist Maps PDF/);
    assert.match(regHtml, /"@type":"TouristDestination"/);
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
