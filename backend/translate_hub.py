#!/usr/bin/env python3
"""
직스테이 로컬 다국어 번들 생성기 (EN / JA / ZH-TW).

`app/web/data/public_travel_hub.json` 과 `app/web/data/public_stays_index.json` 의
스토리·축제·볼거리·먹거리·전통시장·안심숙소 텍스트를 번역해
언어별 온디맨드 JSON(`translations_en.json`, `translations_ja.json`, `translations_zh.json`)을 생성한다.
원문 해시 기반 캐시(`backend/translation_cache.json`)를 사용해 재실행 시 변경분만 증분 번역한다.

번역 엔진 (비용 순):
  1) Azure Translator 무료(F0, 월 200만 자) — AZURE_TRANSLATOR_KEY/REGION 이 있으면 스토리 외 모든 항목에 먼저 쓴다.
     한도 초과·오류가 나면 이번 실행에서는 더 쓰지 않고 2)로 넘긴다.
  2) Gemini Flash-Lite (또는 OpenAI) — 문맥이 중요한 긴 스토리, 그리고 Azure 가 처리하지 못한 나머지.

  python backend/translate_hub.py            # Azure 우선, 나머지 Gemini
  python backend/translate_hub.py --no-azure # Gemini 만
"""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import os
import pathlib
import sys
import threading
import re
import time
import urllib.error
import urllib.request
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

# Azure Translator: 사이트의 zh 는 번체(대만·홍콩) 중국어
AZURE_ENDPOINT = "https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=ko&to=en&to=ja&to=zh-Hant"
AZURE_LANG = {"en": "en", "ja": "ja", "zh-Hant": "zh"}
AZURE_MAX_TEXTS = 100        # 요청당 문장 수 (서비스 한도 1,000)
AZURE_MAX_CHARS = 5000       # 요청당 원문 글자 수
# 무료(F0) 등급은 분당 처리량 제한이 있어(넘으면 429) 요청 간격을 둔다. 과금·한도는 원문 글자 수 × 번역 언어 수.
AZURE_BILLED_CHARS_PER_MIN = 30000
AZURE_KINDS = ("item", "market", "stay")  # 스토리(긴 매거진 글)는 문맥 번역이 나은 Gemini 로
_AZURE = {"enabled": False, "chars": 0, "lock": threading.Lock()}
HANGUL_RE = re.compile(r"[가-힣]")
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
    if it.get("kind") == "culture":
        # 공연·전시(매주 수백 건씩 바뀜): 제목·지역·요약·관람 정보만
        return {
            "title": it.get("title", ""),
            "region_label": it.get("region_label", ""),
            "overview": it.get("overview", ""),
            "pull_quote": it.get("pull_quote", ""),
            "practical_header": it.get("practical_header", ""),
            "practical_info": it.get("practical_info", []),
        }
    if it.get("kind") == "market":
        # 전통시장(약 800곳)은 핵심 정보만: 긴 본문까지 번역하면 무료 번역 한도(월 200만 자)를 거의 다 쓴다.
        # 상세 화면에서 번역이 없는 본문은 한국어 원문으로 보인다.
        return {
            "title": it.get("title", ""),
            "region_label": it.get("region_label", ""),
            "overview": it.get("overview", ""),
            "practical_header": it.get("practical_header", ""),
            "practical_info": it.get("practical_info", []),
        }
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


def _collect_texts(obj: Any, out: list[str]) -> None:
    """번역할 문자열(한글이 든 것)을 순서대로 모은다. 전화번호·URL·시각처럼 한글이 없는 값은 그대로 둔다."""
    if isinstance(obj, str):
        if HANGUL_RE.search(obj):
            out.append(obj)
    elif isinstance(obj, list):
        for v in obj:
            _collect_texts(v, out)
    elif isinstance(obj, dict):
        for v in obj.values():
            _collect_texts(v, out)


def _rebuild(obj: Any, it: "iter[str]") -> Any:
    if isinstance(obj, str):
        return next(it) if HANGUL_RE.search(obj) else obj
    if isinstance(obj, list):
        return [_rebuild(v, it) for v in obj]
    if isinstance(obj, dict):
        return {k: _rebuild(v, it) for k, v in obj.items()}
    return obj


def _azure_request(texts: list[str]) -> list[dict[str, str]] | None:
    """[{en, ja, zh}] (texts 와 같은 순서). 한도 초과·인증 오류면 None 을 돌려주고 Azure 를 끈다."""
    key = os.environ.get("AZURE_TRANSLATOR_KEY", "").strip()
    region = os.environ.get("AZURE_TRANSLATOR_REGION", "").strip()
    body = json.dumps([{"Text": t} for t in texts], ensure_ascii=False).encode("utf-8")
    for attempt in range(4):
        req = urllib.request.Request(AZURE_ENDPOINT, data=body, method="POST", headers={
            "Ocp-Apim-Subscription-Key": key, "Ocp-Apim-Subscription-Region": region,
            "Content-Type": "application/json; charset=UTF-8"})
        try:
            res = json.loads(urllib.request.urlopen(req, timeout=40).read().decode("utf-8"))
            out = []
            for item in res:
                m = {AZURE_LANG[t["to"]]: t["text"] for t in item.get("translations", []) if t.get("to") in AZURE_LANG}
                out.append(m)
            n = sum(len(t) for t in texts)
            with _AZURE["lock"]:
                _AZURE["chars"] += n
            # 분당 처리량 안에 들도록 다음 요청까지 쉰다 (원문 × 3개 언어)
            time.sleep(n * 3 * 60.0 / AZURE_BILLED_CHARS_PER_MIN)
            return out
        except urllib.error.HTTPError as e:
            # 429 = 분당 처리량 초과 → 안내된 시간(없으면 60초) 쉬고 재시도 / 403 = 월 무료 한도 초과 / 401 = 키 오류 → Azure 끄기
            if e.code == 429 and attempt < 3:
                wait = e.headers.get("Retry-After") if e.headers else None
                time.sleep(float(wait) if wait and wait.isdigit() else 60.0)
                continue
            print(f"[azure] HTTP {e.code} — 이번 실행은 Azure 를 끄고 Gemini 로 넘김", file=sys.stderr)
            _AZURE["enabled"] = False
            return None
        except Exception as exc:  # 네트워크 일시 오류
            if attempt < 3:
                time.sleep(2.0 * (attempt + 1))
                continue
            print(f"[azure] {exc} — 이번 실행은 Azure 를 끄고 Gemini 로 넘김", file=sys.stderr)
            _AZURE["enabled"] = False
            return None
    return None


def azure_translate_records(kind: str, pending: list[tuple[str, dict[str, Any]]], cache: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    """Azure 로 번역해 캐시에 넣고, 못 한 항목을 돌려준다."""
    left: list[tuple[str, dict[str, Any]]] = []
    i = 0
    while i < len(pending):
        if not _AZURE["enabled"]:
            left.extend(pending[i:])
            break
        # 문장 수·글자 수 한도 안에서 항목 단위로 묶는다
        group: list[tuple[str, dict[str, Any], list[str]]] = []
        n_texts = n_chars = 0
        while i < len(pending):
            item_id, payload = pending[i]
            texts: list[str] = []
            _collect_texts(payload, texts)
            size = sum(len(t) for t in texts)
            if group and (n_texts + len(texts) > AZURE_MAX_TEXTS or n_chars + size > AZURE_MAX_CHARS):
                break
            group.append((item_id, payload, texts))
            n_texts += len(texts)
            n_chars += size
            i += 1
        flat = [t for _, _, ts in group for t in ts]
        res = _azure_request(flat) if flat else []
        if res is None or len(res) != len(flat):
            left.extend((item_id, payload) for item_id, payload, _ in group)
            continue
        pos = 0
        with _CACHE_LOCK:
            for item_id, payload, texts in group:
                part = res[pos : pos + len(texts)]
                pos += len(texts)
                langs = {lang: _rebuild(payload, iter([p.get(lang, src) for p, src in zip(part, texts)])) for lang in LANGS}
                cache[f"{kind}:{item_id}"] = {"hash": content_hash(payload), "langs": langs, "engine": "azure"}
    return left


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
    if pending and kind in AZURE_KINDS and _AZURE["enabled"]:
        before = len(pending)
        pending = azure_translate_records(kind, pending, cache)
        save_cache(cache)
        print(f"  [{kind}] Azure 번역 {before - len(pending)}건 · 남은 {len(pending)}건 → Gemini", flush=True)
    if pending and openai_client is None and gemini_client is None:
        print(f"  [{kind}] LLM 키가 없어 {len(pending)}건은 다음 실행으로", flush=True)
        pending = []
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
    _AZURE["enabled"] = (
        "--no-azure" not in sys.argv
        and bool(os.environ.get("AZURE_TRANSLATOR_KEY", "").strip())
        and bool(os.environ.get("AZURE_TRANSLATOR_REGION", "").strip())
    )
    if not gemini_key and not openai_key and not _AZURE["enabled"]:
        raise RuntimeError("AZURE_TRANSLATOR_KEY, GEMINI_API_KEY or OPENAI_API_KEY is required in .env")

    gemini_client = genai.Client(api_key=gemini_key) if (use_gemini and gemini_key) else None
    openai_client = None
    if gemini_client is None and openai_key:
        from openai import OpenAI

        openai_client = OpenAI(api_key=openai_key)
    llm = "Gemini " + MODEL_NAME if gemini_client else ("OpenAI gpt-4o-mini" if openai_client else "없음")
    print(f"Using provider: {'Azure Translator(F0) 우선 + ' if _AZURE['enabled'] else ''}{llm}", flush=True)
    cache = load_cache()

    hub = json.loads(HUB_PATH.read_text(encoding="utf-8"))
    stays_doc = json.loads(STAYS_PATH.read_text(encoding="utf-8"))

    story_records = [(st["id"], build_story_payload(st)) for st in hub.get("daily_stories", []) if st.get("id")]
    item_records = []
    for it in hub.get("festivals", []) + hub.get("spots", []) + hub.get("markets", []) + hub.get("culture", []):
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
    if _AZURE["chars"]:
        print(f"[azure] 이번 실행 원문 {_AZURE['chars']:,}자 번역 (무료 한도 월 200만 자, 세 언어 동시 번역은 원문 글자 수 × 3 으로 집계)", flush=True)

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
