// 홈 '오늘의 로컬 스토리'를 서버에서 골라 HTML 스플래시에 넣는다.
// - 스플래시가 앱 첫 화면과 같은 이미지·제목을 보여 주므로 화면 전환이 자연스럽고 LCP 가 스플래시 시점으로 잡힌다.
// - 고른 스토리 id·배지는 window.jikstayTodayStory 로 앱에 넘기고, 앱(홈·지역 전체·검색 없음)은 이를 그대로 쓴다.
//   → 서버가 기준이라 둘이 어긋나지 않는다. 선택 규칙은 앱 pickTodayMunicipalStory(전체 보기)와 같다:
//     개막 0~7일 앞둔 축제(사진 있는 것, 가까운 순 최대 4개) + 이번 달에 맞는 지자체 스토리를 날짜로 순환.
"use strict";

const ROTATION_BASE_UTC = Date.UTC(2026, 10, 15); // 앱 daily_stories.dart 의 DateTime(2026, 11, 15) 과 같아야 한다

/** Dart 의 `a ?? b ?? c` : null·undefined 만 건너뛴다 (빈 문자열은 그대로 쓴다) */
function coalesce(m, keys, fallback = "") {
  for (const k of keys) {
    if (m[k] !== null && m[k] !== undefined) return String(m[k]);
  }
  return fallback;
}

function ymdToUtc(ymd) {
  const s = String(ymd || "").replace(/[^0-9]/g, "");
  if (s.length !== 8) return null;
  return Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8));
}

function strList(v) {
  return Array.isArray(v) ? v.map((x) => String(x).trim()).filter(Boolean) : [];
}

/** 앱 parseDailyStoryFromJson → 스플래시에 필요한 필드만 */
function storyFromJson(m) {
  const id = String(m.id ?? "").trim();
  const title = String(m.title ?? "").trim();
  if (!id || !title) return null;
  const months = Array.isArray(m.months) ? m.months.map((x) => Math.trunc(Number(x) || 0)).filter((d) => d >= 1 && d <= 12) : [];
  const province = coalesce(m, ["province"], "전북");
  const city = coalesce(m, ["city"]);
  const paragraphs = strList(m.paragraphs);
  const pullQuote = coalesce(m, ["pull_quote"]);
  const subtitle = coalesce(m, ["subtitle"]);
  return {
    id,
    title,
    months,
    image: strList(m.images)[0] || "",
    badge: coalesce(m, ["season_badge"], "📖 지자체 공식 스토리"),
    region: `${province} ${city}`.trim(),
    sourceBook: coalesce(m, ["source_book"], "지자체 발행 관광 가이드북"),
    summary: pullQuote || paragraphs[0] || subtitle,
    addressLine: subtitle,
  };
}

/** 앱 _storyFromSpot (축제 → 스토리) 중 스플래시에 쓰는 필드 */
function storyFromFestival(ev, ebooks, badge) {
  const province = ev._province;
  const regionLabel = coalesce(ev, ["region_label", "city"], province);
  const city = regionLabel.startsWith(province) ? regionLabel.slice(province.length).trim() : regionLabel;
  const eb = ebooks.find((e) => coalesce(e, ["province"]) === province);
  const subtitle = coalesce(ev, ["materials", "overview", "summary", "addr"]);
  const pq = coalesce(ev, ["pull_quote", "summary"]);
  return {
    id: String(ev.id),
    title: String(ev.title).trim(),
    months: [],
    image: ev._image,
    badge,
    region: `${province} ${city}`.trim(),
    sourceBook: eb ? String(eb.title) : `${province} 공식 문화관광 자료`,
    summary: pq || subtitle || `${province}에서 만나는 특별한 계절 여행지`,
    addressLine: coalesce(ev, ["addr", "address", "materials"]),
  };
}

/**
 * 오늘(KST, YYYYMMDD)의 홈 스토리. 고를 수 없으면 null.
 * hub: data/hub/core.json (daily_stories, festivals, municipal_ebooks)
 */
function pickTodayStory(hub, todayYmd) {
  if (!hub) return null;
  const today = ymdToUtc(todayYmd);
  if (today === null) return null;
  const month = +String(todayYmd).slice(4, 6);
  const dayOffset = Math.abs(Math.round((today - ROTATION_BASE_UTC) / 86400000));

  const stories = (hub.daily_stories || []).map(storyFromJson).filter(Boolean);
  if (!stories.length) return null;
  const ebooks = (hub.municipal_ebooks || []).filter((e) => e && coalesce(e, ["title"]).trim());

  const imminent = [];
  for (const ev of hub.festivals || []) {
    if (!ev || !String(ev.title ?? "").trim()) continue;
    const end = String(ev.end_date ?? "").trim();
    if (/^\d{8}$/.test(end) && end < todayYmd) continue; // 끝난 축제 (앱 isEndedEventJson)
    const imgs = strList(ev.images);
    const image = coalesce(ev, ["image_url", "image"], imgs[0] || "");
    if (!image) continue;
    const start = ymdToUtc(ev.start_date);
    if (start === null) continue;
    const days = Math.round((start - today) / 86400000);
    if (days < 0 || days > 7) continue;
    imminent.push({ days, ev: { ...ev, _image: image, _province: coalesce(ev, ["province"], "서울") } });
  }
  imminent.sort((a, b) => a.days - b.days); // 안정 정렬: 같은 날이면 core.json 순서
  const imminentStories = imminent.slice(0, 4).map(({ days, ev }) =>
    storyFromFestival(ev, ebooks, days === 0 ? "🔥 오늘 개막 · 임박 축제" : `⏳ 개막 D-${days} · 임박 축제`)
  );

  const seasonal = stories.filter((s) => !s.months.length || s.months.includes(month));
  const pool = [...imminentStories, ...(seasonal.length ? seasonal : stories)];
  return pool[dayOffset % pool.length];
}

function esc(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** 템플릿 스플래시에 스토리를 넣고, 앱이 같은 스토리를 쓰도록 window.jikstayTodayStory 를 심는다 */
function injectTodayStory(template, story, todayYmd) {
  if (!story) return template;
  const m = +String(todayYmd).slice(4, 6);
  const d = +String(todayYmd).slice(6, 8);
  const hint = JSON.stringify({ id: story.id, badge: story.badge, date: String(todayYmd) }).replace(/</g, "\\u003c");
  let html = template
    .replace(/<span class="js-badge-dark">[^<]*<\/span>/, `<span class="js-badge-dark">📖 ${m}월 ${d}일 오늘의 로컬 스토리</span>`)
    .replace(/<span class="js-badge-light">[^<]*<\/span>/, `<span class="js-badge-light">${esc(story.badge)}</span>`)
    .replace(/<p class="js-story-src">[^<]*<\/p>/, `<p class="js-story-src">${esc(`${story.region} · ${story.sourceBook}`)}</p>`)
    .replace(/<p class="js-story-title">[^<]*<\/p>/, `<p class="js-story-title">${esc(story.title)}</p>`)
    .replace(/<p class="js-story-desc">[^<]*<\/p>/, `<p class="js-story-desc">${esc(story.summary)}</p>`)
    .replace(/<span class="js-story-addr">[^<]*<\/span>/, `<span class="js-story-addr">📍 ${esc(story.addressLine)}</span>`)
    .replace(
      /<\/head>/i,
      // 이미지 서버가 그날마다 달라(visitkorea·pstatic 등) 본문 <img> 보다 먼저, head 에서 바로 받기 시작한다
      (story.image ? `  <link rel="preload" as="image" href="${esc(story.image)}" fetchpriority="high">\n` : "") +
        `  <script>window.jikstayTodayStory = ${hint};</script>\n</head>`
    );
  html = story.image
    ? html.replace(
        /(<div class="js-story-img-wrap">\s*<img) src="[^"]*" alt="[^"]*"/,
        `$1 src="${esc(story.image)}" alt="${esc(story.title)}"`
      )
    : html.replace(/<div class="js-story-img-wrap">/, `<div class="js-story-img-wrap" style="display:none">`);
  return html;
}

module.exports = { pickTodayStory, injectTodayStory, storyFromJson };
