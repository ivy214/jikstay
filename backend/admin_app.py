"""관리자 화면 (로컬 전용 웹 · 공공API 큐레이션 및 사용자 후기 관리).

호스트 입점 신청·승인 절차가 폐지되고 공공데이터 자동 선별로 전환됨에 따라,
공공숙소 100선 수집·여행허브 갱신·인허가 정기 재확인·방문 혜택 쿠폰 설정 및
악성/스팸 사용자 후기 삭제(Admin SDK) 기능만 가볍게 제공한다.

실행:  cd backend && .venv\\Scripts\\python admin_app.py   →  http://127.0.0.1:8765
"""
import io
import os
import secrets
import threading
import traceback
from datetime import datetime

from flask import Flask, abort, redirect, render_template_string, request, url_for

from firebase_client import db

CSRF = secrets.token_urlsafe(32)
app = Flask(__name__)
JOBS: dict[str, dict] = {}
JOBS_LOCK = threading.Lock()

LAYOUT = """<!doctype html><html lang=ko><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>직스테이 관리자</title>
<style>
body{font-family:'Malgun Gothic',sans-serif;margin:0;background:#f6f7f9;color:#1d1f23}
header{background:#212529;color:#fff;padding:12px 20px}header a{color:#fff;margin-right:16px;text-decoration:none}
main{max-width:1100px;margin:0 auto;padding:20px}
table{border-collapse:collapse;width:100%;background:#fff}td,th{border-bottom:1px solid #e3e5e8;padding:8px;text-align:left;font-size:14px;vertical-align:top}
.card{background:#fff;border:1px solid #e3e5e8;border-radius:8px;padding:16px;margin-bottom:16px}
.badge{display:inline-block;padding:2px 8px;border-radius:10px;background:#e9ecef;font-size:12px}
.ok{background:#d3f9d8}.warn{background:#fff3bf}.bad{background:#ffe3e3}
button{padding:6px 14px;border-radius:6px;border:1px solid #adb5bd;background:#fff;cursor:pointer}
button.primary{background:#e61e4d;color:#fff;border-color:#e61e4d}button.danger{background:#e03131;color:#fff;border-color:#e03131}
input[type=text]{padding:6px;width:320px}
.imgs img{height:120px;margin:4px;border-radius:4px}pre{white-space:pre-wrap;background:#f1f3f5;padding:8px;font-size:12px}
</style>
<header><a href="/listings">공개 숙소·후기</a><a href="/spots">로컬 스팟·방문쿠폰</a><a href="/analytics">방문·전환 통계</a><a href="/curate">공공수집·17개시도 허브</a><a href="/review">폐업·재확인</a><a href="/jobs">작업</a></header>
<main>{{ body|safe }}</main></html>"""


def page(tpl: str, **ctx):
    body = render_template_string(tpl, csrf=CSRF, **ctx)
    return render_template_string(LAYOUT, body=body)


@app.before_request
def check_csrf():
    if request.method == "POST" and request.form.get("csrf") != CSRF:
        abort(403)


def _status_badge(s: str) -> str:
    cls = {
        "active": "ok",
        "match": "ok",
        "uncertain": "warn",
        "not_found": "warn",
        "suspended": "bad",
        "withdrawn": "bad",
        "closed": "bad",
        "error": "bad",
    }.get(s or "", "")
    return f'<span class="badge {cls}">{s or "-"}</span>'


app.jinja_env.globals["badge"] = _status_badge


# ---------- 백그라운드 작업 ----------
def run_job(name: str, fn, *args, job_key: str | None = None, **kwargs):
    with JOBS_LOCK:
        if job_key:
            for existing_id, j in JOBS.items():
                if j.get("key") == job_key and j["status"] == "running":
                    return existing_id
        job_id = f"{datetime.now():%H%M%S}-{secrets.token_hex(2)}"
        JOBS[job_id] = {"name": name, "key": job_key, "status": "running", "log": "", "started": datetime.now()}

    def target():
        import contextlib

        buf = io.StringIO()
        status = "done"
        try:
            with contextlib.redirect_stdout(buf):
                fn(*args, **kwargs)
        except Exception:  # noqa: BLE001
            status = "failed"
            buf.write(traceback.format_exc())
        with JOBS_LOCK:
            JOBS[job_id]["status"] = status
            JOBS[job_id]["log"] = buf.getvalue()[-8000:]

    threading.Thread(target=target, daemon=True).start()
    return job_id


@app.get("/")
def index():
    return redirect(url_for("listings"))


# ---------- 숙소 & 사용자 별점·후기 관리 ----------
@app.get("/listings")
def listings():
    status = request.args.get("status", "active")
    only_reviewed = request.args.get("reviewed") == "1"
    rows = [(s.id, s.to_dict()) for s in db().collection("listings").where("status", "==", status).limit(300).stream()]
    if only_reviewed:
        rows = [(i, d) for i, d in rows if (d.get("review_count") or 0) > 0]
    rows.sort(key=lambda kv: (kv[1].get("review_count") or 0, kv[1].get("outbound_clicks") or 0), reverse=True)
    return page("""<h2>숙소 목록 ({{rows|length}}건)</h2>
<p>{% for s in ['active','suspended','withdrawn'] %}
<a href="/listings?status={{s}}">{{ badge(s)|safe }}</a> {% endfor %}
| 필터: <a href="/listings?status={{status}}">전체</a> ·
<a href="/listings?status={{status}}&reviewed=1">사용자 후기 보유 숙소만</a></p>
<table><tr><th>숙소</th><th>업종 / 신고번호</th><th>방문자 별점·후기</th><th>외부 연결 클릭</th><th>직거래 창구</th></tr>
{% for id, d in rows %}<tr><td><a href="/listing/{{id}}">{{d.title}}</a><br>{{d.region_depth1}} {{d.region_depth2}}</td>
<td>{{d.license_type}}<br>{{d.license_number}}</td>
<td>{% if (d.review_count or 0) > 0 %}<b>★ {{ '%.1f'|format((d.score_sum or 0) / d.review_count) }}</b> ({{d.review_count}}건){% else %}-{% endif %}</td>
<td>총 {{d.outbound_clicks or 0}}회</td>
<td>{% if d.direct_booking_url %}<a href="{{d.direct_booking_url}}" target=_blank rel=noopener>열기</a>{% else %}-{% endif %}</td></tr>
{% else %}<tr><td colspan=5>없음</td></tr>{% endfor %}</table>""", rows=rows, status=status)


@app.get("/listing/<listing_id>")
def listing_detail(listing_id):
    doc_ref = db().collection("listings").document(listing_id)
    snap = doc_ref.get()
    if not snap.exists:
        abort(404)
    d = snap.to_dict()
    revs = [(r.id, r.to_dict()) for r in doc_ref.collection("reviews").order_by("created_at", direction="DESCENDING").limit(50).stream()]
    rc = int(d.get("review_count") or 0)
    ss = int(d.get("score_sum") or 0)
    avg_str = f"{ss / rc:.2f}" if rc > 0 else "-"
    return page("""<h2>{{d.title}} {{ badge(d.status)|safe }}</h2>
<div class=card><table>
<tr><th>지역 / 유형</th><td>{{d.region_depth1}} {{d.region_depth2}} · {{d.accommodation_type or '-'}}</td></tr>
<tr><th>업종 / 신고번호</th><td>{{d.license_type}} / <b>{{d.license_number}}</b></td></tr>
<tr><th>방문자 평점</th><td><b>★ {{avg_str}}</b> (후기 {{rc}}건 · 총점 {{ss}})</td></tr>
<tr><th>외부 연결 클릭</th><td>누적 {{d.outbound_clicks or 0}}회</td></tr>
<tr><th>하이라이트</th><td>{{d.highlights or d.summary_points}}</td></tr>
<tr><th>편의시설</th><td>{{d.amenities_by_category or d.options}}</td></tr>
<tr><th>네이버 후기 링크</th><td>검색 {{d.naver_blog_total or 0}}건 · 연결 링크 {{(d.naver_reviews or [])|length}}개</td></tr>
<tr><th>위치 안내</th><td>{{d.location_info or '-'}}</td></tr>
{% if d.suspended_reason %}<tr><th>노출 중지 사유</th><td>{{d.suspended_reason}}</td></tr>{% endif %}
</table><div class=imgs>{% for im in d.images %}<img src="{{im.url}}" title="{{im.space_tag}} {{im.caption}}">{% endfor %}</div></div>

<div class=card><h3>방문자 별점 · 후기 관리 ({{revs|length}}건)</h3>
<table><tr><th>작성자 / 태그</th><th>별점</th><th>내용</th><th>작성시각</th><th>관리</th></tr>
{% for rid, rv in revs %}
<tr><td><b>{{rv.nickname}}</b><br><span class=badge>{{rv.visit_tag or rv.lang or '-'}}</span></td>
<td><b>★ {{rv.score}}</b></td>
<td>{{rv.comment}}</td>
<td>{{rv.created_at}}</td>
<td><form method=post action="/listing/{{id}}/review/{{rid}}/delete" style="margin:0">
<input type=hidden name=csrf value="{{csrf}}">
<button class=danger>삭제</button></form></td></tr>
{% else %}<tr><td colspan=5>등록된 사용자 후기가 없습니다.</td></tr>{% endfor %}
</table></div>

<div class=card><h3>노출 상태 변경 (폐업·정보오류 조치)</h3>
<form method=post action="/listing/{{id}}/status"><input type=hidden name=csrf value="{{csrf}}">
{% if d.status == 'active' %}
<input type=hidden name=next_status value="suspended">
사유: <input type=text name=reason required placeholder="예: 폐업 확인 또는 운영자 비공개 요청">
<button class=danger>노출 중지 (suspended)</button>
{% else %}
<input type=hidden name=next_status value="active">
<input type=hidden name=reason value="">
<button class=primary>다시 공개 (active)</button>
{% endif %}</form></div>""", id=listing_id, d=d, revs=revs, rc=rc, ss=ss, avg_str=avg_str)


@app.post("/listing/<listing_id>/review/<review_id>/delete")
def delete_user_review(listing_id, review_id):
    """스팸·욕설 등 부적절한 후기를 Admin SDK로 삭제하고 숙소 평점 합계를 차감 보정한다."""
    doc_ref = db().collection("listings").document(listing_id)
    rev_ref = doc_ref.collection("reviews").document(review_id)
    rev_snap = rev_ref.get()
    if not rev_snap.exists:
        abort(404)
    rev_data = rev_snap.to_dict() or {}
    score = int(rev_data.get("score") or 0)

    listing_snap = doc_ref.get()
    if listing_snap.exists:
        cur = listing_snap.to_dict() or {}
        next_count = max(0, int(cur.get("review_count") or 0) - 1)
        next_sum = max(0, int(cur.get("score_sum") or 0) - score) if next_count > 0 else 0
        doc_ref.update({"review_count": next_count, "score_sum": next_sum})
    rev_ref.delete()
    return redirect(url_for("listing_detail", listing_id=listing_id))


@app.post("/listing/<listing_id>/status")
def listing_status(listing_id):
    next_status = request.form.get("next_status", "").strip()
    if next_status not in ("active", "suspended"):
        abort(400)
    reason = request.form.get("reason", "").strip()
    if next_status == "suspended" and not reason:
        abort(400)
    doc_ref = db().collection("listings").document(listing_id)
    if not doc_ref.get().exists:
        abort(404)
    doc_ref.update({"status": next_status, "suspended_reason": reason})
    return redirect(url_for("listing_detail", listing_id=listing_id))


# ---------- 전국 17개 시·도 로컬 스팟(축제·볼거리·먹거리) & 방문 혜택 쿠폰 관리 ----------
@app.get("/spots")
def spots_list():
    only_sponsored = request.args.get("sponsored") == "1"
    rows = [(s.id, s.to_dict()) for s in db().collection("spots").where("status", "==", "active").limit(350).stream()]
    if only_sponsored:
        rows = [(i, d) for i, d in rows if d.get("is_sponsored")]
    rows.sort(key=lambda kv: (kv[1].get("outbound_clicks") or 0, kv[1].get("review_count") or 0), reverse=True)
    return page("""<h2>전국 로컬 스팟 · 방문혜택 쿠폰 관리 ({{rows|length}}건)</h2>
<p>필터: <a href="/spots">전체</a> · <a href="/spots?sponsored=1">방문혜택 쿠폰/스폰서 업장만</a></p>
<table><tr><th>구분 / 시도</th><th>장소명</th><th>방문 혜택 쿠폰 설정</th><th>방문유도 클릭 / 평점</th></tr>
{% for id, d in rows %}<tr>
<td><b>{{d.province}}</b> · {{d.kind}}</td>
<td><b>{{d.title}}</b><br><small>{{d.addr}}</small></td>
<td><form method=post action="/spot/{{id}}/coupon"><input type=hidden name=csrf value="{{csrf}}">
<label><input type=checkbox name=is_sponsored {% if d.is_sponsored %}checked{% endif %}> 스폰서 추천</label>
<input type=text name=coupon_title value="{{d.coupon_title or ''}}" placeholder="예: 화면 제시 시 음료 1잔 무료" style="width:230px">
<button>저장</button></form></td>
<td>길찾기·쿠폰 <b>{{d.outbound_clicks or 0}}회</b><br>{% if (d.review_count or 0) > 0 %}★ {{ '%.1f'|format((d.score_sum or 0) / d.review_count) }} ({{d.review_count}}){% else %}-{% endif %}</td>
</tr>{% else %}<tr><td colspan=4>동기화된 스팟이 없습니다. [공공수집·17개시도 허브]에서 스팟 동기화를 실행해 주세요.</td></tr>{% endfor %}</table>""", rows=rows)


@app.post("/spot/<spot_id>/coupon")
def spot_coupon_update(spot_id):
    is_spon = bool(request.form.get("is_sponsored"))
    coupon_title = request.form.get("coupon_title", "").strip()[:80]
    db().collection("spots").document(spot_id).set(
        {
            "is_sponsored": is_spon,
            "coupon_title": coupon_title,
            "admin_override_sponsor": True,
        },
        merge=True,
    )
    return redirect(url_for("spots_list"))


@app.get("/analytics")
def analytics_page():
    """지자체 B2G 홍보 리포트 및 스폰서 상점 쿠폰 성과 측정용 방문·전환 요약 대시보드."""
    stays = [(s.id, s.to_dict() or {}) for s in db().collection("listings").where("status", "==", "active").limit(2000).stream()]
    spots = [(s.id, s.to_dict() or {}) for s in db().collection("spots").where("status", "==", "active").limit(1000).stream()]

    total_stay_clicks = sum(int(d.get("outbound_clicks") or 0) for _, d in stays)
    total_spot_clicks = sum(int(d.get("outbound_clicks") or 0) for _, d in spots)
    total_reviews = sum(int(d.get("review_count") or 0) for _, d in stays) + sum(int(d.get("review_count") or 0) for _, d in spots)
    sponsored_cnt = sum(1 for _, d in stays if d.get("is_sponsored")) + sum(1 for _, d in spots if d.get("is_sponsored"))

    prov_stats: dict[str, dict[str, int]] = {}
    for _, d in stays:
        prov = str(d.get("province") or (str(d.get("region_depth1") or "기타")[:2]))
        st = prov_stats.setdefault(prov, {"stays": 0, "spots": 0, "clicks": 0, "reviews": 0})
        st["stays"] += 1
        st["clicks"] += int(d.get("outbound_clicks") or 0)
        st["reviews"] += int(d.get("review_count") or 0)
    for _, d in spots:
        prov = str(d.get("province") or "기타")
        st = prov_stats.setdefault(prov, {"stays": 0, "spots": 0, "clicks": 0, "reviews": 0})
        st["spots"] += 1
        st["clicks"] += int(d.get("outbound_clicks") or 0)
        st["reviews"] += int(d.get("review_count") or 0)

    prov_rows = sorted(prov_stats.items(), key=lambda kv: (kv[1]["clicks"], kv[1]["spots"] + kv[1]["stays"]), reverse=True)

    combined_top = [
        {"id": i, "type": "안심숙소", "prov": d.get("province") or d.get("region_depth1") or "-", "title": d.get("title") or i,
         "clicks": int(d.get("outbound_clicks") or 0), "reviews": int(d.get("review_count") or 0), "sponsored": bool(d.get("is_sponsored"))}
        for i, d in stays
    ] + [
        {"id": i, "type": d.get("kind") or "스팟", "prov": d.get("province") or "-", "title": d.get("title") or i,
         "clicks": int(d.get("outbound_clicks") or 0), "reviews": int(d.get("review_count") or 0), "sponsored": bool(d.get("is_sponsored"))}
        for i, d in spots
    ]
    combined_top.sort(key=lambda r: (r["clicks"], r["reviews"]), reverse=True)

    return page("""<h2>방문자 길찾기·쿠폰·직거래 전환 성과 리포트</h2>
<div class=card>
<b>전체 활성 숙소:</b> {{stays_len}}곳 · <b>전국 로컬 스팟(축제·명소·맛집):</b> {{spots_len}}곳 ·
<b>스폰서/쿠폰 업장:</b> {{sponsored_cnt}}곳<br>
<b>누적 방문유도 클릭(길찾기·쿠폰·예약창구):</b> <span class="badge ok">{{total_clicks}}회</span>
(숙소 {{total_stay_clicks}}회 + 로컬스팟 {{total_spot_clicks}}회) ·
<b>누적 방문자 후기:</b> {{total_reviews}}건
</div>
<div class=card><h3>1) 시·도별 디지털 관광 전환 현황 (B2G 지자체 리포트용)</h3>
<table><tr><th>시·도</th><th>연결 명소·맛집·축제</th><th>합법 안심숙소</th><th>길찾기·쿠폰 전환 클릭</th><th>방문자 후기</th></tr>
{% for prov, st in prov_rows %}
<tr><td><b>{{prov}}</b></td><td>{{st.spots}}곳</td><td>{{st.stays}}곳</td><td><b>{{st.clicks}}회</b></td><td>{{st.reviews}}건</td></tr>
{% else %}<tr><td colspan=5>집계 데이터 없음</td></tr>{% endfor %}</table></div>
<div class=card><h3>2) 실시간 인기 전환 TOP 15 장소 (소상공인 스폰서 리포트용)</h3>
<table><tr><th>순위</th><th>구분 / 지역</th><th>장소명</th><th>전환 클릭수</th><th>방문자 후기</th></tr>
{% for r in top_items %}
<tr><td>{{loop.index}}</td><td>{{r.prov}} · {{r.type}}</td><td><b>{{r.title}}</b> {% if r.sponsored %}<span class="badge warn">스폰서</span>{% endif %}</td>
<td><b>{{r.clicks}}회</b></td><td>{{r.reviews}}건</td></tr>
{% else %}<tr><td colspan=5>데이터 없음</td></tr>{% endfor %}</table></div>""",
        stays_len=len(stays),
        spots_len=len(spots),
        sponsored_cnt=sponsored_cnt,
        total_clicks=total_stay_clicks + total_spot_clicks,
        total_stay_clicks=total_stay_clicks,
        total_spot_clicks=total_spot_clicks,
        total_reviews=total_reviews,
        prov_rows=prov_rows,
        top_items=combined_top[:15],
    )


# ---------- 공공 API 수집 / 정기 재확인 / 작업 ----------
@app.get("/curate")
def curate_page():
    return page("""<h2>공공 인허가 API + 전국 17개 시·도 TourAPI 통합 수집</h2>
<div class=card>
<h3>1) 전국 17개 시·도 지자체 E-book · 축제 · 볼거리 · 먹거리 통합 허브 갱신</h3>
<p>한국관광공사 <code>KorService2</code>에서 전국 17개 시·도 볼거리(12)·먹거리(39)·진행중 축제(searchFestival2)를 균등 수집하고,
지자체 공식 관광지도 PDF/E-book 아카이브 및 지도용 숙소 위경도 색인을 한 번에 생성합니다.</p>
<form method=post action="/curate/hub"><input type=hidden name=csrf value="{{csrf}}">
<label><input type=checkbox name=upload_spots checked> 전국 축제·볼거리·먹거리 Firestore <code>spots</code> 동기화(방문 클릭·별점 활성화)</label><br>
<label><input type=checkbox name=upload> 상위 숙소 상세보강 Firestore 반영</label><br><br>
<button class=primary>17개 시도 로컬 허브 & 지도 색인 갱신</button></form>
</div>
<div class=card>
<h3>2) 권역 × 업종별 100선 합법 숙소 큐레이션</h3>
<p>5대 권역 × 4대 합법 업종별로 영업 중인 정예 숙소를 자동 선별하고 Firestore <code>listings</code>에 반영합니다.</p>
<form method=post action="/curate/run"><input type=hidden name=csrf value="{{csrf}}">
권역(비우면 전체): <input type=text name=regions placeholder="예: 제주,강원" style="width:180px">
버킷당 선별 수: <input type=text name=per_bucket value="100" style="width:70px">
<label><input type=checkbox name=upload checked> Firestore 즉시 반영</label>
<button class=primary>숙소 수집·선별 시작</button></form>
</div>""")


@app.post("/curate/hub")
def curate_hub():
    from build_travel_hub import build_hub_json, enrich_top_stays_with_tour_details

    do_upload = bool(request.form.get("upload"))
    do_upload_spots = bool(request.form.get("upload_spots"))

    def _task():
        build_hub_json(upload_spots=do_upload_spots)
        if do_upload:
            enrich_top_stays_with_tour_details(upload=True)

    job = run_job("전국 17개 시도 로컬 허브 및 지도 색인 갱신", _task, job_key="curate:hub")
    return redirect(url_for("jobs", highlight=job))


@app.post("/curate/run")
def curate_run():
    from curate_public_stays import run_curation

    regions_raw = request.form.get("regions", "").strip()
    regions = [r.strip() for r in regions_raw.split(",") if r.strip()] or None
    try:
        per_bucket = max(1, min(200, int(request.form.get("per_bucket", "100").strip())))
    except ValueError:
        per_bucket = 100
    do_upload = bool(request.form.get("upload"))
    job = run_job(
        f"공공숙소 선별 ({regions_raw or '전권역'}, 버킷당 {per_bucket}곳)",
        run_curation,
        regions=regions,
        per_bucket=per_bucket,
        upload=do_upload,
        job_key="curate:public",
    )
    return redirect(url_for("jobs", highlight=job))


@app.get("/review")
def review():
    flagged = [(s.id, s.to_dict()) for s in db().collection("listings").where("needs_review", "==", True).stream()]
    suspended = [(s.id, s.to_dict()) for s in db().collection("listings").where("status", "==", "suspended").stream()]
    return page("""<h2>폐업·휴업 정기 재확인</h2>
<form method=post action="/recheck"><input type=hidden name=csrf value="{{csrf}}">
CSV(선택) <input type=text name=csv> <button class=primary>공개 숙소 전체 재확인 실행</button></form>
<h3>노출 중지 (폐업·휴업 확인)</h3><ul>{% for id, d in suspended %}<li><a href="/listing/{{id}}">{{d.title}}</a> — {{d.suspended_reason}}</li>{% else %}<li>없음</li>{% endfor %}</ul>
<h3>판단 불가 (직접 확인)</h3><ul>{% for id, d in flagged %}<li><a href="/listing/{{id}}">{{d.title}}</a> — {{d.needs_review_reason}}{% if d.needs_review_detail %} <small>({{d.needs_review_detail}})</small>{% endif %}</li>{% else %}<li>없음</li>{% endfor %}</ul>
""", flagged=flagged, suspended=suspended)


@app.post("/recheck")
def recheck():
    from license_check import recheck_all, sync_static_index

    def _recheck_and_sync(csv_path):
        try:
            recheck_all(csv_path, workers=3)
        finally:
            removed, restored = sync_static_index()
            if removed or restored:
                print("정적 숙소 색인이 바뀌었습니다 — 배포해야 앱 목록·지도에 반영됩니다.")

    job = run_job("인허가 정기 재확인", _recheck_and_sync, request.form.get("csv") or None)
    return redirect(url_for("jobs", highlight=job))


@app.get("/jobs")
def jobs():
    with JOBS_LOCK:
        items = sorted([(k, dict(v)) for k, v in JOBS.items()], key=lambda kv: kv[1]["started"], reverse=True)
    return page("""<h2>작업</h2><p><a href="/jobs">새로고침</a></p>
{% for id, j in items %}<div class=card {% if id == hl %}style="border-color:#e61e4d"{% endif %}>
<b>{{j.name}}</b> {{ badge({'done':'active','failed':'error','running':'uncertain'}[j.status])|safe }} {{j.status}} · {{j.started.strftime('%H:%M:%S')}}
<pre>{{j.log or '(실행 중…)'}}</pre></div>{% else %}<p>없음</p>{% endfor %}""", items=items, hl=request.args.get("highlight"))


if __name__ == "__main__":
    print("관리자 화면: http://127.0.0.1:8765 (이 PC에서만 접속 가능)")
    app.run(host="127.0.0.1", port=8765, debug=False)
