// /rss.xml : 오늘의 로컬 스토리 + 곧 열리는 축제·공연·전시.
// - 네이버 서치어드바이저 'RSS 제출'과 Make·텔레그램 같은 자동화 도구의 입력으로 쓴다.
// - 데이터는 sitemap 과 같은 정적 허브(data/hub/core.json · culture.json)에서 읽는다.
"use strict";

const { pickTodayStory } = require("./today_story");

const WINDOW_DAYS = 14; // 오늘부터 이 기간 안에 시작하는 행사만 '새 소식'으로 싣는다
const LONG_RUNNING_DAYS = 60; // 이보다 긴 상설 공연·전시는 매주 같은 글이 되어 싣지 않는다
const MAX_FESTIVALS = 30;
const MAX_CULTURE = 20;
const DESC_MAX = 300;

function xmlEsc(s) {
  return String(s ?? "")
    // XML 1.0 에서 허용되지 않는 제어 문자는 피드 전체를 깨뜨리므로 지운다
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g, "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function plain(s, max = DESC_MAX) {
  const t = String(s ?? "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

function ymdToUtc(ymd) {
  const s = String(ymd || "");
  return /^\d{8}$/.test(s) ? Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8)) : null;
}

/** KST 그날 00:00 을 RFC 822 날짜로 */
function kstMidnightRfc822(ymd) {
  const utc = ymdToUtc(ymd);
  return utc === null ? "" : new Date(utc - 9 * 3600 * 1000).toUTCString();
}

function fmtYmd(ymd) {
  const s = String(ymd || "");
  return /^\d{8}$/.test(s) ? `${s.slice(0, 4)}.${s.slice(4, 6)}.${s.slice(6, 8)}` : "";
}

/** 오늘 ~ WINDOW_DAYS 안에 시작하고, 상설(LONG_RUNNING_DAYS 초과)이 아닌 행사. 시작일 순 */
function upcoming(list, todayYmd, max) {
  const today = ymdToUtc(todayYmd);
  return (list || [])
    .filter((x) => {
      if (!x || !x.id || !String(x.title || "").trim()) return false;
      const start = ymdToUtc(x.start_date);
      if (start === null) return false;
      const end = ymdToUtc(x.end_date) ?? start;
      if (end < today) return false;
      if ((end - start) / 86400000 > LONG_RUNNING_DAYS) return false;
      return (start - today) / 86400000 <= WINDOW_DAYS;
    })
    .sort((a, b) => String(a.start_date).localeCompare(String(b.start_date)) || String(a.id).localeCompare(String(b.id)))
    .slice(0, max);
}

function regionOf(x) {
  const prov = String(x.province || "").trim();
  const label = String(x.region_label || x.city || "").trim();
  if (!label) return prov;
  return label.startsWith(prov) ? label : `${prov} ${label}`.trim();
}

function eventItem(origin, x, kindLabel, pubDate) {
  const period = [fmtYmd(x.start_date), fmtYmd(x.end_date)].filter(Boolean);
  const when = period.length === 2 && period[0] !== period[1] ? `${period[0]} ~ ${period[1]}` : period[0] || "";
  const region = regionOf(x);
  const head = [kindLabel, region, when, x.place].filter((v) => String(v || "").trim()).join(" · ");
  const desc = [head, plain(x.overview)].filter(Boolean).join("\n");
  const link = `${origin}/?spot=${encodeURIComponent(x.id)}`;
  const title = region ? `[${String(x.province || region)}] ${x.title}` : String(x.title);
  return {
    title,
    link,
    guid: link,
    pubDate,
    category: String(x.province || ""),
    description: desc,
    image: String(x.image_url || ""),
  };
}

/**
 * RSS 2.0 XML.
 * @param {string} origin  https://jikstay.app
 * @param {object} hub     data/hub/core.json (daily_stories, festivals, municipal_ebooks, updated_at)
 * @param {object[]} culture data/hub/culture.json 의 culture
 * @param {string} todayYmd KST YYYYMMDD
 */
function buildRssXml(origin, hub, culture, todayYmd) {
  const h = hub || {};
  const todayPub = kstMidnightRfc822(todayYmd);
  // 축제·공연 목록은 주간 갱신 때 바뀌므로 그 시각을 발행일로 쓴다 (없으면 오늘)
  const hubPub = Number(h.updated_at) > 0 ? new Date(Number(h.updated_at)).toUTCString() : todayPub;
  const items = [];

  const story = pickTodayStory(h, todayYmd);
  if (story) {
    const isDaily = (h.daily_stories || []).some((s) => s && String(s.id) === story.id);
    const link = `${origin}/?${isDaily ? "story" : "spot"}=${encodeURIComponent(story.id)}`;
    const m = +String(todayYmd).slice(4, 6);
    const d = +String(todayYmd).slice(6, 8);
    items.push({
      title: `${m}월 ${d}일 오늘의 로컬 스토리: ${story.title}`,
      link,
      // 같은 스토리가 다른 날 다시 돌아와도 그날의 새 글로 보이도록 날짜를 guid 에 넣는다
      guid: `${origin}/today/${todayYmd}`,
      guidIsPermaLink: false,
      pubDate: todayPub,
      category: "오늘의 로컬 스토리",
      description: [`${story.badge} · ${story.region}`, plain(story.summary), story.sourceBook ? `출처: ${story.sourceBook}` : ""]
        .filter(Boolean)
        .join("\n"),
      image: story.image,
    });
  }
  for (const x of upcoming(h.festivals, todayYmd, MAX_FESTIVALS)) items.push(eventItem(origin, x, "축제", hubPub));
  for (const x of upcoming(culture, todayYmd, MAX_CULTURE)) {
    items.push(eventItem(origin, x, [x.culture_type, x.realm].filter(Boolean).join("/") || "공연·전시", hubPub));
  }

  const body = items
    .map((it) => {
      const parts = [
        `      <title>${xmlEsc(it.title)}</title>`,
        `      <link>${xmlEsc(it.link)}</link>`,
        `      <guid isPermaLink="${it.guidIsPermaLink === false ? "false" : "true"}">${xmlEsc(it.guid)}</guid>`,
        it.pubDate ? `      <pubDate>${it.pubDate}</pubDate>` : "",
        it.category ? `      <category>${xmlEsc(it.category)}</category>` : "",
        `      <description>${xmlEsc(it.description)}</description>`,
        /^https?:\/\//.test(it.image) ? `      <media:content url="${xmlEsc(it.image)}" medium="image"/>` : "",
      ].filter(Boolean);
      return `    <item>\n${parts.join("\n")}\n    </item>`;
    })
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
  <channel>
    <title>직스테이 로컬 · 오늘의 로컬 스토리와 이번 주 축제</title>
    <link>${xmlEsc(origin)}/</link>
    <atom:link href="${xmlEsc(origin)}/rss.xml" rel="self" type="application/rss+xml"/>
    <description>지자체 공식 가이드북에서 고른 오늘의 로컬 스토리와 2주 안에 열리는 전국 지역 축제·공연·전시</description>
    <language>ko</language>
    <lastBuildDate>${todayPub}</lastBuildDate>
    <ttl>360</ttl>
${body}
  </channel>
</rss>
`;
}

module.exports = { buildRssXml, upcomingEvents: upcoming, xmlEsc };
