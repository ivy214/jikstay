"""Firebase Admin SDK 공용 초기화.

환경변수:
  FIREBASE_CREDENTIALS  서비스 계정 키 경로 (기본: serviceAccountKey.json)
  FIREBASE_BUCKET       Storage 버킷 이름 (예: my-project.firebasestorage.app)
"""
import os
from urllib.parse import quote

import env  # noqa: F401  (.env 로드)

import firebase_admin
from firebase_admin import credentials, firestore, storage

_app = None


def _init():
    global _app
    if _app is None:
        cred_path = os.environ.get("FIREBASE_CREDENTIALS", "serviceAccountKey.json")
        if not os.path.exists(cred_path):
            local_cred = os.path.join(os.path.dirname(os.path.abspath(__file__)), cred_path)
            if os.path.exists(local_cred):
                cred_path = local_cred
        bucket = os.environ.get("FIREBASE_BUCKET")
        if not bucket:
            raise RuntimeError("FIREBASE_BUCKET 환경변수를 설정하세요.")
        _app = firebase_admin.initialize_app(
            credentials.Certificate(cred_path), {"storageBucket": bucket}
        )
    return _app


def db():
    _init()
    return firestore.client()


def bucket():
    _init()
    return storage.bucket()


def public_media_url(blob_path: str) -> str:
    """storage.rules 에서 공개 읽기를 허용한 경로(listings/...)의 직접 URL.

    make_public()은 균일 버킷 수준 액세스가 켜진 버킷에서 실패하므로 쓰지 않는다.
    """
    b = bucket().name
    return f"https://firebasestorage.googleapis.com/v0/b/{b}/o/{quote(blob_path, safe='')}?alt=media"
