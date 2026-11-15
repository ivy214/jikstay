"""숙소 등록·승인·반려·철회 (관리자 CLI).

상태 흐름
  host_applications: pending_verification → (listed) → verified | rejected | withdrawn
  listings:          pending_verification → active ⇄ suspended(재확인 시 폐업·휴업) → withdrawn
                                          ↘ rejected

- publish : listing_result.json 을 검수 대기 상태로 등록 (외부 비공개)
- approve : 신고증을 공공 인허가 데이터와 대조한 뒤 공개. 검증자·방법·일시 기록
- reject  : 반려 + 사유 기록. 신고증 사본·연락처 즉시 파기
- withdraw: 호스트 철회/삭제 요청 시 즉시 내림. 사진·신고증·연락처 파기,
            유튜브 영상 삭제(가능할 때). 영업신고 확인 기록(업종·번호·검증 이력)만 보존

개정 공중위생관리법(2026-11-12 시행): 신고증 확인 불가 숙박상품 중개 시 과태료 500만 원.

사용:
  python upload_to_firestore.py publish output/app_123/listing_result.json --application-id app_123
  python upload_to_firestore.py approve stay_ab12cd34 --verified-by 관리자명 --method "공공 인허가 데이터 대조"
  python upload_to_firestore.py reject --application-id app_123 --reason "신고번호 불일치"
  python upload_to_firestore.py reject --listing-id stay_ab12cd34 --reason "신고증 사본 판독 불가"
  python upload_to_firestore.py withdraw stay_ab12cd34 --reason "호스트 삭제 요청(이메일 2026-11-20)"
"""
import argparse
import json
import os
import shutil
import uuid

from firebase_admin import firestore

from firebase_client import bucket, db, public_media_url

ALLOWED_LICENSE_TYPES = {"농어촌민박업", "일반/생활숙박업", "한옥체험업", "외국인관광도시민박업"}


def _apps():
    return db().collection("host_applications")


def _listings():
    return db().collection("listings")


def _confirm(question: str) -> bool:
    print(f"{question} (yes 입력)")
    return input("> ").strip().lower() == "yes"


def purge_local_output(app_id: str) -> bool:
    """관리자 PC의 output/<app_id> 폴더(원본 사진·JSON·쇼츠)를 안전하게 삭제한다."""
    if not app_id or "/" in app_id or "\\" in app_id or ".." in app_id:
        return False
    roots = {
        os.path.realpath(os.environ.get("OUTPUT_DIR", "output")),
        os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "output")),
    }
    removed = False
    for root in roots:
        target = os.path.realpath(os.path.join(root, app_id))
        if target.startswith(root + os.sep) and os.path.isdir(target):
            shutil.rmtree(target)
            removed = True
            print(f"로컬 output 폴더 삭제: {target}")
    return removed


def purge_application_personal_data(app_id: str):
    """신고증 사본과 연락처, 로컬 output 캐시를 파기한다. 업종·신고번호·동의 기록은 남긴다."""
    snap = _apps().document(app_id).get()
    if not snap.exists:
        purge_local_output(app_id)
        return
    path = snap.to_dict().get("license_image_path")
    if path:
        blob = bucket().blob(path)
        if blob.exists():
            blob.delete()
    _apps().document(app_id).update({
        "license_image_path": firestore.DELETE_FIELD,
        "host_phone": firestore.DELETE_FIELD,
        "host_email": firestore.DELETE_FIELD,
        "personal_data_purged_at": firestore.SERVER_TIMESTAMP,
    })
    purge_local_output(app_id)


def publish(json_path: str, application_id: str) -> str:
    snap = _apps().document(application_id).get()
    if not snap.exists:
        raise ValueError(f"신청서 {application_id} 없음")
    app = snap.to_dict()
    if app.get("status") != "pending_verification":
        raise ValueError(f"신청 상태가 {app.get('status')} 입니다. 검수 대기 신청서만 등록할 수 있습니다.")
    if app.get("license_type") not in ALLOWED_LICENSE_TYPES:
        raise ValueError("허용되지 않은 인허가 업종")

    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)

    claim_id = (app.get("claim_listing_id") or "").strip()
    listing_id = f"stay_{uuid.uuid4().hex[:8]}"
    prefer_link_only = os.environ.get("IMAGE_LINK_ONLY", "1") == "1"
    images = []
    for i, img in enumerate(data.get("selected_images", [])):
        ext_url = (img.get("url") or img.get("source_url") or "").strip()
        p = img.get("local_path")
        if ext_url.startswith("https://") and (prefer_link_only or not (p and os.path.exists(p))):
            images.append({"url": ext_url,
                           "space_tag": img.get("space_tag", "객실"),
                           "caption": img.get("caption", "")})
        elif p and os.path.exists(p):
            blob_path = f"listings/{listing_id}/room_{i:02d}.jpg"
            bucket().blob(blob_path).upload_from_filename(p, content_type="image/jpeg")
            images.append({"url": public_media_url(blob_path),
                           "path": blob_path,
                           "space_tag": img.get("space_tag", "객실"),
                           "caption": img.get("caption", "")})

    _listings().document(listing_id).set({
        "listing_id": listing_id,
        "listing_tier": "claimed",
        "claim_target_id": claim_id,
        "is_sponsored": False,
        "cpc_balance": 0,
        "cpc_rate": 300,
        "cpc_charged_clicks": 0,
        "application_id": application_id,
        "title": data["title"],
        "region_depth1": data["region_depth1"],
        "region_depth2": data["region_depth2"],
        "accommodation_type": data["accommodation_type"],
        "capacity_standard": data.get("capacity_standard"),
        "capacity_max": data.get("capacity_max"),
        "room_specs": data.get("room_specs") or {},
        "editorial_story": data.get("editorial_story", ""),
        "summary_points": data.get("summary_points") or [],
        "highlights": data.get("highlights") or [],
        "options": data.get("options") or [],
        "amenities_by_category": data.get("amenities_by_category") or [],
        "unavailable_amenities": data.get("unavailable_amenities") or [],
        "house_rules": data.get("house_rules") or {},
        "location_info": data.get("location_info") or {},
        "promo_title": data.get("promo_title", ""),
        "promo_detail": data.get("promo_detail", ""),
        "pricing": data["pricing"],
        "images": images,
        "source_blog_url": app["blog_url"],
        "direct_booking_url": app["direct_booking_url"],
        "license_type": app["license_type"],
        "license_number": app["license_number"],
        "outbound_clicks": 0,
        "status": "pending_verification",
        "created_at": firestore.SERVER_TIMESTAMP,
    })
    _apps().document(application_id).update({"status": "listed", "listing_id": listing_id})
    print(f"등록(검수 대기): {listing_id} / 사진 {len(images)}장")
    return listing_id


def approve(listing_id: str, verified_by: str, method: str, confirmed: bool = False) -> bool:
    """confirmed=False 이면 터미널에서 확인을 묻는다(관리자 화면은 체크박스로 확인 후 True 전달)."""
    ref = _listings().document(listing_id)
    snap = ref.get()
    if not snap.exists:
        raise ValueError("숙소 없음")
    doc = snap.to_dict()
    if doc.get("status") not in ("pending_verification", "suspended"):
        raise ValueError(f"상태가 {doc.get('status')} 입니다. 검수 대기·노출 중지 숙소만 승인할 수 있습니다.")
    if not doc.get("license_number") or doc.get("license_type") not in ALLOWED_LICENSE_TYPES:
        raise ValueError("인허가 정보가 불완전해 승인할 수 없습니다.")

    app = _apps().document(doc["application_id"]).get().to_dict() or {}
    check = app.get("license_check") or {}
    if not confirmed:
        print(f"[승인 전 확인] {doc['title']} / {doc['license_type']} / {doc['license_number']}")
        print(f"  공공 데이터 대조: {check.get('result', '미실행')} "
              f"{check.get('matched_name', '')} {check.get('matched_status', '')}")
        if not _confirm("신고증 사본과 공공 인허가 데이터(영업 상태)를 직접 대조했습니까?"):
            print("취소")
            return False

    was_suspended = doc.get("status") == "suspended"
    prev_balance = int(doc.get("cpc_balance") or 0)
    cpc_rate = int(doc.get("cpc_rate") or 300)
    # 최초 승인 시 환영 크레딧 30,000원(100클릭분) 기본 부여
    new_balance = prev_balance if (was_suspended or prev_balance > 0) else 30000
    ref.update({
        "status": "active",
        "listing_tier": "claimed",
        "cpc_balance": new_balance,
        "cpc_rate": cpc_rate,
        "is_sponsored": new_balance >= cpc_rate,
        "verified_by": verified_by,
        "verification_method": method,
        "verification_license_check": {k: v for k, v in check.items() if k != "checked_at"},
        "verified_at": firestore.SERVER_TIMESTAMP,
        "needs_review": False,
    })
    # 기존 공공 선별 숙소(stay_pub_...)를 호스트가 클레임한 경우 중복 노출 방지를 위해 기존 공공 카드를 병합·대체 표시
    claim_target = (doc.get("claim_target_id") or app.get("claim_listing_id") or "").strip()
    if claim_target and claim_target != listing_id and claim_target.startswith("stay_pub_"):
        pub_ref = _listings().document(claim_target)
        pub_snap = pub_ref.get()
        if pub_snap.exists:
            pub_data = pub_snap.to_dict() or {}
            inherited_clicks = int(pub_data.get("outbound_clicks") or 0)
            if inherited_clicks > 0 and not was_suspended:
                ref.update({"outbound_clicks": firestore.Increment(inherited_clicks)})
            pub_ref.update({
                "status": "replaced_by_claim",
                "claimed_by_listing_id": listing_id,
                "replaced_at": firestore.SERVER_TIMESTAMP,
            })
    if doc.get("application_id"):
        _apps().document(doc["application_id"]).update({"status": "verified"})
    print(f"승인 완료: {listing_id} (CPC 잔액: {new_balance:,}원)")
    if not was_suspended and doc.get("application_id"):
        from notify import notify_listing

        notify_listing(listing_id, "approved")
    return True


def topup_cpc_credit(listing_id: str, add_krw: int, cpc_rate: int | None = None) -> dict:
    """호스트 CPC 충전금 증액/조정 및 상단 우선 노출(is_sponsored) 상태 자동 갱신."""
    ref = _listings().document(listing_id)
    snap = ref.get()
    if not snap.exists:
        raise ValueError("숙소 없음")
    doc = snap.to_dict() or {}
    rate = int(cpc_rate if cpc_rate and cpc_rate > 0 else (doc.get("cpc_rate") or 300))
    new_balance = max(0, int(doc.get("cpc_balance") or 0) + int(add_krw))
    sponsored = doc.get("status") == "active" and new_balance >= rate
    ref.update({
        "listing_tier": "claimed",
        "cpc_balance": new_balance,
        "cpc_rate": rate,
        "is_sponsored": sponsored,
        "cpc_updated_at": firestore.SERVER_TIMESTAMP,
    })
    print(f"CPC 크레딧 반영: {listing_id} → 잔액 {new_balance:,}원 (클릭당 {rate:,}원, 우선노출={sponsored})")
    return {"cpc_balance": new_balance, "cpc_rate": rate, "is_sponsored": sponsored}


def reject(reason: str, application_id: str | None = None, listing_id: str | None = None):
    if listing_id:
        snap = _listings().document(listing_id).get()
        if not snap.exists:
            raise ValueError("숙소 없음")
        doc = snap.to_dict()
        if doc.get("status") == "active":
            raise ValueError("이미 공개된 숙소입니다. 내리려면 withdraw 를 사용하세요.")
        application_id = doc.get("application_id")
        _delete_listing_media(listing_id, doc)
        _listings().document(listing_id).update({
            "status": "rejected",
            "rejection_reason": reason,
            "rejected_at": firestore.SERVER_TIMESTAMP,
        })
    if not application_id:
        raise ValueError("--application-id 또는 --listing-id 가 필요합니다.")

    _apps().document(application_id).update({
        "status": "rejected",
        "rejection_reason": reason,
        "rejected_at": firestore.SERVER_TIMESTAMP,
    })
    # 연락처를 파기하기 전에 알린다.
    from notify import notify_application

    result = notify_application(application_id, "rejected", reason=reason)
    purge_application_personal_data(application_id)
    print(f"반려 완료: {application_id} (사유: {reason}, 알림: {result})")
    if result != "sent":
        print("※ 알림이 발송되지 않았습니다. 호스트에게 직접 안내하세요.")


def _delete_listing_media(listing_id: str, doc: dict):
    for blob in bucket().list_blobs(prefix=f"listings/{listing_id}/"):
        blob.delete()
    if doc.get("youtube_video_id"):
        print(f"구 유튜브 영상은 Studio에서 직접 삭제하세요: {doc['youtube_video_id']}")
    if doc.get("instagram_url"):
        print(f"구 인스타그램 릴스는 앱에서 직접 삭제하세요: {doc['instagram_url']}")


def withdraw(listing_id: str, reason: str, confirmed: bool = False) -> bool:
    ref = _listings().document(listing_id)
    snap = ref.get()
    if not snap.exists:
        raise ValueError("숙소 없음")
    doc = snap.to_dict()
    if not confirmed:
        print(f"[내림] {doc['title']} ({doc.get('status')}) — 사진·영상·신고증 사본·연락처를 파기합니다.")
        if not _confirm("진행할까요?"):
            print("취소")
            return False

    # 연락처를 파기하기 전에 알린다.
    from notify import notify_listing

    notify_listing(listing_id, "withdrawn")
    _delete_listing_media(listing_id, doc)
    ref.update({
        "status": "withdrawn",
        "withdraw_reason": reason,
        "withdrawn_at": firestore.SERVER_TIMESTAMP,
        "images": [],
        "summary_points": [],
        "highlights": [],
        "options": [],
        "amenities_by_category": [],
        "unavailable_amenities": [],
        "editorial_story": "",
        "promo_title": "",
        "promo_detail": "",
        "direct_booking_url": firestore.DELETE_FIELD,
        "source_blog_url": firestore.DELETE_FIELD,
        "shorts_mp4_url": firestore.DELETE_FIELD,
    })
    if doc.get("application_id"):
        _apps().document(doc["application_id"]).update({"status": "withdrawn"})
        purge_application_personal_data(doc["application_id"])
    print(f"내림 완료: {listing_id} (미디어·신고증·연락처·로컬 output 파기 완료)")
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("publish")
    p.add_argument("json_path")
    p.add_argument("--application-id", required=True)

    p = sub.add_parser("approve")
    p.add_argument("listing_id")
    p.add_argument("--verified-by", required=True)
    p.add_argument("--method", required=True)

    p = sub.add_parser("reject")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--application-id")
    g.add_argument("--listing-id")
    p.add_argument("--reason", required=True)

    p = sub.add_parser("withdraw")
    p.add_argument("listing_id")
    p.add_argument("--reason", required=True)

    p = sub.add_parser("credit")
    p.add_argument("listing_id")
    p.add_argument("--add-krw", type=int, required=True)
    p.add_argument("--cpc-rate", type=int, default=None)

    a = ap.parse_args()
    if a.cmd == "publish":
        publish(a.json_path, a.application_id)
    elif a.cmd == "approve":
        approve(a.listing_id, a.verified_by, a.method)
    elif a.cmd == "reject":
        reject(a.reason, application_id=a.application_id, listing_id=a.listing_id)
    elif a.cmd == "credit":
        topup_cpc_credit(a.listing_id, a.add_krw, cpc_rate=a.cpc_rate)
    else:
        withdraw(a.listing_id, a.reason)
