"""알림 발송 로직 테스트 (가짜 SMTP·가짜 DB, 실제 발송 없음).

  backend\\.venv\\Scripts\\python backend\\tests\\notify_test.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import notify  # noqa: E402

APPS = {
    "with_email": {"consent_privacy_optional": True, "host_email": "host@example.com", "host_phone": ""},
    "no_consent": {"consent_privacy_optional": False, "host_email": "host@example.com", "host_phone": ""},
    "no_contact": {"consent_privacy_optional": False, "host_email": "", "host_phone": ""},
    "both": {"consent_privacy_optional": True, "host_email": "h@x.kr", "host_phone": "010-1234-5678"},
}
LOG = []
SENT_MAIL = []


class Snap:
    def __init__(self, d):
        self._d, self.exists = d, d is not None

    def to_dict(self):
        return self._d


class Coll:
    def __init__(self, name):
        self.name = name

    def document(self, did):
        return type("D", (), {"get": lambda _s: Snap(APPS.get(did))})()

    def add(self, data):
        LOG.append(data)


notify.db = lambda: type("DB", (), {"collection": lambda _s, n: Coll(n)})()


class FakeSMTP:
    def __init__(self, host, port, timeout=None):
        self.host = host

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def starttls(self):
        pass

    def login(self, u, p):
        assert p == "app-password"

    def send_message(self, msg):
        SENT_MAIL.append(msg)


notify.smtplib.SMTP = FakeSMTP
sms_sent = []
notify._solapi_send = lambda to, text: sms_sent.append(to)

for k in ("SMTP_USER", "SMTP_PASSWORD", "SOLAPI_API_KEY", "SOLAPI_API_SECRET", "SOLAPI_SENDER"):
    os.environ.pop(k, None)

# 1) 발송 수단 미설정 → dry_run
assert notify.notify_application("with_email", "approved", title="t", listing_id="stay_00000001") == "dry_run"
# 2) 이메일 설정
os.environ.update(SMTP_USER="sender@gmail.com", SMTP_PASSWORD="app-password")
assert notify.notify_application("with_email", "rejected", reason="신고번호 불일치") == "sent"
m = SENT_MAIL[-1]
assert m["To"] == "host@example.com" and "반려" in m["Subject"] and "신고번호 불일치" in m.get_content()
assert "수신 중단" in m.get_content()
# 3) 선택 동의 없음 → 이메일이 있어도 보내지 않음
n = len(SENT_MAIL)
assert notify.notify_application("no_consent", "approved", title="t", listing_id="x") == "no_contact"
assert len(SENT_MAIL) == n
# 4) 연락처 없음
assert notify.notify_application("no_contact", "approved", title="t", listing_id="x") == "no_contact"
# 5) 이메일만 설정, 전화도 있음 → 이메일만 발송, 결과 sent
assert notify.notify_application("both", "approved", title="t", listing_id="x") == "sent" and not sms_sent
# 6) 문자까지 설정 → 둘 다
os.environ.update(SOLAPI_API_KEY="k", SOLAPI_API_SECRET="s", SOLAPI_SENDER="0212345678")
assert notify.notify_application("both", "approved", title="t", listing_id="x") == "sent" and sms_sent
# 7) 기록에 이메일·전화번호가 남지 않음
for rec in LOG:
    flat = str(rec)
    assert "host@example.com" not in flat and "010-1234-5678" not in flat and "h@x.kr" not in flat, rec
print(f"[OK] 알림 시나리오 7개 통과 (메일 {len(SENT_MAIL)}통, 문자 {len(sms_sent)}건, 기록 {len(LOG)}건, 기록에 연락처 없음)")
print("ALL OK")
