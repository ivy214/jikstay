// 후기 작성자 식별: 익명 로그인 uid를 후기 문서 ID로 사용해 "장소당 1인 1후기"를 보안 규칙으로 강제한다.
// 개인정보는 받지 않으며, uid는 이 브라우저에만 유지되는 무작위 식별자다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 현재 익명 사용자 uid를 반환한다. 로그인 전이면 익명 로그인을 1회 수행한다.
Future<String> ensureReviewerUid() async {
  final auth = FirebaseAuth.instance;
  final current = auth.currentUser;
  if (current != null) return current.uid;
  final cred = await auth.signInAnonymously();
  return cred.user!.uid;
}

/// 후기 작성 결과.
enum ReviewSubmitResult { posted, alreadyReviewed }

/// `{collection}/{targetId}/reviews/{uid}` 후기 생성과 부모 문서 평점 집계를 하나의 배치로 기록한다.
/// 이미 같은 사용자의 후기가 있으면 쓰지 않고 [ReviewSubmitResult.alreadyReviewed]를 돌려준다.
Future<ReviewSubmitResult> submitReviewBatch({
  required String collection,
  required String targetId,
  required String targetIdField,
  required Map<String, dynamic> payload,
  required int score,
}) async {
  final uid = await ensureReviewerUid();
  final db = FirebaseFirestore.instance;
  final parentRef = db.collection(collection).doc(targetId);
  final revRef = parentRef.collection('reviews').doc(uid);

  final existing = await revRef.get();
  if (existing.exists) return ReviewSubmitResult.alreadyReviewed;

  final batch = db.batch();
  batch.set(revRef, <String, dynamic>{
    ...payload,
    targetIdField: targetId,
    'score': score,
    'created_at': FieldValue.serverTimestamp(),
  });
  batch.update(parentRef, <String, dynamic>{
    'review_count': FieldValue.increment(1),
    'score_sum': FieldValue.increment(score),
    'last_review_id': uid,
  });
  await batch.commit();
  return ReviewSubmitResult.posted;
}
