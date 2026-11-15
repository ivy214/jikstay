# -*- coding: utf-8 -*-
"""
각 웹 매거진 스토리의 챕터별로 본문 내용과 정확히 일치하는 대표 사진을
TourAPI searchKeyword2로 조회하여 `chapter_media` 필드로 저장한다.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from google import genai
from google.genai import types

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import _https, _tour_get  # noqa: E402

HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"

# 서울 6개 챕터는 《2026 서울관광안내서》 실제 대표 명소로 1:1 고정
SEOUL_CHAPTER_QUERIES = [
    ("경복궁", "경복궁 · 서울 5대 고궁"),
    ("한양도성", "서울 한양도성 순성길"),
    ("국립중앙박물관", "국립중앙박물관"),
    ("여의도한강공원", "한강공원 · 서울숲"),
    ("북촌한옥마을", "북촌 한옥마을 · 서촌"),
    ("광장시장", "서울 로컬 맛 골목 · 시장"),
]


def _extract_chapter_queries_with_gemini(
    client: genai.Client, prov: str, chapters: list[str]
) -> list[tuple[str, str]]:
    numbered = "\n".join(f"{i+1}. {c[:240]}" for i, c in enumerate(chapters))
    prompt = f"""아래 '{prov}' 여행 가이드북의 각 챕터 본문을 읽고, 한국관광공사 TourAPI 키워드 검색으로 정확한 사진을 찾을 수 있는 **실제 대표 명소/음식/축제 이름 1개**씩만 뽑아주세요.
규칙:
- 반드시 TourAPI에서 검색될 법한 공식 장소명(예: "통영케이블카", "남해 독일마을", "통영 중앙시장", "진주남강유등축제", "거제 바람의언덕", "광안리해수욕장", "해운대", "자갈치시장" 등)만 적으세요.
- 추상적인 단어("힐링", "투어", "코스", "미식")는 절대 쓰지 마세요.
- JSON 배열만 출력: [{{"query": "검색할명소명", "caption": "짧은장소캡션"}}]

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
    out: list[tuple[str, str]] = []
    for item in arr:
        if isinstance(item, dict):
            q = str(item.get("query") or "").strip()
            cap = str(item.get("caption") or q).strip()
            out.append((q, cap))
    return out


def _search_tour_image(query: str, prov: str, used_urls: set[str]) -> tuple[str, str]:
    q_clean = re.sub(r"\s+", " ", query).strip()
    if not q_clean:
        return "", ""
    for kw in (q_clean, f"{prov} {q_clean}"):
        body = _tour_get("searchKeyword2", {"keyword": kw, "numOfRows": 8, "pageNo": 1, "arrange": "Q"}, timeout=8)
        if not body:
            continue
        items = (body.get("items") or {}).get("item") or []
        if isinstance(items, dict):
            items = [items]
        for it in items:
            img = _https(str(it.get("firstimage") or it.get("firstimage2") or ""))
            if not img or img in used_urls:
                continue
            title = str(it.get("title") or q_clean).strip()
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

    updated = 0
    for story in hub.get("daily_stories", []):
        paras = story.get("paragraphs") or []
        chapters = [p for p in paras if isinstance(p, str) and p.strip().startswith("【")]
        if not chapters:
            continue
        prov = str(story.get("province") or "")
        sid = str(story.get("id") or "")
        used_urls = set(story.get("images") or [])

        if sid == "story_seoul_visitseoul_guide":
            queries = SEOUL_CHAPTER_QUERIES
        elif client is not None:
            try:
                queries = _extract_chapter_queries_with_gemini(client, prov, chapters)
            except Exception as exc:
                print(f"  ! Gemini query extract failed for {prov}: {exc}")
                queries = []
        else:
            queries = []

        media_list: list[dict[str, str]] = []
        for idx, ch in enumerate(chapters):
            q, cap = queries[idx] if idx < len(queries) else ("", "")
            img, found_title = _search_tour_image(q, prov, used_urls)
            if not img and len(q.split()) > 1:
                img, found_title = _search_tour_image(q.split()[-1], prov, used_urls)
            media_list.append({
                "image_url": img,
                "label": cap or found_title or q,
            })
        story["chapter_media"] = media_list
        ok_cnt = sum(1 for m in media_list if m["image_url"])
        updated += 1
        print(f"  + {prov} ({sid}): {ok_cnt}/{len(chapters)} 챕터 정확한 대표사진 매칭 ({[m['label'] for m in media_list]})")

    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[완료] 총 {updated}개 스토리 chapter_media 저장 완료")


if __name__ == "__main__":
    main()
