// 검색엔진용 본문.
// 앱(Flutter)은 화면을 캔버스에 그리고 시작 스플래시는 첫 프레임에 지워지므로, 구글이 JS 실행 후 보는 DOM 에는
// 장소 본문이 남지 않는다. 그래서 serveApp 이 페이지마다 그 언어의 본문(이름·설명·주소·이용 안내·주변 장소 링크)을
// 실제 HTML 요소(<main id="jikstay-seo">)로 넣는다. 앱이 뜨면 flutter-view 가 그 위를 덮으므로 사용자 화면은 그대로다.
//
// 번역은 Firestore 가 아니라 호스팅의 정적 파일(backend/split_hub.py 생성물)에 있다:
//   data/hub/core.json                    전체 볼거리·축제 목록(한국어, 좌표 포함)
//   data/i18n/{lang}/core.json            items(볼거리·축제)·stays(숙소) 의 이름·주소·개요 미리보기
//   data/i18n/{lang}/details_{code}.json  본문 문단·이용 안내·전체 개요
// 함수 인스턴스 메모리에 10분 캐시한다. 받지 못하면 한국어 원문으로 대체해 페이지는 항상 나간다.

const CACHE_MS = 10 * 60 * 1000;
const FETCH_TIMEOUT_MS = 2500;
const cache = new Map();

/** backend/split_hub.py 의 PROVINCE_CODES 와 같아야 한다. */
const PROVINCE_CODES = {
  서울: "seoul", 부산: "busan", 대구: "daegu", 인천: "incheon", 광주: "gwangju",
  대전: "daejeon", 울산: "ulsan", 세종: "sejong", 경기: "gyeonggi", 강원: "gangwon",
  충북: "chungbuk", 충남: "chungnam", 전북: "jeonbuk", 전남: "jeonnam", 경북: "gyeongbuk",
  경남: "gyeongnam", 제주: "jeju",
};

const LABELS = {
  ko: { address: "주소", info: "이용 안내", nearby: "주변 볼거리·먹거리·축제", more: "지역 여행 정보", home: "전국 여행 정보",
    festivals: "축제·행사", attractions: "볼거리", food: "먹거리", stays: "숙소", regions: "17개 시·도 여행 정보" },
  en: { address: "Address", info: "Visitor information", nearby: "Nearby attractions, food & festivals", more: "Travel guide",
    home: "Korea travel guide", festivals: "Festivals & events", attractions: "Things to do", food: "Local food",
    stays: "Places to stay", regions: "Travel guides for 17 provinces" },
  ja: { address: "住所", info: "利用案内", nearby: "周辺の観光・グルメ・祭り", more: "旅行ガイド", home: "韓国旅行ガイド",
    festivals: "祭り・イベント", attractions: "観光スポット", food: "グルメ", stays: "宿泊", regions: "17市道の旅行ガイド" },
  zh: { address: "地址", info: "參觀資訊", nearby: "周邊景點・美食・慶典", more: "旅遊指南", home: "韓國旅遊指南",
    festivals: "慶典・活動", attractions: "景點", food: "在地美食", stays: "住宿", regions: "17市道旅遊指南" },
};

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

async function fetchJsonCached(url) {
  const hit = cache.get(url);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.data;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    const res = await fetch(url, { signal: ctrl.signal });
    clearTimeout(timer);
    const data = res.ok ? await res.json() : null;
    cache.set(url, { at: Date.now(), data });
    return data;
  } catch (_) {
    return hit ? hit.data : null; // 실패하면 오래된 캐시라도 쓴다
  }
}

/** 페이지에 필요한 정적 데이터를 한 번에 받는다 (없으면 null). */
async function loadSeoData(origin, lang, provinceCode) {
  const base = `${origin}/data`;
  const jobs = [fetchJsonCached(`${base}/hub/core.json`)];
  if (lang !== "ko") {
    jobs.push(fetchJsonCached(`${base}/i18n/${lang}/core.json`));
    jobs.push(provinceCode ? fetchJsonCached(`${base}/i18n/${lang}/details_${provinceCode}.json`) : Promise.resolve(null));
  }
  const [hub, i18nCore, i18nDetail] = await Promise.all(jobs);
  return { hub: hub || null, i18nCore: i18nCore || null, i18nDetail: i18nDetail || null };
}

function provinceCode(province) {
  return PROVINCE_CODES[province] || "etc";
}

/** 볼거리·축제 한 곳의 표시 필드를 그 언어로 (번역이 없으면 한국어). */
function localizeSpot(spot, id, lang, data) {
  const t = (lang !== "ko" && data && data.i18nCore && data.i18nCore.items && data.i18nCore.items[id]) || {};
  const d = (lang !== "ko" && data && data.i18nDetail && data.i18nDetail[id]) || {};
  const pick = (a, b) => (typeof a === "string" && a.trim() ? a.trim() : b);
  const practical = Array.isArray(d.practical_info) && d.practical_info.length ? d.practical_info : spot.practical_info;
  return {
    title: pick(t.title, String(spot.title || "")),
    koTitle: String(spot.title || ""),
    addr: pick(t.addr, String(spot.addr || spot.address || "")),
    regionLabel: pick(t.region_label, String(spot.region_label || spot.province || "")),
    overview: pick(d.overview, pick(t.overview, String(spot.overview || spot.summary || ""))),
    pullQuote: pick(d.pull_quote, pick(t.pull_quote, String(spot.pull_quote || ""))),
    paragraphs: Array.isArray(d.paragraphs) && d.paragraphs.length ? d.paragraphs : (Array.isArray(spot.paragraphs) ? spot.paragraphs : []),
    practical: Array.isArray(practical) ? practical : [],
    translated: Boolean(t.title),
  };
}

function localizedTitleOf(id, koTitle, lang, data) {
  if (lang === "ko") return koTitle;
  const t = data && data.i18nCore && data.i18nCore.items && data.i18nCore.items[id];
  return (t && t.title) || koTitle;
}

function pageUrl(origin, key, id, lang) {
  const q = `${key}=${encodeURIComponent(id)}`;
  return lang === "ko" ? `${origin}/?${q}` : `${origin}/?${q}&lang=${encodeURIComponent(lang)}`;
}

function distanceKm(a, b) {
  const R = 6371;
  const rad = (x) => (x * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** 같은 시·도에서 가까운 볼거리·먹거리·축제 링크 (좌표 없으면 같은 시·도 앞쪽). */
function nearbyLinks(origin, lang, data, { id, province, lat, lng }, limit = 8) {
  const hub = data && data.hub;
  if (!hub) return [];
  const items = [...(hub.festivals || []), ...(hub.spots || [])].filter(
    (x) => x && x.id && x.id !== id && x.province === province && x.title
  );
  const hasGeo = typeof lat === "number" && typeof lng === "number";
  if (hasGeo) {
    items.sort((a, b) => {
      const da = typeof a.lat === "number" ? distanceKm({ lat, lng }, a) : 1e9;
      const db = typeof b.lat === "number" ? distanceKm({ lat, lng }, b) : 1e9;
      return da - db;
    });
  }
  return items.slice(0, limit).map((x) => ({
    href: pageUrl(origin, "spot", x.id, lang),
    text: localizedTitleOf(x.id, String(x.title), lang, data),
  }));
}

function linkList(links) {
  if (!links.length) return "";
  return `<ul>${links.map((l) => `<li><a href="${escapeHtml(l.href)}">${escapeHtml(l.text)}</a></li>`).join("")}</ul>`;
}

function regionLink(origin, province, provinceLabel, lang) {
  return { href: pageUrl(origin, "region", province, lang), text: provinceLabel };
}

/**
 * <main id="jikstay-seo"> 본문. sections: [{ heading, html }]
 * 앱이 뜨기 전에는 스플래시가, 뜬 뒤에는 flutter-view 가 위를 덮는다 (index.html 의 #jikstay-seo 스타일).
 */
function renderSeoMain({ lang, title, lead, address, imageUrl, imageAlt, paragraphs = [], practical = [], sections = [], breadcrumbs = [] }) {
  const L = LABELS[lang] || LABELS.ko;
  const crumbs = breadcrumbs.length
    ? `<nav aria-label="breadcrumb">${breadcrumbs.map((b) => `<a href="${escapeHtml(b.href)}">${escapeHtml(b.text)}</a>`).join(" › ")}</nav>`
    : "";
  const img = imageUrl ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(imageAlt || title)}" loading="lazy" width="640">` : "";
  const addr = address ? `<p><strong>${escapeHtml(L.address)}</strong>: ${escapeHtml(address)}</p>` : "";
  const body = paragraphs.slice(0, 12).map((p) => `<p>${escapeHtml(p)}</p>`).join("");
  const info = practical.length
    ? `<h2>${escapeHtml(L.info)}</h2><ul>${practical
        .slice(0, 12)
        .map((r) => `<li>${escapeHtml(r.label || "")}: ${escapeHtml(r.value || "")}</li>`)
        .join("")}</ul>`
    : "";
  const secs = sections
    .filter((s) => s && s.html)
    .map((s) => `<section><h2>${escapeHtml(s.heading)}</h2>${s.html}</section>`)
    .join("");
  return `<main id="jikstay-seo" lang="${escapeHtml(lang === "zh" ? "zh-Hant" : lang)}">${crumbs}<article><h1>${escapeHtml(title)}</h1>${
    lead ? `<p>${escapeHtml(lead)}</p>` : ""
  }${img}${addr}${body}${info}</article>${secs}</main>`;
}

function truncate(text, n) {
  const s = String(text || "").replace(/\s+/g, " ").trim();
  return s.length > n ? `${s.slice(0, n - 1).trimEnd()}…` : s;
}

module.exports = {
  LABELS,
  PROVINCE_CODES,
  escapeHtml,
  fetchJsonCached,
  linkList,
  loadSeoData,
  localizeSpot,
  localizedTitleOf,
  nearbyLinks,
  pageUrl,
  provinceCode,
  regionLink,
  renderSeoMain,
  truncate,
  _cache: cache,
};
