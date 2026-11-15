"""프로젝트 루트의 .env 를 읽어 환경변수로 설정한다 (이미 설정된 값은 덮어쓰지 않음).

각 실행 스크립트 맨 위에서 `import env` 한 줄로 사용한다.
"""
import os

_ROOT_ENV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")


def load(path: str = _ROOT_ENV):
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            if value:  # 빈 값(아직 안 채운 칸)은 '설정 안 됨'으로 취급
                os.environ.setdefault(key.strip(), value)


load()
