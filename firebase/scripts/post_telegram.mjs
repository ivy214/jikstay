// 텔레그램 채널에 '오늘의 로컬 스토리'를 올린다 (매일 08:00 KST, GitHub Actions).
// - 스토리는 사이트 첫 화면과 같은 pickTodayStory 로 고른다 → 채널 글과 사이트가 늘 같다.
// - 금요일에는 이번 주말(토·일)에 열리는 축제 목록을 한 번 더 올린다.
// - 데이터는 배포된 https://jikstay.app/data/hub/*.json 에서 읽는다 (저장소 데이터와 어긋나지 않게).
//
// 환경 변수: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (@채널아이디 또는 -100… 숫자)
// 사용: node firebase/scripts/post_telegram.mjs [--dry-run] [--date YYYYMMDD] [--weekend]
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const { pickTodayStory } = require("../functions/today_story.js");

const SITE = "https://jikstay.app";
const CAPTION_MAX = 1024; // sendPhoto 캡션 한도 (태그 제외 글자 수)
const SUMMARY_MAX = 380;
const LONG_RUNNING_DAYS = 60;
const WEEKEND_MAX = 8;

export function esc(s) {
  return String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function clip(s, max) {
  const t = String(s ?? "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
  return t.length > max ? `${t.slice(0, max - 1)}…` : t;
}

function ymdToUtc(ymd) {
  const s = String(ymd || "");
  return /^\d{8}$/.test(s) ? Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8)) : null;
}

function utcToYmd(ms) {
  return new Date(ms).toISOString().slice(0, 10).replace(/-/g, "");
}

export function kstTodayYmd(now = Date.now()) {
  return utcToYmd(now + 9 * 3600 * 1000);
}

function md(ymd) {
  const s = String(ymd || "");
  return /^\d{8}$/.test(s) ? `${+s.slice(4, 6)}.${+s.slice(6, 8)}` : "";
}

/** 해시태그로 쓸 수 있게: 공백·기호 제거 */
function tag(s) {
  const t = String(s || "").replace(/[^0-9A-Za-z가-힣_]/g, "");
  return t ? `#${t}` : "";
}

/** "강원 영월군" → ["#강원여행", "#영월여행"] */
export function regionTags(region) {
  const [prov, city] = String(region || "").trim().split(/\s+/);
  // 시·군·구 이름일 때만 ("동성로·팔공산·근대골목" 같은 설명은 태그로 만들지 않는다)
  const m = /^([가-힣]{1,6})(시|군|구)$/.exec(String(city || ""));
  const cityBase = m ? m[1] : "";
  return [prov && tag(`${prov}여행`), cityBase.length >= 2 && tag(`${cityBase}여행`)].filter(Boolean);
}

export function storyLink(hub, story) {
  const isDaily = (hub.daily_stories || []).some((s) => s && String(s.id) === story.id);
  return `${SITE}/?${isDaily ? "story" : "spot"}=${encodeURIComponent(story.id)}`;
}

/** 오늘의 스토리 캡션 (HTML parse_mode) */
export function buildStoryCaption(hub, story, todayYmd) {
  const link = storyLink(hub, story);
  const tags = [...regionTags(story.region), "#국내여행", "#로컬여행", "#직스테이"].join(" ");
  const head = [
    `📖 <b>${md(todayYmd).replace(".", "월 ")}일 오늘의 로컬 스토리</b>`,
    "",
    `<b>${esc(story.title)}</b>`,
    `${esc(story.badge)} · 📍 ${esc(story.region)}`,
    "",
  ].join("\n");
  const tail = ["", "", `👉 <a href="${esc(link)}">직스테이에서 자세히 보기</a>`, tags].join("\n");
  // 한도는 태그를 뺀 글자 수 기준이지만, 넉넉하게 태그 포함 길이로 맞춘다
  const room = Math.max(80, Math.min(SUMMARY_MAX, CAPTION_MAX - head.length - tail.length - 10));
  return head + esc(clip(story.summary, room)) + tail;
}

/** 이번 주 토·일 (KST). 오늘이 일요일이면 오늘 하루 */
export function weekendRange(todayYmd) {
  const today = ymdToUtc(todayYmd);
  const dow = new Date(today).getUTCDay(); // 0=일 … 6=토
  if (dow === 0) return [todayYmd, todayYmd];
  const sat = today + ((6 - dow) * 86400000);
  return [utcToYmd(sat), utcToYmd(sat + 86400000)];
}

/** 주말에 열리는 축제 (상설 행사 제외), 시작일 순 */
export function weekendFestivals(hub, todayYmd, max = WEEKEND_MAX) {
  const [sat, sun] = weekendRange(todayYmd);
  return (hub.festivals || [])
    .filter((x) => {
      if (!x || !x.id || !String(x.title || "").trim()) return false;
      const start = String(x.start_date || "");
      const end = String(x.end_date || start);
      if (!/^\d{8}$/.test(start) || !/^\d{8}$/.test(end)) return false;
      if ((ymdToUtc(end) - ymdToUtc(start)) / 86400000 > LONG_RUNNING_DAYS) return false;
      return start <= sun && end >= sat;
    })
    .sort((a, b) => String(a.start_date).localeCompare(String(b.start_date)) || String(a.id).localeCompare(String(b.id)))
    .slice(0, max);
}

export function buildWeekendMessage(hub, todayYmd) {
  const list = weekendFestivals(hub, todayYmd);
  if (!list.length) return null;
  const [sat, sun] = weekendRange(todayYmd);
  const lines = list.map((x) => {
    const period = x.start_date === x.end_date ? md(x.start_date) : `${md(x.start_date)}~${md(x.end_date)}`;
    const where = String(x.region_label || x.province || "").trim();
    const link = `${SITE}/?spot=${encodeURIComponent(x.id)}`;
    return `• <a href="${esc(link)}">${esc(x.title)}</a>\n   📍 ${esc(where)} · ${esc(period)}`;
  });
  return [
    `🎪 <b>이번 주말(${md(sat)}${sat === sun ? "" : `~${md(sun)}`}) 열리는 지역 축제</b>`,
    "",
    ...lines,
    "",
    `🗓 전국 축제 일정: <a href="${SITE}/?topic=festival">jikstay.app 축제 일정</a>`,
    "#주말나들이 #지역축제 #국내여행 #직스테이",
  ].join("\n");
}

async function telegram(token, method, body) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!data.ok) throw new Error(`${method} 실패: ${data.description || res.status}`);
  return data.result;
}

async function fetchJson(url) {
  const res = await fetch(url, { headers: { "User-Agent": "jikstay-telegram-poster" } });
  if (!res.ok) throw new Error(`${url} -> HTTP ${res.status}`);
  return res.json();
}

async function main(argv) {
  const dryRun = argv.includes("--dry-run");
  const dateIdx = argv.indexOf("--date");
  const todayYmd = dateIdx >= 0 ? argv[dateIdx + 1] : kstTodayYmd();
  if (!/^\d{8}$/.test(todayYmd || "")) throw new Error("--date 는 YYYYMMDD");
  const isFriday = new Date(ymdToUtc(todayYmd)).getUTCDay() === 5;
  const withWeekend = argv.includes("--weekend") || isFriday;

  const token = process.env.TELEGRAM_BOT_TOKEN || "";
  const chatId = process.env.TELEGRAM_CHAT_ID || "";
  if (!dryRun && (!token || !chatId)) throw new Error("TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID 환경 변수가 필요합니다.");

  const hub = await fetchJson(`${SITE}/data/hub/core.json`);
  const story = pickTodayStory(hub, todayYmd);
  const posts = [];
  if (story) posts.push({ kind: "story", caption: buildStoryCaption(hub, story, todayYmd), image: story.image });
  else console.warn("오늘 고를 스토리가 없습니다.");
  if (withWeekend) {
    const msg = buildWeekendMessage(hub, todayYmd);
    if (msg) posts.push({ kind: "weekend", text: msg });
  }

  for (const p of posts) {
    if (dryRun) {
      console.log(`----- [${p.kind}] ${p.image || ""}\n${p.caption || p.text}\n`);
      continue;
    }
    if (p.kind === "story") {
      try {
        if (!p.image) throw new Error("이미지 없음");
        await telegram(token, "sendPhoto", { chat_id: chatId, photo: p.image, caption: p.caption, parse_mode: "HTML" });
      } catch (err) {
        // 이미지 서버가 텔레그램 요청을 막거나 너무 크면 글만 올린다 (링크 미리보기로 사진이 붙는다)
        console.warn(`사진 전송 실패, 글로 대신 올립니다: ${err.message}`);
        await telegram(token, "sendMessage", { chat_id: chatId, text: p.caption, parse_mode: "HTML" });
      }
    } else {
      await telegram(token, "sendMessage", {
        chat_id: chatId,
        text: p.text,
        parse_mode: "HTML",
        link_preview_options: { is_disabled: true },
      });
    }
    console.log(`게시 완료: ${p.kind}`);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}
