const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

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
const SUPPORTED_LANGS = new Set(["ko", "en", "ja", "zh"]);
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
  const q = [listing.region_depth1, listing.region_depth2, listing.title].filter(Boolean).join(" ").trim() || "합법숙소";
  return `https://map.naver.com/p/search/${encodeURIComponent(q)}`;
}

function buildLocalizedMeta(listing, lang) {
  const i18n = listing && typeof listing.i18n === "object" ? listing.i18n[lang] : null;
  const region = [listing.region_depth1, listing.region_depth2].filter(Boolean).join(" ").trim();
  const points = Array.isArray(listing.summary_points) ? listing.summary_points.slice(0, 2).join(" · ") : "";

  if (lang === "en") {
    const title = (i18n && i18n.title) || listing.title || "Gov-Verified Stay in Korea";
    return {
      htmlLang: "en",
      titleText: `${title} | JikStay Korea (0% Booking Fee)`,
      descText:
        (i18n && i18n.summary) ||
        `100% Korean Government-Licensed Stay (${listing.license_type || "Verified"}) in ${region}. Zero platform commission — book direct with the host.`,
    };
  }
  if (lang === "ja") {
    const title = (i18n && i18n.title) || listing.title || "韓国公認ステイ";
    return {
      htmlLang: "ja",
      titleText: `${title} | JikStay 韓国公認宿・仲介手数料0ウォン`,
      descText:
        (i18n && i18n.summary) ||
        `韓国自治体の営業申告確認済（${listing.license_type || "公認"}）・${region}。予約サイトの仲介手数料0ウォンでホスト直取引。`,
    };
  }
  if (lang === "zh") {
    const title = (i18n && i18n.title) || listing.title || "韓國合法認證住宿";
    return {
      htmlLang: "zh-Hant",
      titleText: `${title} | JikStay 韓國合法民宿・0%手續費直訂`,
      descText:
        (i18n && i18n.summary) ||
        `韓國政府營業申報核實合法住宿（${listing.license_type || "認證"}）・${region}。免平台仲介手續費，直接聯繫屋主預訂。`,
    };
  }

  const titleText = listing.title ? `${listing.title} | 직스테이` : "직스테이 - 수수료 0원 합법 숙소 직거래";
  const descText =
    [region, listing.license_type ? `${listing.license_type} 신고 확인` : "", points].filter(Boolean).join(" | ") ||
    "영업신고를 확인한 합법 숙소를 중개수수료 없이 호스트와 직접 예약하세요.";
  return { htmlLang: "ko", titleText, descText };
}

function buildOgHtml(template, listing, listingId, origin, rawLang = "ko") {
  const lang = normalizeLang(rawLang);
  const { htmlLang, titleText, descText } = buildLocalizedMeta(listing, lang);
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

  const reviews = Array.isArray(listing.naver_reviews) ? listing.naver_reviews.slice(0, 3) : [];
  const reviewItemsHtml = reviews
    .map((r) => `<li>${escapeHtml(r.title || "")} - ${escapeHtml(r.summary || "")}</li>`)
    .join("");
  const seoNoscript = `<noscript id="jikstay-seo"><article><h1>${escapedTitle}</h1><p>${escapedDesc}</p><p>${escapeHtml(
    locInfo.display_address || ""
  )} · ${escapeHtml(listing.license_type || "")}</p>${reviewItemsHtml ? `<ul>${reviewItemsHtml}</ul>` : ""}</article></noscript>`;

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">${ogImageTag}${ogUrlTag}${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoNoscript}\n</body>`);
}

function fmtYmdIso(ymd) {
  const s = String(ymd || "").trim();
  return /^\d{8}$/.test(s) ? `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}` : "";
}

function buildSpotOgHtml(template, spot, spotId, origin, rawLang = "ko") {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const prov = String(spot.province || "");
  const provEn = PROVINCE_EN[prov] || prov || "Korea";
  const kind = String(spot.kind || spot.category || "attraction");
  const isStory = spot.is_story === true;
  const title = String(spot.title || "로컬 명소");
  const addr = String(spot.addr || spot.address || spot.region_label || prov);
  const imageUrl = spot.image_url ? String(spot.image_url) : spot.image ? String(spot.image) : "";
  const queryKey = isStory ? "story" : "spot";

  let titleText = isStory ? `${title} · ${spot.source_book || prov} | 직스테이 로컬 스토리` : `${title} (${prov}) | 직스테이 로컬`;
  let descText = spot.summary
    ? `${spot.summary} (${addr})`
    : `${addr} · 주변 맛집·지자체 공식 관광지도 PDF·합법 안심숙소 동선 안내`;
  if (lang === "en") {
    titleText = `${title} (${provEn}) | Jikstay Korea`;
    descText = spot.en_summary
      ? String(spot.en_summary)
      : `${addr} — Explore official municipal PDF maps, public transit routes, nearby local food & verified stays in ${provEn}.`;
  } else if (lang === "ja") {
    titleText = `${title}（${prov}）| Jikstay Korea`;
    descText = `${addr} — 自治体公式観光地図PDF・乗換ルート・周辺グルメ・公認宿ガイド。`;
  } else if (lang === "zh") {
    titleText = `${title}（${prov}）| Jikstay 韓國`;
    descText = `${addr} — 官方旅遊地圖PDF、大眾運輸路線、周邊在地美食與合法民宿指南。`;
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
  const storyBodyHtml = Array.isArray(spot.paragraphs)
    ? spot.paragraphs.map((p) => `<p>${escapeHtml(p)}</p>`).join("")
    : "";
  const practicalHtml = Array.isArray(spot.practical_info) && spot.practical_info.length > 0
    ? `<ul>${spot.practical_info.map((r) => `<li>${escapeHtml(r.label || "")}: ${escapeHtml(r.value || "")}</li>`).join("")}</ul>`
    : "";
  const seoNoscript = `<noscript id="jikstay-seo"><article><h1>${escapedTitle}</h1><p>${escapedDesc}</p>${storyBodyHtml}${practicalHtml}</article></noscript>`;

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">${ogImageTag}${ogUrlTag}${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoNoscript}\n</body>`);
}

function buildRegionOgHtml(template, province, origin, rawLang = "ko") {
  const lang = normalizeLang(rawLang);
  const htmlLang = lang === "zh" ? "zh-Hant" : lang;
  const provEn = PROVINCE_EN[province] || province;
  let titleText = `${province} 여행 공식 관광지도 PDF·축제·로컬맛집·합법숙소 총정리 | 직스테이 로컬`;
  let descText = `${province} 지자체 공식 가이드북(PDF/E-book), 실시간 축제·오일장, 로컬 맛집 쿠폰과 합법 인허가 안심숙소를 한눈에 확인하세요.`;
  if (lang === "en") {
    titleText = `${provEn} Official Tourist Maps PDF, Festivals, Food & Legal Stays | Jikstay Korea`;
    descText = `Explore ${provEn}, Korea with free official municipal PDF guidebooks, public transit routes, local festivals, restaurants, and verified stays.`;
  } else if (lang === "ja") {
    titleText = `${province} 公式観光地図PDF・祭り・グルメ・公認宿まとめ | Jikstay Korea`;
    descText = `${province}の自治体公式ガイドブックPDF、開催中の祭り、地元グルメ、営業申告確認済の公認宿をマップで一括検索。`;
  } else if (lang === "zh") {
    titleText = `${province} 官方旅遊地圖PDF・慶典・美食・合法民宿總整理 | Jikstay 韓國`;
    descText = `一鍵開啟${province}地方政府官方旅遊指南PDF、大眾運輸路線、慶典活動、在地美食與合法認證住宿。`;
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
  const seoNoscript = `<noscript id="jikstay-seo"><article><h1>${escapedTitle}</h1><p>${escapedDesc}</p></article></noscript>`;

  return template
    .replace(/<html>/i, `<html lang="${htmlLang}">`)
    .replace(/<title>[\s\S]*?<\/title>/, `<title>${escapedTitle}</title>`)
    .replace(/<meta\s+name="description"\s+content="[^"]*">/, `<meta name="description" content="${escapedDesc}">`)
    .replace(/<meta\s+property="og:title"\s+content="[^"]*">/, `<meta property="og:title" content="${escapedTitle}">`)
    .replace(
      /<meta\s+property="og:description"\s+content="[^"]*">/,
      `<meta property="og:description" content="${escapedDesc}">${ogUrlTag}${hreflangTags}${jsonLdTag}`
    )
    .replace(/<\/body>/i, `  ${seoNoscript}\n</body>`);
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
      let snap = await db.collection("listings").doc(rawId).get();
      let data = snap.exists ? snap.data() : null;
      let effectiveId = rawId;
      if (data && data.status === "replaced_by_claim" && LISTING_ID_RE.test(String(data.claimed_by_listing_id || ""))) {
        effectiveId = String(data.claimed_by_listing_id);
        snap = await db.collection("listings").doc(effectiveId).get();
        data = snap.exists ? snap.data() : null;
      }
      if (!data || data.status !== "active") {
        res.set("Cache-Control", "no-cache, no-store, must-revalidate");
        res.status(200).send(template);
        return;
      }
      const html = buildOgHtml(template, data, effectiveId, origin, rawLang);
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
        const html = buildSpotOgHtml(template, data, rawSpot, origin, rawLang);
        res.set("Cache-Control", "public, max-age=300, s-maxage=600");
        res.status(200).send(html);
        return;
      }
    } catch (err) {
      console.error("Spot OG tag injection failed:", err);
    }
  }

  if (PROVINCES_17.includes(rawRegion)) {
    const html = buildRegionOgHtml(template, rawRegion, origin, rawLang);
    res.set("Cache-Control", "public, max-age=600, s-maxage=1200");
    res.status(200).send(html);
    return;
  }

  const lang = normalizeLang(rawLang);
  if (lang !== "ko") {
    const htmlLang = lang === "zh" ? "zh-Hant" : lang;
    const homeTitles = {
      en: "Jikstay Korea — Verified Local Stays, 0% Fee & 17-Province Travel Guides",
      ja: "Jikstay Korea — 韓国公認宿・仲介手数料0円・17市道公式ローカルガイド",
      zh: "Jikstay 韓國 — 韓國合法認證住宿・0%手續費・17市道官方旅遊指南",
    };
    const homeDescs = {
      en: "Book government-verified legal stays in Korea with 0% guest platform fee. Explore festivals, local food & official municipal travel guides across 17 provinces.",
      ja: "韓国政府・自治体の営業届出確認済み宿泊施設を仲介手数料0円で直接予約。全国17市道の祭り・グルメ・公式ガイドを一覧。",
      zh: "免平台手續費直接預訂韓國政府核驗合法民宿與韓屋，一次瀏覽全國17市道慶典、在地美食與官方旅遊指南。",
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
      .replace(/<meta property="og:url" content="[^"]*"\s*\/?>/i, `<meta property="og:url" content="${escapeHtml(canon)}" />`);
    res.set("Cache-Control", "public, max-age=0, s-maxage=300, stale-while-revalidate=3600");
    res.status(200).send(html);
    return;
  }

  // 기본 홈(/)은 브라우저 재검증(max-age=0) + 글로벌 CDN 엣지 캐시(s-maxage=300)로 콜드스타트 없이 즉시 응답
  res.set("Cache-Control", "public, max-age=0, s-maxage=300, stale-while-revalidate=3600");
  res.status(200).send(template);
});

/**
 * 제안 A 수익모델: CPC(클릭당 과금) 리다이렉트 엔진 (/go?id=stay_xxx)
 * - 검색봇(Bot) 클릭 제외 + 동일 IP/브라우저 24시간 중복 클릭 1회만 인정
 * - 호스트 인증 숙소(claimed)이면서 cpc_balance >= cpc_rate 이면 단가 차감 후 직거래 예약창구로 이동
 * - 미인증 공공 숙소(public)이거나 CPC 크레딧 소진 시 과금 없이 네이버 지도/플레이스 검색으로 안전 연결
 */
exports.goRedirect = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  res.set("Cache-Control", "no-store, no-cache, must-revalidate");
  const rawId = typeof req.query.id === "string" ? req.query.id.trim() : "";
  if (!LISTING_ID_RE.test(rawId)) {
    res.redirect(302, "/");
    return;
  }

  const db = getFirestore();
  try {
    let targetId = rawId;
    let ref = db.collection("listings").doc(targetId);
    let snap = await ref.get();
    let data = snap.exists ? snap.data() : null;

    if (data && data.status === "replaced_by_claim" && LISTING_ID_RE.test(String(data.claimed_by_listing_id || ""))) {
      targetId = String(data.claimed_by_listing_id);
      ref = db.collection("listings").doc(targetId);
      snap = await ref.get();
      data = snap.exists ? snap.data() : null;
    }

    if (!data || data.status !== "active") {
      res.redirect(302, "/");
      return;
    }

    const ua = String(req.get("user-agent") || "");
    const isBot = BOT_UA_RE.test(ua);
    const xff = String(req.get("x-forwarded-for") || req.ip || "unknown")
      .split(",")[0]
      .trim();
    const utcDay = new Date().toISOString().slice(0, 10);
    const dedupHash = crypto
      .createHash("sha256")
      .update(`jikstay_cpc_v1|${targetId}|${utcDay}|${xff}|${ua.slice(0, 80)}`)
      .digest("hex");

    let destinationUrl = fallbackNaverMapUrl(data);

    if (!isBot) {
      const dedupRef = db.collection("cpc_click_dedup").doc(dedupHash);
      await db.runTransaction(async (tx) => {
        const [freshSnap, dedupSnap] = await Promise.all([tx.get(ref), tx.get(dedupRef)]);
        if (!freshSnap.exists) return;
        const cur = freshSnap.data() || {};
        const isClaimed = cur.listing_tier === "claimed" || Boolean(cur.application_id);
        const rate = Number(cur.cpc_rate) > 0 ? Number(cur.cpc_rate) : 300;
        const hasLegacyUnlimited = isClaimed && cur.cpc_balance === undefined;
        const balance = Number(cur.cpc_balance) || 0;
        const canUseDirectUrl =
          isClaimed &&
          (hasLegacyUnlimited || balance >= rate) &&
          typeof cur.direct_booking_url === "string" &&
          /^https?:\/\//i.test(cur.direct_booking_url);

        destinationUrl = canUseDirectUrl ? cur.direct_booking_url.trim() : fallbackNaverMapUrl(cur);

        if (!dedupSnap.exists) {
          const updates = { outbound_clicks: FieldValue.increment(1) };
          let charged = 0;
          if (canUseDirectUrl && !hasLegacyUnlimited && balance >= rate) {
            const nextBal = Math.max(0, balance - rate);
            updates.cpc_balance = nextBal;
            updates.cpc_charged_clicks = FieldValue.increment(1);
            updates.is_sponsored = nextBal >= rate;
            charged = rate;
          }
          tx.update(ref, updates);
          tx.set(dedupRef, {
            listing_id: targetId,
            day: utcDay,
            charged_krw: charged,
            created_at: FieldValue.serverTimestamp(),
          });
        }
      });
    } else {
      const isClaimed = data.listing_tier === "claimed" || Boolean(data.application_id);
      const rate = Number(data.cpc_rate) > 0 ? Number(data.cpc_rate) : 300;
      const balance = Number(data.cpc_balance) || 0;
      if (
        isClaimed &&
        (data.cpc_balance === undefined || balance >= rate) &&
        typeof data.direct_booking_url === "string" &&
        /^https?:\/\//i.test(data.direct_booking_url)
      ) {
        destinationUrl = data.direct_booking_url.trim();
      }
    }

    res.redirect(302, destinationUrl);
  } catch (err) {
    console.error("CPC redirect error:", err);
    res.redirect(302, "/");
  }
});

/**
 * 국내(네이버) + 해외(구글/빙) 다국어 Programmatic SEO 사이트맵 (/sitemap.xml)
 */
exports.serveSitemap = onRequest({ region: "asia-northeast3" }, async (req, res) => {
  const proto = req.get("x-forwarded-proto") || "https";
  const host = req.get("x-forwarded-host") || req.get("host") || "jikstay-lkxu1.web.app";
  const origin = `${proto}://${host}`;

  try {
    const db = getFirestore();
    const [listingSnap, spotSnap] = await Promise.all([
      db.collection("listings").where("status", "==", "active").limit(2500).get(),
      db.collection("spots").where("status", "==", "active").limit(1000).get(),
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
    spotSnap.forEach((doc) => {
      if (!SPOT_ID_RE.test(doc.id)) return;
      const d = doc.data() || {};
      const paramKey = d.is_story === true ? "story" : "spot";
      const q = `${paramKey}=${encodeURIComponent(doc.id)}`;
      urls.push(`  <url>\n    <loc>${origin}/?${q}</loc>\n${buildAlternates(q)}\n  </url>`);
    });
    listingSnap.forEach((doc) => {
      if (!LISTING_ID_RE.test(doc.id)) return;
      const q = `id=${encodeURIComponent(doc.id)}`;
      urls.push(`  <url>\n    <loc>${origin}/?${q}</loc>\n${buildAlternates(q)}\n  </url>`);
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
exports.normalizeLang = normalizeLang;
