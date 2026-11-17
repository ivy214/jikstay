#!/usr/bin/env python3
"""
직스테이 로컬 다국어 번들 생성기 (EN / JA / ZH-TW).

`app/web/data/public_travel_hub.json` 과 `app/web/data/public_stays_index.json` 의
스토리·축제·볼거리·먹거리·전통시장·안심숙소 텍스트를 Gemini Flash로 일괄 번역해
언어별 온디맨드 JSON(`translations_en.json`, `translations_ja.json`, `translations_zh.json`)을 생성한다.
원문 해시 기반 캐시(`backend/translation_cache.json`)를 사용해 재실행 시 변경분만 증분 번역한다.
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import pathlib
import sys
import threading
import time
from typing import TYPE_CHECKING, Any

from google import genai
from google.genai import types

if TYPE_CHECKING:  # openai는 Gemini 키가 없을 때만 필요하므로 실행 시에는 지연 import한다.
    from openai import OpenAI

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV_PATH = ROOT / ".env"
HUB_PATH = ROOT / "app" / "web" / "data" / "public_travel_hub.json"
STAYS_PATH = ROOT / "app" / "web" / "data" / "public_stays_index.json"
OUT_DIR = ROOT / "app" / "web" / "data"
CACHE_PATH = ROOT / "backend" / "translation_cache.json"

MODEL_NAME = "gemini-3.5-flash-lite"
LANGS = ("en", "ja", "zh")

_CACHE_LOCK = threading.Lock()
GEMINI_MIN_INTERVAL_SEC = 0.0  # gemini-3.5-flash-lite: 4K RPM / 150K RPD


def load_env() -> None:
    if not ENV_PATH.exists():
        return
    for raw in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def content_hash(obj: Any) -> str:
    encoded = json.dumps(obj, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]


def load_cache() -> dict[str, Any]:
    if CACHE_PATH.exists():
        try:
            return json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {}


def save_cache(cache: dict[str, Any]) -> None:
    with _CACHE_LOCK:
        CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")


def call_llm_json(
    openai_client: OpenAI | None,
    gemini_client: genai.Client | None,
    prompt: str,
    retries: int = 4,
) -> dict[str, Any]:
    for attempt in range(retries):
        try:
            if openai_client is not None:
                resp = openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": prompt}],
                    response_format={"type": "json_object"},
                    temperature=0.2,
                )
                text = (resp.choices[0].message.content or "").strip()
            else:
                assert gemini_client is not None
                resp = gemini_client.models.generate_content(
                    model=MODEL_NAME,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        temperature=0.2,
                        http_options=types.HttpOptions(
                            timeout=45000,
                            retry_options=types.HttpRetryOptions(
                                attempts=4,
                                initial_delay=1.5,
                                max_delay=12.0,
                                http_status_codes=[429, 500, 502, 503, 504],
                            ),
                        ),
                    ),
                )
                text = (resp.text or "").strip()
            if text.startswith("```"):
                lines = text.splitlines()
                if lines[0].startswith("```"):
                    lines = lines[1:]
                if lines and lines[-1].startswith("```"):
                    lines = lines[:-1]
                text = "\n".join(lines).strip()
            return json.loads(text)
        except Exception as exc:
            if attempt == retries - 1:
                print(f"[WARN] LLM batch failed after {retries} attempts: {exc}", file=sys.stderr)
                return {}
            time.sleep(2.0 * (attempt + 1))
    return {}


def build_story_payload(st: dict[str, Any]) -> dict[str, Any]:
    return {
        "season_badge": st.get("season_badge", ""),
        "source_book": st.get("source_book", ""),
        "title": st.get("title", ""),
        "subtitle": st.get("subtitle", ""),
        "address": st.get("address", ""),
        "pull_quote": st.get("pull_quote", ""),
        "paragraphs": st.get("paragraphs", []),
        "practical_header": st.get("practical_header", ""),
        "practical_info": st.get("practical_info", []),
        "pdf_labels": [p.get("label", "") for p in st.get("pdf_links", []) if isinstance(p, dict)],
    }


def build_item_payload(it: dict[str, Any]) -> dict[str, Any]:
    return {
        "title": it.get("title", ""),
        "region_label": it.get("region_label", ""),
        "addr": it.get("addr", ""),
        "overview": it.get("overview", ""),
        "pull_quote": it.get("pull_quote", ""),
        "paragraphs": it.get("paragraphs", []),
        "practical_header": it.get("practical_header", ""),
        "practical_info": it.get("practical_info", []),
        "coupon_title": it.get("coupon_title", ""),
    }


def build_market_payload(mk: dict[str, Any]) -> dict[str, Any]:
    return {
        "title": mk.get("title", ""),
        "city": mk.get("city", ""),
        "specialty": mk.get("specialty", ""),
    }


def build_stay_payload(st: dict[str, Any]) -> dict[str, Any]:
    d1 = str(st.get("region_depth1", "") or "").strip()
    d2 = str(st.get("region_depth2", "") or "").strip()
    region = f"{d1} {d2}".strip()
    summary = str(st.get("summary_points", "") or "").strip()
    if not summary:
        summary = str(st.get("accommodation_type", "") or "").strip()
    return {
        "title": str(st.get("title", "") or "").strip(),
        "region": region,
        "summary": summary,
    }


def translate_batch(
    openai_client: OpenAI | None,
    gemini_client: genai.Client | None,
    kind: str,
    batch: list[tuple[str, dict[str, Any]]],
    cache: dict[str, Any],
) -> None:
    if not batch:
        return
    input_map = {item_id: payload for item_id, payload in batch}
    prompt = (
        "You are a professional Korean travel magazine & tourism translator.\n"
        "Translate each entry in the JSON object below into THREE languages:\n"
        "- 'en': Natural, concise English for travelers (romanize proper place names + descriptive meaning where helpful, e.g. 'Tteunbongsaem Spring, Geumgang Headwaters').\n"
        "- 'ja': Natural Japanese for travelers (カタカナ/漢字 appropriate for Korean places).\n"
        "- 'zh': Natural Traditional Chinese (繁體中文, Taiwan/HK travel style).\n"
        "Preserve exact JSON keys, array lengths, phone numbers, URLs, and time formats.\n"
        "Do NOT translate keys like 'label' and 'value' key names; only translate their string values.\n"
        "Return a JSON object with top-level keys 'en', 'ja', 'zh'. Under each language key, return a map from the exact entry ID to its translated object matching the input schema.\n\n"
        f"INPUT ({kind}):\n"
        + json.dumps(input_map, ensure_ascii=False)
    )
    res = call_llm_json(openai_client, gemini_client, prompt)
    if not isinstance(res, dict):
        return

    with _CACHE_LOCK:
        for item_id, payload in batch:
            h = content_hash(payload)
            entry_langs: dict[str, Any] = {}
            for lang in LANGS:
                lang_map = res.get(lang)
                if isinstance(lang_map, dict) and isinstance(lang_map.get(item_id), dict):
                    entry_langs[lang] = lang_map[item_id]
            if len(entry_langs) == len(LANGS):
                cache[f"{kind}:{item_id}"] = {"hash": h, "langs": entry_langs}


def process_section(
    openai_client: OpenAI | None,
    gemini_client: genai.Client | None,
    kind: str,
    records: list[tuple[str, dict[str, Any]]],
    cache: dict[str, Any],
    batch_size: int,
    max_workers: int,
) -> dict[str, dict[str, Any]]:
    pending: list[tuple[str, dict[str, Any]]] = []
    for item_id, payload in records:
        key = f"{kind}:{item_id}"
        h = content_hash(payload)
        cached = cache.get(key)
        if not (isinstance(cached, dict) and cached.get("hash") == h and isinstance(cached.get("langs"), dict)):
            pending.append((item_id, payload))

    print(f"[{kind}] total={len(records)}, cached={len(records) - len(pending)}, pending={len(pending)}", flush=True)
    if pending:
        batches = [pending[i : i + batch_size] for i in range(0, len(pending), batch_size)]
        done = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as ex:
            futures = [ex.submit(translate_batch, openai_client, gemini_client, kind, b, cache) for b in batches]
            for fut in concurrent.futures.as_completed(futures):
                fut.result()
                done += 1
                print(f"  [{kind}] batch {done}/{len(batches)} complete", flush=True)
                save_cache(cache)

    out: dict[str, dict[str, Any]] = {lang: {} for lang in LANGS}
    for item_id, _ in records:
        cached = cache.get(f"{kind}:{item_id}")
        if isinstance(cached, dict) and isinstance(cached.get("langs"), dict):
            for lang in LANGS:
                if lang in cached["langs"]:
                    out[lang][item_id] = cached["langs"][lang]
    return out


def main() -> None:
    load_env()
    gemini_key = os.environ.get("GEMINI_API_KEY", "").strip()
    openai_key = os.environ.get("OPENAI_API_KEY", "").strip()
    use_gemini = "--gemini" in sys.argv or bool(gemini_key)
    if not gemini_key and not openai_key:
        raise RuntimeError("GEMINI_API_KEY or OPENAI_API_KEY is required in .env")

    gemini_client = genai.Client(api_key=gemini_key) if (use_gemini and gemini_key) else None
    openai_client = None
    if gemini_client is None and openai_key:
        from openai import OpenAI

        openai_client = OpenAI(api_key=openai_key)
    print(f"Using provider: {'Gemini ' + MODEL_NAME if gemini_client else 'OpenAI gpt-4o-mini'}", flush=True)
    cache = load_cache()

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    stays_doc = json.loads(STAYS_PATH.read_text(encoding="utf-8"))

    story_records = [(st["id"], build_story_payload(st)) for st in hub.get("daily_stories", []) if st.get("id")]
    item_records = []
    for it in hub.get("festivals", []) + hub.get("spots", []) + hub.get("markets", []):
        if it.get("id"):
            item_records.append((str(it["id"]), build_item_payload(it)))
    market_records = [(mk["id"], build_market_payload(mk)) for mk in hub.get("traditional_markets", []) if mk.get("id")]
    stay_records = [
        (str(st["listing_id"]), build_stay_payload(st))
        for st in stays_doc.get("items", [])
        if st.get("listing_id")
    ]

    workers = 8
    item_bs = 8
    stay_bs = 35

    stories_out = process_section(openai_client, gemini_client, "story", story_records, cache, batch_size=3, max_workers=workers)
    items_out = process_section(openai_client, gemini_client, "item", item_records, cache, batch_size=item_bs, max_workers=workers)
    markets_out = process_section(openai_client, gemini_client, "market", market_records, cache, batch_size=20, max_workers=workers)
    if "--skip-stays" in sys.argv:
        stays_out = {lang: {} for lang in LANGS}
    else:
        stays_out = process_section(openai_client, gemini_client, "stay", stay_records, cache, batch_size=stay_bs, max_workers=workers)

    save_cache(cache)

    for lang in LANGS:
        bundle = {
            "lang": lang,
            "stories": stories_out[lang],
            "items": items_out[lang],
            "markets": markets_out[lang],
            "stays": stays_out[lang],
        }
        out_file = OUT_DIR / f"translations_{lang}.json"
        out_file.write_text(json.dumps(bundle, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        size_kb = out_file.stat().st_size / 1024
        print(
            f"Wrote {out_file.name}: {size_kb:.1f} KB "
            f"(stories={len(stories_out[lang])}, items={len(items_out[lang])}, "
            f"markets={len(markets_out[lang])}, stays={len(stays_out[lang])})"
        )


if __name__ == "__main__":
    main()
