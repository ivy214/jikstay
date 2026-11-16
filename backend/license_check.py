"""공공 인허가 데이터 대조 + 정기 재확인.

데이터 출처: 공공데이터포털(행정안전부 지방 인허가 정보).
  예) 행정안전부_문화_농어촌민박업 조회서비스 https://www.data.go.kr/data/15155113/openapi.do
      기본 URL https://apis.data.go.kr/1741000/rural_homestays  (사업장명·허가일자·주소·영업상태)
  다른 업종(외국인관광도시민박업, 한옥체험업, 숙박업)도 같은 계열 서비스가 있으므로,
  공공데이터포털에서 활용신청 후 URL을 환경변수로 지정한다.

환경변수
  DATA_GO_KR_SERVICE_KEY      공공데이터포털 서비스키(디코딩 키)
  LICENSE_API_RURAL           농어촌민박업 API URL (기본값 위 URL)
  LICENSE_API_FOREIGN         외국인관광도시민박업 API URL
  LICENSE_API_HANOK           한옥체험업 API URL
  LICENSE_API_LODGING         숙박업 API URL
API 대신 공공데이터포털에서 받은 CSV로 대조할 수도 있다: --csv 파일경로

[한계] 공공 데이터에는 '영업신고번호'가 없을 수 있어 사업장명·주소·영업상태로 대조한다.
숙소 문서에 수집 당시의 인허가 관리번호(public_mng_no)가 있으면 그 번호로 정확히 대조한다. 응답 필드명은 문서에 명시되지 않아
여러 이름 후보로 읽으므로, 첫 사용 때 `python license_check.py probe 농어촌민박업 <상호>` 로
실제 응답을 확인할 것.

사용
  python license_check.py probe 농어촌민박업 "바다집"
  python license_check.py check stay_pub_xxxxxxxx [--csv data.csv]   # 숙소 1곳 대조(저장 안 함)
  python license_check.py recheck [--csv data.csv] [--prune-index]    # 공개 중인 전체 숙소 재확인 (+ 정적 색인 맞춤)
  python license_check.py prune-index                                  # 정적 색인을 Firestore 상태에 맞춤(제외·복원)
  python license_check.py recheck --rotate 4                           # 인허가 출처는 이번 주 1/4 그룹만
  python license_check.py link-kto [--apply]                           # (한 번) 관광공사 출처 숙소의 실제 인허가 찾기
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re

import requests
from firebase_admin import firestore

import env  # noqa: F401  (.env 로드)

API_ENV = {
    "농어촌민박업": ("LICENSE_API_RURAL", "https://apis.data.go.kr/1741000/rural_homestays"),
    "외국인관광도시민박업": ("LICENSE_API_FOREIGN", None),
    "한옥체험업": ("LICENSE_API_HANOK", None),
    "일반/생활숙박업": ("LICENSE_API_LODGING", None),
    # 관광진흥법 등록 업종 (관광호텔·휴양콘도·호스텔 등 / 관광펜션). 2026-11-16 활용신청 승인, 필드 이름은 위와 같음
    "관광숙박업": ("LICENSE_API_TOURIST_ACCOMMODATION", "https://apis.data.go.kr/1741000/tourist_accommodations"),
    "관광펜션업": ("LICENSE_API_TOURIST_PENSION", "https://apis.data.go.kr/1741000/tourist_pensions"),
}

NAME_KEYS = ("BPLC_NM", "bplcNm", "bplcnm", "사업장명")
ADDR_KEYS = ("ROAD_NM_ADDR", "LOTNO_ADDR", "SITE_WHL_ADDR", "RDN_WHL_ADDR", "rdnWhlAddr", "siteWhlAddr",
             "도로명전체주소", "소재지전체주소", "사업장주소", "도로명주소", "지번주소")
STATUS_KEYS = ("SALS_STTS_NM", "DTL_SALS_STTS_NM", "salsSttsNm", "trdStateNm", "dtlStateNm",
               "영업상태명", "상세영업상태명", "영업상태")
DATE_KEYS = ("LCPMT_YMD", "apvPermYmd", "인허가일자", "허가일자")

OK_WORDS = ("영업", "정상")
BAD_WORDS = ("폐업", "휴업", "취소", "말소", "정지")


def _first(row: dict, keys) -> str:
    for k in keys:
        if row.get(k):
            return str(row[k]).strip()
    # 키 이름이 다를 때를 대비한 느슨한 탐색
    for k, v in row.items():
        if any(t.lower() in k.lower() for t in keys) and v:
            return str(v).strip()
    return ""


def _find_rows(obj) -> list[dict]:
    """응답 JSON 어디에 있든 사업장명을 가진 dict 목록을 찾는다."""
    if isinstance(obj, list):
        if obj and all(isinstance(x, dict) for x in obj) and any(_first(x, NAME_KEYS) for x in obj):
            return obj
        for x in obj:
            r = _find_rows(x)
            if r:
                return r
    elif isinstance(obj, dict):
        if _first(obj, NAME_KEYS) and len(obj) > 2:
            return [obj]
        for v in obj.values():
            r = _find_rows(v)
            if r:
                return r
    return []


def _api_url(license_type: str) -> str | None:
    env, default = API_ENV.get(license_type, (None, None))
    return os.environ.get(env, default) if env else None


RETRY_STATUS = {429, 500, 502, 503, 504}


def _get_with_retry(url: str, params: dict, tries: int = 3, timeout: int = 30) -> requests.Response:
    """인허가 API 는 동시 조회 시 응답이 느려 시간 초과·5xx·429 가 잦다 → 잠깐 쉬었다가 다시 시도한다.
    (일일 호출 한도 초과는 200 + 오류 본문이라 재시도해도 소용없으므로 그대로 돌려준다.)"""
    import time

    for attempt in range(tries):
        try:
            r = requests.get(url, params=params, timeout=timeout)
            if r.status_code not in RETRY_STATUS or attempt == tries - 1:
                return r
        except requests.RequestException:
            if attempt == tries - 1:
                raise
        time.sleep(3 * (attempt + 1))
    raise RuntimeError("unreachable")


def query_api(license_type: str, business_name: str, max_pages: int = 5, field: str = "BPLC_NM") -> list[dict]:
    """field 조건으로 LIKE 검색. 기본은 상호(BPLC_NM), 주소로 찾을 때는 field="ROAD_NM_ADDR"."""
    url = _api_url(license_type)
    key = os.environ.get("DATA_GO_KR_SERVICE_KEY")
    if not url or not key:
        raise RuntimeError(f"{license_type}: API URL 또는 DATA_GO_KR_SERVICE_KEY 미설정 (--csv 로 대조 가능)")

    # 실제 조회 경로는 '<엔드포인트>/info' (기본 경로는 400 NO_OPENAPI_SERVICE_ERROR, 2026-11 확인)
    base = url.rstrip("/").removesuffix("/info")
    all_rows: list[dict] = []
    per_page = 100

    for page in range(1, max_pages + 1):
        params = {"serviceKey": key, "pageNo": page, "numOfRows": per_page, "returnType": "json",
                  f"cond[{field}::LIKE]": business_name}
        last = None
        batch = None
        candidates = (base + "/info", base) if page == 1 else (base + "/info",)
        for candidate in candidates:
            r = _get_with_retry(candidate, params)
            last = r
            if r.status_code == 200:
                try:
                    batch = _find_rows(r.json())
                    break
                except ValueError:
                    continue
        if batch is None:
            if page > 1:
                break
            # requests.Response 는 4xx/5xx 일 때 bool 이 False 이므로 'is not None' 으로 검사해야 한다
            detail = f"{last.status_code}: {last.text[:300]}" if last is not None else ""
            if last is not None and last.status_code in (401, 403):
                detail += " (공공데이터포털에서 이 API의 활용신청·승인 여부를 확인하세요)"
            raise RuntimeError(f"API 응답 오류 {detail}")
        all_rows.extend(batch)
        if len(batch) < per_page:
            break
    return all_rows


def query_csv(path: str, business_name: str) -> list[dict]:
    target = _norm(business_name)
    rows = []
    for enc in ("utf-8-sig", "cp949"):
        try:
            with open(path, encoding=enc, newline="") as f:
                for row in csv.DictReader(f):
                    if target and target in _norm(_first(row, NAME_KEYS)):
                        rows.append(row)
            return rows
        except UnicodeDecodeError:
            rows = []
    return rows


def _norm(s: str) -> str:
    return re.sub(r"[\s()\[\]·.,\-]", "", s or "")


def _addr_tokens(addr: str) -> set[str]:
    return {t for t in re.split(r"[\s,()]+", addr or "") if len(t) >= 2}


def evaluate(business_name: str, business_address: str, rows: list[dict]) -> dict:
    best, best_score, best_overlap = None, -1.0, 0
    a = _addr_tokens(business_address)
    for row in rows:
        name = _first(row, NAME_KEYS)
        score = 0.0
        if _norm(name) == _norm(business_name):
            score += 2
        elif _norm(business_name) in _norm(name):
            score += 1
        # 도로명·지번 주소 중 신청 주소와 더 많이 겹치는 쪽으로 계산
        best_addr, overlap = 0.0, 0
        for k in ADDR_KEYS:
            b = _addr_tokens(str(row.get(k) or ""))
            if a and b:
                ov = len(a & b)
                ratio = ov / len(a)
                if ratio > best_addr:
                    best_addr, overlap = ratio, ov
        score += 2 * best_addr
        if score > best_score:
            best, best_score, best_overlap = row, score, overlap

    if not best:
        return {"result": "not_found", "score": 0, "candidates": 0}
    status = _first(best, STATUS_KEYS)
    status_ok = any(w in status for w in OK_WORDS) and not any(w in status for w in BAD_WORDS)
    closed = any(w in status for w in BAD_WORDS)
    # 시/도·시/군/구만 겹치는 동명이인 오판 방지: 최소 3개 토큰(읍/면/동·도로명 포함) 또는 짧은 주소 전체 일치 필요
    addr_strong = bool(a) and (best_overlap >= 3 if len(a) >= 3 else best_overlap == len(a))
    strong = best_score >= 3.2 and addr_strong
    result = "closed" if (strong and closed) else ("match" if (strong and status_ok) else "uncertain")
    return {
        "result": result,
        "score": round(best_score, 2),
        "candidates": len(rows),
        "matched_name": _first(best, NAME_KEYS),
        "matched_address": _first(best, ADDR_KEYS),
        "matched_status": status,
        "matched_permit_date": _first(best, DATE_KEYS),
        "matched_closed_date": str(best.get("CLSBIZ_YMD") or ""),
        "matched_mng_no": str(best.get("MNG_NO") or ""),  # 인허가 관리번호(검증 기록용)
    }


def _status_result(status: str) -> str:
    if any(w in status for w in BAD_WORDS):
        return "closed"
    if any(w in status for w in OK_WORDS):
        return "match"
    return "uncertain"


def check_listing(doc: dict, csv_path: str | None = None) -> dict:
    """공개 숙소 문서(상호·주소·업종·관리번호)를 공공 인허가 데이터와 대조한다."""
    name = str(doc.get("title") or "")
    loc = doc.get("location_info") or {}
    addr = str(loc.get("display_address") or loc.get("lot_address") or "")
    if not name or not doc.get("license_type"):
        return {"result": "error", "error": "숙소 문서에 상호 또는 업종이 없습니다."}
    try:
        rows = query_csv(csv_path, name) if csv_path else query_api(str(doc["license_type"]), name)
    except Exception as e:  # noqa: BLE001
        return {"result": "error", "error": str(e)[:300], "source": "csv" if csv_path else "api"}

    mng_no = str(doc.get("public_mng_no") or "")
    if mng_no.startswith("KTO-"):  # 한국관광공사 콘텐츠 ID — 행안부 인허가 관리번호가 아님
        mng_no = ""
    exact = [r for r in rows if mng_no and str(r.get("MNG_NO") or "") == mng_no]
    if exact:
        # 수집 당시와 같은 인허가 관리번호 → 동명이인 걱정 없이 영업상태만 본다.
        status = _first(exact[0], STATUS_KEYS)
        out = {
            "result": _status_result(status),
            "score": 9.0,
            "candidates": len(rows),
            "matched_name": _first(exact[0], NAME_KEYS),
            "matched_address": _first(exact[0], ADDR_KEYS),
            "matched_status": status,
            "matched_closed_date": str(exact[0].get("CLSBIZ_YMD") or ""),
            "matched_mng_no": mng_no,
            "matched_by": "mng_no",
        }
    else:
        out = evaluate(name, addr, rows)
        out["matched_by"] = "name_address"
    out["source"] = "csv" if csv_path else "api"
    return out


def is_kto(doc: dict) -> bool:
    """한국관광공사 TourAPI 에서 보충한 숙소(관리번호 'KTO-<콘텐츠ID>'). 업종은 관광공사 분류로 추정한 값이라
    그 업종 API 에서 상호를 찾으면 대부분 not_found 가 된다 → 인허가 대조 대신 관광공사 목록 기준으로 확인한다."""
    return str(doc.get("public_mng_no") or "").startswith("KTO-")


def rotation_bucket(listing_id: str, n: int) -> int:
    """숙소 ID 로 정한 고정 그룹(0..n-1). 매주 한 그룹씩 → n 주에 한 번씩 전체가 검사된다."""
    return int(hashlib.md5(listing_id.encode("utf-8")).hexdigest(), 16) % max(1, n)


def current_rotation(n: int, today: dt.date | None = None) -> int:
    return (today or dt.date.today()).isocalendar()[1] % max(1, n)


def fetch_kto_stay_ids() -> set[str] | None:
    """관광공사 TourAPI 에 현재 등록된 숙박(searchStay2) content id 전체. 한 페이지라도 실패하면 None."""
    from build_travel_hub import _tour_get

    ids: set[str] = set()
    page = 1
    while True:
        body = _tour_get("searchStay2", {"numOfRows": 1000, "pageNo": page, "arrange": "A"}, timeout=60)
        if body is None:
            return None
        raw = body.get("items") or {}
        items = (raw.get("item") if isinstance(raw, dict) else None) or []
        if isinstance(items, dict):
            items = [items]
        ids.update(str(it.get("contentid") or "") for it in items)
        if not items or page * 1000 >= int(body.get("totalCount") or 0):
            break
        page += 1
    ids.discard("")
    return ids


def check_kto_listing(doc: dict, live: set[str]) -> dict:
    cid = str(doc.get("public_mng_no") or "").removeprefix("KTO-")
    if cid and cid in live:
        return {"result": "match", "source": "tourapi"}
    return {"result": "kto_missing", "source": "tourapi", "error": f"관광공사 숙박 목록에서 사라짐 (content id {cid})"}


# 관광공사 목록에 여전히 있을 때 풀어도 되는 '확인 필요' 사유 (예전 인허가 대조 결과 포함).
# 그 밖의 사유(예: 다른 업종에서 폐업으로 확인된 license_closed)는 관광공사 목록만으로 풀지 않는다.
KTO_CLEARABLE = {"kto_missing", "not_found", "uncertain", "error"}


def plan_update(doc: dict, res: dict) -> dict | None:
    """대조 결과로 숙소 문서에서 바꿀 필드. 이미 같은 상태면 None(쓰기 생략).
    매주 숙소를 조회하지만, Firestore 에는 상태가 바뀐 숙소만 쓴다."""
    result = res.get("result")
    flagged = doc.get("needs_review") is True
    reason = doc.get("needs_review_reason")

    if doc.get("status") == "suspended":
        # 노출 중지 숙소: 다시 '영업'으로 확인되면 관리자 확인 대상으로만 표시한다(자동 재공개 안 함)
        if result == "match":
            if flagged and reason == "reopened":
                return None
            return {"needs_review": True, "needs_review_reason": "reopened",
                    "needs_review_detail": f"공공 인허가 데이터 영업상태: {res.get('matched_status')} — 재공개 검토"}
        if result == "closed" and flagged and reason == "reopened":
            return {"needs_review": False, "needs_review_reason": firestore.DELETE_FIELD,
                    "needs_review_detail": firestore.DELETE_FIELD}
        return None

    if result == "closed":
        return {
            "status": "suspended",
            "suspended_reason": f"공공 인허가 데이터 영업상태: {res.get('matched_status')}",
            "suspended_at": firestore.SERVER_TIMESTAMP,
            "last_license_check": res,
        }
    if result == "match":
        if res.get("source") == "tourapi" and reason and reason not in KTO_CLEARABLE:
            return None
        if flagged or "needs_review_reason" in doc or "needs_review_detail" in doc:
            return {
                "needs_review": False,
                "needs_review_reason": firestore.DELETE_FIELD,
                "needs_review_detail": firestore.DELETE_FIELD,
            }
        return None
    # not_found / uncertain / error / kto_missing — 사유 분류가 같으면 다시 쓰지 않는다 (오류 문구는 매번 달라 비교에서 뺌)
    if flagged and reason == result:
        return None
    upd = {"needs_review": True, "needs_review_reason": result}
    upd["needs_review_detail"] = str(res["error"])[:300] if res.get("error") else firestore.DELETE_FIELD
    return upd


def recheck_all(csv_path: str | None = None, workers: int = 1, max_error_ratio: float = 0.2,
                flush_every: int = 100, rotate: int = 1, max_kto_missing_ratio: float = 0.1) -> dict:
    """숙소 재확인.

    - 행안부 인허가 출처: 인허가 API(또는 CSV)로 영업상태 대조. 폐업·휴업이 확실하면 노출 중지(suspended),
      판단 불가(not_found/uncertain/error)는 '확인 필요' 표시만. 노출 중지 숙소도 다시 조회해 영업 중이면 'reopened' 표시.
      rotate=N 이면 숙소 ID 로 나눈 N 개 그룹 중 이번 주 그룹만 검사한다(N 주에 한 번씩 전체).
    - 관광공사 출처(KTO-): 매주 전체를 TourAPI 숙박 목록과 대조(한 번에 받는 목록이라 비용이 거의 없음).
      목록에서 사라지면 'kto_missing' 표시만 한다. 사라진 비율이 max_kto_missing_ratio 를 넘으면 API 이상으로 보고 건너뛴다.

    - 결과는 flush_every 건마다 바로 저장하고, 저장 직전에 문서를 다시 읽어 그사이 바뀐 숙소는 건너뛴다.
    - 상태가 바뀐 숙소만 쓴다(plan_update).
    - 인허가 조회 오류는 모아 두었다가, 오류 비율이 max_error_ratio 이하일 때만 '확인 필요'로 표시한다."""
    from concurrent.futures import ThreadPoolExecutor

    from firebase_client import db

    snaps = list(db().collection("listings").where("status", "in", ["active", "suspended"]).stream())
    week = current_rotation(rotate)
    kto_snaps = [s for s in snaps if is_kto(s.to_dict() or {}) and (s.to_dict() or {}).get("status") == "active"]
    lic_snaps = [s for s in snaps if not is_kto(s.to_dict() or {})
                 and (rotate <= 1 or rotation_bucket(s.id, rotate) == week)]
    counts = {"checked": 0, "match": 0, "closed": 0, "review": 0, "error": 0, "kto_checked": 0, "kto_missing": 0,
              "written": 0, "unchanged": 0, "skipped_stale": 0, "skipped_error": 0, "skipped_kto": 0}

    def _flush(items):
        if not items:
            return
        fresh = {s.id: s for s in db().get_all([snap.reference for snap, _ in items])}
        batch, ops = db().batch(), 0
        for snap, res in items:
            cur = fresh.get(snap.id)
            cur_doc = (cur.to_dict() or {}) if cur is not None and cur.exists else None
            if cur_doc is None or cur_doc.get("status") != (snap.to_dict() or {}).get("status"):
                counts["skipped_stale"] += 1  # 그사이 삭제됐거나 관리자가 상태를 바꿈
                continue
            upd = plan_update(cur_doc, res)
            if upd is None:
                counts["unchanged"] += 1
                continue
            batch.update(cur.reference, upd)
            ops += 1
            title = cur_doc.get("title")
            if upd.get("status") == "suspended":
                print(f"노출 중지: {snap.id} {title} ({res.get('matched_status')})")
            elif upd.get("needs_review_reason") == "reopened":
                print(f"재개 검토: {snap.id} {title} ({res.get('matched_status')})")
            elif upd.get("needs_review") is False:
                print(f"확인 해제: {snap.id} {title}")
            else:
                print(f"확인 필요: {snap.id} {title} ({res['result']}{': ' + str(res['error'])[:80] if res.get('error') else ''})")
        if ops:
            batch.commit()
            counts["written"] += ops

    # 1) 관광공사 출처 — TourAPI 숙박 목록에 남아 있는지
    if kto_snaps:
        live = fetch_kto_stay_ids()
        if live is None:
            counts["skipped_kto"] = len(kto_snaps)
            print(f"[경고] 관광공사 숙박 목록 조회 실패 — 관광공사 출처 {len(kto_snaps)}곳은 이번 주 건너뜀")
        else:
            kto_results = [(s, check_kto_listing(s.to_dict() or {}, live)) for s in kto_snaps]
            missing = sum(1 for _, r in kto_results if r["result"] == "kto_missing")
            counts["kto_checked"], counts["kto_missing"] = len(kto_results), missing
            if missing / len(kto_results) > max_kto_missing_ratio:
                counts["skipped_kto"] = len(kto_results)
                print(f"[경고] 관광공사 목록에서 사라진 숙소 {missing}/{len(kto_results)}곳 — 비율이 너무 높아 API 이상으로 보고 건너뜀")
            else:
                for i in range(0, len(kto_results), flush_every):
                    _flush(kto_results[i:i + flush_every])

    # 2) 행안부 인허가 출처 — 인허가 API 로 영업상태 대조
    def _work(snap):
        try:
            return snap, check_listing(snap.to_dict() or {}, csv_path)
        except Exception as e:  # noqa: BLE001
            return snap, {"result": "error", "error": str(e)[:300], "source": "csv" if csv_path else "api"}

    pending, deferred = [], []
    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        for snap, res in pool.map(_work, lic_snaps):  # 제출 순서로 받지만, 조회는 병렬로 진행된다
            counts["checked"] += 1
            r = res["result"]
            counts["review" if r in ("not_found", "uncertain") else r] += 1
            if r == "error" and res.get("source"):  # 조회 오류(상호·업종 누락 같은 문서 문제는 바로 표시)
                deferred.append((snap, res))
                continue
            pending.append((snap, res))
            if len(pending) >= flush_every:
                _flush(pending)
                pending = []
    _flush(pending)

    api_errors = len(deferred)
    api_broken = counts["checked"] > 0 and api_errors / counts["checked"] > max_error_ratio
    if api_broken:
        counts["skipped_error"] = api_errors
        print(f"[경고] 인허가 조회 오류 {api_errors}/{counts['checked']}건(기준 {max_error_ratio:.0%} 초과) "
              "— 키·호출 한도·API 장애로 보고 오류 건은 표시하지 않습니다.")
    else:
        for i in range(0, len(deferred), flush_every):
            _flush(deferred[i:i + flush_every])

    group = f"{week + 1}/{rotate} 그룹" if rotate > 1 else "전체"
    summary = (f"재확인 완료 — 인허가 출처 {group} {counts['checked']}곳: 정상 {counts['match']} · 폐업·휴업 {counts['closed']} · "
               f"판단 불가 {counts['review']} · 오류 {counts['error']} | 관광공사 출처 {counts['kto_checked']}곳: "
               f"목록에서 사라짐 {counts['kto_missing']} → 저장 {counts['written']}건 "
               f"(변화 없음 {counts['unchanged']} · 도중 변경으로 건너뜀 {counts['skipped_stale']}"
               + (f" · 오류 표시 생략 {counts['skipped_error']}" if counts["skipped_error"] else "")
               + (f" · 관광공사 확인 생략 {counts['skipped_kto']}" if counts["skipped_kto"] else "") + ")")
    print(summary)
    try:  # 실행 기록은 숙소마다가 아니라 문서 하나에만 남긴다
        db().collection("meta").document("license_recheck").set(
            {**counts, "api_broken": api_broken, "source": "csv" if csv_path else "api",
             "rotate": rotate, "rotation_group": week if rotate > 1 else None,
             "finished_at": firestore.SERVER_TIMESTAMP})
    except Exception as e:  # noqa: BLE001
        print(f"[경고] 실행 기록 저장 실패: {str(e)[:160]}")
    if api_broken:
        raise RuntimeError(summary + " — 인허가 조회 오류가 많아 일부만 반영됨")
    return counts


_HERE = os.path.dirname(os.path.abspath(__file__))
INDEX_PATH = os.path.join(_HERE, "..", "app", "web", "data", "public_stays_index.json")
# 노출 중지로 색인에서 뺀 숙소 원본. 다시 active 가 되면 여기서 색인으로 되돌린다.
HELD_PATH = os.path.join(_HERE, "stays_index_suspended.json")


def plan_index_sync(items: list[dict], held: list[dict], status: dict[str, str]) -> tuple[list[dict], list[dict], int, int]:
    """(새 색인 항목, 새 보류 항목, 뺀 수, 되돌린 수).
    - 색인: Firestore 상태가 active 가 아닌 숙소를 뺀다(문서가 없으면 판단할 수 없어 그대로 둔다).
    - 보류: Firestore 에서 다시 active 가 된 숙소는 색인으로 되돌린다.
      색인을 새로 만들어(curate_public_stays) 이미 색인에 다시 있는 숙소는 보류에서 지운다."""
    def lid(it):
        return str(it.get("listing_id"))

    kept = [it for it in items if status.get(lid(it), "active") == "active"]
    removed = [it for it in items if status.get(lid(it), "active") != "active"]
    in_index = {lid(it) for it in items}
    restore = [it for it in held if lid(it) not in in_index and status.get(lid(it)) == "active"]
    restored_ids = {lid(it) for it in restore}
    new_held = [it for it in held if lid(it) not in in_index and lid(it) not in restored_ids]
    held_ids = {lid(it) for it in new_held}
    new_held += [it for it in removed if lid(it) not in held_ids]
    return kept + restore, new_held, len(removed), len(restore)


def sync_static_index(index_path: str = INDEX_PATH, held_path: str = HELD_PATH) -> tuple[int, int]:
    """정적 숙소 색인(public_stays_index.json)을 Firestore 숙소 상태에 맞춘다.
    앱은 목록·지도를 이 색인으로 그리므로, 노출 중지·재개가 화면에 반영되려면 이 단계(+배포)가 필요하다."""
    from firebase_client import db

    with open(index_path, encoding="utf-8") as f:
        data = json.load(f)
    held: list[dict] = []
    if os.path.exists(held_path):
        with open(held_path, encoding="utf-8") as f:
            held = (json.load(f) or {}).get("items") or []
    items = data.get("items") or []
    status = {s.id: (s.to_dict() or {}).get("status") for s in db().collection("listings").select(["status"]).stream()}
    new_items, new_held, removed, restored = plan_index_sync(items, held, status)

    if removed or restored:
        data["items"] = new_items
        with open(index_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    if new_held != held:
        with open(held_path, "w", encoding="utf-8") as f:
            json.dump({"items": new_held}, f, ensure_ascii=False, indent=1)
    print(f"정적 숙소 색인: 노출 중지 {removed}곳 제외 · 재개 {restored}곳 복원 → {len(new_items)}곳 (보류 {len(new_held)}곳)")
    return removed, restored


def _doc_addr(doc: dict) -> str:
    loc = doc.get("location_info") or {}
    return str(loc.get("display_address") or loc.get("lot_address") or "")


def find_license_for_kto(doc: dict) -> dict:
    """관광공사 출처 숙소를 업종별 인허가 API(6개) 에서 모두 찾아본다(추정 업종 먼저).
    상호+주소가 확실히 맞는 첫 결과(match/closed)를 업종과 함께 돌려준다."""
    name = str(doc.get("title") or "")
    addr = _doc_addr(doc)
    guessed = str(doc.get("license_type") or "")
    order = [guessed] + [lt for lt in API_ENV if lt != guessed] if guessed in API_ENV else list(API_ENV)
    errors = []
    for lt in order:
        try:
            rows = query_api(lt, name)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{lt}: {str(e)[:120]}")
            continue
        ev = evaluate(name, addr, rows)
        if ev["result"] in ("match", "closed"):
            ev["license_type"] = lt
            ev["guessed_license_type"] = guessed
            ev["matched_by"] = "name_address"
            return ev

    # 상호로 못 찾으면 도로명 주소(예: '귀계길 17-25')로 찾고, 같은 시·군 + 상호 핵심어가 겹칠 때만 연결한다.
    # (관광공사 이름과 등록 상호가 다른 경우: '구토란펜션' ↔ '경주 한옥펜션 구토란')
    road = road_key(addr)
    if road:
        for lt in order:
            try:
                rows = query_api(lt, road, max_pages=1, field="ROAD_NM_ADDR")
            except Exception as e:  # noqa: BLE001
                errors.append(f"{lt}(주소): {str(e)[:120]}")
                continue
            best = pick_address_match(name, addr, rows)
            if best:
                status = _first(best, STATUS_KEYS)
                return {
                    "result": _status_result(status),
                    "score": 5.0,
                    "candidates": len(rows),
                    "matched_name": _first(best, NAME_KEYS),
                    "matched_address": _first(best, ADDR_KEYS),
                    "matched_status": status,
                    "matched_permit_date": _first(best, DATE_KEYS),
                    "matched_closed_date": str(best.get("CLSBIZ_YMD") or ""),
                    "matched_mng_no": str(best.get("MNG_NO") or ""),
                    "matched_by": "road_address",
                    "license_type": lt,
                    "guessed_license_type": guessed,
                }
    if errors and len(errors) >= len(order) * (2 if road else 1):
        return {"result": "error", "error": " | ".join(errors)}
    return {"result": "not_found", "partial_errors": errors}


_ROAD_RE = re.compile(r"([가-힣A-Za-z0-9·]+(?:로|길))\s*(\d+(?:-\d+)?)")
# 상호 비교에서 빼는 일반어 (업종·형태를 나타낼 뿐 업소를 구분하지 않음)
_GENERIC_NAME_WORDS = ("게스트하우스", "풀빌라", "펜션", "민박", "한옥", "호텔", "스테이", "하우스", "리조트",
                       "모텔", "캠핑", "글램핑", "레지던스", "the", "더")


def road_key(addr: str) -> str:
    """'경상북도 경주시 내남면 귀계길 17-25' → '귀계길 17-25' (도로명 + 건물번호). 없으면 ''."""
    m = _ROAD_RE.search(addr or "")
    return f"{m.group(1)} {m.group(2)}" if m else ""


def _core_name(s: str) -> str:
    n = _norm(s).lower()
    for w in _GENERIC_NAME_WORDS:
        n = n.replace(w, "")
    return n


def _bigrams(s: str) -> set[str]:
    return {s[i:i + 2] for i in range(len(s) - 1)}


def names_match_loosely(a: str, b: str) -> bool:
    """일반어를 뺀 상호 핵심이 한쪽에 포함되거나, 두 글자 조각이 절반 이상 겹치면 같은 업소로 본다."""
    ca, cb = _core_name(a), _core_name(b)
    if len(ca) >= 2 and len(cb) >= 2 and (ca in cb or cb in ca):
        return True
    ba, bb = _bigrams(ca), _bigrams(cb)
    return bool(ba and bb) and len(ba & bb) / min(len(ba), len(bb)) >= 0.5


def _city_tokens(addr: str) -> set[str]:
    return {t for t in _addr_tokens(addr) if t.endswith(("시", "군", "구"))}


def pick_address_match(name: str, addr: str, rows: list[dict]) -> dict | None:
    """같은 도로명·건물번호로 찾은 인허가 행 중 같은 시·군·구이고 상호가 비슷한 행. 영업 중인 행을 우선한다."""
    key, cities = road_key(addr), _city_tokens(addr)
    hits = []
    for row in rows:
        row_addr = " ".join(str(row.get(k) or "") for k in ADDR_KEYS)
        if key and not re.search(re.escape(key) + r"(?![\d-])", row_addr):
            continue  # LIKE 검색이라 '귀계길 17-251' 같은 다른 번지가 섞일 수 있음
        if cities and not (cities & _city_tokens(row_addr)):
            continue
        if names_match_loosely(name, _first(row, NAME_KEYS)):
            hits.append(row)
    if not hits:
        return None
    hits.sort(key=lambda r: _status_result(_first(r, STATUS_KEYS)) != "match")
    return hits[0]


def link_kto_listings(apply: bool = False, workers: int = 3, index_path: str = INDEX_PATH,
                      results_path: str | None = None) -> dict:
    """(한 번만 실행) 관광공사 출처 숙소의 실제 인허가를 찾아 연결한다.

    - match: 실제 업종·인허가 관리번호를 저장(public_mng_no 를 행안부 번호로 바꿈, 관광공사 ID 는 kto_content_id 로 보존)
             → 이후 재확인은 관리번호로 정확히 대조된다. 정적 색인의 업종·출처(src=mois)도 고친다.
    - closed: 자동 노출 중지하지 않고 '확인 필요(license_closed)'로만 표시 (이름이 같은 다른 업소일 수 있음).
    - 이미 다른 숙소가 쓰는 관리번호면 중복 등록일 수 있어 연결하지 않고 보고만 한다.
    apply=False(기본)는 결과만 출력한다."""
    from concurrent.futures import ThreadPoolExecutor

    from firebase_client import db

    all_snaps = list(db().collection("listings").stream())
    # 한옥체험업·외국인관광도시민박업 관리번호는 지자체별 일련번호라 전국에서 겹친다(NOTES §9)
    # → 관리번호가 같아도 이름이나 주소까지 같아야 같은 숙소(중복 등록)로 본다.
    holders: dict[str, list[tuple[str, str, set[str]]]] = {}
    for s in all_snaps:
        d = s.to_dict() or {}
        holders.setdefault(str(d.get("public_mng_no") or ""), []).append(
            (s.id, _norm(str(d.get("title") or "")), _addr_tokens(_doc_addr(d))))

    def _same_stay(mng: str, sid: str, doc: dict) -> str | None:
        name, addr = _norm(str(doc.get("title") or "")), _addr_tokens(_doc_addr(doc))
        for other_id, other_name, other_addr in holders.get(mng, []):
            if other_id != sid and (other_name == name or len(addr & other_addr) >= 4):
                return other_id
        return None

    kto = [s for s in all_snaps if is_kto(s.to_dict() or {}) and (s.to_dict() or {}).get("status") == "active"]

    if results_path and apply and os.path.exists(results_path):
        # 미리보기에서 저장한 결과를 그대로 반영 (같은 조회를 다시 하지 않고, 확인한 결과와 반영 결과가 같도록)
        with open(results_path, encoding="utf-8") as f:
            saved = json.load(f)
        results = [(s, saved[s.id]) for s in kto if s.id in saved]
        print(f"저장된 미리보기 결과 {len(results)}곳을 반영합니다 ({results_path})")
    else:
        print(f"관광공사 출처 공개 숙소 {len(kto)}곳을 {len(API_ENV)}개 업종 인허가 API 에서 찾는 중...")

        def _work(snap):
            try:
                return snap, find_license_for_kto(snap.to_dict() or {})
            except Exception as e:  # noqa: BLE001
                return snap, {"result": "error", "error": str(e)[:200]}

        with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
            results = list(pool.map(_work, kto))
        if results_path:
            with open(results_path, "w", encoding="utf-8") as f:
                json.dump({s.id: r for s, r in results}, f, ensure_ascii=False, default=str)
            print(f"조회 결과 저장: {results_path}")

    counts = {"match": 0, "match_other_type": 0, "by_address": 0, "closed": 0, "duplicate": 0, "no_mng": 0, "not_found": 0, "error": 0}
    linked: dict[str, dict] = {}
    batch, ops = db().batch(), 0
    for snap, res in results:
        doc = snap.to_dict() or {}
        r = res["result"]
        title = doc.get("title")
        mng = str(res.get("matched_mng_no") or "")
        if r == "match" and not mng:
            counts["no_mng"] += 1  # 인허가 행에 관리번호가 없어 연결할 수 없음
            continue
        other = _same_stay(mng, snap.id, doc) if r == "match" else None
        if other:
            counts["duplicate"] += 1
            print(f"[중복] {snap.id} {title} — 같은 인허가({mng})로 이미 등록된 숙소 {other}")
            upd = {"needs_review": True, "needs_review_reason": "duplicate",
                   "needs_review_detail": f"같은 인허가 관리번호 {mng} 로 등록된 숙소 {other} 와 중복 — 한쪽 노출 중지 검토"}
        elif r == "match":
            holders.setdefault(mng, []).append((snap.id, _norm(str(title or "")), _addr_tokens(_doc_addr(doc))))
            counts["match"] += 1
            if res["license_type"] != res["guessed_license_type"]:
                counts["match_other_type"] += 1
            if res.get("matched_by") == "road_address":
                counts["by_address"] += 1
            print(f"[연결] {snap.id} {title} — {res['guessed_license_type']} → {res['license_type']} {mng} "
                  f"({res.get('matched_status')}, {str(res.get('matched_address'))[:40]}"
                  + (f", 주소로 찾음: 등록 상호 '{res.get('matched_name')}'" if res.get("matched_by") == "road_address" else "") + ")")
            linked[snap.id] = {"license_type": res["license_type"]}
            upd = {
                "license_type": res["license_type"],
                "public_mng_no": mng,
                "kto_content_id": str(doc.get("public_mng_no") or "").removeprefix("KTO-"),
                "public_licensed_at": res.get("matched_permit_date") or firestore.DELETE_FIELD,
                "license_linked_at": firestore.SERVER_TIMESTAMP,
                "last_license_check": res,
            }
            if doc.get("needs_review_reason") in KTO_CLEARABLE:
                upd.update({"needs_review": False, "needs_review_reason": firestore.DELETE_FIELD,
                            "needs_review_detail": firestore.DELETE_FIELD})
        elif r == "closed":
            counts["closed"] += 1
            print(f"[폐업 기록] {snap.id} {title} — {res['license_type']} {res.get('matched_name')} "
                  f"{str(res.get('matched_address'))[:40]} ({res.get('matched_status')} {res.get('matched_closed_date')})")
            upd = {"needs_review": True, "needs_review_reason": "license_closed",
                   "needs_review_detail": f"{res['license_type']} 인허가 데이터 영업상태: {res.get('matched_status')} "
                                          f"(폐업일 {res.get('matched_closed_date')}, {str(res.get('matched_address'))[:60]})",
                   "last_license_check": res}
        else:
            counts[r if r in counts else "not_found"] += 1
            continue
        if apply:
            batch.update(snap.reference, upd)
            ops += 1
            if ops >= 400:
                batch.commit()
                batch, ops = db().batch(), 0
    if apply and ops:
        batch.commit()

    if apply and linked:
        with open(index_path, encoding="utf-8") as f:
            data = json.load(f)
        for it in data.get("items") or []:
            hit = linked.get(str(it.get("listing_id")))
            if hit:
                it["license_type"] = hit["license_type"]
                it["src"] = "mois"
        with open(index_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

    print(f"{'반영' if apply else '미리보기'}: 연결 {counts['match']}곳(추정 업종과 다름 {counts['match_other_type']} · 주소로 찾음 {counts['by_address']}) · "
          f"폐업 기록 {counts['closed']} · 중복 등록 {counts['duplicate']} · 관리번호 없음 {counts['no_mng']} · "
          f"못 찾음 {counts['not_found']} · 오류 {counts['error']}"
          + ("" if apply else "  (--apply 로 반영)"))
    return counts


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("probe", help="API 원본 응답 확인(필드명 점검용)")
    p.add_argument("license_type")
    p.add_argument("business_name")
    p = sub.add_parser("check", help="숙소 1곳 대조 결과 출력(저장하지 않음)")
    p.add_argument("listing_id")
    p.add_argument("--csv")
    p = sub.add_parser("recheck", help="숙소 재확인 (인허가 출처: 폐업·휴업 → 노출 중지 / 관광공사 출처: 목록 대조)")
    p.add_argument("--csv")
    p.add_argument("--workers", type=int, default=4, help="동시 조회 수")
    p.add_argument("--rotate", type=int, default=1,
                   help="인허가 출처를 N 개 그룹으로 나눠 이번 주 그룹만 검사 (기본 1 = 전체)")
    p.add_argument("--prune-index", action="store_true",
                   help="끝나면 정적 숙소 색인을 Firestore 상태에 맞춤(노출 중지 제외·재개 복원)")
    sub.add_parser("prune-index", help="정적 숙소 색인을 Firestore 상태에 맞춤(노출 중지 제외·재개 복원)")
    p = sub.add_parser("link-kto", help="(한 번) 관광공사 출처 숙소의 실제 인허가를 6개 업종에서 찾아 연결")
    p.add_argument("--apply", action="store_true", help="Firestore·정적 색인에 반영 (없으면 미리보기)")
    p.add_argument("--results", help="미리보기 때 조회 결과를 이 파일에 저장, --apply 때 있으면 이 결과로 반영(재조회 안 함)")
    p.add_argument("--workers", type=int, default=3)
    a = ap.parse_args()

    if a.cmd == "probe":
        rows = query_api(a.license_type, a.business_name)
        print(json.dumps(rows[:3], ensure_ascii=False, indent=2))
        print(f"... 총 {len(rows)}건")
    elif a.cmd == "check":
        from firebase_client import db

        snap = db().collection("listings").document(a.listing_id).get()
        if not snap.exists:
            raise SystemExit(f"숙소 없음: {a.listing_id}")
        print(json.dumps(check_listing(snap.to_dict(), a.csv), ensure_ascii=False, indent=2, default=str))
    elif a.cmd == "prune-index":
        sync_static_index()
    elif a.cmd == "link-kto":
        link_kto_listings(apply=a.apply, workers=a.workers, results_path=a.results)
    else:
        try:
            recheck_all(a.csv, workers=a.workers, rotate=a.rotate)
        finally:
            # 오류가 많아 실패로 끝나도, 그때까지 저장된 노출 중지는 색인에 반영한다
            if a.prune_index:
                sync_static_index()
