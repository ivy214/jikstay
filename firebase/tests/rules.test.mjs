import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  increment,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";
import {
  deleteObject,
  getBytes,
  ref,
  uploadBytes,
} from "firebase/storage";

const PROJECT_ID = "jikstay-rules-test";

let testEnv;

function validReview(listingId, overrides = {}) {
  return {
    listing_id: listingId,
    nickname: "제주여행자",
    score: 5,
    comment: "조용하고 깨끗한 합법 숙소라 안심하고 머물렀습니다!",
    visit_tag: "커플·2인",
    lang: "ko",
    created_at: serverTimestamp(),
    ...overrides,
  };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
    },
    storage: {
      rules: readFileSync(new URL("../storage.rules", import.meta.url), "utf8"),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

describe("Firestore 보안 규칙 (공공API 전용 + 사용자 별점·후기)", () => {
  it("active 숙소만 읽기 허용, suspended/withdrawn 숙소는 거부", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "listings/stay_active01"), {
        status: "active",
        title: "공개 숙소",
        outbound_clicks: 0,
      });
      await setDoc(doc(db, "listings/stay_suspend1"), {
        status: "suspended",
        title: "중지 숙소",
        outbound_clicks: 0,
      });
    });

    const guestDb = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(guestDb, "listings/stay_active01")));
    await assertFails(getDoc(doc(guestDb, "listings/stay_suspend1")));
  });

  it("outbound_clicks는 active 숙소에서 정확히 +1만 허용하고 그 외 임의 수정·삭제는 거부", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "listings/stay_active01"), {
        status: "active",
        title: "공개 숙소",
        outbound_clicks: 5,
      });
    });

    const guestDb = testEnv.unauthenticatedContext().firestore();
    const activeRef = doc(guestDb, "listings/stay_active01");

    await assertSucceeds(updateDoc(activeRef, { outbound_clicks: increment(1) }));
    const afterSnap = await getDoc(activeRef);
    assert.equal(afterSnap.data().outbound_clicks, 6);

    await assertFails(updateDoc(activeRef, { outbound_clicks: increment(2) }));
    await assertFails(updateDoc(activeRef, { outbound_clicks: 0 }));
    await assertFails(updateDoc(activeRef, { outbound_clicks: increment(1), title: "변조" }));
    await assertFails(setDoc(doc(guestDb, "listings/stay_new00001"), { status: "active" }));
    await assertFails(deleteDoc(activeRef));
  });

  // 익명 로그인 uid = 후기 문서 ID = last_review_id
  function reviewBatch(db, col, targetId, uid, review, scoreInc) {
    const parentRef = doc(db, `${col}/${targetId}`);
    const b = writeBatch(db);
    b.set(doc(db, `${col}/${targetId}/reviews/${uid}`), review);
    b.update(parentRef, {
      review_count: increment(1),
      score_sum: increment(scoreInc),
      last_review_id: uid,
    });
    return b.commit();
  }

  it("사용자 별점(1~5) 및 후기는 익명 로그인 + 원자적 배치로만 등록되며 1인 1후기·평점 조작·삭제를 차단", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "listings/stay_pub_001"), {
        status: "active",
        title: "프레리아 독채펜션",
        outbound_clicks: 0,
      });
      await setDoc(doc(db, "listings/stay_suspended"), {
        status: "suspended",
        title: "중지 숙소",
      });
    });

    const aliceDb = testEnv.authenticatedContext("uid_alice_0001").firestore();
    const bobDb = testEnv.authenticatedContext("uid_bob_00002").firestore();
    const malloryDb = testEnv.authenticatedContext("uid_mallory_03").firestore();
    const guestDb = testEnv.unauthenticatedContext().firestore();
    const listingRef = doc(aliceDb, "listings/stay_pub_001");
    const aliceRev = doc(aliceDb, "listings/stay_pub_001/reviews/uid_alice_0001");

    // 1. 비로그인 사용자는 후기 작성 불가
    await assertFails(reviewBatch(guestDb, "listings", "stay_pub_001", "rev_guest_01", validReview("stay_pub_001"), 5));

    // 2. 정상 등록 (초기 review_count/score_sum 없는 문서에서도 동작)
    await assertSucceeds(reviewBatch(aliceDb, "listings", "stay_pub_001", "uid_alice_0001", validReview("stay_pub_001", { score: 5 }), 5));
    assert.equal((await getDoc(aliceRev)).data().score, 5);
    let stay = await getDoc(listingRef);
    assert.equal(stay.data().review_count, 1);
    assert.equal(stay.data().score_sum, 5);

    // 3. 다른 사용자의 두 번째 후기
    await assertSucceeds(
      reviewBatch(bobDb, "listings", "stay_pub_001", "uid_bob_00002",
        validReview("stay_pub_001", { nickname: "Alex", score: 4, comment: "Great legal stay near Aewol coast!", lang: "en" }), 4)
    );
    stay = await getDoc(listingRef);
    assert.equal(stay.data().review_count, 2);
    assert.equal(stay.data().score_sum, 9);

    // 4. 같은 사용자의 중복 후기 → 차단 (문서 ID가 uid로 고정되므로 재생성 불가)
    await assertFails(reviewBatch(aliceDb, "listings", "stay_pub_001", "uid_alice_0001", validReview("stay_pub_001", { score: 1 }), 1));

    // 5. 다른 사람 uid 또는 임의 ID로 문서를 만들어 1인 1후기를 우회하는 시도 → 차단
    await assertFails(reviewBatch(malloryDb, "listings", "stay_pub_001", "uid_someone_else", validReview("stay_pub_001"), 5));
    await assertFails(reviewBatch(malloryDb, "listings", "stay_pub_001", "rev_random_123", validReview("stay_pub_001"), 5));

    // 6. 후기 없이 평점만 단독 조작 → 차단
    await assertFails(
      updateDoc(doc(malloryDb, "listings/stay_pub_001"), {
        review_count: increment(1),
        score_sum: increment(5),
        last_review_id: "uid_mallory_03",
      })
    );

    // 7. 후기 1점 + 합산 5점 불일치 → 차단
    await assertFails(reviewBatch(malloryDb, "listings", "stay_pub_001", "uid_mallory_03", validReview("stay_pub_001", { score: 1 }), 5));

    // 8. 범위 밖 별점(6점) → 차단
    await assertFails(reviewBatch(malloryDb, "listings", "stay_pub_001", "uid_mallory_03", validReview("stay_pub_001", { score: 6 }), 6));

    // 9. 본인 후기라도 수정·삭제 불가
    await assertFails(updateDoc(aliceRev, { comment: "후기 변조 시도" }));
    await assertFails(deleteDoc(aliceRev));

    // 10. 중지된(suspended) 숙소에 후기 → 차단
    await assertFails(reviewBatch(malloryDb, "listings", "stay_suspended", "uid_mallory_03", validReview("stay_suspended"), 5));
  });

  it("전국 로컬 스팟(spots: 축제·볼거리·먹거리) CPC 클릭 +1 및 방문자 별점·후기 원자적 집계 허용", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "spots/spot_fo_101"), {
        status: "active",
        kind: "food",
        title: "장수 한우명가",
        is_sponsored: true,
        coupon_title: "방문 시 음료 서비스",
        outbound_clicks: 3,
      });
    });

    const guestDb = testEnv.unauthenticatedContext().firestore();
    const spotRef = doc(guestDb, "spots/spot_fo_101");

    // CPC 방문유도(길찾기·전화·쿠폰) 클릭 +1 허용 (로그인 불필요)
    await assertSucceeds(updateDoc(spotRef, { outbound_clicks: increment(1) }));
    assert.equal((await getDoc(spotRef)).data().outbound_clicks, 4);
    await assertFails(updateDoc(spotRef, { outbound_clicks: increment(3) }));

    const spotReview = {
      spot_id: "spot_fo_101",
      nickname: "무진장여행러",
      score: 5,
      comment: "관광안내도 보고 들렀는데 쿠폰 혜택도 받고 정말 맛있었어요!",
      visit_tag: "가족여행",
      lang: "ko",
      created_at: serverTimestamp(),
    };

    // 비로그인 → 차단, 익명 로그인 → 허용, 같은 사용자 재작성 → 차단
    await assertFails(reviewBatch(guestDb, "spots", "spot_fo_101", "srev_guest01", spotReview, 5));
    const visitorDb = testEnv.authenticatedContext("uid_visitor_01").firestore();
    await assertSucceeds(reviewBatch(visitorDb, "spots", "spot_fo_101", "uid_visitor_01", spotReview, 5));
    await assertFails(reviewBatch(visitorDb, "spots", "spot_fo_101", "uid_visitor_01", spotReview, 5));

    const afterSpot = await getDoc(spotRef);
    assert.equal(afterSpot.data().review_count, 1);
    assert.equal(afterSpot.data().score_sum, 5);
  });

  it("폐지된 host_applications 및 임의 경로는 생성·읽기·쓰기 모두 전면 차단", async () => {
    const guestDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      setDoc(doc(guestDb, "host_applications/app_1"), {
        business_name: "구 입점신청 차단 확인",
        submitted_at: serverTimestamp(),
      })
    );
    await assertFails(getDoc(doc(guestDb, "host_applications/app_1")));
    await assertFails(getDoc(doc(guestDb, "notifications/n1")));
    await assertFails(setDoc(doc(guestDb, "arbitrary/doc1"), { x: 1 }));
  });
});

describe("Storage 보안 규칙 (신고증 업로드 폐지 반영)", () => {
  it("licenses/ 경로를 포함한 모든 클라이언트 파일 업로드를 전면 차단", async () => {
    const guestStorage = testEnv.unauthenticatedContext().storage();
    const bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
    await assertFails(
      uploadBytes(ref(guestStorage, "licenses/app_1/license.jpg"), bytes, {
        contentType: "image/jpeg",
      })
    );
    await assertFails(uploadBytes(ref(guestStorage, "other/x.txt"), bytes));
  });

  it("listings/ 경로는 공개 읽기만 허용하고 클라이언트 쓰기·삭제는 차단", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminStorage = ctx.storage();
      await uploadBytes(
        ref(adminStorage, "listings/stay_active01/room_00.jpg"),
        new Uint8Array([1, 2, 3, 4]),
        { contentType: "image/jpeg" }
      );
    });

    const guestStorage = testEnv.unauthenticatedContext().storage();
    const roomRef = ref(guestStorage, "listings/stay_active01/room_00.jpg");
    await assertSucceeds(getBytes(roomRef));
    await assertFails(uploadBytes(roomRef, new Uint8Array([9, 9]), { contentType: "image/jpeg" }));
    await assertFails(deleteObject(roomRef));
  });
});
