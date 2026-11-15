"""호스트 알림 — 이메일(기본) + 문자(선택).

- 연락처(이메일·전화)는 호스트가 [선택] 연락처 동의를 했을 때만 저장되므로, 없으면 보내지 않는다.
- 이메일: SMTP (기본 Gmail). 환경변수
    SMTP_USER       보내는 Gmail 주소
    SMTP_PASSWORD   Gmail '앱 비밀번호'(16자리). 일반 비밀번호가 아님 — 2단계 인증 후 발급
    SMTP_HOST/PORT  기본 smtp.gmail.com / 587 (STARTTLS)
    MAIL_FROM_NAME  보내는 사람 이름 (기본 SERVICE_NAME)
- 문자: SOLAPI 키(SOLAPI_API_KEY, SOLAPI_API_SECRET, SOLAPI_SENDER)가 있고 전화번호가 있을 때만 추가 발송.
- 발송 수단이 하나도 설정되지 않으면 dry-run: notifications 컬렉션에 기록만 남긴다(관리자 화면에서 확인).
- 모든 메시지는 서비스 이용에 관한 정보성 안내다. 광고 문구를 넣지 않는다(정보통신망법 제50조).
- 반려·철회처럼 연락처를 파기하는 작업은 반드시 이 알림을 먼저 보낸 뒤 파기한다.
"""
import hashlib
import hmac
import os
import secrets
import smtplib
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import formataddr

import requests
from firebase_admin import firestore

import env  # noqa: F401  (.env 로드)
from firebase_client import db

SITE_URL = os.environ.get("SITE_URL", "https://jikstay-lkxu1.web.app")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "직스테이")
CONTACT_EMAIL = os.environ.get("CONTACT_EMAIL", "[문의 이메일]")

TEMPLATES = {
    "approved": ("숙소가 공개되었습니다",
                 "[{svc}] '{title}' 숙소가 영업신고 확인을 마치고 공개되었습니다.\n{site}/?id={listing_id}"),
    "rejected": ("입점 신청이 반려되었습니다",
                 "[{svc}] 입점 신청이 반려되었습니다.\n사유: {reason}\n보완 후 다시 신청해 주세요. "
                 "제출하신 신고증 사본과 연락처는 파기되었습니다."),
    "withdrawn": ("게시물을 내렸습니다",
                  "[{svc}] 요청하신 대로 '{title}' 숙소 게시물을 내리고, 신고증 사본·연락처를 파기했습니다."),
    "weekly_report": ("지난주 숙소 성과",
                      "[{svc}] '{title}' 지난주 성과\n게스트 직거래 예약·문의 연결 {clicks}건 (누적 {clicks_total}건)"),
    "suspended": ("숙소 노출이 일시 중지되었습니다",
                  "[{svc}] 공공 인허가 데이터에서 '{title}'의 영업 상태가 '{status}'(으)로 확인되어 노출을 일시 중지했습니다. "
                  "착오라면 {email} 로 알려주세요."),
}

FOOTER = ("\n\n---\n본 메일은 {svc} 입점 신청 시 동의하신 연락처로 발송되는 서비스 안내입니다.\n"
          "알림 수신 중단·연락처 삭제 요청: {email}")


def render(kind: str, **fields) -> str:
    fields.setdefault("clicks_total", fields.get("clicks", 0))
    return TEMPLATES[kind][1].format(svc=SERVICE_NAME, site=SITE_URL, email=CONTACT_EMAIL, **fields)


def subject(kind: str) -> str:
    return f"[{SERVICE_NAME}] {TEMPLATES[kind][0]}"


def _email_configured() -> bool:
    return bool(os.environ.get("SMTP_USER") and os.environ.get("SMTP_PASSWORD"))


def _sms_configured() -> bool:
    return all(os.environ.get(k) for k in ("SOLAPI_API_KEY", "SOLAPI_API_SECRET", "SOLAPI_SENDER"))


def send_email(to: str, subj: str, body: str):
    user = os.environ["SMTP_USER"]
    msg = EmailMessage()
    msg["Subject"] = subj
    msg["From"] = formataddr((os.environ.get("MAIL_FROM_NAME", SERVICE_NAME), user))
    msg["To"] = to
    msg.set_content(body + FOOTER.format(svc=SERVICE_NAME, email=CONTACT_EMAIL))
    host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    port = int(os.environ.get("SMTP_PORT", "587"))
    with smtplib.SMTP(host, port, timeout=20) as s:
        s.starttls()
        s.login(user, os.environ["SMTP_PASSWORD"])
        s.send_message(msg)


def _solapi_send(to: str, text: str):
    key, secret = os.environ["SOLAPI_API_KEY"], os.environ["SOLAPI_API_SECRET"]
    date = datetime.now(timezone.utc).isoformat()
    salt = secrets.token_hex(16)
    sig = hmac.new(secret.encode(), (date + salt).encode(), hashlib.sha256).hexdigest()
    r = requests.post(
        "https://api.solapi.com/messages/v4/send",
        headers={"Authorization": f"HMAC-SHA256 apiKey={key}, date={date}, salt={salt}, signature={sig}"},
        json={"message": {"to": to.replace("-", ""), "from": os.environ["SOLAPI_SENDER"], "text": text}},
        timeout=15,
    )
    r.raise_for_status()


def notify_application(app_id: str, kind: str, **fields) -> str:
    """신청서의 연락처로 알림. 결과: sent | partial | dry_run | no_contact | failed"""
    snap = db().collection("host_applications").document(app_id).get()
    app = snap.to_dict() if snap.exists else {}
    consented = app.get("consent_privacy_optional") is True
    email = (app.get("host_email") or "").strip() if consented else ""
    phone = (app.get("host_phone") or "").strip() if consented else ""
    text = render(kind, **fields)

    attempts: list[tuple[str, str]] = []  # (채널, 결과)
    if email and _email_configured():
        try:
            send_email(email, subject(kind), text)
            attempts.append(("email", "sent"))
        except Exception as e:  # noqa: BLE001
            attempts.append(("email", f"failed: {str(e)[:200]}"))
    if phone and _sms_configured():
        try:
            _solapi_send(phone, text)
            attempts.append(("sms", "sent"))
        except Exception as e:  # noqa: BLE001
            attempts.append(("sms", f"failed: {str(e)[:200]}"))

    if not email and not phone:
        result, detail = "no_contact", "연락처 없음 — 관리자가 직접 안내 필요"
    elif not attempts:
        result, detail = "dry_run", "발송 수단 미설정(SMTP/SOLAPI) — 실제 발송 안 함"
    else:
        sent = [c for c, r in attempts if r == "sent"]
        result = "sent" if len(sent) == len(attempts) else ("partial" if sent else "failed")
        detail = "; ".join(f"{c}:{r}" for c, r in attempts)

    # 기록에는 이메일·전화번호를 남기지 않는다(파기 대상이므로).
    db().collection("notifications").add({
        "application_id": app_id,
        "kind": kind,
        "channels": [c for c, _ in attempts],
        "text": text,
        "result": result,
        "detail": detail,
        "created_at": firestore.SERVER_TIMESTAMP,
    })
    print(f"[알림:{kind}] {result} {detail}\n{text}")
    return result


def notify_listing(listing_id: str, kind: str, **fields) -> str:
    snap = db().collection("listings").document(listing_id).get()
    doc = snap.to_dict() if snap.exists else {}
    if not doc.get("application_id"):
        return "no_contact"
    fields.setdefault("title", doc.get("title", ""))
    fields.setdefault("listing_id", listing_id)
    return notify_application(doc["application_id"], kind, **fields)
