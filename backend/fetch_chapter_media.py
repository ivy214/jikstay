# -*- coding: utf-8 -*-
"""
각 웹 매거진 스토리의 챕터별로 본문 내용과 정확히 일치하는 대표 사진을 저장한다.
- 서울(《2026 서울관광안내서》): 원본 PDF에서 추출한 실제 챕터 사진(`assets/guide/seoul_ch1~6.jpg`)
- 그 외 12개 시·도: TourAPI `searchKeyword2` + `contentTypeId` + 제목 일치 검증을 통과한 사진만 매칭
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

from google import genai
from google.genai import types

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import _https, _tour_get  # noqa: E402

HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"

SEOUL_PDF_MEDIA = [
    {"image_url": "assets/guide/seoul_ch1.jpg", "label": "경복궁 · 서울 5대 고궁 (공식 PDF p.4)"},
    {"image_url": "assets/guide/seoul_ch2.jpg", "label": "서울 도심 성곽길 · 하이킹 (공식 PDF p.7)"},
    {"image_url": "assets/guide/seoul_ch3.jpg", "label": "국립중앙박물관 · 문화예술 (공식 PDF p.8)"},
    {"image_url": "assets/guide/seoul_ch4.jpg", "label": "서울의 숲 · 한강공원 (공식 PDF p.11)"},
    {"image_url": "assets/guide/seoul_ch5.jpg", "label": "서촌 · 북촌 한옥마을 (공식 PDF p.19)"},
    {"image_url": "assets/guide/seoul_ch6.jpg", "label": "TASTY SEOUL · 서울 맛 골목 (공식 PDF p.34)"},
]


def _extract_chapter_queries_with_gemini(
    client: genai.Client, prov: str, chapters: list[str]
) -> list[dict[str, str]]:
    numbered = "\n".join(f"{i+1}. {c[:240]}" for i, c in enumerate(chapters))
    prompt = f"""아래 '{prov}' 여행 가이드북의 각 챕터 본문을 읽고, 한국관광공사 TourAPI 키워드 검색으로 정확한 사진을 찾을 수 있는 **실제 대표 명소/음식/축제 이름 1개**와 유형을 뽑아주세요.
규칙:
- query는 반드시 TourAPI에 등록된 실제 장소명(예: "통영케이블카", "남해 독일마을", "통영 중앙시장", "진주남강유등축제", "태화강국가정원", "도담삼봉", "성산일출봉")만 적으세요.
- content_type은 관광지/명소="12", 전통시장/음식="39", 축제/행사="15" 중 하나를 고르세요.
- JSON 배열만 출력: [{{"query": "장소명", "caption": "짧은캡션", "content_type": "12"}}]

챕터 목록:
{numbered}
"""
    resp = client.models.generate_content(
        model="gemini-3.5-flash-lite",
        contents=prompt,
        config=types.GenerateContentConfig(
            temperature=0.1,
            response_mime_type="application/json",
        ),
    )
    arr = json.loads(resp.text or "[]")
    out: list[dict[str, str]] = []
    for item in arr:
        if isinstance(item, dict):
            out.append({
                "query": str(item.get("query") or "").strip(),
                "caption": str(item.get("caption") or item.get("query") or "").strip(),
                "content_type": str(item.get("content_type") or "12").strip(),
            })
    return out


def _title_matches(query: str, title: str) -> bool:
    q_tokens = [t for t in re.split(r"\s+", query) if len(t) >= 2]
    t_norm = re.sub(r"\s+", "", title)
    return any(tok in t_norm for tok in q_tokens)


def _search_exact_tour_image(
    query: str, content_type: str, used_urls: set[str]
) -> tuple[str, str]:
    q_clean = re.sub(r"\s+", " ", query).strip()
    if not q_clean:
        return "", ""
    params: dict[str, object] = {
        "keyword": q_clean,
        "numOfRows": 10,
        "pageNo": 1,
        "arrange": "Q",
    }
    if content_type in ("12", "14", "15", "39"):
        params["contentTypeId"] = content_type
    body = _tour_get("searchKeyword2", params, timeout=8)
    if not body:
        return "", ""
    items = (body.get("items") or {}).get("item") or []
    if isinstance(items, dict):
        items = [items]
    for it in items:
        img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
        title = str(it.get("title") or "").strip()
        if not img or img in used_urls:
            continue
        if _title_matches(q_clean, title):
            used_urls.add(img)
            return img, title
    return "", ""


def main() -> None:
    env_path = ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    client = genai.Client(api_key=api_key) if api_key else None
    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))

    for story in hub.get("daily_stories", []):
        paras = story.get("paragraphs") or []
        chapters = [p for p in paras if isinstance(p, str) and p.strip().startswith("【")]
        if not chapters:
            continue
        prov = str(story.get("province") or "")
        sid = str(story.get("id") or "")
        if sid == "story_seoul_visitseoul_guide":
            story["chapter_media"] = SEOUL_PDF_MEDIA[: len(chapters)]
            print(f"  + 서울: 원본 PDF 6/6 챕터 사진 적용")
            continue

        used_urls = set(story.get("images") or [])
        queries = _extract_chapter_queries_with_gemini(client, prov, chapters) if client else []
        media_list: list[dict[str, str]] = []
        for idx, _ in enumerate(chapters):
            q_info = queries[idx] if idx < len(queries) else {}
            q = q_info.get("query", "")
            ct = q_info.get("content_type", "12")
            cap = q_info.get("caption", q)
            img, found_title = _search_exact_tour_image(q, ct, used_urls)
            if not img and ct != "12":
                img, found_title = _search_exact_tour_image(q, "12", used_urls)
            media_list.append({
                "image_url": img,
                "label": found_title or cap or q,
            })
        story["chapter_media"] = media_list
        ok_cnt = sum(1 for m in media_list if m["image_url"])
        print(f"  + {prov} ({sid}): {ok_cnt}/{len(chapters)} 챕터 제목 일치 사진 매칭")

    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("[완료] 정합성 검증된 chapter_media 저장 완료")


if __name__ == "__main__":
    main()
