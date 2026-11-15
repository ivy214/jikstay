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

  it("사용자 별점(1~5) 및 후기는 원자적 배치(WriteBatch)로만 등록되며 평점 조작·덮어쓰기·삭제를 차단", async () => {
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

    const guestDb = testEnv.unauthenticatedContext().firestore();
    const listingRef = doc(guestDb, "listings/stay_pub_001");
    const revRef1 = doc(guestDb, "listings/stay_pub_001/reviews/rev_good_01");

    // 1. 정상 별점(5점) + 후기 원자적 배치 등록 (초기 review_count/score_sum 없는 문서에서도 정상 동작)
    const batch1 = writeBatch(guestDb);
    batch1.set(revRef1, validReview("stay_pub_001", { score: 5 }));
    batch1.update(listingRef, {
      review_count: increment(1),
      score_sum: increment(5),
      last_review_id: "rev_good_01",
    });
    await assertSucceeds(batch1.commit());

    // 등록된 후기 공개 조회 확인
    const savedRev = await getDoc(revRef1);
    assert.equal(savedRev.data().score, 5);
    const updatedStay = await getDoc(listingRef);
    assert.equal(updatedStay.data().review_count, 1);
    assert.equal(updatedStay.data().score_sum, 5);

    // 2. 두 번째 후기(4점, 영문 게스트) 연속 등록 검증
    const revRef2 = doc(guestDb, "listings/stay_pub_001/reviews/rev_good_02");
    const batch2 = writeBatch(guestDb);
    batch2.set(
      revRef2,
      validReview("stay_pub_001", {
        nickname: "Alex",
        score: 4,
        comment: "Great legal stay near Aewol coast!",
        lang: "en",
      })
    );
    batch2.update(listingRef, {
      review_count: increment(1),
      score_sum: increment(4),
      last_review_id: "rev_good_02",
    });
    await assertSucceeds(batch2.commit());
    const stayAfter2 = await getDoc(listingRef);
    assert.equal(stayAfter2.data().review_count, 2);
    assert.equal(stayAfter2.data().score_sum, 9);

    // 3. 실제 후기 생성 없이 평점(score_sum)만 단독 조작 시도 → 차단
    await assertFails(
      updateDoc(listingRef, {
        review_count: increment(1),
        score_sum: increment(5),
        last_review_id: "rev_good_02",
      })
    );

    // 4. 후기 점수는 1점인데 숙소 합산에는 5점을 더하는 불일치 조작 시도 → 차단
    const revFake = doc(guestDb, "listings/stay_pub_001/reviews/rev_mismatch");
    const badBatch = writeBatch(guestDb);
    badBatch.set(revFake, validReview("stay_pub_001", { score: 1 }));
    badBatch.update(listingRef, {
      review_count: increment(1),
      score_sum: increment(5),
      last_review_id: "rev_mismatch",
    });
    await assertFails(badBatch.commit());

    // 5. 범위 밖 별점(6점 / 0점) 또는 너무 짧은 후기 차단
    const revBadScore = doc(guestDb, "listings/stay_pub_001/reviews/rev_bad_score");
    const badScoreBatch = writeBatch(guestDb);
    badScoreBatch.set(revBadScore, validReview("stay_pub_001", { score: 6 }));
    badScoreBatch.update(listingRef, {
      review_count: increment(1),
      score_sum: increment(6),
      last_review_id: "rev_bad_score",
    });
    await assertFails(badScoreBatch.commit());

    // 6. 기존 후기 수정·덮어쓰기·삭제 시도 → 차단
    await assertFails(updateDoc(revRef1, { comment: "타인 후기 변조" }));
    await assertFails(deleteDoc(revRef1));

    // 7. 중지된(suspended) 숙소에 후기 등록 시도 → 차단
    const suspRef = doc(guestDb, "listings/stay_suspended");
    const suspRev = doc(guestDb, "listings/stay_suspended/reviews/rev_susp_01");
    const suspBatch = writeBatch(guestDb);
    suspBatch.set(suspRev, validReview("stay_suspended", { score: 5 }));
    suspBatch.update(suspRef, {
      review_count: increment(1),
      score_sum: increment(5),
      last_review_id: "rev_susp_01",
    });
    await assertFails(suspBatch.commit());
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

    // CPC 방문유도(길찾기·전화·쿠폰) 클릭 +1 허용
    await assertSucceeds(updateDoc(spotRef, { outbound_clicks: increment(1) }));
    assert.equal((await getDoc(spotRef)).data().outbound_clicks, 4);
    await assertFails(updateDoc(spotRef, { outbound_clicks: increment(3) }));

    // 스팟 방문자 별점(5점) + 후기 원자적 등록 허용
    const sRevRef = doc(guestDb, "spots/spot_fo_101/reviews/srev_001");
    const batch = writeBatch(guestDb);
    batch.set(sRevRef, {
      spot_id: "spot_fo_101",
      nickname: "무진장여행러",
      score: 5,
      comment: "관광안내도 보고 들렀는데 쿠폰 혜택도 받고 정말 맛있었어요!",
      visit_tag: "가족여행",
      lang: "ko",
      created_at: serverTimestamp(),
    });
    batch.update(spotRef, {
      review_count: increment(1),
      score_sum: increment(5),
      last_review_id: "srev_001",
    });
    await assertSucceeds(batch.commit());
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
