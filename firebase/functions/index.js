const fs = require("node:fs");
const path = require("node:path");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

const seo = require("./seo_content");

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

  const titleText = listing.title ? `${listing.title} | 직스테이` : "직스테이 로컬 - 공공데이터 숙소·로컬 여행 정보";
  const descText =
    [region, listing.license_type || "", points].filter(Boolean).join(" | ") ||
    "공공데이터에 등록된 숙소와 주변 볼거리·먹거리·축제를 한 번에 찾아보세요.";
  return { htmlLang: "ko", titleText, descText };
}

function buildOgHtml(template, listing, listingId, origin, rawLang = "ko", data = null) {
  const lang = normalizeLang(rawLang);
  const tStay = (lang !== "ko" && data && data.i18nCore && data.i18nCore.stays && data.i18nCore.stays[listingId]) || null;
  const { htmlLang, titleText, descText } = buildLocalizedMeta(listing, lang, tStay);
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
  const plainTitle = titleText.replace(/\s*\|[^|]*$/, "");
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

  const schemaType = kind === "event" ? "Festival" : kind === "food" ? "Restaurant" : "TouristAttraction";
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
  let titleText = `${province} 여행 가볼만한 곳·축제·맛집·숙소 총정리 | 직스테이 로컬`;
  let descText = `${province} 가볼만한 곳, 진행 중인 축제·오일장, 로컬 맛집, 지자체 공식 가이드북(PDF/E-book)과 공공데이터 등록 숙소를 한눈에 확인하세요.`;
  if (lang === "en") {
    titleText = `Things to Do in ${provEn}, Korea: Festivals, Local Food & Stays | Jikstay Korea`;
    descText = `Things to do in ${provEn}, Korea: attractions, festivals happening now, local food and places to stay, plus free official municipal tourist maps (PDF).`;
  } else if (lang === "ja") {
    titleText = `${provLabel}観光 おすすめスポット・祭り・グルメ・宿泊 | Jikstay Korea`;
    descText = `${provLabel}のおすすめ観光スポット、開催中の祭り、地元グルメ、宿泊施設と自治体公式観光ガイドブックPDFをまとめて紹介。`;
  } else if (lang === "zh") {
    titleText = `${provLabel}旅遊 必去景點・慶典・美食・住宿 | Jikstay 韓國`;
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

exports.serveApp = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  const template = CACHED_TEMPLATE || fs.readFileSync(TEMPLATE_PATH, "utf8");
  const rawId = typeof req.query.id === "string" ? req.query.id.trim() : "";
  const rawStory = typeof req.query.story === "string" ? req.query.story.trim() : "";
  const rawSpot = rawStory || (typeof req.query.spot === "string" ? req.query.spot.trim() : "");
  const rawRegion = typeof req.query.region === "string" ? req.query.region.trim() : "";
  const rawLang = typeof req.query.lang === "string" ? req.query.lang.trim() : "ko";
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || "jikstay-lkxu1.web.app";
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

  if (PROVINCES_17.includes(rawRegion)) {
    const [seoData, staysIndex] = await Promise.all([
      seo.loadSeoData(origin, normalizeLang(rawLang), null),
      seo.fetchJsonCached(`${origin}/data/public_stays_index.json`),
    ]);
    const html = buildRegionOgHtml(template, rawRegion, origin, rawLang, seoData, staysIndex);
    res.set("Cache-Control", "public, max-age=600, s-maxage=1200");
    res.status(200).send(html);
    return;
  }

  const lang = normalizeLang(rawLang);
  if (lang !== "ko") {
    const htmlLang = lang === "zh" ? "zh-Hant" : lang;
    const homeTitles = {
      en: "Jikstay Korea — Local Stories, Stays & 17-Province Travel Guides",
      ja: "Jikstay Korea — ローカル旅行ストーリー・宿・17市道公式ガイド",
      zh: "Jikstay 韓國 — 在地旅遊故事・住宿・17市道官方旅遊指南",
    };
    const homeDescs = {
      en: "Find stays listed in Korean public tourism data and explore festivals, local food & official municipal travel guides across 17 provinces.",
      ja: "韓国の公共観光データに登録された宿泊施設と、全国17市道の祭り・グルメ・公式ガイドを一覧。",
      zh: "查看登錄於韓國公共旅遊資料的住宿，一次瀏覽全國17市道慶典、在地美食與官方旅遊指南。",
    };
    const t = escapeHtml(homeTitles[lang] || homeTitles.en);
    const d = escapeHtml(homeDescs[lang] || homeDescs.en);
    const canon = `${origin}/?lang=${encodeURIComponent(lang)}`;
    const html = template
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
    template.replace(
      /<\/body>/i,
      `  ${buildHomeSeoMain(origin, "ko", "직스테이 로컬 — 전국 17개 시·도 여행 정보", "공공데이터에 등록된 숙소와 전국 17개 시·도의 볼거리·먹거리·축제, 지자체 공식 관광 가이드북을 한 곳에서 찾아보세요.")}
</body>`
    )
  );
});

/** 홈: 17개 시·도 여행 정보 페이지로 가는 링크 (검색엔진이 지역 페이지를 찾아가는 입구) */
function buildHomeSeoMain(origin, lang, title, lead) {
  const L = seo.LABELS[lang] || seo.LABELS.ko;
  return seo.renderSeoMain({
    lang,
    title,
    lead,
    sections: [{ heading: L.regions, html: seo.linkList(PROVINCES_17.map((p) => seo.regionLink(origin, p, provinceLabel(p, lang), lang))) }],
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
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || "jikstay-lkxu1.web.app";
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

exports.serveRobots = onRequest({ region: "asia-northeast3" }, (req, res) => {
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || "jikstay-lkxu1.web.app";
  res.set("Content-Type", "text/plain; charset=utf-8");
  res.set("Cache-Control", "public, max-age=3600");
  res.status(200).send(`User-agent: *\nAllow: /\nDisallow: /go\nSitemap: ${proto}://${host}/sitemap.xml\n`);
});

exports.buildOgHtml = buildOgHtml;
exports.buildSpotOgHtml = buildSpotOgHtml;
exports.buildRegionOgHtml = buildRegionOgHtml;
exports.escapeHtml = escapeHtml;
exports.directBookingUrl = directBookingUrl;
exports.normalizeLang = normalizeLang;
exports.shortProvince = shortProvince;
exports.cleanListSummary = cleanListSummary;
exports.lastmodTag = lastmodTag;
