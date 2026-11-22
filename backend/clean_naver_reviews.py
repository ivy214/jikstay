#!/usr/bin/env python3
"""
public_travel_hub.json 의 '네이버 방문기'(naver_reviews) 중 장소와 무관한 글을 걸러낸다.

- 판정 기준은 build_travel_hub.is_relevant_place_snippet (장소 핵심 이름이 글 제목에 있어야 함 등).
- 상세 보강 캐시(spot_editorial_detail_cache.json)도 같이 정리해, 다시 빌드해도 무관한 글이 돌아오지 않게 한다.
- --refetch: 정리 후 방문기가 0건이 된 장소만 새 필터로 다시 검색한다(장소당 블로그 API 1회).

사용법
  python backend/clean_naver_reviews.py --dry-run
  python backend/clean_naver_reviews.py --refetch
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from build_travel_hub import _fetch_naver_place_blog_snippets, is_relevant_place_snippet

ROOT = Path(__file__).resolve().parent.parent
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
CACHE_PATH = ROOT / "output" / "curated_stays_cache" / "spot_editorial_detail_cache.json"


def _filter(rec: dict[str, Any]) -> tuple[int, int]:
    reviews = rec.get("naver_reviews") or []
    kept = [
        r for r in reviews
        if is_relevant_place_snippet(
            str(rec.get("title") or ""), str(rec.get("region_label") or ""), str(rec.get("province") or ""), r
        )
    ]
    if reviews:
        rec["naver_reviews"] = kept
    return len(reviews), len(kept)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--refetch", action="store_true", help="방문기가 0건이 된 장소를 새 필터로 다시 검색")
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    records = list(hub.get("spots", [])) + list(hub.get("festivals", []))

    before = after = 0
    emptied: list[dict[str, Any]] = []
    for rec in records:
        b, a = _filter(rec)
        before += b
        after += a
        if b and not a:
            emptied.append(rec)
    print(f"[hub] 방문기 {before}건 → {after}건 (제거 {before - after}), 0건이 된 장소 {len(emptied)}곳")

    refetched = 0
    if args.refetch and not args.dry_run:
        for rec in emptied:
            kind = str(rec.get("kind") or "attraction")
            suffix = "후기" if kind in ("food", "attraction", "outdoor") else "일정 후기"
            region = str(rec.get("region_label") or rec.get("province") or "")
            title = str(rec.get("title") or "")
            found = _fetch_naver_place_blog_snippets(
                f"{region} {title} {suffix}".strip(),
                max_items=2,
                place_title=title,
                region_label=region,
                province=str(rec.get("province") or ""),
            )
            if found:
                rec["naver_reviews"] = found
                refetched += 1
        print(f"[hub] 재검색으로 방문기를 다시 찾은 장소 {refetched}/{len(emptied)}곳")

    # 캐시 정리: 키는 "{kind}:{content_id 또는 title}" — 허브 레코드의 결과를 그대로 반영한다.
    cache_fixed = 0
    if CACHE_PATH.exists():
        cache = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        by_key = {}
        for rec in records:
            cid = str(rec.get("content_id") or "").strip()
            by_key[f"{rec.get('kind') or 'attraction'}:{cid or rec.get('title')}"] = rec
        for key, info in cache.items():
            if not isinstance(info, dict) or not info.get("naver_reviews"):
                continue
            rec = by_key.get(key)
            if rec is not None:
                new = rec.get("naver_reviews") or []
            else:
                title = key.split(":", 1)[-1]
                new = [r for r in info["naver_reviews"] if is_relevant_place_snippet(title, "", "", r)]
            if new != info["naver_reviews"]:
                info["naver_reviews"] = new
                cache_fixed += 1
        if not args.dry_run:
            CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[cache] 방문기 정리 {cache_fixed}건")

    if args.dry_run:
        print("--dry-run: 저장하지 않았습니다.")
        return
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("저장 완료:", HUB_PATH.name)


if __name__ == "__main__":
    main()
