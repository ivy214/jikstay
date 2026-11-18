# -*- coding: utf-8 -*-
"""
주간 자동 업데이트 스크립트:
1) 기존 17개 시·도 웹 매거진(daily_stories), chapter_media, 검증된 E-book URL은 그대로 보존
2) TourAPI searchFestival2(전국 + 17개 시·도별) + 네이버 지역 축제 일정 검색으로 최신 임박·신규 축제/행사 수집
3) GEMINI_API_KEY가 있으면 translate_hub.py --gemini 증분 번역 실행
"""

from __future__ import annotations

import datetime as dt
import hashlib
import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, quote, unquote, urlparse

import requests

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    PROVINCE_17_ORDER,
    PROVINCE_17_TOUR_PARAMS,
    _https,
    _parse_wgs84,
    _tour_get,
    classify_region_group,
    enrich_spots_and_festivals_details,
    normalize_place_name,
    normalize_province_short,
    parse_korean_address,
)

HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"

PROVINCE_CENTERS: dict[str, tuple[float, float]] = {
    "서울": (37.5665, 126.9780),
    "부산": (35.1796, 129.0756),
    "대구": (35.8714, 128.6014),
    "인천": (37.4563, 126.7052),
    "광주": (35.1595, 126.8526),
    "대전": (36.3504, 127.3845),
    "울산": (35.5384, 129.3114),
    "세종": (36.4800, 127.2890),
    "경기": (37.4138, 127.5183),
    "강원": (37.8228, 128.1555),
    "충북": (36.6357, 127.4914),
    "충남": (36.6588, 126.6728),
    "전북": (35.8202, 127.1088),
    "전남": (34.8161, 126.4629),
    "경북": (36.5760, 128.5056),
    "경남": (35.2383, 128.6924),
    "제주": (33.4996, 126.5312),
}


def _load_env() -> None:
    env_path = ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _tour_items_to_events(items: list[dict[str, Any]], seen_cids: set[str]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for it in items:
        cid = str(it.get("contentid") or "").strip()
        if not cid or cid in seen_cids:
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
        seen_cids.add(cid)
        out.append({
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
    return out


def fetch_latest_festivals() -> list[dict[str, Any]]:
    today = dt.date.today()
    start_ymd = today.strftime("%Y%m%d")
    end_ymd = (today + dt.timedelta(days=90)).strftime("%Y%m%d")

    collected: list[dict[str, Any]] = []
    seen_cids: set[str] = set()

    # 1. 전국 TourAPI searchFestival2
    for page in (1, 2, 3):
        body = _tour_get(
            "searchFestival2",
            {
                "eventStartDate": start_ymd,
                "eventEndDate": end_ymd,
                "numOfRows": 60,
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
        collected.extend(_tour_items_to_events(items, seen_cids))

    # 2. 시·도별 TourAPI searchFestival2 보강
    for entry in PROVINCE_17_TOUR_PARAMS:
        prov, q_list = entry[0], entry[1]
        if not q_list:
            continue
        body = _tour_get(
            "searchFestival2",
            {**q_list[0], "eventStartDate": start_ymd, "eventEndDate": end_ymd, "numOfRows": 40, "pageNo": 1},
            timeout=10,
        )
        if not body:
            continue
        items = (body.get("items") or {}).get("item") or []
        if isinstance(items, dict):
            items = [items]
        collected.extend(_tour_items_to_events(items, seen_cids))

    return collected


def _decode_naver_thumb(raw_url: str) -> str:
    if "src=" in raw_url:
        try:
            qs = parse_qs(urlparse(raw_url).query)
            if qs.get("src"):
                return _https(unquote(qs["src"][0]))
        except Exception:
            pass
    return _https(raw_url)


# 주소 맨 앞의 시·도 이름 (있으면 그 시·도가 확실하다)
_PROVINCE_PREFIX = re.compile(r"^(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충청|충북|충남|전라|전북|전남|경상|경북|경남|제주)")


def naver_result_in_province(prov: str, addr: str, norm_prov: str) -> bool:
    """'{시·도} 축제' 네이버 검색 결과가 그 시·도 행사인지.
    세종 행사는 주소를 '조치원읍 …'처럼 시·도 없이 쓰는 경우가 많아(해석하면 엉뚱한 시·도) 그런 주소는 받아 주되,
    주소가 다른 시·도 이름으로 시작하면 세종이라도 뺀다 ('세종 축제' 검색에 섞여 나오는 부산 BEXCO 행사 등)."""
    if norm_prov == prov:
        return True
    return prov == "세종" and not _PROVINCE_PREFIX.match(addr.strip())


def fetch_naver_province_festivals() -> list[dict[str, Any]]:
    today = dt.date.today()
    today_ymd = today.strftime("%Y%m%d")
    next_month = (today.month % 12) + 1
    results: list[dict[str, Any]] = []
    seen_titles: set[str] = set()
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}

    for prov in PROVINCE_17_ORDER:
        queries = [f"{prov} 지역 축제 일정", f"{prov} {today.month}월 {next_month}월 축제"]
        for q in queries:
            try:
                r = requests.get(
                    "https://search.naver.com/search.naver",
                    params={"where": "nexearch", "query": q},
                    headers=headers,
                    timeout=8,
                )
                if r.status_code != 200:
                    continue
            except Exception:
                continue

            for m in re.finditer(r'class="area_text_box"', r.text):
                pre = r.text[max(0, m.start() - 950) : m.start()]
                # 태그 중간(class="…">)부터 자르면 속성 문자열이 제목으로 잡히므로 태그가 닫힌 뒤부터 읽는다.
                tag_end = r.text.find(">", m.end())
                body_start = tag_end + 1 if tag_end != -1 else m.end()
                block = r.text[body_start : body_start + 950]
                plain = html.unescape(re.sub(r"<[^>]+>", "\n", block))
                lines = [re.sub(r"\s+", " ", ln).strip() for ln in plain.splitlines() if ln.strip()]
                if not lines or "일시적인 오류" in lines[0]:
                    continue

                title = ""
                for ln in lines:
                    if ln not in ("area_text_box", "기간", "장소", "지도", "~") and len(ln) >= 3:
                        if not re.match(r"^\d{4}\.\d{2}\.\d{2}", ln) and not re.search(r'[<>="]', ln):
                            title = normalize_place_name(ln)
                            break
                if not title:
                    continue

                dates = re.findall(r"(\d{4})\.(\d{2})\.(\d{2})\.", plain)
                if not dates:
                    continue
                start_ymd = "".join(dates[0])
                end_ymd = "".join(dates[1]) if len(dates) >= 2 else start_ymd
                if end_ymd < today_ymd:
                    continue

                addr = ""
                for idx, ln in enumerate(lines):
                    if ln == "장소" and idx + 1 < len(lines):
                        addr = lines[idx + 1]
                        break
                if not addr:
                    addr = prov

                d1, d2 = parse_korean_address(addr)
                norm_prov = normalize_province_short(d1, d2) or prov
                if not naver_result_in_province(prov, addr, norm_prov):
                    continue

                imgs = re.findall(r'(?:src|data-lazysrc)="(https://[^"]+)"', pre + block)
                img_url = _decode_naver_thumb(imgs[0]) if imgs else ""
                if not img_url or "ssl.pstatic.net/sstatic" in img_url:
                    continue

                dedup_key = f"{prov}:{re.sub(r'[^가-힣a-zA-Z0-9]', '', title)}"
                if dedup_key in seen_titles:
                    continue
                seen_titles.add(dedup_key)

                lat, lng = PROVINCE_CENTERS.get(prov, (36.35, 127.38))
                ev_id = "spot_ev_nv_" + hashlib.md5(dedup_key.encode("utf-8")).hexdigest()[:10]
                results.append({
                    "id": ev_id,
                    "kind": "event",
                    "content_id": ev_id,
                    "title": title,
                    "province": prov,
                    "region_group": classify_region_group(d1 or prov) or "전체",
                    "region_label": f"{prov} {d2}".strip(),
                    "addr": addr,
                    "lat": lat,
                    "lng": lng,
                    "image_url": img_url,
                    "tel": "",
                    "start_date": start_ymd,
                    "end_date": end_ymd,
                    "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
                })
    return results


def main() -> None:
    _load_env()
    if not HUB_PATH.exists():
        raise FileNotFoundError(f"Missing {HUB_PATH}")
    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))

    tour_events = fetch_latest_festivals()
    naver_events = fetch_naver_province_festivals()
    print(f"[weekly] 수집 결과: TourAPI={len(tour_events)}건, 네이버 지역축제={len(naver_events)}건")

    combined = tour_events + naver_events
    if combined:
        existing_by_cid = {str(f.get("content_id") or f.get("id")): f for f in hub.get("festivals", [])}
        existing_titles = {
            f"{f.get('province')}:{re.sub(r'[^가-힣a-zA-Z0-9]', '', str(f.get('title') or ''))}": f
            for f in hub.get("festivals", [])
        }
        added = 0
        for ev in combined:
            key = str(ev.get("content_id") or ev.get("id"))
            tkey = f"{ev.get('province')}:{re.sub(r'[^가-힣a-zA-Z0-9]', '', str(ev.get('title') or ''))}"
            if key in existing_by_cid:
                old = existing_by_cid[key]
                for keep_k in ("overview", "paragraphs", "pull_quote", "practical_info", "naver_reviews"):
                    if old.get(keep_k) and not ev.get(keep_k):
                        ev[keep_k] = old[keep_k]
                existing_by_cid[key] = ev
            elif tkey in existing_titles:
                # 동일 축제가 이미 TourAPI로 있으면 네이버 버전으로 중복 추가하지 않고 일정만 보강
                old = existing_titles[tkey]
                if not old.get("start_date") and ev.get("start_date"):
                    old["start_date"] = ev["start_date"]
                    old["end_date"] = ev["end_date"]
            else:
                existing_by_cid[key] = ev
                existing_titles[tkey] = ev
                added += 1

        today_ymd = dt.date.today().strftime("%Y%m%d")
        active_list = [
            ev for ev in existing_by_cid.values()
            if not ev.get("end_date") or str(ev.get("end_date")) >= today_ymd
        ]
        active_list.sort(key=lambda x: str(x.get("start_date") or "99999999"))
        need_enrich = [
            ev for ev in active_list
            if not ev.get("naver_reviews") or (str(ev.get("content_id") or "").isdigit() and not ev.get("paragraphs"))
        ]
        if need_enrich:
            print(f"[weekly] 축제 상세·네이버 후기 보강 대상: {len(need_enrich)}건")
            enrich_spots_and_festivals_details(
                need_enrich,
                cache_path=str(ROOT / "output" / "curated_stays_cache" / "spot_editorial_detail_cache.json"),
            )
        hub["festivals"] = active_list
        jb_cnt = sum(1 for x in active_list if x.get("province") == "전북")
        rev_cnt = sum(1 for x in active_list if x.get("naver_reviews"))
        print(f"[weekly] 축제 최종 반영: 총 {len(active_list)}건 (신규 {added}건, 전북={jb_cnt}건, 네이버후기={rev_cnt}건)")

    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    # CI는 번역을 별도 단계로 실행해 실패를 드러낸다(--no-translate).
    if "--no-translate" in sys.argv:
        return
    if os.getenv("GEMINI_API_KEY", "").strip():
        print("[weekly] 다국어 증분 번역 실행 중...")
        rc = subprocess.run(
            [sys.executable, str(ROOT / "backend" / "translate_hub.py"), "--gemini"],
            check=False,
        ).returncode
        if rc != 0:
            # 허브 JSON은 이미 저장됐으므로 축제 갱신은 유지하고, 번역 실패만 종료 코드로 알린다.
            print(f"[weekly] 오류: 다국어 번역 실패 (종료 코드 {rc})", file=sys.stderr)
            sys.exit(rc)


if __name__ == "__main__":
    main()
