# -*- coding: utf-8 -*-
"""
주간 자동 업데이트 스크립트:
1) 기존 17개 시·도 웹 매거진(daily_stories), chapter_media, 검증된 E-book URL은 그대로 보존
2) TourAPI searchFestival2(오늘 ~ +90일)로 최신 임박·신규 축제/행사만 갱신·병합
3) GEMINI_API_KEY가 있으면 translate_hub.py --gemini 증분 번역 실행
"""

from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    _https,
    _parse_wgs84,
    _tour_get,
    classify_region_group,
    normalize_place_name,
    normalize_province_short,
    parse_korean_address,
)

HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"


def _load_env() -> None:
    env_path = ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def fetch_latest_festivals() -> list[dict[str, Any]]:
    today = dt.date.today()
    start_ymd = today.strftime("%Y%m%d")
    end_ymd = (today + dt.timedelta(days=90)).strftime("%Y%m%d")

    collected: list[dict[str, Any]] = []
    seen: set[str] = set()
    for page in (1, 2):
        body = _tour_get(
            "searchFestival2",
            {
                "eventStartDate": start_ymd,
                "eventEndDate": end_ymd,
                "numOfRows": 40,
                "pageNo": page,
                "arrange": "A",
            },
            timeout=12,
        )
        if not body:
            break
        items = (body.get("items") or {}).get("item") or []
        if isinstance(items, dict):
            items = [items]
        if not items:
            break
        for it in items:
            cid = str(it.get("contentid") or "").strip()
            if not cid or cid in seen:
                continue
            img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
            if not img:
                continue
            addr1 = str(it.get("addr1") or "").strip()
            d1, d2 = parse_korean_address(addr1)
            prov = normalize_province_short(d1, d2) or "기타"
            title = normalize_place_name(str(it.get("title") or ""))
            if not title:
                continue
            lat, lng = _parse_wgs84(it, prov)
            seen.add(cid)
            collected.append({
                "id": f"spot_ev_{cid}",
                "kind": "event",
                "content_id": cid,
                "title": title,
                "province": prov,
                "region_group": classify_region_group(d1) or "전체",
                "region_label": f"{prov} {d2}".strip(),
                "addr": addr1,
                "lat": lat,
                "lng": lng,
                "image_url": img,
                "tel": str(it.get("tel") or "").strip(),
                "start_date": str(it.get("eventstartdate") or "").strip(),
                "end_date": str(it.get("eventenddate") or "").strip(),
                "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
            })
    return collected


def main() -> None:
    _load_env()
    if not HUB_PATH.exists():
        raise FileNotFoundError(f"Missing {HUB_PATH}")
    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))

    fresh = fetch_latest_festivals()
    if fresh:
        existing = {str(f.get("content_id") or f.get("id")): f for f in hub.get("festivals", [])}
        added = 0
        for ev in fresh:
            key = str(ev.get("content_id") or ev.get("id"))
            if key not in existing:
                added += 1
            else:
                # 기존 상세 개요/블로그 스니펫이 있으면 유지하면서 최신 일정·이미지 병합
                old = existing[key]
                for keep_k in ("overview", "paragraphs", "pull_quote", "practical_info", "naver_reviews"):
                    if old.get(keep_k) and not ev.get(keep_k):
                        ev[keep_k] = old[keep_k]
            existing[key] = ev
        today_ymd = dt.date.today().strftime("%Y%m%d")
        active_list = [
            ev for ev in existing.values()
            if not ev.get("end_date") or str(ev.get("end_date")) >= today_ymd
        ]
        active_list.sort(key=lambda x: str(x.get("start_date") or "99999999"))
        hub["festivals"] = active_list
        print(f"[weekly] TourAPI 축제 갱신: 총 {len(active_list)}건 (신규 {added}건)")
    else:
        print("[weekly] TourAPI 응답 없음 — 기존 festivals 유지")

    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    if os.getenv("GEMINI_API_KEY", "").strip():
        print("[weekly] 다국어 증분 번역 실행 중...")
        subprocess.run(
            [sys.executable, str(ROOT / "backend" / "translate_hub.py"), "--gemini"],
            check=False,
        )


if __name__ == "__main__":
    main()
