"""IndexNow URL submission helper for Naver Search Advisor & Bing/Global search engines.

Reads updated festival/story URLs from app/web/data/public_travel_hub.json and
submits them to IndexNow endpoints after weekly data updates or deployments.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import List
from urllib.parse import quote

import requests

ROOT = Path(__file__).resolve().parent.parent
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
HOST = "jikstay-lkxu1.web.app"
INDEXNOW_KEY = "jikstayindexnow20260000"
KEY_LOCATION = f"https://{HOST}/{INDEXNOW_KEY}.txt"

PROVINCES = [
    "서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종",
    "경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주",
]


def collect_priority_urls(limit: int = 80) -> List[str]:
    urls: List[str] = [
        f"https://{HOST}/",
        f"https://{HOST}/?lang=en",
        f"https://{HOST}/?lang=ja",
        f"https://{HOST}/?lang=zh",
    ]
    for prov in PROVINCES:
        urls.append(f"https://{HOST}/?region={quote(prov)}")

    if HUB_PATH.exists():
        data = json.loads(HUB_PATH.read_text(encoding="utf-8"))
        for ev in (data.get("events") or [])[:25]:
            eid = str(ev.get("id") or "").strip()
            if eid:
                urls.append(f"https://{HOST}/?spot={quote(eid)}")
        for st in (data.get("daily_stories") or [])[:15]:
            sid = str(st.get("id") or "").strip()
            if sid:
                urls.append(f"https://{HOST}/?story={quote(sid)}")

    return urls[:limit]


def submit_indexnow(urls: List[str]) -> None:
    payload = {
        "host": HOST,
        "key": INDEXNOW_KEY,
        "keyLocation": KEY_LOCATION,
        "urlList": urls,
    }
    endpoints = [
        "https://api.indexnow.org/indexnow",
        "https://searchadvisor.naver.com/indexnow",
    ]
    for ep in endpoints:
        try:
            resp = requests.post(ep, json=payload, timeout=10)
            print(f"[IndexNow] {ep} -> HTTP {resp.status_code} ({len(urls)} URLs)")
        except Exception as exc:
            print(f"[IndexNow] {ep} skipped/error: {exc}")


if __name__ == "__main__":
    submit_indexnow(collect_priority_urls())
