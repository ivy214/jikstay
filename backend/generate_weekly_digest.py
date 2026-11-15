"""Weekly Naver Blog / SNS / Community marketing digest generator.

Reads app/web/data/public_travel_hub.json and public_stays_index.json to
generate ready-to-publish Korean blog markdown (docs/weekly_digest.md) and
short SNS / English community copy (docs/weekly_digest_sns.txt).
"""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
STAYS_PATH = ROOT / "app" / "web" / "data" / "public_stays_index.json"
DOCS_DIR = ROOT / "docs"
SITE = "https://jikstay-lkxu1.web.app"


def _parse_ymd(val: Any) -> dt.date | None:
    s = str(val or "").strip().replace("-", "").replace(".", "")
    if len(s) >= 8 and s[:8].isdigit():
        try:
            return dt.date(int(s[:4]), int(s[4:6]), int(s[6:8]))
        except ValueError:
            return None
    return None


def _upcoming_events(hub: Dict[str, Any], today: dt.date, limit: int = 8) -> List[Dict[str, Any]]:
    scored: List[tuple[int, Dict[str, Any]]] = []
    for ev in hub.get("events") or []:
        s = _parse_ymd(ev.get("event_start_date"))
        e = _parse_ymd(ev.get("event_end_date")) or s
        if e and e < today:
            continue
        if s and s > today + dt.timedelta(days=21):
            continue
        days_left = (s - today).days if s else 99
        scored.append((max(0, days_left), ev))
    scored.sort(key=lambda x: x[0])
    return [x[1] for x in scored[:limit]]


def generate_digest(today: dt.date | None = None) -> tuple[Path, Path]:
    today = today or dt.date.today()
    hub = json.loads(HUB_PATH.read_text(encoding="utf-8")) if HUB_PATH.exists() else {}
    stays_raw = json.loads(STAYS_PATH.read_text(encoding="utf-8")) if STAYS_PATH.exists() else {}
    stays = stays_raw.get("items") if isinstance(stays_raw, dict) else stays_raw
    stays = stays if isinstance(stays, list) else []

    events = _upcoming_events(hub, today, limit=6)
    DOCS_DIR.mkdir(parents=True, exist_ok=True)

    week_label = today.strftime("%Y년 %m월 %d일")
    md_lines = [
        f"# 이번 주말 국내여행 · 지역 축제 & 수수료 0원 숙소 총정리 ({week_label} 기준)",
        "",
        "이번 주 바로 떠나기 좋은 **개막·진행 중 지역 축제**와 **주변 로컬 맛집 · 정부/지자체 검증 합법 숙소(중개수수료 0원)** 코스를 한눈에 정리했습니다.",
        "",
        "## 1. 이번 주 주목할 지역 축제·행사 TOP 6",
        "",
    ]

    for idx, ev in enumerate(events, 1):
        title = ev.get("title", "지역 축제")
        prov = ev.get("province", "")
        period = f"{ev.get('event_start_date', '')} ~ {ev.get('event_end_date', '')}".strip(" ~")
        eid = ev.get("id", "")
        link = f"{SITE}/?spot={quote(str(eid))}" if eid else f"{SITE}/?region={quote(str(prov))}"
        md_lines.append(f"{idx}. **[{prov}] {title}** ({period or '일정 확인'})")
        md_lines.append(f"   - 주변 맛집·합법숙소·오시는 길 바로보기: {link}")

    top_prov = events[0].get("province", "전북") if events else "전북"
    prov_stays = [s for s in stays if top_prov in str(s.get("region_depth1", ""))][:3]
    plan_url = f"{SITE}/?plan=d2:{quote(top_prov)}:festival:0:"
    md_lines.extend([
        "",
        f"## 2. 추천 주말 1박2일 코스 ({top_prov} 중심)",
        f"- **원클릭 주말 코스 열기**: {plan_url}",
        "- 토요일 오전: 지역 공식 가이드북 명소 산책 → 점심: 로컬 5일장·대표 맛집 → 오후: 메인 축제 관람 → 숙박: 수수료 0원 합법 숙소",
        "",
        f"### {top_prov} 직거래·공공 검증 숙소 예시",
    ])
    for st in prov_stays:
        sid = st.get("id", "")
        stitle = st.get("title", "숙소")
        md_lines.append(f"- **{stitle}**: {SITE}/?id={quote(str(sid))}")

    md_lines.extend([
        "",
        "---",
        "#국내여행 #주말여행 #1박2일여행코스 #지역축제 #직스테이로컬 #수수료없는숙소 #반값여행",
    ])

    md_path = DOCS_DIR / "weekly_digest.md"
    md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")

    # SNS / Global Reddit / Threads short copy
    sns_lines = [
        f"[이번 주 주말 어디 갈까? ({week_label})]",
        f"이번 주 개막/진행 중인 지역 축제 {len(events)}선 + 주변 수수료 0원 합법 숙소 코스!",
        *[f"• [{e.get('province', '')}] {e.get('title', '')}" for e in events[:4]],
        f"👉 내 주말 1박2일 코스 자동 생성: {SITE}/",
        "",
        "--- [English / Global Community Copy (Reddit r/koreatravel, X)] ---",
        f"Planning a Korea trip? Check this week's local festivals & government-verified legal stays (0% guest OTA fee):",
        f"👉 Korea 3-Day / 5-Day Trip Planner: {SITE}/?lang=en",
    ]
    sns_path = DOCS_DIR / "weekly_digest_sns.txt"
    sns_path.write_text("\n".join(sns_lines) + "\n", encoding="utf-8")
    return md_path, sns_path


if __name__ == "__main__":
    md_p, sns_p = generate_digest()
    print(f"Generated weekly digest: {md_p}, {sns_p}")
