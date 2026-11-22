# -*- coding: utf-8 -*-
"""
자연·액티비티(kind=outdoor) 1단계: 한국관광공사 레포츠(contentTypeId=28) 시·도별 수집.

17개 시·도마다 대표 이미지가 있는 레포츠 장소를 조회순으로 PER_PROVINCE 곳까지 허브 JSON 의 spots 에 더한다.
체험형은 sub="activity", 이름으로 알 수 있는 걷기·자전거 길은 sub="trail" (거리·난이도는 두루누비 단계에서),
캠핑장·야영장·글램핑·카라반은 고르지 않는다 — 전국 캠핑장은 refresh_camping.py(고캠핑)가 camping 섹션으로 따로 모은다.
골프장·실내 체육시설·경기장·청소년 수련시설은 고르지 않는다.
기존 항목(content_id 기준)은 건드리지 않고, 다시 실행하면 모자란 시·도만 채운다.
이후 새로 등록되는 레포츠·폐업 반영은 weekly_spot_refresh.py 가 맡는다.

  python backend/collect_outdoor_spots.py --dry-run   # 시·도별로 고른 곳만 출력 (저장 안 함)
  python backend/collect_outdoor_spots.py             # 수집 + 상세 보강 + 허브 JSON 저장
  python backend/collect_outdoor_spots.py --upload    # 위 + Firestore spots 문서 생성(후기·클릭 집계용)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))
from build_travel_hub import (  # noqa: E402
    PROVINCE_17_TOUR_PARAMS,
    _tour_get,
    enrich_spots_and_festivals_details,
    upload_spots_to_firestore,
)
from collect_half_price_spots import DETAIL_CACHE, HUB_PATH, _items, _load_env, _spot_doc  # noqa: E402

PER_PROVINCE = 8  # 레포츠·걷기길

# 여행 동선에 넣기 어려운 레포츠 시설은 고르지 않는다 (관광공사 목록에 있어도 '여행 액티비티'로 보기 어렵다).
# - 회원제 위주 골프장, 실내 체육시설·경기장, 청소년 수련시설
EXCLUDE_RE = re.compile(
    r"(골프|컨트리\s?클럽|(?<![A-Za-z])(CC|GC)(?![A-Za-z])|스크린|볼링|당구|헬스|피트니스|체육관|체육센터|국민체육|"
    r"스포츠센터|축구센터|수영장|실내|경기장|운동장|야구장|축구장|볼파크|챔피언스|테니스|배드민턴|게이트볼|사격장|"
    r"경마|경륜|경정|아이스링크|롤러장|인라인|체육공원|스타디움|라이온즈|아레나|싸이클장|레이저태그|렌탈|대여점|스키샵|"
    r"수련관|수련원|청소년|교육문화관)",
    re.IGNORECASE,
)
# 캠핑장·야영장: 레포츠 목록에도 많지만 고캠핑(refresh_camping.py)이 더 정확해 여기서는 뺀다.
CAMP_RE = re.compile(r"(캠핑|캠프|글램핑|카라반|야영|오토캠)")
# 직접 해 보는 액티비티 → 먼저 고른다
ACTIVITY_RE = re.compile(
    r"(짚라인|집라인|패러|행글라이|레일바이크|루지|요트|마리나|카약|카누|서핑|SUP|래프팅|승마|번지|스카이|"
    r"케이블카|ATV|수상|해양레포츠|레저|스쿠버|다이빙|바다낚시|낚시|하강|모노레일|썰매|스키|해상)",
    re.IGNORECASE,
)
# 걷기·자전거 길 → sub="trail" (시·도당 절반까지)
# 같은 종류는 시·도당 TYPE_CAP 곳까지 (낚시터만 8곳 같은 쏠림 방지)
TYPE_CAP = 2
_TYPE_ALIASES = {"집라인": "짚라인", "마리나": "요트", "바다낚시": "낚시", "행글라이": "패러", "카누": "카약", "하강": "짚라인"}


def activity_type(title: str) -> str:
    m = ACTIVITY_RE.search(title)
    return _TYPE_ALIASES.get(m.group(1), m.group(1)) if m else ""


TRAIL_RE = re.compile(r"(둘레길|올레|누리길|나들길|바우길|구불길|해파랑길|옛길|산책로|자전거길|비렁길|꽃섬길|[가-힣]길$|\d+\s?(코스|구간))")


def is_excluded(title: str) -> bool:
    return bool(EXCLUDE_RE.search(title) or CAMP_RE.search(title))


def outdoor_sub(title: str) -> str:
    return "trail" if TRAIL_RE.search(title) else "activity"


def series_key(title: str) -> str:
    """'[대구올레 팔공산 3코스] 부인사 도보길' → '대구올레팔공산'. 같은 길 연작은 시·도당 1곳만 고른다."""
    m = re.match(r"\s*\[([^\]]+)\]", title)
    base = m.group(1) if m else title
    return re.sub(r"제?\s*\d+\s*(코스|구간)?|코스|구간|\s", "", base) if m or TRAIL_RE.search(title) else title


def _fetch_all(q: dict[str, str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for page in range(1, 4):
        body = _tour_get("areaBasedList2", {**q, "contentTypeId": "28", "numOfRows": 500, "pageNo": page, "arrange": "Q"}, timeout=30)
        got = _items(body)
        rows += got
        if not body or len(got) < 500:
            break
    return rows


def pick_for_province(cands: list[dict[str, Any]], need: int) -> list[dict[str, Any]]:
    """액티비티 우선 · 같은 종류는 2곳·길은 절반까지 · 같은 연작 1곳 · 시·군·구를 돌아가며 고른다."""
    def score(d: dict[str, Any]) -> int:
        return 2 if d["sub"] == "activity" and ACTIVITY_RE.search(d["title"]) else (1 if d["sub"] == "trail" else 0)

    buckets: dict[str, list[dict[str, Any]]] = {}
    for d in sorted(cands, key=score, reverse=True):
        buckets.setdefault(d["region_label"], []).append(d)
    order = sorted(buckets, key=lambda k: -score(buckets[k][0]))
    picked: list[dict[str, Any]] = []
    seen_series: set[str] = set()
    type_count: dict[str, int] = {}
    trail_cap = need // 2
    while len(picked) < need and any(buckets.values()):
        for k in order:
            b = buckets[k]
            while b:
                d = b.pop(0)
                sk = series_key(d["title"])
                ty = "trail" if d["sub"] == "trail" else activity_type(d["title"])
                cap = trail_cap if ty == "trail" else TYPE_CAP
                if sk in seen_series or (ty and type_count.get(ty, 0) >= cap):
                    continue
                seen_series.add(sk)
                if ty:
                    type_count[ty] = type_count.get(ty, 0) + 1
                picked.append(d)
                break
            if len(picked) >= need:
                break
    return picked


def collect(hub: dict[str, Any], per_province: int = PER_PROVINCE) -> list[dict[str, Any]]:
    existing_cids = {
        str(x.get("content_id") or "")
        for x in [*(hub.get("spots") or []), *(hub.get("festivals") or [])]
        if x.get("content_id")
    }
    have: dict[str, int] = {}
    for x in hub.get("spots") or []:
        if x.get("kind") == "outdoor" and x.get("sub") != "camping":
            have[x.get("province") or ""] = have.get(x.get("province") or "", 0) + 1

    out: list[dict[str, Any]] = []
    for prov, q_list in PROVINCE_17_TOUR_PARAMS:
        need = per_province - have.get(prov, 0)
        if need <= 0:
            continue
        cands: list[dict[str, Any]] = []
        seen: set[str] = set()
        for q in q_list:
            for it in _fetch_all(q):
                doc = _spot_doc(it, "outdoor")
                # 전남 쿼리(12)에 광주 구가 섞이는 등 시·도가 다르면 건너뛴다
                if not doc or doc["content_id"] in existing_cids or doc["content_id"] in seen or doc["province"] != prov:
                    continue
                if is_excluded(doc["title"]):
                    continue
                seen.add(doc["content_id"])
                doc["sub"] = outdoor_sub(doc["title"])
                cands.append(doc)
        picked = pick_for_province(cands, need)
        existing_cids.update(d["content_id"] for d in picked)
        out += picked
        print(f"  {prov}: 레포츠 +{len(picked)} (후보 {len(cands)})" + ("" if len(picked) >= need else f" — 목표 {need}곳 중 부족"))
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="자연·액티비티 1단계: 관광공사 레포츠 시·도별 수집")
    ap.add_argument("--dry-run", action="store_true", help="고른 곳만 출력하고 저장하지 않음")
    ap.add_argument("--upload", action="store_true", help="새 항목을 Firestore spots 에 생성(후기·클릭 집계용)")
    ap.add_argument("--per-province", type=int, default=PER_PROVINCE)
    args = ap.parse_args()

    _load_env()
    if not (os.environ.get("TOUR_API_KEY") or os.environ.get("DATA_GO_KR_SERVICE_KEY")):
        sys.exit("TOUR_API_KEY 가 없습니다 (.env)")
    if _tour_get("ldongCode2", {"numOfRows": 1, "pageNo": 1}) is None:
        sys.exit("TourAPI 응답 없음 (키 오류 또는 일일 호출 한도 초과) — 저장하지 않고 종료")

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    print("[자연·액티비티] 레포츠 수집 중...")
    new_spots = collect(hub, args.per_province)
    print(f"  → 새 레포츠·걷기길 {len(new_spots)}곳")
    if args.dry_run:
        for s in new_spots:
            print(f"    {s['province']} · {s['sub']:8} · {s['title']} · {s['region_label']}")
        return
    if not new_spots:
        return

    today = dt.date.today().strftime("%Y%m%d")
    for s in new_spots:
        s["added_at"] = today
    enrich_spots_and_festivals_details(new_spots, cache_path=str(DETAIL_CACHE))

    # Firestore 를 먼저 쓴다: 실패하면 허브도 바꾸지 않는다 (weekly_spot_refresh 와 같은 순서)
    if args.upload:
        upload_spots_to_firestore(new_spots)

    hub["spots"] = [*(hub.get("spots") or []), *new_spots]
    hub["updated_at"] = int(dt.datetime.now(dt.timezone.utc).timestamp() * 1000)
    HUB_PATH.write_text(json.dumps(hub, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[자연·액티비티] 저장: {HUB_PATH.name} ({HUB_PATH.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
