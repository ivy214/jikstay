const fs = require("node:fs");
const path = require("node:path");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

const seo = require("./seo_content");
const todayStory = require("./today_story");
const rss = require("./rss");

initializeApp();

const LISTING_ID_RE = /^stay_[a-zA-Z0-9_-]{4,32}$/;
const SPOT_ID_RE = /^[a-zA-Z0-9_-]{4,64}$/;
const PROVINCES_17 = [
  "서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
  "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주",
];
const PROVINCE_EN = {
  서울: "Seoul", 부산: "Busan", 대구: "Daegu", 인천: "Incheon", 광주: "Gwangju",
  대전: "Daejeon", 울산: "Ulsan", 세종: "Sejong", 경기: "Gyeonggi", 강원: "Gangwon",
  충북: "Chungbuk", 충남: "Chungnam", 전북: "Jeonbuk", 전남: "Jeonnam", 경북: "Gyeongbuk",
  경남: "Gyeongnam", 제주: "Jeju",
};
const PROVINCE_JA = {
  서울: "ソウル", 부산: "釜山", 대구: "大邱", 인천: "仁川", 광주: "光州", 대전: "大田", 울산: "蔚山", 세종: "世宗",
  경기: "京畿道", 강원: "江原道", 충북: "忠清北道", 충남: "忠清南道", 전북: "全羅北道", 전남: "全羅南道",
  경북: "慶尚北道", 경남: "慶尚南道", 제주: "済州",
};
const PROVINCE_ZH = {
  서울: "首爾", 부산: "釜山", 대구: "大邱", 인천: "仁川", 광주: "光州", 대전: "大田", 울산: "蔚山", 세종: "世宗",
  경기: "京畿道", 강원: "江原道", 충북: "忠清北道", 충남: "忠清南道", 전북: "全羅北道", 전남: "全羅南道",
  경북: "慶尚北道", 경남: "慶尚南道", 제주: "濟州",
};
const SUPPORTED_LANGS = new Set(["ko", "en", "ja", "zh"]);
const HANGUL_RE = /[가-힣]/;

function provinceLabel(prov, lang) {
  if (lang === "en") return PROVINCE_EN[prov] || prov;
  if (lang === "ja") return PROVINCE_JA[prov] || prov;
  if (lang === "zh") return PROVINCE_ZH[prov] || prov;
  return prov;
}

/** '서울특별시'→'서울', '충청북도'→'충북', '전북특별자치도'→'전북', '전남광주통합특별시'→'전남' */
function shortProvince(name) {
  const s = String(name || "").trim();
  if (/^(충청|전라|경상)/.test(s)) return s[0] + s[2];
  return s.slice(0, 2);
}

/** "['위치: …', '주차 …']" 처럼 목록이 문자열로 저장된 요약을 '위치: … · 주차 …' 로 */
function cleanListSummary(s) {
  const t = String(s || "").trim();
  if (!(t.startsWith("[") && t.endsWith("]"))) return t;
  const parts = t.slice(1, -1).match(/'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"/g);
  return parts ? parts.map((p) => p.slice(1, -1)).filter(Boolean).join(" · ") : t;
}
const BOT_UA_RE =
  /bot|crawler|spider|slurp|yeti|daumoa|bingpreview|facebookexternalhit|kakaotalk-scrap|slackbot|discordbot|whatsapp|telegrambot|headless|curl|wget|python-requests/i;
const TEMPLATE_PATH = path.join(__dirname, "index.html");
const CACHED_TEMPLATE = fs.existsSync(TEMPLATE_PATH) ? fs.readFileSync(TEMPLATE_PATH, "utf8") : "";

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalizeLang(rawLang) {
  const s = String(rawLang ?? "").trim().toLowerCase();
  if (s.startsWith("en")) return "en";
  if (s.startsWith("ja")) return "ja";
  if (s.startsWith("zh")) return "zh";
  return SUPPORTED_LANGS.has(s) ? s : "ko";
}

function fallbackNaverMapUrl(listing) {
  if (typeof listing.naver_map_url === "string" && /^https?:\/\//i.test(listing.naver_map_url)) {
    return listing.naver_map_url;
  }
  const q = [listing.region_depth1, listing.region_depth2, listing.title].filter(Boolean).join(" ").trim() || "숙소";
  return `https://map.naver.com/p/search/${encodeURIComponent(q)}`;
}

// 숙소 업종 → 사람들이 실제로 검색하는 말 (검색 제목용)
const STAY_KIND_KO = {
  "한옥체험업": "한옥스테이",
  "외국인관광도시민박업": "게스트하우스",
  "농어촌민박업": "펜션·민박",
  "관광펜션업": "펜션",
  "관광숙박업": "호텔",
};

/** 검색 제목용 지역 이름: "태안군 남면" → "태안", "서귀포시" → "서귀포", "해운대구" → "부산 해운대구" */
function stayRegionShort(listing) {
  const prov = shortProvince(listing.region_depth1);
  const first = String(listing.region_depth2 || "").trim().split(/\s+/)[0] || "";
  if (/^[가-힣]{2,}[시군]$/.test(first)) return first.slice(0, -1);
  if (/^[가-힣]+구$/.test(first)) return prov ? `${prov} ${first}` : first;
  return prov;
}

/** 한국어 숙소 검색 제목 괄호 안: "태안 펜션·민박" (지역·업종 중 아는 것만) */
function stayTitleQualifierKo(listing) {
  let kind = STAY_KIND_KO[String(listing.license_type || "").trim()] || "";
  if (!kind) {
    // 일반/생활숙박업은 펜션·모텔·호텔이 섞여 있어 상호에 든 말을 쓴다
    const m = String(listing.title || "").match(/(풀빌라|펜션|리조트|호텔|모텔|레지던스|게스트하우스|글램핑|캠핑)/);
    kind = m ? m[1] : "숙소";
  }
  return [stayRegionShort(listing), kind].filter(Boolean).join(" ");
}

function buildLocalizedMeta(listing, lang, tStay = null) {
  const docI18n = listing && typeof listing.i18n === "object" ? listing.i18n[lang] : null;
  // 숙소 문서의 i18n 제목은 한국어 상호 그대로인 경우가 많다('리코 하우스 2 (Seoul)').
  // 번역 번들(translations_{lang}.json 의 stays)에 제대로 번역된 제목이 있으면 그것을 쓴다.
  const i18n = docI18n ? { ...docI18n } : {};
  if (tStay && tStay.title && (!i18n.title || HANGUL_RE.test(i18n.title))) i18n.title = String(tStay.title);
  const region = [listing.region_depth1, listing.region_depth2].filter(Boolean).join(" ").trim();
  const points = Array.isArray(listing.summary_points) ? listing.summary_points.slice(0, 2).join(" · ") : "";

  if (lang === "en") {
    const title = (i18n && i18n.title) || listing.title || "Local Stay in Korea";
    return {
      htmlLang: "en",
      titleText: `${title} | JikStay Korea`,
      descText:
        (i18n && i18n.summary) ||
        `Stay in ${region} listed in Korean public tourism data. See the location, official links and local reviews, then contact the property directly.`,
    };
  }
  if (lang === "ja") {
    const title = (i18n && i18n.title) || listing.title || "韓国の宿泊施設";
    return {
      htmlLang: "ja",
      titleText: `${title} | JikStay Korea`,
      descText:
        (i18n && i18n.summary) ||
        `韓国の公共観光データに登録された${region}の宿泊施設。場所・公式リンク・現地レビューを確認できます。`,
    };
  }
  if (lang === "zh") {
    const title = (i18n && i18n.title) || listing.title || "韓國住宿";
    return {
      htmlLang: "zh-Hant",
      titleText: `${title} | JikStay 韓國`,
      descText:
        (i18n && i18n.summary) ||
        `登錄於韓國公共旅遊資料的${region}住宿。可查看位置、官方連結與在地評價。`,
    };
  }

  // "그림일기펜션 (태안 펜션·민박) | 직스테이" — 이름만으로는 "태안 펜션" 같은 검색에 걸리지 않으므로 지역·업종을 붙인다
  const titleText = listing.title
    ? `${listing.title} (${stayTitleQualifierKo(listing)}) | 직스테이`
    : "직스테이 로컬 - 공공데이터 숙소·로컬 여행 정보";
  const descText =
    [region, listing.license_type || "", points].filter(Boolean).join(" | ") ||
    "공공데이터에 등록된 숙소와 주변 볼거리·먹거리·축제를 한 번에 찾아보세요.";
  return { htmlLang: "ko", titleText, descText, heading: listing.title ? String(listing.title) : "" };
}

function buildOgHtml(template, listing, listingId, origin, rawLang = "ko", data = null) {
  const lang = normalizeLang(rawLang);
  const tStay = (lang !== "ko" && data && data.i18nCore && data.i18nCore.stays && data.i18nCore.stays[listingId]) || null;
  const { htmlLang, titleText, descText, heading } = buildLocalizedMeta(listing, lang, tStay);
  const images = Array.isArray(listing.images) ? listing.images : [];
  const imageUrl = images.length > 0 && images[0].url ? String(images[0].url) : "";
  const encodedId = encodeURIComponent(listingId);
  const canonicalUrl =
    lang === "ko" ? `${origin}/?id=${encodedId}` : `${origin}/?id=${encodedId}&lang=${encodeURIComponent(lang)}`;

  const escapedTitle = escapeHtml(titleText);
  const escapedDesc = escapeHtml(descText);
  const ogImageTag = imageUrl ? `\n  <meta property="og:image" content="${escapeHtml(imageUrl)}">` : "";
  const ogUrlTag = `\n  <meta property="og:url" content="${escapeHtml(canonicalUrl)}">`;
  const hreflangTags = [
    `\n  <link rel="canonical" href="${escapeHtml(canonicalUrl)}">`,
    `\n  <link rel="alternate" hreflang="ko" href="${escapeHtml(`${origin}/?id=${encodedId}`)}">`,
    `\n  <link rel="alternate" hreflang="en" href="${escapeHtml(`${origin}/?id=${encodedId}&lang=en`)}">`,
    `\n  <link rel="alternate" hreflang="ja" href="${escapeHtml(`${origin}/?id=${encodedId}&lang=ja`)}">`,
    `\n  <link rel="alternate" hreflang="zh-Hant" href="${escapeHtml(`${origin}/?id=${encodedId}&lang=zh`)}">`,
    `\n  <link rel="alternate" hreflang="x-default" href="${escapeHtml(`${origin}/?id=${encodedId}`)}">`,
  ].join("");

  const locInfo = listing.location_info && typeof listing.location_info === "object" ? listing.location_info : {};
  const jsonLdObj = {
    "@context": "https://schema.org",
    "@type": "LodgingBusiness",
    name: String(listing.title || ""),
    description: descText,
    url: canonicalUrl,
    address: {
      "@type": "PostalAddress",
      addressCountry: "KR",
      addressRegion: String(listing.region_depth1 || ""),
      addressLocality: String(listing.region_depth2 || ""),
      streetAddress: String(locInfo.display_address || ""),
    },
  };
  if (imageUrl) jsonLdObj.image = [imageUrl];
  if (locInfo.public_phone) jsonLdObj.telephone = String(locInfo.public_phone);
  const reviewCount = Number(listing.review_count) || 0;
  const scoreSum = Number(listing.score_sum) || 0;
  if (reviewCount > 0 && scoreSum > 0) {
    jsonLdObj.aggregateRating = {
      "@type": "AggregateRating",
      ratingValue: Number((scoreSum / reviewCount).toFixed(2)),
      reviewCount,
      bestRating: 5,
      worstRating: 1,
    };
  }
  // </script> 탈출 방지
  const safeJsonLd = JSON.stringify(jsonLdObj).replace(/</g, "\\u003c");
  const jsonLdTag = `\n  <script type="application/ld+json">${safeJsonLd}</script>`;

  const L = seo.LABELS[lang] || seo.LABELS.ko;
  const prov = shortProvince(listing.region_depth1);
  const provLabel = provinceLabel(prov, lang);
  // 본문 제목(h1)·JSON-LD 이름은 상호만 (검색 제목의 지역·업종 괄호는 빼고)
  const plainTitle = heading || titleText.replace(/\s*\|[^|]*$/, "");
  // 네이버 방문기는 한국어 원문이라 한국어 페이지에만 넣는다
  const reviews = lang === "ko" && Array.isArray(listing.naver_reviews) ? listing.naver_reviews.slice(0, 3) : [];
  const reviewHtml = reviews.length
    ? `<ul>${reviews.map((r) => `<li>${escapeHtml(r.title || "")} - ${escapeHtml(r.summary || "")}</li>`).join("")}</ul>`
    : "";
  const tSummary = tStay ? cleanListSummary(tStay.summary) : "";
  const practical = [];
  if (listing.license_type) practical.push({ label: lang === "ko" ? "업종" : "License", value: String(listing.license_type) });
  if (tSummary) practical.push({ label: L.info, value: tSummary });
  const seoMain = seo.renderSeoMain({
    lang,
    title: plainTitle,
    lead: descText,
    address: lang === "ko" ? locInfo.display_address : (tStay && tStay.region) || locInfo.display_address,
    imageUrl,
    imageAlt: plainTitle,
    practical,
    breadcrumbs: [
      { href: lang === "ko" ? `${origin}/` : `${origin}/?lang=${lang}`, text: L.home },
      seo.regionLink(origin, prov, provLabel, lang),
    ],
    sections: [
      { heading: lang === "ko" ? "방문기" : "", html: reviewHtml },
      { heading: `${provLabel} · ${L.nearby}`, html: seo.linkList(seo.nearbyLinks(origin, lang, data, { id: listingId, province: prov }, 10)) },
    ],
  });

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">${ogImageTag}${ogUrlTag}${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoMain}\n</body>`);
}

function fmtYmdIso(ymd) {
  const s = String(ymd || "").trim();
  return /^\d{8}$/.test(s) ? `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}` : "";
}

function buildSpotOgHtml(template, spot, spotId, origin, rawLang = "ko", data = null) {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const prov = String(spot.province || "");
  const provEn = PROVINCE_EN[prov] || prov || "Korea";
  const provLabel = provinceLabel(prov, lang);
  const kind = String(spot.kind || spot.category || "attraction");
  const isStory = spot.is_story === true;
  // 외국어 페이지는 번역 번들의 이름·주소·개요·본문을 쓴다 (없으면 한국어 원문)
  const loc = seo.localizeSpot(spot, spotId, lang, data);
  const title = loc.title || "로컬 명소";
  const addr = loc.addr || String(spot.region_label || prov);
  const imageUrl = spot.image_url ? String(spot.image_url) : spot.image ? String(spot.image) : "";
  const queryKey = isStory ? "story" : "spot";
  const overviewDesc = loc.overview ? seo.truncate(loc.overview, 155) : "";

  let titleText = isStory ? `${title} · ${spot.source_book || prov} | 직스테이 로컬 스토리` : `${title} (${prov}) | 직스테이 로컬`;
  if (kind === "culture" && !isStory) {
    // "개방 수장고 개편 (청주 전시) | 직스테이 로컬" — "청주 전시", "대학로 연극" 검색에 걸리도록
    const city = String(spot.city || "").replace(/^([가-힣]{2,})[시군]$/, "$1") || prov;
    titleText = `${title} (${city} ${String(spot.culture_type || "공연")}) | 직스테이 로컬`;
  }
  if (kind === "market" && !isStory) {
    // "곡성기차마을전통시장 (곡성 5일장 · 장날) | 직스테이 로컬" — "곡성 5일장", "곡성 장날" 검색에 걸리도록
    const city = String(spot.city || "").replace(/^([가-힣]{2,})[시군]$/, "$1") || prov;
    const type = String(spot.market_type || "전통시장");
    titleText = `${title} (${city} ${type}${Array.isArray(spot.days) && spot.days.length ? " · 장날" : ""}) | 직스테이 로컬`;
  }
  let descText = spot.summary
    ? `${spot.summary} (${addr})`
    : overviewDesc || `${addr} · 주변 맛집·지자체 공식 관광지도·숙소 동선 안내`;
  if (lang === "en") {
    titleText = `${title} (${provEn}) | Jikstay Korea`;
    descText = (loc.translated && overviewDesc) || (spot.en_summary
      ? String(spot.en_summary)
      : `${addr} — Explore official municipal PDF maps, public transit routes, nearby local food & stays in ${provEn}.`);
  } else if (lang === "ja") {
    titleText = `${title}（${provLabel}）| Jikstay Korea`;
    descText = (loc.translated && overviewDesc) || `${addr} — 自治体公式観光地図PDF・乗換ルート・周辺グルメ・宿泊ガイド。`;
  } else if (lang === "zh") {
    titleText = `${title}（${provLabel}）| Jikstay 韓國`;
    descText = (loc.translated && overviewDesc) || `${addr} — 官方旅遊地圖PDF、大眾運輸路線、周邊在地美食與住宿指南。`;
  }

  const encodedId = encodeURIComponent(spotId);
  const canonicalUrl =
    lang === "ko"
      ? `${origin}/?${queryKey}=${encodedId}`
      : `${origin}/?${queryKey}=${encodedId}&lang=${encodeURIComponent(lang)}`;
  const escapedTitle = escapeHtml(titleText);
  const escapedDesc = escapeHtml(descText);
  const ogImageTag = imageUrl ? `\n  <meta property="og:image" content="${escapeHtml(imageUrl)}">` : "";
  const ogUrlTag = `\n  <meta property="og:url" content="${escapeHtml(canonicalUrl)}">`;
  const hreflangTags = [
    `\n  <link rel="canonical" href="${escapeHtml(canonicalUrl)}">`,
    `\n  <link rel="alternate" hreflang="ko" href="${escapeHtml(`${origin}/?${queryKey}=${encodedId}`)}">`,
    `\n  <link rel="alternate" hreflang="en" href="${escapeHtml(`${origin}/?${queryKey}=${encodedId}&lang=en`)}">`,
    `\n  <link rel="alternate" hreflang="ja" href="${escapeHtml(`${origin}/?${queryKey}=${encodedId}&lang=ja`)}">`,
    `\n  <link rel="alternate" hreflang="zh-Hant" href="${escapeHtml(`${origin}/?${queryKey}=${encodedId}&lang=zh`)}">`,
    `\n  <link rel="alternate" hreflang="x-default" href="${escapeHtml(`${origin}/?${queryKey}=${encodedId}`)}">`,
  ].join("");

  const schemaType = kind === "event" ? "Festival" : kind === "food" ? "Restaurant" : kind === "market" ? "Store" : "TouristAttraction";
  const jsonLdObj = {
    "@context": "https://schema.org",
    "@type": schemaType,
    name: title,
    description: descText,
    url: canonicalUrl,
    address: { "@type": "PostalAddress", addressCountry: "KR", addressRegion: prov, streetAddress: addr },
  };
  if (loc.koTitle && loc.koTitle !== title) jsonLdObj.alternateName = loc.koTitle; // 한국어 이름으로 검색해도 연결
  if (imageUrl) jsonLdObj.image = [imageUrl];
  if (spot.tel) jsonLdObj.telephone = String(spot.tel);
  if (typeof spot.lat === "number" && typeof spot.lng === "number") {
    jsonLdObj.geo = { "@type": "GeoCoordinates", latitude: spot.lat, longitude: spot.lng };
  }
  if (kind === "event") {
    const sd = fmtYmdIso(spot.start_date);
    const ed = fmtYmdIso(spot.end_date);
    if (sd) jsonLdObj.startDate = sd;
    if (ed) jsonLdObj.endDate = ed;
  }
  if (kind === "culture") {
    // 공연·전시: schema.org Event (Google 이벤트 검색 결과 조건 — 이름·시작일·장소)
    const realm = String(spot.realm || "");
    jsonLdObj["@type"] = spot.culture_type === "전시" ? "ExhibitionEvent"
      : /음악|콘서트/.test(realm) ? "MusicEvent"
      : /연극|뮤지컬|오페라/.test(realm) ? "TheaterEvent"
      : /무용|발레/.test(realm) ? "DanceEvent" : "Event";
    const sd = fmtYmdIso(spot.start_date);
    const ed = fmtYmdIso(spot.end_date);
    if (sd) jsonLdObj.startDate = sd;
    if (ed) jsonLdObj.endDate = ed;
    jsonLdObj.eventStatus = "https://schema.org/EventScheduled";
    jsonLdObj.eventAttendanceMode = "https://schema.org/OfflineEventAttendanceMode";
    jsonLdObj.location = { "@type": "Place", name: String(spot.place || title), address: jsonLdObj.address };
    if (jsonLdObj.geo) jsonLdObj.location.geo = jsonLdObj.geo;
    delete jsonLdObj.address;
    delete jsonLdObj.geo;
    delete jsonLdObj.telephone;
    if (spot.url) jsonLdObj.offers = { "@type": "Offer", url: String(spot.url) };
  }
  const reviewCount = Number(spot.review_count) || 0;
  const scoreSum = Number(spot.score_sum) || 0;
  if (reviewCount > 0 && scoreSum > 0) {
    jsonLdObj.aggregateRating = {
      "@type": "AggregateRating",
      ratingValue: Number((scoreSum / reviewCount).toFixed(2)),
      reviewCount,
      bestRating: 5,
      worstRating: 1,
    };
  }
  const safeJsonLd = JSON.stringify(jsonLdObj).replace(/</g, "\\u003c");
  const jsonLdTag = `\n  <script type="application/ld+json">${safeJsonLd}</script>`;
  const L = seo.LABELS[lang] || seo.LABELS.ko;
  const seoMain = seo.renderSeoMain({
    lang,
    title,
    lead: loc.pullQuote || "",
    address: addr,
    imageUrl,
    imageAlt: title,
    paragraphs: loc.paragraphs.length ? loc.paragraphs : loc.overview ? [loc.overview] : [],
    practical: loc.practical,
    breadcrumbs: [
      { href: lang === "ko" ? `${origin}/` : `${origin}/?lang=${lang}`, text: L.home },
      seo.regionLink(origin, prov, provLabel, lang),
    ],
    sections: [
      {
        heading: L.nearby,
        html: seo.linkList(seo.nearbyLinks(origin, lang, data, { id: spotId, province: prov, lat: spot.lat, lng: spot.lng })),
      },
    ],
  });

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">${ogImageTag}${ogUrlTag}${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoMain}\n</body>`);
}

function buildPlanOgHtml(template, rawPlan, origin, rawLang = "ko") {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const parts = String(rawPlan || "").split(":");
  const days = Math.max(1, Math.min(5, parseInt((parts[0] || "d2").replace(/^d/, ""), 10) || 2));
  const prov = parts[1] && parts[1] !== "전체" ? parts[1] : (lang === "ko" ? "대한민국" : "Korea");
  const provEn = PROVINCE_EN[prov] || prov;
  const titleText =
    lang === "ko"
      ? `${prov} ${days - 1}박${days}일 추천 여행코스 · 축제·맛집·숙소 | 직스테이 로컬`
      : lang === "ja"
        ? `${prov} ${days}日間おすすめ旅行プラン・宿泊 | Jikstay Korea`
        : lang === "zh"
          ? `${prov} ${days}日推薦行程・慶典美食與住宿 | Jikstay 韓國`
          : `${provEn} ${days}-Day Korea Trip Itinerary & Verified Stays | Jikstay Korea`;
  const descText =
    lang === "ko"
      ? `${prov} 임박 축제, 로컬 맛집, 공공데이터 등록 숙소를 반경 55km 동선으로 묶은 맞춤 여행코스입니다.`
      : `Custom ${days}-day ${provEn} itinerary combining local festivals, top food spots & public-data stays.`;
  const canon = `${origin}/?plan=${encodeURIComponent(rawPlan)}${lang === "ko" ? "" : `&lang=${encodeURIComponent(lang)}`}`;
  const jsonLd = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "TouristTrip",
    name: titleText,
    description: descText,
    url: canon,
    touristType: lang === "ko" ? "Domestic Weekend Travelers" : "International Travelers",
  }).replace(/</g, "\\u003c");
  const escT = escapeHtml(titleText);
  const escD = escapeHtml(descText);
  const noscript = `<noscript id="jikstay-seo"><article><h1>${escT}</h1><p>${escD}</p></article></noscript>`;
  return template
    .replace(/<html\b[^>]*>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escT}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escD}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escT}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escD}">\n  <meta property="og:url" content="${escapeHtml(canon)}">\n  <script type="application/ld+json">${jsonLd}</script>`
    )
    .replace(/<\/body>/i, `  ${noscript}\n</body>`);
}

function buildRegionOgHtml(template, province, origin, rawLang = "ko", data = null, staysIndex = null) {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const provEn = PROVINCE_EN[province] || province;
  const provLabel = provinceLabel(province, lang);
  // 외국인은 장소 이름보다 '지역 + 할 것·맛집·숙소'로 검색한다 → 제목을 그 검색어에 맞춘다
  let titleText = `${province} 가볼만한 곳·축제·공연·전시·맛집·숙소 총정리 | 직스테이 로컬`;
  let descText = `${province} 가볼만한 곳, 진행 중인 축제·공연·전시회·5일장, 로컬 맛집, 지자체 공식 가이드북(PDF/E-book)과 공공데이터 등록 숙소를 한눈에 확인하세요.`;
  if (lang === "en") {
    titleText = `Things to Do in ${provEn}, Korea: Festivals, Shows, Exhibitions, Local Food & Stays | Jikstay Korea`;
    descText = `Things to do in ${provEn}, Korea: attractions, festivals happening now, local food and places to stay, plus free official municipal tourist maps (PDF).`;
  } else if (lang === "ja") {
    titleText = `${provLabel}観光 おすすめスポット・祭り・公演・展示・グルメ・宿泊 | Jikstay Korea`;
    descText = `${provLabel}のおすすめ観光スポット、開催中の祭り、地元グルメ、宿泊施設と自治体公式観光ガイドブックPDFをまとめて紹介。`;
  } else if (lang === "zh") {
    titleText = `${provLabel}旅遊 必去景點・慶典・演出・展覽・美食・住宿 | Jikstay 韓國`;
    descText = `${provLabel}必去景點、正在舉行的慶典、在地美食與住宿，以及地方政府官方旅遊指南PDF一次看。`;
  }

  const encodedProv = encodeURIComponent(province);
  const canonicalUrl =
    lang === "ko" ? `${origin}/?region=${encodedProv}` : `${origin}/?region=${encodedProv}&lang=${encodeURIComponent(lang)}`;
  const escapedTitle = escapeHtml(titleText);
  const escapedDesc = escapeHtml(descText);
  const ogUrlTag = `\n  <meta property="og:url" content="${escapeHtml(canonicalUrl)}">`;
  const hreflangTags = [
    `\n  <link rel="canonical" href="${escapeHtml(canonicalUrl)}">`,
    `\n  <link rel="alternate" hreflang="ko" href="${escapeHtml(`${origin}/?region=${encodedProv}`)}">`,
    `\n  <link rel="alternate" hreflang="en" href="${escapeHtml(`${origin}/?region=${encodedProv}&lang=en`)}">`,
    `\n  <link rel="alternate" hreflang="ja" href="${escapeHtml(`${origin}/?region=${encodedProv}&lang=ja`)}">`,
    `\n  <link rel="alternate" hreflang="zh-Hant" href="${escapeHtml(`${origin}/?region=${encodedProv}&lang=zh`)}">`,
    `\n  <link rel="alternate" hreflang="x-default" href="${escapeHtml(`${origin}/?region=${encodedProv}`)}">`,
  ].join("");

  const jsonLdObj = {
    "@context": "https://schema.org",
    "@type": "TouristDestination",
    name: `${province} (${provEn})`,
    description: descText,
    url: canonicalUrl,
  };
  const safeJsonLd = JSON.stringify(jsonLdObj).replace(/</g, "\\u003c");
  const jsonLdTag = `\n  <script type="application/ld+json">${safeJsonLd}</script>`;

  const L = seo.LABELS[lang] || seo.LABELS.ko;
  const hub = (data && data.hub) || {};
  const today = new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, "");
  const spotLinks = (items, limit) =>
    items.slice(0, limit).map((x) => ({
      href: seo.pageUrl(origin, "spot", x.id, lang),
      text: seo.localizedTitleOf(x.id, String(x.title), lang, data),
    }));
  const inProv = (x) => x && x.id && x.title && x.province === province;
  const festivals = (hub.festivals || [])
    .filter((x) => inProv(x) && (!x.end_date || String(x.end_date) >= today))
    .sort((a, b) => String(a.start_date || "").localeCompare(String(b.start_date || "")));
  const spots = (hub.spots || []).filter(inProv);
  const stays = ((staysIndex && staysIndex.items) || [])
    .filter((x) => x && x.listing_id && x.province === province)
    .sort((a, b) => (Number(b.curated_score) || 0) - (Number(a.curated_score) || 0))
    .slice(0, 15)
    .map((x) => {
      const t = lang !== "ko" && data && data.i18nCore && data.i18nCore.stays && data.i18nCore.stays[x.listing_id];
      return { href: seo.pageUrl(origin, "id", x.listing_id, lang), text: (t && t.title) || String(x.title || "") };
    });
  const otherRegions = PROVINCES_17.filter((p) => p !== province).map((p) => seo.regionLink(origin, p, provinceLabel(p, lang), lang));
  const seoMain = seo.renderSeoMain({
    lang,
    title: titleText.replace(/\s*\|[^|]*$/, ""),
    lead: descText,
    breadcrumbs: [{ href: lang === "ko" ? `${origin}/` : `${origin}/?lang=${lang}`, text: L.home }],
    sections: [
      { heading: `${provLabel} · ${L.festivals}`, html: seo.linkList(spotLinks(festivals, 15)) },
      { heading: `${provLabel} · ${L.attractions}`, html: seo.linkList(spotLinks(spots.filter((x) => x.kind === "attraction"), 30)) },
      { heading: `${provLabel} · ${L.food}`, html: seo.linkList(spotLinks(spots.filter((x) => x.kind === "food"), 30)) },
      { heading: `${provLabel} · ${L.stays}`, html: seo.linkList(stays) },
      { heading: `${provLabel} · ${MARKET_LABEL[lang] || MARKET_LABEL.ko}`, html: seo.linkList(spotLinks(((data && data.markets) || []).filter(inProv), 40)) },
      { heading: `${provLabel} · ${(TOPIC_TEXT.culture[lang] || TOPIC_TEXT.culture.ko).exhibitions}`, html: seo.linkList(spotLinks(activeCulture({ culture: (data && data.culture) || [] }, today).filter(inProv), 30)) },
      { heading: `${provLabel} · ${TOPIC_TEXT.festival[lang].byRegion}`, html: seo.linkList(regionTopicLinks(origin, province, lang, { ...hub, markets: (data && data.markets) || [], culture: (data && data.culture) || [] })) },
      { heading: L.regions, html: seo.linkList(otherRegions) },
    ],
  });

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">${ogUrlTag}${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoMain}\n</body>`);
}

// ---------------------------------------------------------------------------
// 주제 페이지 (?topic=festival | market, 선택 &region=시·도)
// "전국 지역축제", "전북 축제 일정", "5일장 장날" 같은 검색어로 들어오는 입구.
// ---------------------------------------------------------------------------
const TOPICS = new Set(["festival", "market", "culture"]);
const MARKET_LABEL = { ko: "전통시장·5일장", en: "Traditional markets", ja: "伝統市場・五日市", zh: "傳統市場・五日市集" };

const TOPIC_TEXT = {
  festival: {
    ko: {
      title: (p, y) => (p ? `${p} 축제 일정 ${y} · 지역 축제·행사 모음` : `전국 지역축제 일정 ${y} · 지금 열리는 축제·행사 찾기`),
      desc: (p, y) =>
        p
          ? `${y}년 ${p}에서 지금 열리고 있거나 곧 열리는 지역 축제와 행사를 날짜순으로 모았습니다. 한국관광공사 공식 정보와 주변 맛집·숙소까지 함께 확인하세요.`
          : `${y}년 전국 17개 시·도의 지역 축제와 행사 일정을 한곳에 모았습니다. 이번 주 열리는 축제, 다가오는 행사, 시·도별 축제 일정을 한국관광공사 공식 정보로 확인하세요.`,
      now: "지금 열리는 축제·행사", soon: "다가오는 축제·행사", byRegion: "시·도별 축제 일정", other: "5일장 장날 일정",
    },
    en: {
      title: (p, y) => (p ? `${p} Festivals ${y}: Local Festivals & Events Calendar` : `Korea Festival Calendar ${y}: Local Festivals & Events`),
      desc: (p, y) =>
        p
          ? `Festivals and events happening now and coming up in ${p}, Korea in ${y}, with official Korea Tourism Organization details, nearby food and stays.`
          : `Calendar of local festivals and events across Korea's 17 provinces in ${y}: what's on this week, upcoming events, and festivals by region.`,
      now: "Happening now", soon: "Coming up", byRegion: "Festivals by province", other: "Traditional 5-day market days",
    },
    ja: {
      title: (p, y) => (p ? `${p}のお祭り・イベント日程 ${y}` : `韓国の地域祭り・イベント日程 ${y}`),
      desc: (p, y) => (p ? `${y}年に${p}で開催中・開催予定の祭りとイベントを日付順に紹介。` : `${y}年 韓国全国17市道の地域祭り・イベント日程をまとめて確認。`),
      now: "開催中の祭り・イベント", soon: "これから開催", byRegion: "地域別の祭り日程", other: "五日市（5日市場）の市日",
    },
    zh: {
      title: (p, y) => (p ? `${p}慶典・活動日程 ${y}` : `韓國地方慶典・活動日程 ${y}`),
      desc: (p, y) => (p ? `${y}年${p}正在舉行與即將舉行的慶典和活動，依日期整理。` : `${y}年韓國全國17市道地方慶典與活動日程一次看。`),
      now: "正在舉行", soon: "即將舉行", byRegion: "各地區慶典日程", other: "五日市集開市日",
    },
  },
  culture: {
    ko: {
      title: (p, y) => (p ? `${p} 전시회·공연 일정 ${y} · 지금 볼 수 있는 전시·공연` : `전국 전시회·공연 일정 ${y} · 이번 주 볼 만한 전시·공연`),
      desc: (p, y) =>
        p
          ? `${y}년 ${p}에서 지금 볼 수 있는 전시회와 이번 주·다가오는 공연(연극·뮤지컬·콘서트·국악)을 기간·장소·요금과 함께 모았습니다.`
          : `${y}년 전국 미술관·박물관 전시회와 연극·뮤지컬·콘서트·국악 공연 일정을 지역별로 모았습니다. 기간·장소·요금과 예매 링크까지 확인하세요.`,
      exhibitions: "지금 볼 수 있는 전시", thisWeek: "이번 주 공연", soon: "다가오는 공연", byRegion: "시·도별 전시·공연 일정", other: "함께 볼 일정",
    },
    en: {
      title: (p, y) => (p ? `${p} Exhibitions & Shows ${y}` : `Korea Exhibitions & Shows ${y}: What's On This Week`),
      desc: (p, y) => (p ? `Exhibitions on now and upcoming theater, musicals, concerts and gugak in ${p}, Korea in ${y}, with dates, venues and prices.` : `Museum and gallery exhibitions plus theater, musical, concert and gugak performances across Korea in ${y}, by region.`),
      exhibitions: "Exhibitions on now", thisWeek: "Performances this week", soon: "Upcoming performances", byRegion: "Exhibitions & shows by province", other: "More calendars",
    },
    ja: {
      title: (p, y) => (p ? `${p}の展示・公演スケジュール ${y}` : `韓国の展示・公演スケジュール ${y}`),
      desc: (p, y) => (p ? `${y}年に${p}で開催中の展示と今週・今後の公演を紹介。` : `${y}年 韓国各地の美術館・博物館の展示と演劇・ミュージカル・コンサートの公演日程。`),
      exhibitions: "開催中の展示", thisWeek: "今週の公演", soon: "今後の公演", byRegion: "地域別の展示・公演", other: "そのほかの日程",
    },
    zh: {
      title: (p, y) => (p ? `${p}展覽・演出日程 ${y}` : `韓國展覽・演出日程 ${y}`),
      desc: (p, y) => (p ? `${y}年${p}正在展出的展覽與本週、即將上演的演出。` : `${y}年韓國各地美術館・博物館展覽與戲劇・音樂劇・音樂會演出日程。`),
      exhibitions: "正在展出", thisWeek: "本週演出", soon: "即將上演", byRegion: "各地區展覽・演出", other: "其他日程",
    },
  },
  market: {
    ko: {
      title: (p) => (p ? `${p} 5일장 장날 일정 · 오일장·전통시장` : "전국 5일장 장날 일정 · 오일장·전통시장 찾기"),
      desc: (p) =>
        p
          ? `${p} 5일장(오일장) 장날과 다음 장 서는 날, 대표 먹거리·특산물을 정리했습니다. 장 구경 전에 장날을 확인하세요.`
          : "전국 5일장(오일장) 장날을 한눈에. 시장별로 매달 장이 서는 날짜와 다음 장날, 대표 먹거리·특산물을 정리했습니다.",
      list: "5일장 장날", permanent: "상설 전통시장", byRegion: "시·도별 5일장", other: "지역축제 일정", every: "매월", next: "다음 장날", specialty: "대표 먹거리·특산물",
    },
    en: {
      title: (p) => (p ? `${p} 5-Day Market Days: Traditional Market Schedule` : "Korea 5-Day Market Schedule: Traditional Market Days"),
      desc: (p) => (p ? `Market days and the next opening date of traditional 5-day markets in ${p}, Korea, with local specialties.` : "When Korea's traditional 5-day markets open each month, the next market day, and what to eat and buy."),
      list: "5-day market days", permanent: "Everyday traditional markets", byRegion: "Markets by province", other: "Festival calendar", every: "Every month on day", next: "Next market day", specialty: "Local specialties",
    },
    ja: {
      title: (p) => (p ? `${p}の五日市 市日カレンダー` : "韓国の五日市（5日市場）市日カレンダー"),
      desc: (p) => (p ? `${p}の五日市の市日と次回開催日、名物を紹介。` : "韓国各地の五日市が立つ日と次回の市日、名物グルメをまとめて紹介。"),
      list: "五日市の市日", permanent: "常設の伝統市場", byRegion: "地域別の五日市", other: "地域祭りの日程", every: "毎月", next: "次の市日", specialty: "名物・特産品",
    },
    zh: {
      title: (p) => (p ? `${p}五日市集開市日` : "韓國五日市集開市日一覽"),
      desc: (p) => (p ? `${p}五日市集的開市日、下次開市日期與在地特產。` : "韓國各地傳統五日市集每月開市日期、下次開市日與特色美食。"),
      list: "五日市集開市日", permanent: "常設傳統市場", byRegion: "各地區五日市集", other: "地方慶典日程", every: "每月", next: "下次開市", specialty: "特色美食・特產",
    },
  },
};

function kstTodayYmd() {
  return new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, "");
}

function fmtMd(ymd) {
  const s = String(ymd || "");
  return /^\d{8}$/.test(s) ? `${s.slice(4, 6)}.${s.slice(6, 8)}` : "";
}

/** 5일장 장날: days [1, 6] → 매월 [1, 6, 11, 16, 21, 26] (31일에는 장이 서지 않는다) */
function marketDaysOfMonth(days) {
  const base = new Set((Array.isArray(days) ? days : []).map((d) => ((Number(d) % 5) + 5) % 5));
  const out = [];
  for (let d = 1; d <= 30; d++) if (base.has(d % 5)) out.push(d);
  return out;
}

/** 오늘(포함) 이후 첫 장날 "YYYYMMDD" (없으면 "") */
function nextMarketYmd(days, todayYmd) {
  const list = marketDaysOfMonth(days);
  if (!list.length) return "";
  const y = Number(todayYmd.slice(0, 4));
  const m = Number(todayYmd.slice(4, 6));
  const d = Number(todayYmd.slice(6, 8));
  for (let k = 0; k < 2; k++) {
    const yy = m + k > 12 ? y + 1 : y;
    const mm = ((m - 1 + k) % 12) + 1;
    const lastDay = new Date(Date.UTC(yy, mm, 0)).getUTCDate();
    for (const day of list) {
      if (day > lastDay || (k === 0 && day < d)) continue;
      return `${yy}${String(mm).padStart(2, "0")}${String(day).padStart(2, "0")}`;
    }
  }
  return "";
}

function topicUrl(origin, topic, province, lang) {
  const q = [`topic=${topic}`];
  if (province) q.push(`region=${encodeURIComponent(province)}`);
  if (lang && lang !== "ko") q.push(`lang=${encodeURIComponent(lang)}`);
  return `${origin}/?${q.join("&")}`;
}

/** 현재·예정 축제 (종료일 지난 것 제외), 시작일 순 */
function activeFestivals(hub, todayYmd) {
  return (hub.festivals || [])
    .filter((x) => x && x.id && x.title && (!x.end_date || String(x.end_date) >= todayYmd))
    .sort((a, b) => String(a.start_date || "").localeCompare(String(b.start_date || "")));
}

/** 진행 중·예정 공연·전시 (종료일 지난 것 제외), 시작일 순 */
function activeCulture(hub, todayYmd) {
  return ((hub && hub.culture) || [])
    .filter((x) => x && x.id && x.title && (!x.end_date || String(x.end_date) >= todayYmd))
    .sort((a, b) => String(a.start_date || "").localeCompare(String(b.start_date || "")));
}

/** 사이트맵·링크용: 내용이 있는 시·도만 */
function topicProvinces(hub, topic, todayYmd) {
  const src = topic === "festival"
    ? activeFestivals(hub || {}, todayYmd)
    : topic === "culture"
      ? activeCulture(hub || {}, todayYmd)
      : [...((hub && hub.traditional_markets) || []), ...((hub && hub.markets) || [])];
  return PROVINCES_17.filter((p) => src.some((x) => x && x.province === p));
}

/** 지역·홈 페이지에서 주제 페이지로 가는 링크 (축제 일정 · 5일장 장날). hub 가 있으면 내용 있는 것만 */
function regionTopicLinks(origin, province, lang, hub) {
  const today = kstTodayYmd();
  const year = today.slice(0, 4);
  const label = province ? provinceLabel(province, lang) : "";
  return ["festival", "market", "culture"]
    .filter((t) => !province || !hub || topicProvinces(hub, t, today).includes(province))
    .map((t) => ({ href: topicUrl(origin, t, province, lang), text: (TOPIC_TEXT[t][lang] || TOPIC_TEXT[t].ko).title(label, year) }));
}

function buildTopicOgHtml(template, topic, province, origin, rawLang = "ko", data = null) {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const T = TOPIC_TEXT[topic][lang] || TOPIC_TEXT[topic].ko;
  const today = kstTodayYmd();
  const year = today.slice(0, 4);
  const provLabel = province ? provinceLabel(province, lang) : "";
  const titleText = `${T.title(provLabel, year)} | ${lang === "ko" ? "직스테이 로컬" : "Jikstay Korea"}`;
  const descText = T.desc(provLabel, year);
  const canonicalUrl = topicUrl(origin, topic, province, lang);
  const hub = { ...((data && data.hub) || {}), markets: (data && data.markets) || [], culture: (data && data.culture) || [] };
  const L = seo.LABELS[lang] || seo.LABELS.ko;
  const inProv = (x) => !province || x.province === province;
  const spotText = (x) => seo.localizedTitleOf(x.id, String(x.title), lang, data);

  const sections = [];
  const listItems = [];
  if (topic === "culture") {
    const items = activeCulture(hub, today).filter(inProv);
    const week = (() => { const d = new Date(Date.now() + 9 * 3600 * 1000 + 7 * 86400000); return d.toISOString().slice(0, 10).replace(/-/g, ""); })();
    const line = (x) => {
      const range = [fmtMd(x.start_date), fmtMd(x.end_date)].filter(Boolean).join("~");
      const where = [province ? "" : provinceLabel(x.province, lang), x.place || ""].filter(Boolean).join(" ");
      return { href: seo.pageUrl(origin, "spot", x.id, lang), text: `${spotText(x)} (${[where, range, x.price_text ? String(x.price_text).slice(0, 24) : ""].filter(Boolean).join(" · ")})` };
    };
    const exhibitions = items.filter((x) => x.culture_type === "전시" && (!x.start_date || String(x.start_date) <= week));
    const shows = items.filter((x) => x.culture_type !== "전시");
    const thisWeek = shows.filter((x) => !x.start_date || String(x.start_date) <= week);
    const soon = shows.filter((x) => x.start_date && String(x.start_date) > week);
    const cap = province ? 80 : 120;
    sections.push({ heading: province ? `${provLabel} ${T.exhibitions}` : T.exhibitions, html: seo.linkList(exhibitions.slice(0, cap).map(line)) });
    sections.push({ heading: province ? `${provLabel} ${T.thisWeek}` : T.thisWeek, html: seo.linkList(thisWeek.slice(0, cap).map(line)) });
    sections.push({ heading: province ? `${provLabel} ${T.soon}` : T.soon, html: seo.linkList(soon.slice(0, cap).map(line)) });
    for (const x of [...exhibitions, ...thisWeek].slice(0, 30)) listItems.push({ name: spotText(x), url: seo.pageUrl(origin, "spot", x.id, lang) });
  } else if (topic === "festival") {
    const fests = activeFestivals(hub, today).filter(inProv);
    const line = (x) => {
      const range = [fmtMd(x.start_date), fmtMd(x.end_date)].filter(Boolean).join("~");
      const where = province ? String(x.region_label || "") : String(x.region_label || provinceLabel(x.province, lang));
      return { href: seo.pageUrl(origin, "spot", x.id, lang), text: `${spotText(x)} (${[where, range].filter(Boolean).join(" · ")})` };
    };
    const now = fests.filter((x) => !x.start_date || String(x.start_date) <= today);
    const soon = fests.filter((x) => x.start_date && String(x.start_date) > today);
    sections.push({ heading: T.now, html: seo.linkList(now.slice(0, 60).map(line)) });
    sections.push({ heading: T.soon, html: seo.linkList(soon.slice(0, 60).map(line)) });
    for (const x of [...now, ...soon].slice(0, 30)) listItems.push({ name: spotText(x), url: seo.pageUrl(origin, "spot", x.id, lang) });
  } else {
    const markets = ((hub.traditional_markets || []).filter((x) => x && x.title && inProv(x)))
      .sort((a, b) => nextMarketYmd(a.days, today).localeCompare(nextMarketYmd(b.days, today)));
    const items = markets.map((x) => {
      const days = marketDaysOfMonth(x.days).join("·");
      const next = nextMarketYmd(x.days, today);
      const parts = [
        `${provinceLabel(x.province, lang)} ${x.city || ""}`.trim(),
        days ? `${T.every} ${days}${lang === "ko" ? "일" : ""}` : "",
        next ? `${T.next} ${fmtMd(next)}` : "",
        x.specialty ? `${T.specialty}: ${x.specialty}` : "",
      ].filter(Boolean);
      const name = String(x.id || "").startsWith("spot_mk_")
        ? `<a href="${escapeHtml(seo.pageUrl(origin, "spot", x.id, lang))}">${escapeHtml(spotText(x))}</a>`
        : escapeHtml(String(x.title));
      return `<li><strong>${name}</strong> — ${escapeHtml(parts.join(" · "))}</li>`;
    });
    sections.push({ heading: province ? `${provLabel} ${T.list}` : T.list, html: items.length ? `<ul>${items.join("")}</ul>` : "" });
    for (const x of markets.slice(0, 30)) {
      const isPage = String(x.id || "").startsWith("spot_mk_");
      listItems.push({ name: isPage ? spotText(x) : String(x.title), url: isPage ? seo.pageUrl(origin, "spot", x.id, lang) : canonicalUrl });
    }
    // 장날 없는 상설 전통시장도 함께 (상세 페이지로 연결)
    const permanent = ((data && data.markets) || []).filter((x) => x && x.id && x.title && inProv(x) && !(Array.isArray(x.days) && x.days.length));
    sections.push({
      heading: province ? `${provLabel} ${T.permanent}` : T.permanent,
      html: seo.linkList(permanent.slice(0, province ? 120 : 200).map((x) => ({
        href: seo.pageUrl(origin, "spot", x.id, lang),
        text: `${spotText(x)} (${[x.region_label || provinceLabel(x.province, lang), x.specialty ? String(x.specialty).slice(0, 40) : ""].filter(Boolean).join(" · ")})`,
      }))),
    });
  }

  const provs = topicProvinces(hub, topic, today).filter((p) => p !== province);
  sections.push({
    heading: T.byRegion,
    html: seo.linkList(provs.map((p) => ({ href: topicUrl(origin, topic, p, lang), text: T.title(provinceLabel(p, lang), year) }))),
  });
  const otherLinks = [...TOPICS].filter((t) => t !== topic).map((t) => {
    const p = province && topicProvinces(hub, t, today).includes(province) ? province : "";
    return { href: topicUrl(origin, t, p, lang), text: (TOPIC_TEXT[t][lang] || TOPIC_TEXT[t].ko).title(p ? provLabel : "", year) };
  });
  sections.push({
    heading: T.other,
    html: seo.linkList([...otherLinks, ...(province ? [seo.regionLink(origin, province, `${provLabel} · ${L.more}`, lang)] : [])]),
  });

  const alt = (l) => topicUrl(origin, topic, province, l);
  const hreflangTags = [
    `\n  <link rel="canonical" href="${escapeHtml(canonicalUrl)}">`,
    `\n  <link rel="alternate" hreflang="ko" href="${escapeHtml(alt("ko"))}">`,
    `\n  <link rel="alternate" hreflang="en" href="${escapeHtml(alt("en"))}">`,
    `\n  <link rel="alternate" hreflang="ja" href="${escapeHtml(alt("ja"))}">`,
    `\n  <link rel="alternate" hreflang="zh-Hant" href="${escapeHtml(alt("zh"))}">`,
    `\n  <link rel="alternate" hreflang="x-default" href="${escapeHtml(alt("ko"))}">`,
  ].join("");
  const jsonLdObj = {
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    name: titleText.replace(/\s*\|[^|]*$/, ""),
    description: descText,
    url: canonicalUrl,
    mainEntity: {
      "@type": "ItemList",
      itemListElement: listItems.map((x, i) => ({ "@type": "ListItem", position: i + 1, name: x.name, url: x.url })),
    },
  };
  const jsonLdTag = `\n  <script type="application/ld+json">${JSON.stringify(jsonLdObj).replace(/</g, "\\u003c")}</script>`;
  const crumbs = [{ href: lang === "ko" ? `${origin}/` : `${origin}/?lang=${lang}`, text: L.home }];
  if (province) crumbs.push({ href: topicUrl(origin, topic, "", lang), text: T.title("", year) });
  const seoMain = seo.renderSeoMain({ lang, title: titleText.replace(/\s*\|[^|]*$/, ""), lead: descText, breadcrumbs: crumbs, sections });
  const escapedTitle = escapeHtml(titleText);
  const escapedDesc = escapeHtml(descText);

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">\n  <meta property="og:url" content="${escapeHtml(canonicalUrl)}">${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoMain}\n</body>`);
}

/** 종료일이 지났거나(KST 기준 오늘보다 이전) 정리 작업이 ended 로 바꾼 축제·공연·전시 */
function isEndedSpot(spot) {
  if (!spot) return false;
  if (spot.status === "ended") return true;
  const ed = String(spot.end_date || "").trim();
  return /^\d{8}$/.test(ed) && ed < kstTodayYmd();
}

const ENDED_TEXT = {
  ko: { tag: "종료", lead: (k, d, p) => `이 ${k}${/[가-힣]$/.test(k) && (k.charCodeAt(k.length - 1) - 0xac00) % 28 ? "은" : "는"} ${d}에 종료되었습니다. 지금 ${p}에서 열리는 공연·전시·축제를 확인해 보세요.`,
        now: (p) => `지금 ${p}에서 열리는 공연·전시·축제`, kind: { culture: "공연·전시", event: "축제·행사" } },
  en: { tag: "Ended", lead: (k, d, p) => `This ${k} ended on ${d}. See what's on now in ${p}.`,
        now: (p) => `On now in ${p}`, kind: { culture: "show or exhibition", event: "festival" } },
  ja: { tag: "終了", lead: (k, d, p) => `この${k}は${d}に終了しました。${p}で開催中の公演・展示・祭りをご覧ください。`,
        now: (p) => `${p}で開催中`, kind: { culture: "公演・展示", event: "祭り・イベント" } },
  zh: { tag: "已結束", lead: (k, d, p) => `此${k}已於${d}結束。看看${p}正在舉行的演出、展覽與慶典。`,
        now: (p) => `${p}正在舉行`, kind: { culture: "演出・展覽", event: "慶典活動" } },
};

function buildEndedSpotHtml(template, spot, spotId, origin, rawLang = "ko", data = null) {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const T = ENDED_TEXT[lang] || ENDED_TEXT.ko;
  const prov = String(spot.province || "");
  const provLabel = provinceLabel(prov, lang) || prov;
  const title = seo.localizedTitleOf(spotId, String(spot.title || ""), lang, data);
  const ed = String(spot.end_date || "");
  const endText = /^\d{8}$/.test(ed) ? `${ed.slice(0, 4)}.${ed.slice(4, 6)}.${ed.slice(6, 8)}` : "";
  const kindLabel = T.kind[spot.kind === "culture" ? "culture" : "event"];
  const titleText = `${title} (${T.tag}) | ${lang === "ko" ? "직스테이 로컬" : "Jikstay Korea"}`;
  const descText = T.lead(kindLabel, endText, provLabel);
  const today = kstTodayYmd();
  const hub = { ...((data && data.hub) || {}), culture: (data && data.culture) || [] };
  const inProv = (x) => x && x.id && x.title && x.province === prov && x.id !== spotId;
  const nowItems = [...activeFestivals(hub, today).filter(inProv), ...activeCulture(hub, today).filter(inProv)]
    .filter((x) => !x.start_date || String(x.start_date) <= today)
    .slice(0, 20)
    .map((x) => ({ href: seo.pageUrl(origin, "spot", x.id, lang), text: seo.localizedTitleOf(x.id, String(x.title), lang, data) }));
  const seoMain = seo.renderSeoMain({
    lang,
    title: `${title} (${T.tag})`,
    lead: descText,
    breadcrumbs: [{ href: lang === "ko" ? `${origin}/` : `${origin}/?lang=${lang}`, text: (seo.LABELS[lang] || seo.LABELS.ko).home }],
    sections: [
      { heading: T.now(provLabel), html: seo.linkList(nowItems) },
      { heading: provLabel, html: seo.linkList(regionTopicLinks(origin, prov, lang, null)) },
    ],
  });
  const t = escapeHtml(titleText);
  const d = escapeHtml(descText);
  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${t}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${d}">
  <meta name="robots" content="noindex,follow">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${t}">`)
    .replace(/<meta\s+property="og:description"\s+content="[^"]*">/, `<meta property="og:description" content="${d}">`)
    .replace(/<\/body>/i, `  ${seoMain}
</body>`);
}

// 대표 도메인. Firebase 기본 주소(*.web.app, *.firebaseapp.com)로 들어온 페이지 요청은 이쪽으로 301 이동시켜
// 같은 내용이 두 주소로 색인되지 않게 한다. (정적 파일은 Hosting 이 직접 내보내므로 영향 없음)
const PRIMARY_HOST = "jikstay.app";
const DEFAULT_HOST_RE = /\.(web\.app|firebaseapp\.com)$/i;

/** 기본 주소로 들어온 요청이면 대표 도메인으로 보낼 URL, 아니면 "" */
function primaryDomainRedirectUrl(host, originalUrl) {
  const h = String(host || "").split(":")[0].trim().toLowerCase();
  if (!h || !DEFAULT_HOST_RE.test(h)) return "";
  const path = String(originalUrl || "/").startsWith("/") ? String(originalUrl || "/") : "/";
  return `https://${PRIMARY_HOST}${path}`;
}

function redirectToPrimaryDomain(req, res) {
  const target = primaryDomainRedirectUrl(req.get("x-forwarded-host") || req.get("host"), req.originalUrl || req.url);
  if (!target) return false;
  res.set("Cache-Control", "public, max-age=3600");
  res.redirect(301, target);
  return true;
}

exports.serveApp = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  if (redirectToPrimaryDomain(req, res)) return;
  const template = CACHED_TEMPLATE || fs.readFileSync(TEMPLATE_PATH, "utf8");
  const rawId = typeof req.query.id === "string" ? req.query.id.trim() : "";
  const rawStory = typeof req.query.story === "string" ? req.query.story.trim() : "";
  const rawSpot = rawStory || (typeof req.query.spot === "string" ? req.query.spot.trim() : "");
  const rawRegion = typeof req.query.region === "string" ? req.query.region.trim() : "";
  const rawLang = typeof req.query.lang === "string" ? req.query.lang.trim() : "ko";
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || PRIMARY_HOST;
  const origin = `${proto}://${host}`;

  if (LISTING_ID_RE.test(rawId)) {
    try {
      const db = getFirestore();
      const snap = await db.collection("listings").doc(rawId).get();
      const data = snap.exists ? snap.data() : null;
      const effectiveId = rawId;
      if (!data || data.status !== "active") {
        res.set("Cache-Control", "no-cache, no-store, must-revalidate");
        res.status(200).send(template);
        return;
      }
      const lang0 = normalizeLang(rawLang);
      const seoData = await seo.loadSeoData(origin, lang0, null);
      const html = buildOgHtml(template, data, effectiveId, origin, rawLang, seoData);
      res.set("Cache-Control", "public, max-age=300, s-maxage=600");
      res.status(200).send(html);
      return;
    } catch (err) {
      console.error("Listing OG tag injection failed:", err);
      res.set("Cache-Control", "no-cache, no-store, must-revalidate");
      res.status(200).send(template);
      return;
    }
  }

  if (SPOT_ID_RE.test(rawSpot)) {
    try {
      const snap = await getFirestore().collection("spots").doc(rawSpot).get();
      const data = snap.exists ? snap.data() : null;
      if (data && (data.status === "active" || data.status === "ended") && isEndedSpot(data)) {
        // 끝난 축제·공연·전시: '종료' 안내 + 같은 지역의 진행 중인 일정으로 연결, 검색 결과에서는 빠지게(noindex)
        const [seoData, cultureDoc] = await Promise.all([
          seo.loadSeoData(origin, normalizeLang(rawLang), null),
          seo.fetchJsonCached(`${origin}/data/hub/culture.json`),
        ]);
        seoData.culture = (cultureDoc && cultureDoc.culture) || [];
        const html = buildEndedSpotHtml(template, data, rawSpot, origin, rawLang, seoData);
        res.set("Cache-Control", "public, max-age=600, s-maxage=3600");
        res.status(200).send(html);
        return;
      }
      if (data && data.status === "active") {
        const seoData = await seo.loadSeoData(origin, normalizeLang(rawLang), seo.provinceCode(String(data.province || "")));
        const html = buildSpotOgHtml(template, data, rawSpot, origin, rawLang, seoData);
        res.set("Cache-Control", "public, max-age=300, s-maxage=600");
        res.status(200).send(html);
        return;
      }
    } catch (err) {
      console.error("Spot OG tag injection failed:", err);
    }
  }

  const rawPlan = typeof req.query.plan === "string" ? req.query.plan.trim() : "";
  if (rawPlan) {
    const html = buildPlanOgHtml(template, rawPlan, origin, rawLang);
    res.set("Cache-Control", "public, max-age=300, s-maxage=600");
    res.status(200).send(html);
    return;
  }

  const rawTopic = typeof req.query.topic === "string" ? req.query.topic.trim() : "";
  if (TOPICS.has(rawTopic)) {
    const [seoData, marketsDoc, cultureDoc] = await Promise.all([
      seo.loadSeoData(origin, normalizeLang(rawLang), null),
      seo.fetchJsonCached(`${origin}/data/hub/markets.json`),
      seo.fetchJsonCached(`${origin}/data/hub/culture.json`),
    ]);
    seoData.markets = (marketsDoc && marketsDoc.markets) || [];
    seoData.culture = (cultureDoc && cultureDoc.culture) || [];
    const html = buildTopicOgHtml(template, rawTopic, PROVINCES_17.includes(rawRegion) ? rawRegion : "", origin, rawLang, seoData);
    res.set("Cache-Control", "public, max-age=600, s-maxage=1200");
    res.status(200).send(html);
    return;
  }

  if (PROVINCES_17.includes(rawRegion)) {
    const [seoData, staysIndex, marketsDoc, cultureDoc] = await Promise.all([
      seo.loadSeoData(origin, normalizeLang(rawLang), null),
      seo.fetchJsonCached(`${origin}/data/public_stays_index.json`),
      seo.fetchJsonCached(`${origin}/data/hub/markets.json`),
      seo.fetchJsonCached(`${origin}/data/hub/culture.json`),
    ]);
    seoData.markets = (marketsDoc && marketsDoc.markets) || [];
    seoData.culture = (cultureDoc && cultureDoc.culture) || [];
    const html = buildRegionOgHtml(template, rawRegion, origin, rawLang, seoData, staysIndex);
    res.set("Cache-Control", "public, max-age=600, s-maxage=1200");
    res.status(200).send(html);
    return;
  }

  // 홈: 오늘의 스토리를 스플래시에 넣는다 (앱도 같은 스토리를 쓴다 → today_story.js). 실패하면 기본 템플릿 그대로
  const homeTemplate = await withTodayStory(template, origin);
  const lang = normalizeLang(rawLang);
  if (lang !== "ko") {
    const htmlLang = lang === "zh" ? "zh-Hant" : lang;
    const homeTitles = {
      en: "Jikstay Korea — Festivals, Shows, Exhibitions, Markets & Stays Across Korea",
      ja: "Jikstay Korea — 韓国各地の祭り・公演・展示・市場・宿泊ガイド",
      zh: "Jikstay 韓國 — 全韓慶典・演出・展覽・傳統市場與住宿指南",
    };
    const homeDescs = {
      en: "Festivals, theater, musicals, concerts and museum exhibitions happening now across Korea's 17 provinces, plus traditional 5-day markets, local food and stays listed in public tourism data.",
      ja: "韓国全国17市道で開催中の祭り・演劇・ミュージカル・コンサート・展示、五日市、グルメと公共データ登録の宿泊施設を一覧。",
      zh: "一次瀏覽韓國全國17市道正在舉行的慶典、戲劇・音樂劇・音樂會、展覽、五日市集、在地美食與公共資料登錄住宿。",
    };
    const t = escapeHtml(homeTitles[lang] || homeTitles.en);
    const d = escapeHtml(homeDescs[lang] || homeDescs.en);
    const canon = `${origin}/?lang=${encodeURIComponent(lang)}`;
    const html = homeTemplate
      .replace(/<html\b[^>]*>/i, `<html lang="${htmlLang}">`)
      .replace(/<title>[^<]*<\/title>/i, `<title>${t}</title>`)
      .replace(/<meta name="description" content="[^"]*"\s*\/?>/i, `<meta name="description" content="${d}" />`)
      .replace(/<meta property="og:title" content="[^"]*"\s*\/?>/i, `<meta property="og:title" content="${t}" />`)
      .replace(/<meta property="og:description" content="[^"]*"\s*\/?>/i, `<meta property="og:description" content="${d}" />`)
      .replace(/<meta property="og:url" content="[^"]*"\s*\/?>/i, `<meta property="og:url" content="${escapeHtml(canon)}" />`)
      .replace(/<\/body>/i, `  ${buildHomeSeoMain(origin, lang, homeTitles[lang] || homeTitles.en, homeDescs[lang] || homeDescs.en)}
</body>`);
    res.set("Cache-Control", "public, max-age=0, s-maxage=300, stale-while-revalidate=3600");
    res.status(200).send(html);
    return;
  }

  // 기본 홈(/)은 브라우저 재검증(max-age=0) + 글로벌 CDN 엣지 캐시(s-maxage=300)로 콜드스타트 없이 즉시 응답
  res.set("Cache-Control", "public, max-age=0, s-maxage=300, stale-while-revalidate=3600");
  res.status(200).send(
    homeTemplate.replace(
      /<\/body>/i,
      `  ${buildHomeSeoMain(origin, "ko", "직스테이 로컬 — 전국 지역축제·공연·전시회·5일장 일정과 여행 정보", "전국 17개 시·도의 지역축제, 연극·뮤지컬·콘서트 공연, 미술관·박물관 전시회, 5일장 장날과 볼거리·먹거리, 공공데이터에 등록된 숙소를 한 곳에서 찾아보세요.")}
</body>`
    )
  );
});

async function withTodayStory(template, origin) {
  try {
    const hub = await seo.fetchJsonCached(`${origin}/data/hub/core.json`);
    const today = kstTodayYmd();
    return todayStory.injectTodayStory(template, todayStory.pickTodayStory(hub, today), today);
  } catch (err) {
    console.error("Today story injection failed:", err);
    return template;
  }
}

/** 홈: 17개 시·도 여행 정보 페이지로 가는 링크 (검색엔진이 지역 페이지를 찾아가는 입구) */
function buildHomeSeoMain(origin, lang, title, lead) {
  const L = seo.LABELS[lang] || seo.LABELS.ko;
  return seo.renderSeoMain({
    lang,
    title,
    lead,
    sections: [
      { heading: L.festivals, html: seo.linkList(regionTopicLinks(origin, "", lang, null)) },
      { heading: L.regions, html: seo.linkList(PROVINCES_17.map((p) => seo.regionLink(origin, p, provinceLabel(p, lang), lang))) },
    ],
  });
}

/**
 * 숙소 외부 연결 리다이렉트 (/go?id=stay_xxx)
 * - 검색봇이 아니면 outbound_clicks +1 (방문 통계용, 과금 없음)
 * - 운영자 직거래 링크(direct_booking_url, 네이버 지도 URL 제외)가 있으면 그쪽으로, 없으면 네이버 지도 검색으로 이동
 */
function directBookingUrl(data) {
  const url = typeof data.direct_booking_url === "string" ? data.direct_booking_url.trim() : "";
  if (!/^https?:\/\//i.test(url)) return "";
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host.includes("map.naver.") ? "" : url;
  } catch (_) {
    return "";
  }
}

exports.goRedirect = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  res.set("Cache-Control", "no-store, no-cache, must-revalidate");
  const rawId = typeof req.query.id === "string" ? req.query.id.trim() : "";
  if (!LISTING_ID_RE.test(rawId)) {
    res.redirect(302, "/");
    return;
  }

  try {
    const ref = getFirestore().collection("listings").doc(rawId);
    const snap = await ref.get();
    const data = snap.exists ? snap.data() : null;
    if (!data || data.status !== "active") {
      res.redirect(302, "/");
      return;
    }

    if (!BOT_UA_RE.test(String(req.get("user-agent") || ""))) {
      try {
        await ref.update({ outbound_clicks: FieldValue.increment(1) });
      } catch (err) {
        console.error("click count error:", err); // 통계 실패는 이동을 막지 않는다.
      }
    }
    res.redirect(302, directBookingUrl(data) || fallbackNaverMapUrl(data));
  } catch (err) {
    console.error("redirect error:", err);
    res.redirect(302, "/");
  }
});

/** 문서가 마지막으로 바뀐 날 (검색엔진이 다시 가져올 페이지를 고르는 데 쓴다) */
function lastmodTag(doc) {
  const t = doc && doc.updateTime && typeof doc.updateTime.toDate === "function" ? doc.updateTime.toDate() : null;
  return t ? `\n    <lastmod>${t.toISOString().slice(0, 10)}</lastmod>` : "";
}

/**
 * 국내(네이버) + 해외(구글/빙) 다국어 Programmatic SEO 사이트맵 (/sitemap.xml)
 * 상한 없음: 볼거리·축제는 매주 늘어난다. 사이트맵 한 파일은 50,000 URL 까지 가능하다.
 */
exports.serveSitemap = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  if (redirectToPrimaryDomain(req, res)) return;
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || PRIMARY_HOST;
  const origin = `${proto}://${host}`;

  try {
    const db = getFirestore();
    const [listingSnap, spotSnap] = await Promise.all([
      db.collection("listings").where("status", "==", "active").get(),
      db.collection("spots").where("status", "==", "active").get(),
    ]);
    const urls = [];

    const buildAlternates = (baseQuery) => {
      const sep = baseQuery ? "&amp;" : "";
      const prefix = baseQuery ? `/?${baseQuery}` : "/";
      return [
        `    <xhtml:link rel="alternate" hreflang="ko" href="${origin}${prefix}"/>`,
        `    <xhtml:link rel="alternate" hreflang="en" href="${origin}${prefix}${sep}${baseQuery ? "lang=en" : "?lang=en"}"/>`,
        `    <xhtml:link rel="alternate" hreflang="ja" href="${origin}${prefix}${sep}${baseQuery ? "lang=ja" : "?lang=ja"}"/>`,
        `    <xhtml:link rel="alternate" hreflang="zh-Hant" href="${origin}${prefix}${sep}${baseQuery ? "lang=zh" : "?lang=zh"}"/>`,
        `    <xhtml:link rel="alternate" hreflang="x-default" href="${origin}${prefix}"/>`,
      ].join("\n");
    };

    urls.push(`  <url>\n    <loc>${origin}/</loc>\n${buildAlternates("")}\n  </url>`);
    for (const prov of PROVINCES_17) {
      const q = `region=${encodeURIComponent(prov)}`;
      urls.push(`  <url>\n    <loc>${origin}/?${q}</loc>\n${buildAlternates(q)}\n  </url>`);
    }
    // 주제 페이지(축제 일정·5일장 장날): 전국 + 내용이 있는 시·도. XML 안에서는 & 를 &amp; 로 쓴다
    const [hubCore, marketsDoc, cultureDoc] = await Promise.all([
      seo.fetchJsonCached(`${origin}/data/hub/core.json`),
      seo.fetchJsonCached(`${origin}/data/hub/markets.json`),
      seo.fetchJsonCached(`${origin}/data/hub/culture.json`),
    ]);
    const hubForTopics = hubCore
      ? { ...hubCore, markets: (marketsDoc && marketsDoc.markets) || [], culture: (cultureDoc && cultureDoc.culture) || [] }
      : null;
    for (const topic of TOPICS) {
      const provs = hubForTopics ? topicProvinces(hubForTopics, topic, kstTodayYmd()) : [];
      for (const prov of ["", ...provs]) {
        const q = prov ? `topic=${topic}&amp;region=${encodeURIComponent(prov)}` : `topic=${topic}`;
        urls.push(`  <url>\n    <loc>${origin}/?${q}</loc>\n${buildAlternates(q)}\n  </url>`);
      }
    }
    // 종료일이 지난 행사는 제출하지 않는다 (주간 갱신은 허브에서만 빼고 Firestore 상태는 그대로 둔다)
    const todayKst = new Date(Date.now() + 9 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, "");
    spotSnap.forEach((doc) => {
      if (!SPOT_ID_RE.test(doc.id)) return;
      const d = doc.data() || {};
      const endYmd = String(d.end_date || "").trim();
      if (/^\d{8}$/.test(endYmd) && endYmd < todayKst) return;
      const paramKey = d.is_story === true ? "story" : "spot";
      const q = `${paramKey}=${encodeURIComponent(doc.id)}`;
      urls.push(`  <url>\n    <loc>${origin}/?${q}</loc>${lastmodTag(doc)}\n${buildAlternates(q)}\n  </url>`);
    });
    listingSnap.forEach((doc) => {
      if (!LISTING_ID_RE.test(doc.id)) return;
      const q = `id=${encodeURIComponent(doc.id)}`;
      urls.push(`  <url>\n    <loc>${origin}/?${q}</loc>${lastmodTag(doc)}\n${buildAlternates(q)}\n  </url>`);
    });

    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls.join(
      "\n"
    )}\n</urlset>`;
    res.set("Content-Type", "application/xml; charset=utf-8");
    res.set("Cache-Control", "public, max-age=1800, s-maxage=3600");
    res.status(200).send(xml);
  } catch (err) {
    console.error("Sitemap error:", err);
    res.status(500).send("Sitemap error");
  }
});

exports.serveRss = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  if (redirectToPrimaryDomain(req, res)) return;
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || PRIMARY_HOST;
  const origin = `${proto}://${host}`;
  try {
    const [hubCore, cultureDoc] = await Promise.all([
      seo.fetchJsonCached(`${origin}/data/hub/core.json`),
      seo.fetchJsonCached(`${origin}/data/hub/culture.json`),
    ]);
    if (!hubCore) throw new Error("hub core.json unavailable");
    const xml = rss.buildRssXml(origin, hubCore, (cultureDoc && cultureDoc.culture) || [], kstTodayYmd());
    res.set("Content-Type", "application/rss+xml; charset=utf-8");
    // 오늘의 스토리가 KST 자정에 바뀌므로 CDN 캐시는 1시간까지만
    res.set("Cache-Control", "public, max-age=1800, s-maxage=3600");
    res.status(200).send(xml);
  } catch (err) {
    console.error("RSS error:", err);
    res.status(500).send("RSS error");
  }
});

exports.serveRobots = onRequest({ region: "asia-northeast3" }, (req, res) => {
  if (redirectToPrimaryDomain(req, res)) return;
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || PRIMARY_HOST;
  res.set("Content-Type", "text/plain; charset=utf-8");
  res.set("Cache-Control", "public, max-age=3600");
  res.status(200).send(`User-agent: *\nAllow: /\nDisallow: /go\nSitemap: ${proto}://${host}/sitemap.xml\n`);
});

exports.buildOgHtml = buildOgHtml;
exports.primaryDomainRedirectUrl = primaryDomainRedirectUrl;
exports.stayTitleQualifierKo = stayTitleQualifierKo;
exports.buildTopicOgHtml = buildTopicOgHtml;
exports.buildEndedSpotHtml = buildEndedSpotHtml;
exports.isEndedSpot = isEndedSpot;
exports.marketDaysOfMonth = marketDaysOfMonth;
exports.nextMarketYmd = nextMarketYmd;
exports.buildSpotOgHtml = buildSpotOgHtml;
exports.buildRegionOgHtml = buildRegionOgHtml;
exports.escapeHtml = escapeHtml;
exports.directBookingUrl = directBookingUrl;
exports.normalizeLang = normalizeLang;
exports.shortProvince = shortProvince;
exports.cleanListSummary = cleanListSummary;
exports.lastmodTag = lastmodTag;
