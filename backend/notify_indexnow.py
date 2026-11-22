"""IndexNow 제출 (네이버 서치어드바이저 · Bing 등 IndexNow 참여 검색엔진).

주간 갱신 뒤 바뀐 페이지만 알린다:
  --prev 이전 허브 JSON 을 주면 새로 생기거나 내용이 바뀌거나 빠진 항목의 URL 만 제출한다
  (빠진 항목도 알려야 검색엔진이 '종료된 행사' 페이지로 다시 읽어 간다).
  --prev 가 없으면 진행 중인 축제·공연·전시와 스토리 전체를 제출한다.
홈·주제 페이지(축제 일정·5일장·공연전시)는 해당 섹션이 바뀌었을 때만 함께 넣는다.

사용:
  python backend/notify_indexnow.py --prev /tmp/hub_prev.json
  python backend/notify_indexnow.py --dry-run
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List
from urllib.parse import quote

import requests

ROOT = Path(__file__).resolve().parent.parent
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
HOST = "jikstay.app"
SITE = f"https://{HOST}"
INDEXNOW_KEY = "jikstayindexnow20260000"
KEY_LOCATION = f"{SITE}/{INDEXNOW_KEY}.txt"
# api.indexnow.org 는 참여 검색엔진(Bing·Yandex 등)에 공유하고, 네이버는 자체 엔드포인트로도 받는다
ENDPOINTS = (
    "https://api.indexnow.org/indexnow",
    "https://searchadvisor.naver.com/indexnow",
)
MAX_URLS = 10_000  # IndexNow 한 번 요청 상한

# 허브 섹션 → (URL 파라미터, 주제 페이지)
SECTIONS = {
    "festivals": ("spot", "festival"),
    "culture": ("spot", "culture"),
    "markets": ("spot", "market"),
    "traditional_markets": ("spot", "market"),
    "spots": ("spot", None),
    "daily_stories": ("story", None),
}


def _kst_today_ymd() -> str:
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=9)).strftime("%Y%m%d")


def _fingerprint(item: Dict[str, Any]) -> str:
    return hashlib.sha1(json.dumps(item, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()


def _index(hub: Dict[str, Any], section: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for item in hub.get(section) or []:
        if isinstance(item, dict) and str(item.get("id") or "").strip():
            out[str(item["id"]).strip()] = _fingerprint(item)
    return out


def _is_active(item: Dict[str, Any], today: str) -> bool:
    end = str(item.get("end_date") or "").strip()
    return not (len(end) == 8 and end.isdigit() and end < today)


def _item_url(param: str, item_id: str) -> str:
    return f"{SITE}/?{param}={quote(item_id)}"


def _topic_urls(topic: str, hub: Dict[str, Any]) -> List[str]:
    sections = [s for s, (_, t) in SECTIONS.items() if t == topic]
    provinces = sorted({str(x.get("province") or "") for s in sections for x in (hub.get(s) or []) if isinstance(x, dict)} - {""})
    return [f"{SITE}/?topic={topic}"] + [f"{SITE}/?topic={topic}&region={quote(p)}" for p in provinces]


def collect_changed_urls(hub: Dict[str, Any], prev: Dict[str, Any] | None, today: str | None = None) -> List[str]:
    """prev 와 비교해 바뀐 URL. prev 가 None 이면 진행 중인 행사·스토리 전체."""
    today = today or _kst_today_ymd()
    urls: List[str] = []
    changed_topics: set[str] = set()

    for section, (param, topic) in SECTIONS.items():
        cur = _index(hub, section)
        if prev is None:
            if section == "spots":  # 볼거리·먹거리(수천 곳)는 처음 한 번에 몰아 넣지 않고 sitemap 에 맡긴다
                continue
            items = {str(x["id"]): x for x in hub.get(section) or [] if isinstance(x, dict) and x.get("id")}
            ids = [i for i in cur if _is_active(items[i], today)]
        else:
            old = _index(prev, section)
            ids = [i for i, fp in cur.items() if old.get(i) != fp] + [i for i in old if i not in cur]
        if ids and topic:
            changed_topics.add(topic)
        urls.extend(_item_url(param, i) for i in ids)

    head = [f"{SITE}/"] if (urls or prev is None) else []
    for topic in sorted(changed_topics):
        head.extend(_topic_urls(topic, hub))
    return _dedupe(head + urls)[:MAX_URLS]


def _dedupe(urls: Iterable[str]) -> List[str]:
    seen: set[str] = set()
    return [u for u in urls if not (u in seen or seen.add(u))]


def submit_indexnow(urls: List[str]) -> bool:
    """하나라도 200/202 로 받아 주면 True."""
    if not urls:
        print("[IndexNow] 바뀐 URL 이 없어 제출하지 않습니다.")
        return True
    payload = {"host": HOST, "key": INDEXNOW_KEY, "keyLocation": KEY_LOCATION, "urlList": urls}
    ok = False
    for ep in ENDPOINTS:
        try:
            resp = requests.post(ep, json=payload, timeout=20)
            print(f"[IndexNow] {ep} -> HTTP {resp.status_code} ({len(urls)} URLs)")
            if resp.status_code in (200, 202):
                ok = True
            else:
                print(f"[IndexNow]   응답: {resp.text[:300]}")
        except requests.RequestException as exc:
            print(f"[IndexNow] {ep} 오류: {exc}")
    return ok


def _load(path: Path) -> Dict[str, Any] | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"[IndexNow] {path} 를 읽지 못했습니다: {exc}")
        return None


def main(argv: List[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prev", type=Path, help="갱신 전 public_travel_hub.json (없으면 전체 제출)")
    ap.add_argument("--hub", type=Path, default=HUB_PATH)
    ap.add_argument("--dry-run", action="store_true", help="제출하지 않고 URL 만 출력")
    args = ap.parse_args(argv)

    hub = _load(args.hub)
    if hub is None:
        return 1
    prev = _load(args.prev) if args.prev else None
    if args.prev and prev is None:
        print("[IndexNow] 이전 허브가 없어 전체 제출로 바꿉니다.")
    urls = collect_changed_urls(hub, prev)
    print(f"[IndexNow] 제출 대상 {len(urls)}개")
    if args.dry_run:
        print("\n".join(urls))
        return 0
    return 0 if submit_indexnow(urls) else 1


if __name__ == "__main__":
    sys.exit(main())
