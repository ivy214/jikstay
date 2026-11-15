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

describe("CPC 과금 중복 판정용 클라이언트 IP", () => {
  it("Hosting CDN이 넣는 fastly-client-ip를 가장 먼저 사용", () => {
    assert.equal(
      fn.resolveClientIp({ "fastly-client-ip": "203.0.113.7", "x-forwarded-for": "1.1.1.1, 203.0.113.7" }),
      "203.0.113.7"
    );
  });

  it("요청자가 조작할 수 있는 X-Forwarded-For 첫 값은 무시하고 마지막 값을 사용", () => {
    const a = fn.resolveClientIp({ "x-forwarded-for": "9.9.9.1, 198.51.100.20" });
    const b = fn.resolveClientIp({ "x-forwarded-for": "9.9.9.2, 198.51.100.20" });
    assert.equal(a, "198.51.100.20");
    assert.equal(a, b);
  });

  it("헤더가 없으면 unknown", () => {
    assert.equal(fn.resolveClientIp({}), "unknown");
  });

  it("일일 과금 상한은 KST 날짜 기준", () => {
    // 2026-11-15 15:30 UTC = 2026-11-16 00:30 KST
    assert.equal(fn.kstDay(Date.UTC(2026, 10, 15, 15, 30)), "2026-11-16");
    assert.equal(fn.kstDay(Date.UTC(2026, 10, 15, 14, 59)), "2026-11-15");
  });
});
