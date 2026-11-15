"""호스트 후보 목록 만들기 (네이버 검색 오픈 API 전용).

[수정 사항]
- 이전 버전은 m.search.naver.com 검색 결과 페이지를 API 없이 긁고, 각 블로그 글 본문에
  직접 접속해 사진 수까지 셌다. 이는 스스로 정한 "무단 크롤링 금지" 원칙과 네이버 이용약관에
  어긋나므로 제거했다.
- 이제 공식 검색 API가 돌려주는 메타데이터(제목·요약·링크·블로거명)만 사용한다.
  블로그 본문·사진은 수집하지 않는다.
- 결과는 "사람이 직접 검토할 후보 목록"일 뿐이다. 영업신고 여부는 반드시
  호스트가 신청 폼에 낸 신고증 + 공공 인허가 데이터로 확인한다.

환경변수: NAVER_CLIENT_ID, NAVER_CLIENT_SECRET  (developers.naver.com 에서 발급)
"""
import csv
import os
import re
import time

import env  # noqa: F401  (.env 로드)

import requests

API_LEGACY_URL = "https://openapi.naver.com/v1/search/blog.json"
API_HUB_URL = "https://naverapihub.apigw.ntruss.com/search/v1/blog"

QUERIES = [
    "제주 애월 농어촌민박 한달살기 예약안내",
    "제주 구좌 독채민박 보름살기 예약문의",
    "제주 서귀포 농어촌민박 한달살기 요금 안내",
    "제주 한림 독채 농어촌민박 직접예약",
    "제주 조천 농어촌민박 장기숙박",
]

REVIEW_STOPWORDS = ["내돈내산", "협찬", "방문후기", "다녀왔", "숙박후기", "리뷰", "원고료", "솔직후기"]
HOST_KEYWORDS = ["예약안내", "예약문의", "입실", "퇴실", "환불규정", "농어촌민박", "사업자", "요금표"]


def clean_html(raw: str) -> str:
    return re.sub(r"<.*?>", "", raw)


def find_candidates(target_count: int = 50, out_csv: str = "output/host_candidates.csv"):
    client_id = os.environ.get("NAVER_CLIENT_ID")
    client_secret = os.environ.get("NAVER_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise RuntimeError("NAVER_CLIENT_ID / NAVER_CLIENT_SECRET 환경변수를 설정하세요.")

    # 네이버 클라우드 플랫폼(NAVER API HUB) 키는 Secret이 40자, 기존 developers.naver.com 키는 10자
    use_hub = len(client_secret) >= 20 or os.environ.get("NAVER_API_MODE", "").lower() == "hub"
    api_url = API_HUB_URL if use_hub else API_LEGACY_URL
    headers = (
        {"X-NCP-APIGW-API-KEY-ID": client_id, "X-NCP-APIGW-API-KEY": client_secret}
        if use_hub
        else {"X-Naver-Client-Id": client_id, "X-Naver-Client-Secret": client_secret}
    )
    found: dict[str, dict] = {}

    for q in QUERIES:
        for start in range(1, 100, 30):
            if len(found) >= target_count:
                break
            params = {"query": q, "display": 30, "start": start, "sort": "sim"}
            if use_hub:
                params["format"] = "json"
            resp = requests.get(
                api_url,
                headers=headers,
                params=params,
                timeout=10,
            )
            if resp.status_code != 200:
                print(f"API 오류 {resp.status_code}: {resp.text[:200]}")
                break

            for item in resp.json().get("items", []):
                title = clean_html(item["title"])
                desc = clean_html(item["description"])
                if any(s in title or s in desc for s in REVIEW_STOPWORDS):
                    continue
                if not any(k in f"{title} {desc} {item['bloggername']}" for k in HOST_KEYWORDS):
                    continue

                blog_id = item["bloggerlink"].rstrip("/").split("/")[-1]
                if blog_id in found:
                    continue
                found[blog_id] = {
                    "blogger_name": item["bloggername"],
                    "blog_home": f"https://blog.naver.com/{blog_id}",
                    "sample_post_title": title,
                    "sample_post_url": item["link"],
                    "search_keyword": q,
                    "license_checked": "",   # 사람이 검토 후 기입
                    "contact_channel": "",   # 호스트가 공개한 문의 채널(사람이 기입)
                    "contacted_at": "",
                    "opted_out": "",          # 거절/수신거부 시 Y — 재연락 금지
                }
                if len(found) >= target_count:
                    break
            time.sleep(0.2)

    os.makedirs(os.path.dirname(out_csv), exist_ok=True)
    fields = list(next(iter(found.values())).keys()) if found else ["blogger_name"]
    with open(out_csv, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(found.values())
    print(f"후보 {len(found)}곳 저장: {out_csv} (사람 검토 필요)")


if __name__ == "__main__":
    find_candidates(50)
