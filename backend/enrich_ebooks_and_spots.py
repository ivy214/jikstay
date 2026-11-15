#!/usr/bin/env python3
"""
전국 17개 시·도 지자체 공식 E-book 사이트 조사 · 대표 배너 스토리 생성 ·
볼거리/먹거리/숙소 추가 추출기.

1. `public_travel_hub.json`의 `municipal_ebooks` 17개 시·도 공식 URL을 직접 크롤링하여
   PDF/E-book 링크, 가이드북 주제, 추천 권역·명소·먹거리·숙소 키워드를 수집한다.
2. 아직 `daily_stories`에 전용 웹 에디션이 없는 12개 시·도에 대해
   `gemini-3.5-flash-lite`로 지자체 공식 E-book 기반 웹 매거진 스토리를 생성한다.
3. 지자체 사이트에서 추출한 대표 키워드 및 TourAPI(KorService2) 2페이지/숙소(32) API로
   시·도별 볼거리·먹거리·특색 숙소를 추가 추출해 `public_travel_hub.json`을 보강한다.
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import pathlib
import re
import sys
import time
from typing import Any
from urllib.parse import quote, urljoin

from bs4 import BeautifulSoup
from google import genai
from google.genai import types
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))

from build_travel_hub import (  # noqa: E402
    PROVINCE_17_TOUR_PARAMS,
    _https,
    _parse_wgs84,
    _strip_overview_html,
    _tour_get,
)
from curate_public_stays import (  # noqa: E402
    classify_region_group,
    normalize_place_name,
    normalize_province_short,
    parse_korean_address,
)

ENV_PATH = ROOT / ".env"
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
MODEL_NAME = "gemini-3.5-flash-lite"


def load_env() -> None:
    if not ENV_PATH.exists():
        return
    for raw in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def probe_ebook_site(ebook: dict[str, Any]) -> dict[str, Any]:
    url = str(ebook.get("url", "") or "").strip()
    prov = str(ebook.get("province", "") or "").strip()
    found_pdfs: list[dict[str, str]] = list(ebook.get("pdf_links") or [])
    seen_urls = {p.get("url", "") for p in found_pdfs if isinstance(p, dict)}
    snippets: list[str] = []
    page_title = ""

    if url:
        try:
            r = requests.get(
                url,
                headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0"},
                timeout=10,
                verify=False,
            )
            if r.status_code == 200 and r.text:
                soup = BeautifulSoup(r.text, "html.parser")
                if soup.title and soup.title.string:
                    page_title = re.sub(r"\s+", " ", soup.title.string).strip()[:100]
                for a in soup.find_all("a", href=True):
                    href = str(a.get("href") or "").strip()
                    txt = re.sub(r"\s+", " ", a.get_text(" ", strip=True)).strip()
                    low = (href + " " + txt).lower()
                    if any(k in low for k in (".pdf", "ebook", "e-book", "다운로드", "download", "getfile", "guidebook")):
                        abs_url = urljoin(url, href)
                        if abs_url.startswith("http") and abs_url not in seen_urls and len(found_pdfs) < 4:
                            seen_urls.add(abs_url)
                            label = txt[:48] if txt else f"{prov} 공식 가이드북/PDF"
                            found_pdfs.append({"label": f"📖 {label}", "url": abs_url})
                for tag in soup(["script", "style", "nav", "footer"]):
                    tag.decompose()
                text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
                if text:
                    snippets.append(text[:1800])
        except Exception:
            pass

    return {
        "id": ebook.get("id", ""),
        "province": prov,
        "title": ebook.get("title", ""),
        "url": url,
        "page_title": page_title,
        "pdf_links": found_pdfs,
        "snippet": " ".join(snippets),
    }


def generate_provincial_story(
    client: genai.Client,
    probe: dict[str, Any],
    prov_spots: list[dict[str, Any]],
) -> tuple[dict[str, Any] | None, list[str]]:
    prov = probe["province"]
    sample_names = [f"{s['title']}({s['kind']})" for s in prov_spots[:10]]
    prompt = (
        f"You are an editor for a Korean local travel magazine.\n"
        f"Based on the official municipal e-book/tourism portal info for '{prov}', create:\n"
        f"1) 'story': A compelling Korean web magazine story summarizing the province's official guidebook.\n"
        f"2) 'extract_keywords': 6 specific famous Korean attraction/food/stay keywords featured in {prov}'s official tourism guide (short Korean nouns like '해운대 블루라인파크', '부산 돼지국밥', '태종대' etc.) for TourAPI search.\n\n"
        f"PROVINCE: {prov}\n"
        f"EBOOK TITLE: {probe['title']}\n"
        f"EBOOK URL: {probe['url']}\n"
        f"PAGE SNIPPET: {probe['snippet'][:900]}\n"
        f"EXISTING SPOTS: {', '.join(sample_names)}\n\n"
        "Return strict JSON matching:\n"
        "{\n"
        '  "story": {\n'
        '    "city": "대표 권역 (예: 해운대·광안리·남포)",\n'
        '    "season_badge": "이모지 포함 테마 배지 (예: 🌊 공식 E-book 해안·미식 가이드)",\n'
        '    "source_book": "공식 가이드북 출처명",\n'
        '    "title": "매거진 기사 제목 (18~36자)",\n'
        '    "subtitle": "부제 (권역 · 웹 에디션 요약)",\n'
        '    "address": "대표 중심 주소",\n'
        '    "pull_quote": "핵심 한 줄 요약 (40~90자)",\n'
        '    "paragraphs": ["문단1 (2~3문장, 품격 있는 매거진 톤)", "문단2 (웹 가이드북 활용법 및 로컬 코스 안내)"],\n'
        '    "practical_header": "가이드북 핵심 권역 · 교통 · 관광안내",\n'
        '    "practical_info": [{"label": "핵심 권역", "value": "..."}, {"label": "대표 먹거리", "value": "..."}, {"label": "관광 안내", "value": "..."}],\n'
        '    "en_summary": "1-2 sentence English summary of this municipal guidebook."\n'
        "  },\n"
        '  "extract_keywords": ["키워드1", "키워드2", "키워드3", "키워드4", "키워드5", "키워드6"]\n'
        "}"
    )
    for attempt in range(3):
        try:
            resp = client.models.generate_content(
                model=MODEL_NAME,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    temperature=0.3,
                    http_options=types.HttpOptions(timeout=45000),
                ),
            )
            data = json.loads((resp.text or "").strip())
            st = data.get("story")
            kws = [str(x).strip() for x in (data.get("extract_keywords") or []) if str(x).strip()]
            if isinstance(st, dict) and st.get("title"):
                return st, kws
        except Exception as exc:
            if attempt == 2:
                print(f"[WARN] story gen failed for {prov}: {exc}")
            time.sleep(1.5)
    return None, []


def fetch_extra_tour_spots_for_province(
    prov: str,
    q_list: list[dict[str, str]],
    keywords: list[str],
    existing_cids: set[str],
    target_new: int = 8,
) -> list[dict[str, Any]]:
    """TourAPI page=2 + 키워드 검색으로 추가 볼거리(12)·먹거리(39)를 추출한다."""
    added: list[dict[str, Any]] = []
    seen = set(existing_cids)

    def _add_raw(it: dict[str, Any], kind_key: str) -> bool:
        cid = str(it.get("contentid") or "").strip()
        if not cid or cid in seen:
            return False
        img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
        if not img:
            return False
        addr1 = str(it.get("addr1") or "").strip()
        d1, d2 = parse_korean_address(addr1)
        norm_prov = normalize_province_short(d1, d2)
        if norm_prov and norm_prov != prov and prov != "세종":
            return False
        title = normalize_place_name(str(it.get("title") or ""))
        if not title:
            return False
        lat, lng = _parse_wgs84(it, prov)
        rg = classify_region_group(d1) or "전체"
        seen.add(cid)
        added.append({
            "id": f"spot_{kind_key[:2]}_{cid}",
            "kind": kind_key,
            "content_id": cid,
            "title": title,
            "province": prov,
            "region_group": rg,
            "region_label": f"{prov} {d2}".strip(),
            "addr": addr1,
            "lat": lat,
            "lng": lng,
            "image_url": img,
            "tel": str(it.get("tel") or "").strip(),
            "map_url": f"https://map.naver.com/p/search/{quote(f'{prov} {title}'.strip())}",
        })
        return True

    # 1. 지자체 E-book에서 추출한 대표 키워드 기반 TourAPI 검색
    for kw in keywords[:6]:
        if len(added) >= target_new:
            break
        body = _tour_get("searchKeyword2", {"keyword": kw, "numOfRows": 8, "pageNo": 1, "arrange": "Q"}, timeout=10)
        if not body:
            continue
        items = (body.get("items") or {}).get("item") or []
        if isinstance(items, dict):
            items = [items]
        for it in items:
            ct = str(it.get("contenttypeid") or "")
            kind_key = (
                "food" if ct == "39"
                else ("stay" if ct == "32"
                      else ("attraction" if ct in ("12", "14", "28") else ""))
            )
            if not kind_key:
                continue
            if _add_raw(it, kind_key):
                break

    # 2. 부족분은 시·도 areaBasedList2 page=2에서 균형 보충
    if len(added) < target_new and q_list:
        q0 = q_list[0]
        for ct, kind_key in (("12", "attraction"), ("39", "food"), ("32", "stay")):
            if len(added) >= target_new:
                break
            body = _tour_get(
                "areaBasedList2",
                {**q0, "contentTypeId": ct, "numOfRows": 20, "pageNo": 2, "arrange": "Q"},
                timeout=12,
            )
            if not body:
                continue
            items = (body.get("items") or {}).get("item") or []
            if isinstance(items, dict):
                items = [items]
            cnt = 0
            for it in items:
                if _add_raw(it, kind_key):
                    cnt += 1
                if cnt >= 3 or len(added) >= target_new:
                    break

    return added


def enrich_spot_common_overview(spot: dict[str, Any]) -> dict[str, Any]:
    cid = str(spot.get("content_id") or "").strip()
    if not cid or spot.get("overview"):
        return spot
    body = _tour_get("detailCommon2", {"contentId": cid, "numOfRows": 1, "pageNo": 1}, timeout=8)
    if not body:
        return spot
    items = (body.get("items") or {}).get("item") or []
    if isinstance(items, dict):
        items = [items]
    if items:
        ov = _strip_overview_html(str(items[0].get("overview") or ""))
        if ov:
            spot["overview"] = ov
            spot["paragraphs"] = [ov[:550]]
            spot["pull_quote"] = ov.split(".")[0][:120]
        hp = str(items[0].get("homepage") or "").strip()
        m = re.search(r"https?://[^\s\"'<>]+", hp)
        if m and not spot.get("url"):
            spot["url"] = m.group(0)
    return spot


def main() -> None:
    load_env()
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is missing in .env")
    client = genai.Client(api_key=api_key)

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    ebooks = hub.get("municipal_ebooks", [])
    stories = hub.get("daily_stories", [])
    spots = hub.get("spots", [])

    existing_story_provs = {s.get("province") for s in stories if s.get("province")}
    existing_cids = {str(s.get("content_id") or "") for s in spots if s.get("content_id")}
    tour_param_map = {prov: qs for prov, qs in PROVINCE_17_TOUR_PARAMS}

    print(f"[1/4] 전국 {len(ebooks)}개 지자체 E-book 사이트 크롤링 중...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        probes = list(ex.map(probe_ebook_site, ebooks))

    # municipal_ebooks에 추출된 pdf_links 반영
    probe_by_id = {p["id"]: p for p in probes}
    for eb in ebooks:
        pr = probe_by_id.get(eb.get("id", ""))
        if pr and pr["pdf_links"]:
            eb["pdf_links"] = pr["pdf_links"]

    # 시·도별 대표 E-book 1개씩 매핑
    prov_probe: dict[str, dict[str, Any]] = {}
    for pr in probes:
        prov = pr["province"]
        if prov and prov not in prov_probe:
            prov_probe[prov] = pr

    print(f"[2/4] 미수록 시·도 공식 E-book 웹 매거진 스토리 생성 중 (기존 {len(existing_story_provs)}개 시·도)...", flush=True)
    keywords_by_prov: dict[str, list[str]] = {}
    new_stories: list[dict[str, Any]] = []

    def _gen_for_prov(prov_and_pr: tuple[str, dict[str, Any]]):
        prov, pr = prov_and_pr
        if prov in existing_story_provs:
            return None
        prov_spots = [s for s in spots if s.get("province") == prov]
        st_data, kws = generate_provincial_story(client, pr, prov_spots)
        if not st_data:
            return None
        imgs = [s.get("image_url", "") for s in prov_spots if s.get("image_url")][:4]
        lat = prov_spots[0]["lat"] if prov_spots else 36.5
        lng = prov_spots[0]["lng"] if prov_spots else 127.8
        pdf_links = list(pr.get("pdf_links") or [])
        if pr.get("url") and not any(p.get("url") == pr["url"] for p in pdf_links):
            pdf_links.append({"label": f"🌐 {prov} 공식 관광·E-book 포털", "url": pr["url"]})
        story_obj = {
            "id": f"story_ebook_{pr['id'].replace('ebook_', '')}",
            "province": prov,
            "city": st_data.get("city", prov),
            "season_badge": st_data.get("season_badge", f"📖 {prov} 공식 E-book 가이드"),
            "source_book": st_data.get("source_book", pr["title"]),
            "months": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            "title": st_data.get("title", pr["title"]),
            "subtitle": st_data.get("subtitle", pr["title"]),
            "address": st_data.get("address", f"{prov} 주요 관광 권역"),
            "lat": lat,
            "lng": lng,
            "phone": "",
            "pull_quote": st_data.get("pull_quote", ""),
            "paragraphs": st_data.get("paragraphs", []),
            "images": imgs,
            "practical_header": st_data.get("practical_header", f"{prov} 공식 가이드북 핵심 안내"),
            "practical_info": st_data.get("practical_info", []),
            "pdf_links": pdf_links,
            "en_summary": st_data.get("en_summary", ""),
        }
        return (prov, story_obj, kws)

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        for res in ex.map(_gen_for_prov, prov_probe.items()):
            if res:
                prov, st_obj, kws = res
                new_stories.append(st_obj)
                keywords_by_prov[prov] = kws
                print(f"  + {prov}: {st_obj['title']} (keywords={len(kws)})", flush=True)

    stories.extend(new_stories)

    print("[3/4] 지자체 가이드북 키워드 + TourAPI 추가 볼거리·먹거리 추출 중...", flush=True)
    added_spots: list[dict[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        futs = {}
        for prov, qs in tour_param_map.items():
            kws = keywords_by_prov.get(prov, [prov])
            futs[ex.submit(fetch_extra_tour_spots_for_province, prov, qs, kws, existing_cids, 6)] = prov
        for fut in concurrent.futures.as_completed(futs):
            prov = futs[fut]
            chunk = fut.result()
            for sp in chunk:
                if sp["content_id"] not in existing_cids:
                    existing_cids.add(sp["content_id"])
                    added_spots.append(sp)
            print(f"  + {prov} 추가 추출: {len(chunk)}건", flush=True)

    print(f"[4/4] 신규 추출 {len(added_spots)}건 상세 개요 보강 및 저장 중...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        added_spots = list(ex.map(enrich_spot_common_overview, added_spots))

    spots.extend(added_spots)
    hub["municipal_ebooks"] = ebooks
    hub["daily_stories"] = stories
    hub["spots"] = spots
    hub["updated_at"] = int(time.time() * 1000)

    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(
        f"[완료] daily_stories={len(stories)} (전 시도 커버!), spots={len(spots)} (+{len(added_spots)}건 추가)",
        flush=True,
    )


if __name__ == "__main__":
    main()
