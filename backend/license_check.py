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
  python license_check.py recheck [--csv data.csv]                    # 공개 중인 전체 숙소 재확인
"""
import argparse
import csv
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


def query_api(license_type: str, business_name: str, max_pages: int = 5) -> list[dict]:
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
                  "cond[BPLC_NM::LIKE]": business_name}
        last = None
        batch = None
        candidates = (base + "/info", base) if page == 1 else (base + "/info",)
        for candidate in candidates:
            r = requests.get(candidate, params=params, timeout=20)
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


def recheck_all(csv_path: str | None = None):
    """공개 중인 숙소를 다시 대조. 폐업·휴업이 확실하면 노출 중지(suspended).
    판단 불가(not_found/uncertain/error)는 자동 조치하지 않고 관리자 확인 대상으로 표시만 한다."""
    from firebase_client import db

    counts = {"closed": 0, "match": 0, "review": 0}
    for snap in db().collection("listings").where("status", "==", "active").stream():
        doc = snap.to_dict()
        res = check_listing(doc, csv_path)
        if res["result"] == "closed":
            snap.reference.update({
                "status": "suspended",
                "suspended_reason": f"공공 인허가 데이터 영업상태: {res.get('matched_status')}",
                "suspended_at": firestore.SERVER_TIMESTAMP,
                "last_license_check": res,
            })
            counts["closed"] += 1
            print(f"노출 중지: {snap.id} {doc.get('title')} ({res.get('matched_status')})")
        elif res["result"] != "match":
            snap.reference.update({"needs_review": True, "needs_review_reason": res.get("error") or res["result"]})
            counts["review"] += 1
            print(f"확인 필요: {snap.id} {doc.get('title')} ({res['result']})")
        else:
            snap.reference.update({
                "needs_review": False,
                "needs_review_reason": firestore.DELETE_FIELD,
                "last_license_check_at": firestore.SERVER_TIMESTAMP,
            })
            counts["match"] += 1
    print(f"재확인 완료: 정상 {counts['match']} · 노출 중지 {counts['closed']} · 확인 필요 {counts['review']}")
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
    p = sub.add_parser("recheck")
    p.add_argument("--csv")
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
    else:
        recheck_all(a.csv)
