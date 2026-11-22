// Firestore spots 에서 자동으로 붙었던 가짜 방문 혜택·제휴 표시를 지운다 (1회 정리용).
//
// 예전 build_travel_hub 가 시·도별 상위 2곳에 '화면 제시 시 음료/사이드 서비스' 쿠폰과
// '로컬 추천 파트너' 표시를 실제 협의 없이 붙였고, upload_spots_to_firestore 가 그대로 복사했다.
// 쿠폰 문구가 인용구(pull_quote)로도 복사돼 serveApp 의 검색엔진용 HTML 에까지 나갔다.
// 관리자가 직접 지정한 제휴(admin_override_sponsor)는 건드리지 않는다.
//
// 사용 (firebase/functions 의 firebase-admin 을 쓴다):
//   GOOGLE_APPLICATION_CREDENTIALS=serviceAccountKey.json node firebase/scripts/clear_auto_perks.mjs          # 미리보기
//   GOOGLE_APPLICATION_CREDENTIALS=serviceAccountKey.json node firebase/scripts/clear_auto_perks.mjs --apply  # 실제 정리
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { initializeApp, applicationDefault } = require("../functions/node_modules/firebase-admin/lib/app/index.js");
const { getFirestore, FieldValue } = require("../functions/node_modules/firebase-admin/lib/firestore/index.js");

const AUTO_COUPON_TITLES = [
  "직스테이 방문 혜택 · 화면 제시 시 음료/사이드 서비스",
  "로컬 추천 파트너 · 주변 맛집·안심숙소 연계 코스",
];
const AUTO_RE = /화면 제시 시 음료|로컬 추천 파트너 · 주변 맛집/;

function clip(s, n = 95) {
  const t = String(s ?? "").trim();
  return t.length > n ? `${t.slice(0, n)}…` : t;
}

const apply = process.argv.includes("--apply");
initializeApp({ credential: applicationDefault(), projectId: "jikstay-lkxu1" });
const db = getFirestore();
const col = db.collection("spots");

const targets = new Map();
const add = (snap) => {
  const d = snap.data() || {};
  if (!d.admin_override_sponsor) targets.set(snap.id, { ref: snap.ref, d });
};
(await col.where("is_sponsored", "==", true).get()).forEach(add);
for (const t of AUTO_COUPON_TITLES) (await col.where("coupon_title", "==", t).get()).forEach(add);
for (const t of AUTO_COUPON_TITLES) (await col.where("pull_quote", "==", t).get()).forEach(add);

let pqFixed = 0;
let batch = db.batch();
let n = 0;
for (const [id, { ref, d }] of targets) {
  const update = { is_sponsored: FieldValue.delete(), coupon_title: FieldValue.delete() };
  if (AUTO_RE.test(String(d.pull_quote || ""))) {
    const paras = Array.isArray(d.paragraphs) ? d.paragraphs : [];
    const first = clip(paras.length ? paras[0] : d.overview);
    update.pull_quote = first || FieldValue.delete();
    pqFixed++;
  }
  console.log(`  ${id}  ${d.province || ""} ${d.title || ""} | ${d.coupon_title || d.pull_quote || ""}`);
  if (apply) {
    batch.update(ref, update);
    if (++n % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
}
if (apply && targets.size) await batch.commit();
console.log(`[clear-perks] 대상 ${targets.size}개 (인용구 복구 ${pqFixed}개) — ${apply ? "정리 완료" : "미리보기, --apply 로 실행"}`);
