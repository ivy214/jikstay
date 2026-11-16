#!/usr/bin/env python3
"""
초기 로딩 경량화: public_travel_hub.json(원본, ~1.6MB)을
  - app/web/data/hub/core.json            목록·카드·지도·주변 거리 계산에 필요한 필드만 (첫 화면에서 로드)
  - app/web/data/hub/details_{code}.json  시·도별 상세 전용 필드 (상세 화면을 열 때 해당 시·도만 로드)
  - app/web/data/i18n/{en|ja|zh}/core.json + details_{code}.json  번역 번들도 같은 방식으로 분할
으로 나눈다.

원본 파일은 그대로 두고(번역·다이제스트·보강 스크립트가 계속 원본을 읽고 씀), 이 스크립트는 빌드 직전에 실행한다.
deploy.ps1 과 CI 배포 단계에서 자동 실행되며, 생성물(app/web/data/hub/)은 git에 올리지 않는다.

  python backend/split_hub.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
OUT_DIR = ROOT / "app" / "web" / "data" / "hub"
I18N_SRC_DIR = ROOT / "app" / "web" / "data"
I18N_OUT_DIR = ROOT / "app" / "web" / "data" / "i18n"
LANGS = ("en", "ja", "zh")
# 번역 번들에서 상세 화면에서만 쓰는 필드 (목록·카드는 title/addr/region_label/overview 미리보기/coupon_title 만 사용)
I18N_DETAIL_FIELDS = ("paragraphs", "practical_info", "practical_header", "pull_quote")

# app/lib/hub_details.dart 의 kProvinceDetailCodes 와 같아야 한다.
PROVINCE_CODES = {
    "서울": "seoul", "부산": "busan", "대구": "daegu", "인천": "incheon", "광주": "gwangju",
    "대전": "daejeon", "울산": "ulsan", "세종": "sejong", "경기": "gyeonggi", "강원": "gangwon",
    "충북": "chungbuk", "충남": "chungnam", "전북": "jeonbuk", "전남": "jeonnam", "경북": "gyeongbuk",
    "경남": "gyeongnam", "제주": "jeju",
}
OTHER_CODE = "etc"

SPLIT_SECTIONS = ("spots", "festivals")
# 상세 화면(spot_detail_sheet·story_detail_page, hydrateDiscoveryItem 으로 합침)에서만 쓰는 필드.
# 첫 화면 데이터는 볼거리 수에 비례해 커지므로(상한 없음) 카드·검색·지도·일정 짜기에 안 쓰는 필드는 모두 여기로.
# tel(자동 생성 스토리)·url(이벤트 배너)은 목록 단계에서도 쓰므로 core 에 둔다.
DETAIL_FIELDS = ("paragraphs", "naver_reviews", "practical_info", "practical_header", "images",
                 "pull_quote", "naver_link", "content_id")
OVERVIEW_PREVIEW_CHARS = 50  # 카드 부제목(1줄)·검색용 미리보기 길이 (전체는 상세 파일에)
# app/lib/trip_planner.dart 의 아침·야간 판정 키워드. 잘린 개요에서 빠지는 키워드는 'kw' 필드로 보존한다.
TRIP_KEYWORDS = ("야간", "밤길", "야경", "불빛", "별빛", "달빛", "야시장", "나이트", "night", "모닝", "아침", "새벽", "일출", "morning")


def _default_map_url(province: str, title: str) -> str:
    """앱(parseSpotJson)이 map_url 이 없을 때 만드는 기본 URL과 동일 (Dart Uri.encodeComponent 규칙)."""
    return "https://map.naver.com/p/search/" + quote(f"{province} {title}", safe="-_.!~*'()")


def _dump(path: Path, data: Any) -> int:
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    path.write_text(text, encoding="utf-8")
    return len(text.encode("utf-8"))


def split(hub: dict[str, Any]) -> tuple[dict[str, Any], dict[str, dict[str, dict[str, Any]]]]:
    core = {k: v for k, v in hub.items() if k not in SPLIT_SECTIONS}
    details: dict[str, dict[str, dict[str, Any]]] = {}
    for sec in SPLIT_SECTIONS:
        out_items = []
        for item in hub.get(sec, []):
            slim = dict(item)
            detail: dict[str, Any] = {}
            for f in DETAIL_FIELDS:
                if f in slim:
                    val = slim.pop(f)
                    if val not in (None, "", [], {}):
                        detail[f] = val
            overview = str(slim.get("overview") or "")
            if len(overview) > OVERVIEW_PREVIEW_CHARS:
                preview = overview[:OVERVIEW_PREVIEW_CHARS].rstrip()
                lost = [k for k in TRIP_KEYWORDS if k in overview.lower() and k not in preview.lower()]
                if lost:
                    slim["kw"] = lost
                detail["overview"] = overview
                slim["overview"] = preview + "…"
            if slim.get("map_url") == _default_map_url(str(slim.get("province") or ""), str(slim.get("title") or "")):
                slim.pop("map_url")
            if detail and slim.get("id"):
                slim["has_details"] = True
                code = PROVINCE_CODES.get(str(slim.get("province") or ""), OTHER_CODE)
                details.setdefault(code, {})[str(slim["id"])] = detail
            out_items.append(slim)
        core[sec] = out_items
    return core, details


def split_translations(bundle: dict[str, Any], province_of: dict[str, str]) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    """번역 번들의 items 섹션을 목록용 core 와 시·도별 상세로 나눈다 (stories·markets·stays 는 core 에 그대로)."""
    core = {k: v for k, v in bundle.items() if k != "items"}
    core_items: dict[str, Any] = {}
    details: dict[str, dict[str, Any]] = {}
    for item_id, entry in (bundle.get("items") or {}).items():
        if not isinstance(entry, dict):
            continue
        slim = dict(entry)
        detail: dict[str, Any] = {}
        for f in I18N_DETAIL_FIELDS:
            # 번역 개요가 없으면 카드 설명이 pull_quote 로 대체되므로(DiscoveryItem.tSubtitle) core 에 둔다
            if f == "pull_quote" and not slim.get("overview"):
                continue
            if f in slim:
                val = slim.pop(f)
                if val not in (None, "", [], {}):
                    detail[f] = val
        overview = str(slim.get("overview") or "")
        if len(overview) > OVERVIEW_PREVIEW_CHARS * 2:  # 외국어는 글자 수가 많아 한국어 미리보기의 2배까지
            detail["overview"] = overview
            slim["overview"] = overview[: OVERVIEW_PREVIEW_CHARS * 2].rstrip() + "…"
        if detail:
            code = PROVINCE_CODES.get(province_of.get(item_id, ""), OTHER_CODE)
            details.setdefault(code, {})[item_id] = detail
        core_items[item_id] = slim
    core["items"] = core_items
    return core, details


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    core, details = split(hub)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("details_*.json"):
        old.unlink()
    core_bytes = _dump(OUT_DIR / "core.json", core)
    detail_sizes = {code: _dump(OUT_DIR / f"details_{code}.json", d) for code, d in sorted(details.items())}

    province_of = {str(it.get("id")): str(it.get("province") or "") for sec in ("spots", "festivals") for it in hub.get(sec, [])}
    for lang in LANGS:
        src = I18N_SRC_DIR / f"translations_{lang}.json"
        if not src.exists():
            continue
        t_core, t_details = split_translations(json.loads(src.read_text(encoding="utf-8")), province_of)
        out = I18N_OUT_DIR / lang
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("details_*.json"):
            old.unlink()
        c = _dump(out / "core.json", t_core)
        for code, d in t_details.items():
            _dump(out / f"details_{code}.json", d)
        print(f"[split-i18n] {lang}: 원본 {src.stat().st_size / 1024:.0f}KB → core {c / 1024:.0f}KB + 시·도별 상세 {len(t_details)}개")

    full = len(HUB_PATH.read_bytes())
    print(f"[split-hub] 원본 {full / 1024:.0f}KB → core {core_bytes / 1024:.0f}KB "
          f"+ 시·도별 상세 {len(detail_sizes)}개 (평균 {sum(detail_sizes.values()) / max(1, len(detail_sizes)) / 1024:.0f}KB)")


if __name__ == "__main__":
    main()
