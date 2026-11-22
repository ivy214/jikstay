# 직스테이 로컬 — 현재 구조 노트

> 기준일 2026-11-15. 코드 기준으로 정리한 **현재** 구조다. 폐지된 기능을 포함한 지난 이력은 [docs/CHANGELOG.md](docs/CHANGELOG.md).
> 서비스: <https://jikstay.app> (기본 주소 jikstay-lkxu1.web.app 은 301 이동) · Firebase 프로젝트 `jikstay-lkxu1` (서울 `asia-northeast3`)

## 1. 한 줄 요약

지자체 공식 가이드북·한국관광공사 공공데이터로 만든 **하루 한 편 로컬 여행 스토리 매거진**에,
행정안전부 인허가로 영업이 확인된 **합법 숙소**와 주변 볼거리·먹거리·축제 동선을 이어 주는 정보 사이트.
예약·결제의 당사자가 아니며, 방문자 개인정보는 후기 작성 시 닉네임·익명 식별자 외에는 받지 않는다.

폐지된 것(되살리지 말 것): 호스트 입점 신청·신고증 업로드, 블로그→상세페이지 AI 생성, 쇼츠·유튜브·릴스,
호스트 알림·주간 리포트, 숙소 주인 등록(claim), 숙소 CPC 과금(잔액 차감·중복 클릭 판정).

## 2. 디렉토리

```text
app/                    Flutter Web (Dart 3.14 / Flutter 3.50)
  lib/main.dart           앱 진입·HomePage(상태·데이터 로딩) — 홈 카드 위젯은 lib/home/*
  lib/home/               피드 패널 · 오늘의 스토리 히어로 카드 · 피드 카드 (main.dart 의 part)
  lib/detail_page.dart    숙소 공통 헬퍼(요금·직거래 판정·문의 문구) — 화면은 lib/detail/*
  lib/detail/             숙소 상세 페이지 · 예약 카드 · 이용정보 · 갤러리 · 후기/주변 (detail_page.dart 의 part)
  lib/discovery_models.dart  DiscoveryItem 등 모델 — 파싱·5일장·시드·스토리 선정은 lib/discovery/*
  lib/spot_detail_sheet.dart 명소·먹거리·축제 상세 / lib/story_detail_page.dart 스토리 상세
  lib/hub_details.dart    허브 데이터 지연 로드 (core.json + 시·도별 상세)
  lib/naver_place_info.dart  네이버 업종·공식 링크 표시 / lib/review_auth.dart 익명 로그인 후기 작성
  lib/trip_planner.dart · travel_hub.dart · local_calendar_view.dart · naver_map_view.dart
  lib/event_banner.dart   홈 상단 이벤트 배너(kPromoEvents: 기간 안에 든 것 중 홈 진입 시 무작위 1개) — 이미지는 web/assets/events/
  lib/i18n.dart · translation_store.dart  KO/EN/JA/ZH(번체) UI·데이터 번역
  web/data/               정적 데이터(원본) — public_travel_hub.json, public_stays_index.json, translations_*.json
  web/data/hub/           (생성물, git 제외) split_hub.py 가 빌드 직전에 만든 core.json + details_{시도}.json
  web/data/i18n/{lang}/   (생성물, git 제외) 번역 번들도 같은 방식으로 core.json + details_{시도}.json
  lib/ux_widgets.dart     찜(기기 저장)·공유(기기 공유 시트)·상세 하단 행동 바·핵심 정보 칩·출처/기준일 표기
backend/                Python 3.12 데이터 파이프라인·로컬 관리자 (Admin SDK, 로컬 PC 또는 GitHub Actions)
firebase/               보안 규칙 · 인덱스 · Cloud Functions(Node 22) · 규칙/함수 테스트
deploy.ps1              분할 → Flutter 빌드 → firebase/public 배치 → (선택) 배포
.github/workflows/      ci.yml (테스트) · weekly-travel-hub-update.yml (주간 데이터 갱신)
```

## 3. 데이터 흐름

```text
공공 API ─┬─ 행안부 인허가 4종(숙소) ─┐
          ├─ TourAPI KorService2 ─────┼─ backend 스크립트 ─▶ app/web/data/*.json (git 커밋)
          └─ 네이버 검색 API Hub ─────┘        │                     │
                                                 │                     └─ split_hub.py ─▶ web/data/hub/ ─▶ Hosting
                                                 └─ --upload / --upload-spots ─▶ Firestore listings · spots
브라우저: core.json·숙소 색인(정적) → 상세 화면에서 시·도 상세 JSON 지연 로드 → Firestore 는 평점·클릭·후기만 덧씌움
```

- **첫 화면 용량**: 허브 원본 약 2.4MB 중 core.json 약 530KB(gzip 125KB)만 받는다. 본문 문단·네이버 방문기·탐방정보·갤러리·
  긴 개요·인용문(pull_quote)·공식 링크(naver_link)·content_id 는 `details_{seoul|busan|…}.json`(평균 114KB)에 있고,
  상세 화면을 열 때 해당 시·도 파일만 1회 받는다. core 의 개요는 카드·검색용 50자 미리보기.
  볼거리·먹거리 수에는 상한이 없다(주간 신규 등록이 계속 쌓임) — core 는 한 곳에 약 0.6KB씩 늘어난다.
  더 줄여야 하면 다음 단계는 카드 설명까지 지연 로드(core 를 검색·지도용 색인만으로)하는 것.
  core 가 없으면(로컬 개발) 앱이 원본 `public_travel_hub.json` 으로 대체한다.
- **캠핑장·휴양림**: `camping` 섹션은 `hub/camping.json`(약 1.6MB)으로 따로 두고 앱이 2단계에서 받는다. 기본 피드에는 안 나오고
  '자연·액티비티' 칩·검색·지도에서만 보인다. 상세 본문은 `details_camping_{시·도}.json` 에 따로 있어 다른 장소 상세를 열 때 받지 않는다.
  번역은 이름·지역·한 줄 소개만(무료 번역 한도).
- **번역**: `translate_hub.py` 가 원문 해시 캐시(`backend/translation_cache.json`, git 커밋)로 변경분만 Gemini 번역.
  앱은 외국어 전환 시 `i18n/{lang}/core.json`(목록용)만 받고, 상세를 열면 그 시·도의 본문 번역을 추가로 받는다.

## 4. Firestore · Storage

| 경로 | 내용 | 클라이언트 권한 |
| --- | --- | --- |
| `listings/{stay_…}` | 공공 선별 숙소 (status, 업종, 위치, 이미지 URL, 평점 집계, `outbound_clicks`) | `active`만 읽기 · 클릭 정확히 +1 · 평점 집계는 후기 생성과 같은 배치일 때만 |
| `listings/{id}/reviews/{uid}` | 방문자 후기 | 공개 읽기 · **익명 로그인 + 문서 ID = 본인 uid**일 때만 생성(장소당 1인 1후기) · 수정·삭제 불가 |
| `spots/{id}` · `spots/{id}/reviews/{uid}` | 축제·볼거리·먹거리, 방문 혜택 쿠폰(`is_sponsored`, `coupon_title`) | 위와 동일 |
| 그 외 모든 경로 | — | 전면 차단 |
| Storage `listings/**` | (구) 숙소 사진 | 읽기만 · 쓰기 차단 |

후기 삭제·노출 중지는 관리자 화면(Admin SDK)에서만 한다.

## 5. Cloud Functions (`firebase/functions/index.js`)

| 함수 | 경로 | 역할 |
| --- | --- | --- |
| `serveApp` | `**` | Flutter `index.html` 템플릿에 `?id=` `?spot=` `?story=` `?region=` 별 OG·hreflang·JSON-LD 와 검색엔진용 본문 `<main id="jikstay-seo">`(그 언어의 이름·설명·본문·이용 안내·주변/지역 링크) 주입. 번역은 호스팅의 `data/i18n/{lang}/` 분할 파일을 받아 10분 캐시(`seo_content.js`). Flutter 는 캔버스라 이 본문이 없으면 구글이 읽을 내용이 없다 |
| `goRedirect` | `/go?id=` | 숙소 외부 연결: 봇이 아니면 `outbound_clicks` +1(통계) 후 운영자 직거래 링크 → 없으면 네이버 지도 검색으로 이동. 과금 없음 |
| `serveSitemap` / `serveRobots` | `/sitemap.xml` `/robots.txt` | 동적 사이트맵(상한 없음, `lastmod`=문서 수정일) |

`firebase/public` 에 `index.html` 이 있으면 rewrite 가 무시되어 위 주입이 멈춘다 → 배포 스크립트·CI 모두 index.html 을 빼고 복사한다.

## 6. 백엔드 스크립트

| 스크립트 | 용도 |
| --- | --- |
| `curate_public_stays.py` | 행안부 인허가 + TourAPI + 네이버 블로그로 권역×업종별 숙소 선별 → `public_stays_index.json` (+ `--upload`) |
| `build_travel_hub.py` | 17개 시·도 E-book·볼거리·먹거리·축제·코스 허브 생성 → `public_travel_hub.json` (+ `--upload-spots`) |
| `weekly_hub_refresh.py` | 주간: 진행 중 축제 갱신·상세 보강 (CI 에서는 `--no-translate` 후 번역을 별도 단계로) |
| `weekly_spot_refresh.py` | 주간: 볼거리·먹거리 삭제 확인·반값여행 시·군 보충·신규 등록 추가 (`--dry-run` 으로 미리 보기) |
| `collect_half_price_spots.py` | 반값여행 대상 25개 시·군별 볼거리 6·먹거리 4·축제(조회순)를 시·군 코드로 추가 수집(`half_price_city` 표시, `--upload` 로 Firestore 문서 생성). 허브를 `build_travel_hub.py` 로 새로 만들면 다시 실행 |
| `collect_outdoor_spots.py` | (한 번) 자연·액티비티(`kind: outdoor`): 관광공사 레포츠(28) 시·도별 8곳 — 체험형 우선·같은 종류 2곳·길(`sub: trail`) 절반까지·시·군·구 분산, 캠핑장·골프장·실내 체육시설 제외. 이후 신규·폐업은 `weekly_spot_refresh.py` |
| `refresh_camping.py` | 주간: 고캠핑 전체(운영 중·사진·좌표 있는 약 2,250곳, `spot_cp_…`, 이용 안내는 고캠핑 값만) + TourAPI 자연휴양림·치유의숲(약 170곳, `spot_fr_…`) → 허브 `camping` 섹션. 사라진 곳 closed(10% 넘으면 보류) |
| `translate_hub.py` | EN/JA/ZH 증분 번역 (Gemini, 키 없으면 OpenAI) |
| `enrich_naver_local.py` | 네이버 지역 검색으로 `naver_link`(공식 링크, OTA 제외)·`naver_category` 보강. 허브/색인을 다시 만들면 재실행(캐시로 즉시 복원) |
| `clean_naver_reviews.py` | 장소와 무관한 네이버 방문기 제거(`is_relevant_place_snippet`), `--refetch` 로 빈 곳 재검색 |
| `split_hub.py` | 빌드 직전 허브 분할 (deploy.ps1·CI 가 자동 실행) |
| `license_check.py` | 인허가 대조. `recheck` = 공개 숙소 전체 폐업·휴업 재확인 → 확실하면 `suspended`, 애매하면 `needs_review`. 인허가 출처는 `--rotate 4` 로 매주 1/4(4주에 한 번 전체, 노출 중지 숙소도 다시 조회해 영업이면 `reopened` 표시), 관광공사 출처(`KTO-`)는 매주 전체를 TourAPI 숙박 목록과 대조(사라지면 `kto_missing`). `link-kto [--apply]` = (한 번) 관광공사 출처의 실제 인허가를 4개 업종에서 찾아 관리번호 연결. 상태가 바뀐 숙소만 저장(100건마다), 조회 오류가 20% 넘으면 오류 건은 표시 안 하고 실패 처리, 실행 기록은 `meta/license_recheck`. `--prune-index`/`prune-index` = 정적 색인을 Firestore 상태에 맞춤(노출 중지 제외 → `backend/stays_index_suspended.json` 보류, 재개되면 복원) |
| `enrich_ebooks_and_spots.py` · `upgrade_web_magazines_and_links.py` · `fetch_chapter_media.py` | 지자체 E-book·웹매거진·챕터 사진 보강 (수동 실행) |
| `generate_weekly_digest.py` · `notify_indexnow.py` | 주간 SNS 다이제스트 · IndexNow 제출 |
| `admin_app.py` | 로컬 관리자(127.0.0.1:8765, CSRF): 숙소·후기 삭제·노출 상태, 스팟 쿠폰, 통계, 공공 수집 실행, 재확인 |

## 7. 실행 · 배포 · CI

```powershell
# 관리자 화면
backend\.venv\Scripts\python backend\admin_app.py
# 배포 (분할 → 빌드 → firestore·storage·functions·hosting)
.\deploy.ps1 -Deploy            # App Check 를 켜려면 -RecaptchaKey 또는 RECAPTCHA_SITE_KEY
```

- **CI (`ci.yml`, push·PR)**: Flutter analyze/test · Functions 단위 테스트 · 보안 규칙 에뮬레이터 테스트(`demo-jikstay`) · 백엔드 단위 테스트.
- **주간 (`weekly-travel-hub-update.yml`, 월 06:00 KST)**: 축제 갱신 → 볼거리·먹거리 갱신(`weekly_spot_refresh.py`) →
  숙소 재확인(`license_check.py recheck --rotate 4 --prune-index`) → 번역 → 다이제스트 → 데이터 커밋(허브·숙소 색인).
  `FIREBASE_SERVICE_ACCOUNT_JIKSTAY` 시크릿이 있으면 Hosting(+템플릿 바뀌면 Functions)까지 배포하고, 같은 키로 Firestore 도 갱신한다
  (키에 Firestore 쓰기 권한이 없으면 인허가 재확인 단계가 실패로 표시됨). 번역·볼거리·인허가 단계가 실패해도 나머지 데이터는 커밋하고 워크플로만 실패 표시.
  - 볼거리·먹거리: 관광공사 목록에서 사라진 곳 제거(Firestore `closed`) · 반값여행 시·군 보충 · 최근 14일 신규 등록 시·도별 종류당 2곳(상한 없음)
    · Firestore 문서가 없는 허브 항목(주간 축제 포함) 보충. Firestore 쓰기를 먼저 하고 허브를 저장하며, 쓰기 권한이 없으면 아무것도 바꾸지 않고 실패
  - 숙소: 폐업·휴업이 확실할 때만 `suspended` + 정적 색인에서 제외. 못 찾음·불확실·API 오류는 `needs_review` 표시만(관리자 화면에서 확인)

### 환경변수 (`.env`, GitHub Actions 시크릿은 같은 이름)

| 변수 | 용도 |
| --- | --- |
| `TOUR_API_KEY`, `DATA_GO_KR_SERVICE_KEY` (+선택 `LICENSE_API_LODGING/HANOK/FOREIGN`) | TourAPI · 행안부 인허가 |
| `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET` | 네이버 API Hub(블로그·지역·이미지 검색). 구 `openapi.naver.com` 경로는 401 |
| `GEMINI_API_KEY` (+선택 `OPENAI_API_KEY`) | 번역·E-book 보강 |
| `FIREBASE_CREDENTIALS`, `FIREBASE_BUCKET` | Admin SDK (`serviceAccountKey.json`, 커밋 금지) |
| `RECAPTCHA_SITE_KEY` | Flutter `--dart-define` (App Check). `.env` 가 아닌 Windows 사용자 환경변수 / GitHub 시크릿 |

### 테스트

```powershell
cd app; flutter test                                   # 위젯·로직
cd firebase; npm run test:functions; npm run test:rules  # 함수 · 보안 규칙(에뮬레이터)
backend\.venv\Scripts\python backend\tests\<name>.py   # smoke / admin / curate / naver_filters / split_hub
```

`backend/tests/license_live_test.py`, `license_probe_all.py` 는 실제 공공 API 키가 필요해 CI 에서 돌리지 않는다.

## 8. 남은 일 · 알려진 한계

- [ ] `app/lib/legal.dart` 사업자 정보·개인정보 보호책임자 자리표시자 교체 + 법률 검토 (문구 바꾸면 `kConsentVersion` 올리기)
- [x] ~~reCAPTCHA Enterprise 키 발급~~ → GitHub Actions 시크릿 `RECAPTCHA_SITE_KEY` 등록 완료 (주간 워크플로 빌드에 적용).
- [ ] 키로 빌드·배포된 것을 확인한 **뒤에** App Check 다시 시행 (Firestore·Storage ENFORCED).
  로컬 `deploy.ps1` 은 `.env` 를 읽지 않으므로 Windows 사용자 환경변수 `RECAPTCHA_SITE_KEY` 를 설정해 두지 않으면 키 없이 빌드된다
  → 시행 후 로컬 배포하면 같은 장애가 재발한다.
  2026-11-14~16 사이 키 없이 Firestore·Storage 가 ENFORCED 로 켜져 사이트의 모든 Firestore 요청(숙소 상세·후기·클릭)이 거부됐었다.
  11-16 UNENFORCED 로 되돌림. 순서를 바꾸면 같은 장애가 재발한다.
- [x] ~~TourAPI 출처 숙소의 인허가 `not_found` 대량 발생~~ → 업종을 관광공사 분류로 추정해 엉뚱한 업종 API 에서 찾던 것이 원인.
  2026-11-16 부터 관광공사 출처는 관광공사 숙박 목록으로 확인. `link-kto` 로 실제 인허가를 찾은 숙소는 관리번호로 대조
- [ ] 관광공사 출처 숙소의 `public_licensed_at` 은 인허가일이 아니라 관광공사 정보 수정일(`curate_public_stays.py` 보충 경로) — 화면에 쓰지 말 것
- [ ] 숙소 348곳은 아직 근사 좌표(`approx_coord`) — 화면은 거리 대신 '시·군 단위 위치'로 표시, '내 주변' 정렬에서는 뒤로
- [ ] 이름·지역이 같은 숙소 13쌍, 대표사진을 공유하는 숙소 34곳 — 중복 등록 또는 사진 오매칭 여부 수동 확인 필요
- [ ] 네이버 검색 API 결과 저장·표시 조건(이용약관) 확인. 현재 링크·업종만 저장하고 "정보 출처: 네이버" 표기
- [ ] 주간 갱신의 네이버 지역 축제는 검색 결과 HTML 을 직접 파싱(API 아님) — 약관·구조 변경 위험

## 9. 데이터 정확성 규칙 (2026-11-16 정리)

- **숙소 ID**: 한옥체험업·외국인관광도시민박업 관리번호는 지자체별 일련번호라 전국에서 겹친다. 겹치면 `assign_unique_listing_ids` 가
  주소를 넣어 ID를 분리한다 (이전에 171곳이 80개 ID를 공유해 다른 숙소 상세가 열렸음).
- **출처 표기**: 숙소 색인의 `src` = `mois`(행정안전부 인허가 대조) / `kto`(한국관광공사 TourAPI 등록, 1,171곳).
  관광공사 출처를 "인허가 영업확인"으로 표시하지 않는다 (`stayVerificationLabel`). 다국어 요약·SEO 문구도 "정부 인증·합법"을 쓰지 않는다.
- **링크**: 코스는 TourAPI ID가 웹사이트 주소와 달라 구석구석 검색으로 연결. 가이드북·PDF 후보에서 SNS 주소 제외(`is_social_link`).
  접속 점검에서 죽은 네이버 공식 링크는 `backend/naver_dead_links.json` 에 남겨 재보강 때 다시 붙지 않게 한다.
- **좌표**: 근사 좌표 숙소는 네이버 지역 검색에서 이름 완전 일치 + 도로명 일치일 때만 실제 좌표로 교체(176곳).
- **문구**: "실시간"(데이터는 주 1회 갱신), 근거 없는 "수수료 절감액" 배지는 쓰지 않는다. 반값여행 등 정책 정보에는 기준 연도와 확인 안내를 단다.
