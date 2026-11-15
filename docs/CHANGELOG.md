# 직스테이 변경 이력 (2026-11-12 ~ 11-15)

> 이 문서는 2026-11-15까지의 구현 노트 원본을 그대로 보관한 것이다. 호스트 입점 신청·쇼츠 제작·주인 등록·CPC 과금 등
> **지금은 폐지된 기능의 설명이 섞여 있으니**, 현재 구조는 루트의 [NOTES.md](../NOTES.md)를 본다.
>
> 2026-11-15 운영 데이터 정리: 샘플 입점 신청서 5건·`[샘플]` 숙소 5곳(+Storage 사진 15개) 삭제,
> 숙소 1,678곳의 `listing_tier`·`cpc_*` 필드와 이용규칙의 "[내 숙소 주인 등록]" 문구, 스팟 68곳 `cpc_rate`, `cpc_click_dedup` 2건 제거.

---

# 직스테이 (jikstay) 구현 현황 노트


> 작성 2026-11-14 · 코드 전체를 다시 읽고 정리. 이전 NOTES.md(2026-11-12) 내용은 아래 "변경 이력"에 합쳤다.
> 원본 기획: `단기 숙소 예약 site 를 만들고 싶은데.txt`

---

## 0. 한 줄 요약


**영업신고를 확인한 합법 숙소만** 올려, 게스트가 **중개수수료 없이 호스트 예약 창구로 바로 가게** 하는 광고·정보 사이트.
호스트가 블로그 글 URL을 내면 AI가 상세페이지와 쇼츠 대본을 만들고, 관리자가 신고증·공공 인허가 데이터를 대조해 승인하면 공개된다. 공개 후 유튜브 쇼츠·인스타 릴스로 홍보한다.

- 근거 법령: 개정 「공중위생관리법」(2026-11-12 시행) — 온라인 중개 시 영업신고증 확인 의무, 미확인 상품 중개 시 과태료(시행령 부과기준 500만 원)
- 사이트는 예약·결제의 당사자가 아니다(통신판매 당사자 아님). 게스트 개인정보는 수집하지 않고, 직거래 버튼 클릭 수만 센다.

---

## 1. 전체 구조


```
36rd/
├─ app/                 Flutter Web (에어비앤비 벤치마킹 게스트 탐색·상세 + 호스트 입점 신청)
│  └─ lib/ main.dart · detail_page.dart · amenities.dart · demo_data.dart · legal.dart · firebase_options.dart
├─ backend/             Python 3.12 관리자 도구 (Admin SDK, 로컬 PC에서만 실행)
│  ├─ admin_app.py         로컬 관리자 웹 (Flask, 127.0.0.1:8765)
│  ├─ blog_to_listing.py   블로그 글 1건 → 숙소 JSON + 쇼츠 대본 (OpenAI/Gemini)
│  ├─ video_maker.py       JSON → 1080×1920 쇼츠 MP4 (Azure TTS)
│  ├─ upload_to_firestore.py  등록·승인·반려·철회 CLI
│  ├─ license_check.py     공공데이터포털 인허가 대조·정기 재확인
│  ├─ upload_youtube.py    유튜브 업로드/삭제
│  ├─ instagram_reels.py   인스타 릴스 게시
│  ├─ notify.py            호스트 알림 (이메일 기본 + 문자 선택)
│  ├─ weekly_report.py     주간 성과 리포트
│  ├─ find_hosts.py        네이버 검색 오픈 API로 섭외 후보 목록 (사람 검토용)
│  ├─ collect_50_jeju_hosts.py  API 없이 검색 결과·블로그 본문 직접 수집 (2026-11-14 재도입, 10절 참고)
│  ├─ firebase_client.py · env.py   공용 초기화 / .env 로더
│  └─ tests/               스모크·관리자·알림·E2E·LLM 비교·공공 API 점검
├─ firebase/            Firebase 프로젝트 (jikstay-lkxu1, 서울 asia-northeast3)
│  ├─ firestore.rules · storage.rules
│  ├─ functions/          Cloud Functions(Node 22): serveApp — ?id= 링크용 OG 태그 주입
│  ├─ public/             Flutter 빌드 결과(호스팅 배포본, index.html 제외)
│  └─ tests/rules.test.mjs  보안 규칙 단위 테스트
├─ docs/                공공데이터포털 활용신청용 '데이터 활용 계획' 이미지와 생성 스크립트
├─ .env                 비밀 키 (커밋 금지)
└─ serviceAccountKey.json  Admin SDK 서비스 계정 키 (커밋 금지)
```

권한 분리 원칙

- **웹앱(클라이언트)**: 공개 숙소 읽기, 클릭 +1, 신청서·신고증 "생성"만 가능. 나머지는 규칙으로 전부 차단.
- **관리자(Python, Admin SDK)**: 규칙을 우회해 등록·승인·삭제·신고증 열람. 관리자 화면은 인터넷에 올리지 않으므로 별도 로그인이 없다.

---

## 2. 상태 흐름


```
host_applications: pending_verification → listed → verified
                                         ↘ rejected   ↘ withdrawn
listings:          pending_verification → active ⇄ suspended → withdrawn
                                         ↘ rejected
```

| 단계 | 실행 | 결과 |
|---|---|---|
| 1. 입점 신청 | 웹앱 신청 폼 | 신고증 → `licenses/<appId>/license.<ext>`, 신청서 `pending_verification` |
| 2. 인허가 대조 | `license_check.py check` / 관리자 화면 "대조 실행" | 신청서에 `license_check` {result: match/closed/uncertain/not_found/error, …} |
| 3. 분석 + 쇼츠 | `blog_to_listing.py` → `video_maker.py` / 관리자 "1. 블로그 분석 + 쇼츠 생성" | `output/<appId>/listing_result.json`, `final_shorts.mp4` |
| 4. 검수 대기 등록 | `upload_to_firestore.py publish` / "2. 검수 대기로 등록" | 사진 → `listings/<id>/room_NN.jpg`, 숙소 `pending_verification`, 신청서 `listed` |
| 5. 승인 | `approve` (CLI 확인 질문 / 관리자 체크박스 3개) | 숙소 `active`, 검증자·방법·대조 결과·일시 기록, 신청서 `verified`, 호스트에 승인 알림 |
| 6. 홍보 | 관리자 "유튜브·릴스 게시" | `listings/<id>/shorts.mp4` 공개 업로드 → 유튜브 public → (설정 시) 릴스 → 호스트 알림 |
| 7. 주간 리포트 | `weekly_report.py` (작업 스케줄러) | `stats_snapshots`, 호스트에 클릭·조회수 알림 |
| 8. 정기 재확인 | `license_check.py recheck` / 관리자 "확인 필요" | 폐업·휴업 확실 → `suspended` + 알림 / 판단 불가 → `needs_review` 표시만 |
| 반려 | `reject --application-id` 또는 `--listing-id` | 사유 기록 → **알림 먼저** → 신고증 사본·연락처·로컬 output 파기 |
| 철회(내림) | `withdraw` | **알림 먼저** → 사진·쇼츠·유튜브 영상 삭제(릴스는 수동), 신고증·연락처·로컬 output 파기. 업종·신고번호·검증 이력만 보존 |

---

## 3. 데이터 모델


### Firestore

| 컬렉션 | 주요 필드 | 클라이언트 권한 |
|---|---|---|
| `listings/{stay_xxxxxxxx}` | title, region_depth1/2, accommodation_type, capacity_standard/max, summary_points, options, pricing{nightly_min, weekly_price, monthly_price, price_note}, images[{url, path, space_tag, caption}], direct_booking_url, source_blog_url, license_type/number, outbound_clicks, status, created_at, application_id, verified_by/verification_method/verification_license_check/verified_at, youtube_video_id/url, shorts_mp4_url, instagram_media_id/url, ig_keyword, needs_review(_reason), suspended_reason, last_report, last_license_check_at | `active`만 읽기. `outbound_clicks` 정확히 +1만 수정 |
| `host_applications/{autoId}` | blog_url, direct_booking_url, host_phone, host_email, business_name, business_address, license_type, license_number, license_image_path, consent_copyright/marketing/direct_liability/privacy(필수), consent_privacy_optional, consent_version, status, submitted_at (+관리자 기록: license_check, listing_id, rejection_reason, personal_data_purged_at …) | 생성만 (필드 화이트리스트·검증) |
| `notifications` | application_id, kind, channels, text, result(sent/partial/dry_run/no_contact/failed), detail, created_at — **연락처는 남기지 않음** | 차단 |
| `stats_snapshots/{listingId}_{date}` | clicks_total/week, views_total/week | 차단 |

### Storage

| 경로 | 규칙 |
|---|---|
| `licenses/{appId}/{file}` | 5MB 미만 이미지 **생성만**. 읽기·수정·삭제 불가 → 관리자가 Admin SDK로만 열람. 다운로드 URL 미발급 |
| `listings/{listingId}/{file}` | 공개 읽기, 클라이언트 쓰기 불가 (사진·쇼츠 원본) |

### 인허가 업종 (4종, 앱·규칙·백엔드 공통)

농어촌민박업 · 일반/생활숙박업 · 한옥체험업 · 외국인관광도시민박업(외국인 전용 — 카드·상세·이동 안내에 경고 표시)

---

## 4. 구성 요소별 상세


### 4-1. Flutter 웹앱 (`app/`)

- **진입**: `?id=stay_xxx`(정규식 `^stay_[a-zA-Z0-9_-]{4,32}$`)면 상세페이지를 바로 연다. 유튜브 설명란·릴스 캡션·ManyChat DM 링크용. 공개 숙소가 아니면 "공개 중인 숙소를 찾을 수 없습니다".
- **목록** (`HomePage`): `status == active` 실시간 구독(StreamBuilder). 클라이언트에서
  - 지역 칩 6개 — 칩별 시/도 키워드 목록으로 `region_depth1` 매칭 (`kRegionKeywords`)
  - 검색 — 제목·지역·숙소유형·옵션·매력 포인트
  - 정렬 — 최신순 / 낮은 요금순(1박→일주일→한달 순으로 있는 값) / 인기순(클릭)
  - 12개씩 "더 보기" 페이징
- **카드·상세**: 신고 확인 배지, 외국인 전용 배지, 사진 갤러리(좌우 버튼), 매력 포인트·옵션·요금표, 유튜브 쇼츠 링크.
- **직거래 이동** (`goDirectBooking`): 안내 다이얼로그(인허가·외국인 전용·"예약 당사자 아님, 예금주 확인") → 클릭 +1(실패해도 이동) → http(s) 링크만 외부 앱으로 연다.
- **입점 신청** (`HostOnboardingDialog`): 블로그 URL(현재 `blog.naver.com`만), 직거래 링크, 업종, 신고번호, 상호, 소재지 주소, 신고증 이미지(5MB 미만), 선택 연락처(이메일·전화). 필수 동의 4개 + 연락처 선택 동의. 연락처를 적었는데 선택 동의가 없으면 막는다. 약관 버전 `kConsentVersion = 2026-11-12.2` 저장.
- **이미지 로드** (`StorageImage`): Storage 경로가 있으면 SDK `getData`로 받아 App Check 토큰을 붙인다(시행 중에도 이미지가 보이도록). 경로가 없으면 URL로 로드.
- **App Check**: reCAPTCHA Enterprise, `--dart-define=RECAPTCHA_SITE_KEY=…`. 키가 없으면 경고만 출력하고 비활성.
- **법적 고지** (`legal.dart`): 동의 문구, 개인정보 수집·이용(필수/선택) 상세, 개인정보처리방침 요약, 하단 사업자 정보(`LegalFooter`).
- `firebase_options.dart`는 실제 프로젝트(jikstay-lkxu1) 웹 설정값으로 채워져 있음.

### 4-2. Cloud Functions — OG 태그 (`firebase/functions/index.js`)

- 호스팅의 모든 요청을 `serveApp`(asia-northeast3)으로 rewrite. `firebase/public`에 **index.html을 두지 않아** 정적 파일보다 함수가 먼저 처리된다(정적 파일이 있으면 rewrite가 무시되므로).
- `?id=`가 공개 숙소면 템플릿(`functions/index.html`)의 title·description·og:title/description에 숙소 정보를 넣고 og:image(첫 사진)·og:url을 추가. 값은 HTML 이스케이프. 캐시 5분(CDN 10분).
- 그 외·오류 시 기본 템플릿을 no-cache로 반환.

### 4-3. 관리자 화면 (`backend/admin_app.py`)

- 127.0.0.1:8765 전용. 실행할 때마다 새 CSRF 토큰, 모든 POST 검사.
- 페이지: 신청서 목록(상태별) / 신청서 상세(신고증 이미지 열람 `no-store`, 대조 실행, 분석+쇼츠, 등록, 반려) / 숙소 목록·상세(승인 체크리스트 3개 + 검증자·방법, 홍보 게시, 반려, 내림) / 확인 필요(노출 중지·판단 불가 목록, 전체 재확인) / 작업(백그라운드 스레드 로그, 같은 작업 중복 실행 방지) / 알림 기록(최근 100건).
- 로컬 파일 제공(`/media/<appId>/…`)은 경로 탈출 차단.

### 4-4. 블로그 분석 (`backend/blog_to_listing.py`)

- **동의 게이트**: 필수 동의 4개가 모두 true이고 반려·철회가 아닌 신청서의 `blog_url`만 처리. `--own-url`은 개발자 본인 블로그 테스트 전용.
- 네이버 모바일 페이지로 변환해 **단일 글 1건만** 수집: 본문(최대 8000자), 이미지 최대 15장(짧은 변 400px 미만·스티커 제외, 고해상도 `type=w966`로 교체).
- AI: `LLM_PROVIDER`로 선택 — OpenAI Responses API(`gpt-5.4-mini`, reasoning low) / Gemini(`gemini-3.8-flash`). 둘 다 같은 Pydantic 스키마로 구조화 출력, 시간 제한·재시도 횟수 지정(`LLM_TIMEOUT_S`, `LLM_ATTEMPTS`).
- 표시광고법 규칙을 시스템 프롬프트에 명시: 본문에 없는 가격·시설 금지(null), 숙소 공간 사진만 최대 6장, 나레이션 첫·끝 문장 형식.
- 후처리: 범위 밖 이미지 인덱스 제거, 컷 대본을 사진 수에 맞춰 자름.

### 4-5. 쇼츠 제작 (`backend/video_maker.py`)

- 1080×1920, 30fps. 사진은 정사각형으로 잘라 1080×1080 줌인/줌아웃(Ken Burns)으로 (0, 340)에 배치, 위에 UI 오버레이(배지·훅 문구·지역/제목·공간 태그·자막 2줄·가격/안내 2줄).
- 컷별 TTS 길이(+0.35초, 최소 3초)로 장면 길이 결정. BGM은 선택(볼륨 12%, 반복·페이드아웃).
- TTS: 기본 **Azure AI Speech 공식 REST**(ko-KR-SunHiNeural). `--tts edge`는 테스트 전용이며 결과 파일이 `final_shorts_TEST_ONLY.mp4` → 유튜브·릴스 업로더가 거부.

### 4-6. 인허가 대조 (`backend/license_check.py`)

- 공공데이터포털 행정안전부 인허가 API 4종, 엔드포인트 `https://apis.data.go.kr/1741000/{rural_homestays|lodgings|hanok_experience|foreigner_city_homestays}/info`. 사업장명 LIKE 검색, 최대 5페이지×100건. CSV 대조도 지원(`--csv`, utf-8-sig/cp949).
- 판정(`evaluate`): 상호 일치(정확 2점/포함 1점) + 주소 토큰 겹침 비율×2. 점수 ≥ 3.2 **이고** 주소 토큰 3개 이상 겹침(짧은 주소는 전부)일 때만 강한 일치 → 영업상태로 `match`/`closed`, 아니면 `uncertain`. 결과 없으면 `not_found`. 관리번호(`MNG_NO`)·폐업일 기록.
- 한계: 공공 데이터에 영업신고번호가 없을 수 있어 번호 확인은 관리자가 신고증 사본을 눈으로 본다.

### 4-7. 알림 (`backend/notify.py`)

- 채널: **이메일(SMTP, 기본 Gmail 앱 비밀번호)** + 문자(SOLAPI, 키가 있고 전화번호가 있을 때만). 둘 다 미설정이면 dry-run 기록.
- 선택 동의가 있을 때만 연락처를 사용. 종류: approved / rejected / withdrawn / video_ready / weekly_report / suspended. 정보성 안내만(정보통신망법 제50조), 메일 하단에 수신 중단 안내.
- 반려·철회는 알림 → 연락처 파기 순서.

### 4-8. 홍보 채널

- **유튜브** (`upload_youtube.py`): OAuth(`client_secret.json`, `youtube_token.json`, 범위 `youtube` — 삭제까지 하기 위해). 기본 private, unlisted/public은 `active` 숙소만. `containsSyntheticMedia: true`, 설명란에 `?id=` 링크와 AI 음성 고지. 업로드 후 `youtube_video_id` 기록 → 철회 시 자동 삭제. 미검증 API 프로젝트는 업로드가 비공개로 제한되므로 감사 승인 전에는 Studio 수동 업로드.
- **인스타 릴스** (`instagram_reels.py`): Graph API 컨테이너 생성 → 처리 대기(최대 10분) → 게시 → permalink 기록. `active`만. 댓글 키워드(ManyChat DM용) 선택. Graph API로 삭제가 안 될 수 있어 철회 시 앱에서 수동 삭제.

### 4-9. 기타

- `weekly_report.py`: active 숙소별 클릭·유튜브 조회수 누적값과 지난 리포트 차이 계산 → `stats_snapshots` + `last_report` 갱신 → 알림. `--no-send` 지원. Windows 작업 스케줄러 예시는 파일 머리말 참고.
- `find_hosts.py`: 네이버 검색 오픈 API 메타데이터만(본문·사진 수집 안 함). 후기성 글 제외, 호스트성 키워드 포함 글만 → `output/host_candidates.csv`(검토·연락·거절 기록 열 포함). 섭외는 호스트가 공개한 문의 채널로 1회, 거절 시 재연락 금지.
- `docs/make_usage_image.py`: 공공데이터포털 활용신청 첨부용 1600×900 '데이터 활용 계획' 이미지.

---

## 5. 보안·법적 장치 요약


| 위험 | 장치 |
|---|---|
| 미확인 숙소 노출(과태료) | 등록은 항상 `pending_verification`, 승인 시 확인 질문/체크리스트 + 검증자·방법·대조 결과 기록, 규칙상 `active`만 공개, 정기 재확인으로 폐업 시 `suspended` |
| 신고증 사본 유출 | Storage 생성만 허용, 다운로드 URL 없음, 관리자 로컬 화면에서만 열람, 반려·철회 시 즉시 파기 |
| 클릭 수 조작 | 규칙: `outbound_clicks` 단일 필드, 정확히 +1 |
| 신청서 오남용 | 필드 화이트리스트, 길이·형식(URL·이메일) 검사, 업종 4종, 상태·서버시간 강제, 신고증 경로가 자기 신청서 ID 아래인지 검사, App Check |
| 저작권(2차적 저작물) | 동의한 신청서의 글만 처리, 동의 전 샘플 선제작·업로드 금지, 사진 변형 없이 사용 |
| 허위·과장 광고 | 프롬프트 규칙 + 승인 체크리스트 "사실과 다른 표현 없음" |
| 개인정보 | 필수/선택 동의 분리·버전 기록, 선택 동의 없으면 연락처 저장 불가(규칙), 알림 기록에 연락처 미저장, 게스트 정보 미수집 |
| 관리자 화면 | 로컬 바인딩, CSRF, 경로 탈출 차단, HTML 이스케이프(Jinja) |
| 합성 음성 | 공식 TTS만 배포, 유튜브 합성 미디어 표기, 설명란·캡션에 AI 음성 고지 |

---

## 6. 테스트·검증 현황


| 테스트 | 내용 | 실행 |
|---|---|---|
| `app/test/widget_test.dart` | 지역 매칭, 이메일 형식, 가격 표기, 검색·정렬, ListingCard 렌더링(외국인 배지), 신청 폼 필수값 안내 | `cd app && flutter test` |
| `firebase/tests/rules.test.mjs` | Firestore: active만 읽기, 클릭 +1만, 신청서 화이트리스트·동의·형식, 기타 경로 차단 / Storage: licenses 생성만·5MB·이미지, listings 공개 읽기 | `cd firebase && npm run test:rules` |
| `backend/tests/e2e_emulator_test.py` | 에뮬레이터에서 신청 → 동의 확인 → CSV 대조 → 등록 → 관리자 승인 → 주간 리포트 → 철회·파기 7단계 (실제 발송 키 제거) | `cd firebase && npm run test:e2e` |
| `backend/tests/smoke_test.py` | 실제 쇼츠 렌더링(1080×1920), 인허가 판정, 알림 문구 | 키 불필요 |
| `backend/tests/admin_test.py` | 관리자 화면 렌더링·이스케이프·CSRF·경로 탈출 (가짜 DB) | 키 불필요 |
| `backend/tests/notify_test.py` | 동의·연락처 조합별 발송/기록 (가짜 SMTP·DB) | 키 불필요 |
| `gemini_test.py`, `llm_compare.py` | 실제 LLM 호출, 지어내기 여부·속도 비교 | API 키 필요 |
| `license_probe_all.py`, `license_live_test.py` | 공공 API 4종 연결·필드 확인, 실제 대조 판정 | 서비스키 필요 |

2026-11-12 기록된 결과: 스모크·관리자 테스트 통과, `flutter analyze` 오류 0, `flutter test` 통과, `flutter build web` 성공, 헤드리스 Chrome에서 목록·`?id=` 진입 확인, 공공 API 4종 연결 확인, LLM 비교에서 Gemini 504 시간 초과·OpenAI 평균 5~11초·검사 21/21.
이후 규칙 테스트·E2E 테스트가 추가되었고 `firebase/firestore-debug.log`에 에뮬레이터 실행 흔적이 있다(이 노트 작성 시 재실행은 하지 않음).
`firebase/.firebase/hosting.*.cache`가 2026-11-14에 갱신되어 호스팅 배포가 한 번 이상 이뤄진 것으로 보인다.

---

## 7. 실행 방법


### 환경

- Python 3.12 64비트 가상환경 `backend/.venv` (시스템 Python 3.14는 32비트라 `cryptography` 등 설치 불가)
- Flutter 3.50.0 (`C:\Users\dongchae\dev\flutter`), Node 22 (Functions)
- `.vscode/settings.json`: 터미널에서 `.env` 자동 사용

### 관리자 작업
```
backend\.venv\Scripts\python backend\admin_app.py      → http://127.0.0.1:8765
```
CLI로 할 때:
```
python backend/license_check.py check --application-id <ID> [--csv <파일>]
python backend/blog_to_listing.py --application-id <ID>
python backend/video_maker.py output/<ID>/listing_result.json --bgm <상업용 BGM>
python backend/upload_to_firestore.py publish output/<ID>/listing_result.json --application-id <ID>
python backend/upload_to_firestore.py approve <listing_id> --verified-by <이름> --method "<대조 방법>"
python backend/upload_youtube.py <mp4> <json> --listing-id <listing_id> --privacy public --site <URL>
python backend/instagram_reels.py <mp4> --listing-id <listing_id> [--keyword 제주01]

반려:  upload_to_firestore.py reject --application-id <ID> --reason "<사유>"   (등록 후: --listing-id)
철회:  upload_to_firestore.py withdraw <listing_id> --reason "<요청 경위>"
재확인: license_check.py recheck [--csv <파일>]
리포트: weekly_report.py [--no-send]
```

### 웹 배포
```
cd app && flutter build web --dart-define=RECAPTCHA_SITE_KEY=<키>
# build/web → firebase/public 복사 (index.html 제외), index.html → firebase/functions/index.html
cd firebase && firebase deploy --only firestore:rules,storage,functions,hosting
```
※ 복사 단계는 스크립트가 없어 수동이다. `firebase/public`에 index.html이 들어가면 OG 함수가 동작하지 않는다.

### 환경변수 (`.env`, 값은 비밀)

| 변수 | 용도 | 현재 .env |
|---|---|---|
| `FIREBASE_CREDENTIALS`, `FIREBASE_BUCKET` | Admin SDK | 있음 |
| `LLM_PROVIDER`, `OPENAI_API_KEY`, `GEMINI_API_KEY` (+선택 `OPENAI_MODEL`, `GEMINI_MODEL`, `LLM_TIMEOUT_S`, `LLM_ATTEMPTS`) | 블로그 분석 | 있음 |
| `DATA_GO_KR_SERVICE_KEY`, `LICENSE_API_LODGING/HANOK/FOREIGN` (`RURAL`은 기본값) | 인허가 대조 | 있음 |
| `SMTP_USER`, `SMTP_PASSWORD`, `MAIL_FROM_NAME`, `CONTACT_EMAIL`, `SITE_URL` | 이메일 알림·링크 | 있음 |
| `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION` | 쇼츠 나레이션 | **없음** |
| `SOLAPI_API_KEY/SECRET/SENDER` | 문자 알림(선택) | 없음 |
| `IG_USER_ID`, `IG_ACCESS_TOKEN`, `GRAPH_API_VERSION` | 릴스(선택) | 없음 |
| `NAVER_CLIENT_ID/SECRET` | 섭외 후보 검색 | 없음 |
| `BGM_PATH`, `TTS_PROVIDER`, `OUTPUT_DIR`, `SERVICE_NAME`, `FONT_*_PATH` | 선택 | — |
| `RECAPTCHA_SITE_KEY` | Flutter `--dart-define` (App Check) | .env 아님 |

유튜브는 `client_secret.json`(OAuth 클라이언트) 필요 → 첫 실행 때 브라우저 로그인 후 `youtube_token.json` 생성.

---

## 8. 분석 중 발견한 불일치·주의점


1. **Azure TTS 키가 .env에 없음** → 관리자 화면 "분석 + 쇼츠 생성"(기본 `TTS_PROVIDER=azure`)이 나레이션 단계에서 실패한다. 공개용 영상을 만들려면 Azure Speech 키가 필요.
2. **LLM 기본값 표기 불일치**: 코드 기본값은 `gemini`(`analyze_listing`), 이전 노트·.env 주석은 OpenAI 권장. 실제 동작은 .env의 `LLM_PROVIDER` 값을 따른다. `LLM_PROVIDER`를 지우면 Gemini로 돌아간다는 점 주의.
3. **"3대 동의" 주석**: `blog_to_listing.py` 머리말·`firestore.rules` 주석은 "3대 동의"라고 쓰지만 실제 필수 동의는 4개(개인정보 포함).
4. **알림 설명 낡음**: `weekly_report.py` 머리말은 "문자로 보낸다", `admin_app.py` 머리말은 `GEMINI_API_KEY`·`SOLAPI_*`만 언급 — 지금은 이메일(SMTP)이 기본 채널, LLM은 OpenAI/Gemini 선택.
5. **material_ui 이전 미완**: `pubspec.yaml`에 `material_ui`가 추가됐지만 코드는 여전히 `package:flutter/material.dart`를 import.
6. **재승인 시 알림 없음**: `suspended` → `active` 재승인 때는 승인 알림을 보내지 않는다(의도된 동작으로 보이나 호스트가 복구 사실을 모름).
7. **목록 확장성**: 공개 숙소 전체를 한 번에 구독한 뒤 클라이언트에서 필터·정렬·페이징한다. 숙소가 수백 개 이상이면 서버 쿼리·커서 페이징으로 바꿔야 한다. `StorageImage` 캐시도 비우지 않는다.
8. **재확인 비용**: `recheck_all`은 공개 숙소마다 공공 API를 따로 호출한다(최대 5페이지). 숙소가 많아지면 업종별 일괄 다운로드(CSV)로 대조하는 편이 낫다.
9. **에뮬레이터 경고**: E2E는 projectId `jikstay-e2e`를 쓰지만 에뮬레이터는 `jikstay-lkxu1` 단일 프로젝트 모드라 경고가 반복 기록된다(`firestore-debug.log`). 동작에는 문제없음. `firebase.json`에 emulators 설정이 없다.
10. **처리방침 수탁사**: 개인정보처리방침에 Firebase·Gmail만 적혀 있음. SOLAPI(문자) 사용 시 추가 필요. 블로그 본문·사진은 OpenAI/Gemini, 나레이션 문장은 Azure로 전송된다는 점도 법률 검토 때 함께 볼 것.

---

## 9. 남은 일


- [ ] `legal.dart` 자리표시 `[상호]`, `[대표자명]`, `[사업자등록번호]`, `[통신판매업 신고번호]`, `[사업장 주소]`, `[문의·삭제요청 이메일]`, `[기간]`, `[성명]`, `[기타 수탁사]` 실제 정보로 교체 + 법률 검토 (문구 바꾸면 `kConsentVersion` 올리기)
- [ ] reCAPTCHA Enterprise 키 발급 → `--dart-define` 빌드 → 콘솔에서 Firestore·Storage App Check **시행(Enforce)**
- [ ] Azure Speech 키 발급(.env), 상업 이용 허용 BGM 준비
- [ ] 유튜브 OAuth 클라이언트(`client_secret.json`) 준비, API 프로젝트 감사(Audit) 신청 — 승인 전에는 Studio 수동 업로드
- [ ] (선택) SOLAPI 발신번호 등록, 인스타 프로페셔널 계정·Meta 앱 권한, 네이버 검색 API 키
- [ ] 빌드 → `firebase/public`·`functions/index.html` 복사 자동화 스크립트
- [ ] 주간 리포트·정기 재확인 작업 스케줄러 등록
- [ ] 섭외 연락의 정보통신망법 제50조 해당 여부 법률 자문
- [ ] 8번 항목의 주석·문서 불일치 정리, material_ui 이전 검토

---

## 10. 변경 이력


### 2026-11-12 이전 — 원본 기획 대비 사실 확인

| 주장 | 결과 |
|---|---|
| 개정 공중위생관리법 2026-11-12 시행, 미확인 숙박상품 중개 시 과태료 500만 원 | 사실. 법률 2025-11-11 공포. 법률상 상한 1,000만 원, 시행령(2026-10-20 공포) 부과기준 500만 원. 기존 등록 상품도 재확인 필요 |
| YouTube `status.containsSyntheticMedia` | 사실. `videos.insert` 공식 필드 |
| "제주 레퍼런스 10선" 숙소명 | 검증 불가 → 사용 중단 |

### 운영 방식 변경 (법적 모순 제거)

- 네이버 검색결과 스크래핑·타인 블로그 본문 방문(`collect_50_jeju_hosts.py`) 삭제 → `find_hosts.py`(오픈 API 메타데이터만)
- "선 제작 후 제안" 폐지: 동의 전 샘플 영상 제작·업로드 금지
- 블로그 처리는 동의한 신청서 URL만

### 코드 수정

| 문제 | 수정 |
|---|---|
| 등록 즉시 `active` | `publish` → `pending_verification`, `approve` 후에만 `active` |
| 누구나 클릭 수 임의 수정 | 규칙: 정확히 +1 |
| 신청서 필드 무제한 | 화이트리스트·형식·상태·시간 강제 |
| Storage 규칙 없음, 신고증 공개 URL | `storage.rules`, 앱은 경로만 저장 |
| `make_public()` 실패(균일 버킷 액세스) | `listings/` 공개 읽기 규칙 + 직접 URL |
| 지역 필터 '부산/경상' 오동작 | 칩별 키워드 목록 매칭 |
| 영상 클립 크기 불일치, 하단 문구 넘침 | 1080×1080 VideoClip, 2줄 분리 |
| edge-tts 상업 이용 불명확 | Azure 공식 REST 기본, edge는 `_TEST_ONLY` |
| 유튜브 기본 unlisted 샘플 업로드 | 기본 private, 공개는 active만 |

### 2026-11-12 — 기획서 대비 보강·운영 기능

- 개인정보 필수/선택 동의 분리, 약관 버전 기록, 사업자 정보·처리방침 푸터
- 반려(`reject`)·철회(`withdraw`)와 파기, `?id=` 상세페이지, 유튜브 영상 ID 추적·삭제
- 호스트 알림, 인스타 릴스, 주간 리포트, 로컬 관리자 화면, App Check, 인허가 대조·재확인
- 공공데이터 API 4종 연결 확인, 블로그 분석에 OpenAI 추가(LLM 비교)

### 2026-11-12 이후 (코드에서 확인)

- Firebase 프로젝트 `jikstay-lkxu1` 생성, `firebase_options.dart` 실제 값 반영
- 알림 기본 채널을 **이메일(SMTP/Gmail)**로 변경, 문자는 선택. 선택 동의 항목에 이메일 추가(약관 `2026-11-12.2`)
- 목록 검색·정렬·더 보기 페이징, App Check 대응 `StorageImage`
- Cloud Functions `serveApp`: `?id=` 링크 미리보기용 OG 태그 주입
- 보안 규칙 단위 테스트(`rules.test.mjs`)와 에뮬레이터 E2E 테스트 추가
- 철회·반려 시 관리자 PC의 `output/<appId>` 로컬 캐시까지 파기
- 인허가 판정 강화(주소 토큰 3개 이상 겹침 조건, 도로명·지번 중 더 맞는 쪽, 관리번호·폐업일 기록)

### 2026-11-14 — 직접 수집기 재도입 (운영자 결정)

- `backend/collect_50_jeju_hosts.py` 추가: API 키 없이 네이버 모바일 검색 결과 → 각 블로그 글 본문을 직접 방문해
  후기 제외, 호스트 신호 단어 3개 이상, 사진 5장 이상인 글만 `output/jeju_50_verified_hosts.csv`로 저장
- **11-12에 이용약관·robots.txt 위반 우려로 삭제했던 방식을 운영자가 위험을 감수하고 다시 도입한 것.** `find_hosts.py`(API 전용)는 그대로 둠
- 붙여넣은 원본 대비 수정: 검색어의 `-내돈내산 -후기` 제외 연산자 제거(붙이면 결과 0건), `PostView.naver?blogId=&logNo=` 형식 링크도 추출,
  `license_mentioned`는 숫자가 붙은 신고번호·사업자번호 표기만 Y(원본은 '농어촌민박' 단어만 있어도 Y), 사진은 주소 기준 중복 제거,
  본문 앞부분의 협찬 고지도 제외, 같은 글 재방문 방지, 검토·연락·거절 기록 열(`opted_out` 등) 추가
- 테스트 실행(3개 지역, 목표 3): 2곳 수집. 그중 1곳은 호스트가 아닌 한달살기 정보글이라 **결과는 반드시 사람이 검토**해야 함
- 수집 결과를 근거로 방명록·댓글에 광고성 연락을 하면 정보통신망법 제50조 문제가 생길 수 있음

### 2026-11-14 — 에어비앤비 벤치마킹 UI/UX 전면 개편 & 동영상 제작 제거

- **동영상(쇼츠) 제작·배포 파이프라인 제거**:
  - `admin_app.py`에서 `video_maker` 렌더링 및 유튜브·릴스 홍보 게시(`pipeline_promote`) 제거 → `1. 숙소 상세 AI 분석` 단일 단계로 단순화 (Azure Speech 키 불필요)
  - `blog_to_listing.py`에서 `ShortsScript` 스키마 제거, 사진 선별 최대 15장으로 확대, 네이버 블로그 외 일반 `https://` 숙소 소개 페이지 수집 지원
  - `weekly_report.py`, `notify.py`, `legal.dart`(`kConsentVersion = 2026-11-14.1`)에서 쇼츠·유튜브 관련 문구 정리
- **표준 Amenity(편의시설) 및 필수 스펙 체계 도입 (`app/lib/amenities.dart`)**:
  - 9대 표준 카테고리(`전망 및 입지`, `스파 및 부대시설`, `주차 및 출입`, `주방 및 다이닝`, `가족 및 키즈`, `객실 및 침구`, `세탁 및 다림질`, `엔터테인먼트·업무`, `냉난방 및 안전`) + 60여 개 아이콘 매핑 + `[편의시설 N개 모두 보기]` 모달 + **`숙소에 없는 시설(unavailable_amenities)` 취소선 표기**
  - 객실 물리 스펙(`침실·침대·욕실·층수`), 3대 핵심 하이라이트 카드, 숙소 이용규칙(`체크인/아웃·매너타임·금연·반려동물`), 위치·주변 안내 섹션 신설
- **직거래 예약·입점 신청 전환율 극대화 (`app/lib/main.dart`, `app/lib/detail_page.dart`)**:
  - 랜딩(`stays-kr` 참조): 통합 검색 Hero 바(여행지·일정·인원·키워드) + Amenity 아이콘 카테고리 탭 바 + 3대 안심 가치 카드 + FAQ 6문 6답 아코디언 + 호스트 입점 유도 배너
  - 상세(`rooms` 참조): 데스크톱 5분할 벤토 포토 그리드 + 공간별 사진 투어 모달 + 2단 레이아웃 우측 Sticky 신청 카드(일정·인원 선택 시 예상 금액 & 약 14% 수수료 절감액 배지 계산, 호스트 이벤트 체크박스, 신청 문구 클립보드 자동 복사 브릿지 모달)
  - `?demo=1` 및 `?id=stay_demo_haeundae`로 해운대·송정 5층 오션뷰 레퍼런스 숙소 구성을 로컬에서 즉시 미리보기 지원 (`app/lib/demo_data.dart`)

### 2026-11-15 — 공공 API 선(先)구축 2-Tier 검색 플랫폼 전환 · CPC 수익모델 · 글로벌(4개국어) 확장

- **공공 인허가 API + 네이버 오픈 API 결합 큐레이션 파이프라인 (`backend/curate_public_stays.py`)**:
  - 5대 권역(`제주`·`강원`·`부산/경상`·`전라/충청`·`서울/경기`) × 4대 합법 인허가 업종(`농어촌민박업`·`일반/생활숙박업`·`한옥체험업`·`외국인관광도시민박업`)별로 `영업/정상` 숙소를 조회하고 충실도·후기수 점수로 상위 100개씩 선별
  - Storage 용량 0원 설계: 이미지 파일을 복제 저장하지 않고 한국관광공사 `KorService2`(`searchStay2` 3,123곳 사진 카탈로그 + 상위 숙소 `detailImage2` 객실·외관 다중 갤러리, `.env` `TOUR_API_KEY` 연동 완료) 외부 공식 `https://tong.visitkorea.or.kr/...` 이미지 URL 링크만 참조 (`WebHtmlElementStrategy.fallback`으로 CORS 대응 + 미보유 숙소 전용 비주얼 히어로 배너 제공)
  - 네이버 블로그 검색 오픈 API 메타데이터(제목·요약·블로거명·원문 링크 최대 4건) 및 네이버 지도·통합검색 아웃링크 보완 (무단 본문 스크래핑 없음)
- **2-Tier(`public` 미인증 / `claimed` 공식인증) UX 및 호스트 주인 등록 (`app/lib/main.dart`, `app/lib/detail_page.dart`, `firebase/firestore.rules`)**:
  - 공공 자동선별 숙소 상세 하단에 `[무료 주인 등록 · 직거래 연결]` 배너 노출 → 클릭 시 상호·주소·업종·`claim_listing_id`가 자동 기입된 입점 모달 실행
  - 승인(`approve`) 시 기존 공공 숙소의 누적 클릭수를 승계하고 신규 환영 크레딧 **30,000원(100클릭분)** 자동 부여 및 `is_sponsored` 최상단 우선 노출 활성화 (`backend/upload_to_firestore.py`, `backend/admin_app.py`)
- **CPC(클릭당 과금) 리다이렉트 엔진 (`firebase/functions/index.js` — `/go?id=stay_xxx`)**:
  - 검색봇(Bot User-Agent) 필터링 + SHA-256 해시 기반 동일 IP·브라우저 24시간 중복 클릭 차단(`cpc_click_dedup`)
  - 유효 클릭 시 `outbound_clicks` +1 및 `cpc_balance`에서 `cpc_rate`(기본 300원) 차감, 잔액 소진 시 숙소를 내리지 않고 자동으로 일반 무료(네이버 지도 연결) 모드로 전환
- **국내·해외 동시 타겟팅 다국어 UI & Programmatic SEO (`app/lib/i18n.dart`, `firebase/functions/index.js`)**:
  - 한국어(`ko`) · 영어(`en`) · 일본어(`ja`) · 번체중국어(`zh`, 대만·홍콩 타겟) 4개 국어 UI 전환기 및 **한국어+외국어 자동 병기 예약 문의 문구 복사 브릿지** 탑재
  - Cloud Functions에서 다국어 OG 태그, `hreflang`, `Schema.org/LodgingBusiness` JSON-LD, `<noscript>` 본문 스냅샷, 동적 `/sitemap.xml` 및 `/robots.txt` 제공
- **초경량 다이어트 & 공공 여행·혜택·매거진 허브 (`backend/build_travel_hub.py`, `app/lib/travel_hub.dart`)**:
  - **경량화**: 미사용 패키지(`material_ui`, `cupertino_icons` 등 5종) 및 폐기된 레거시 영상·크롤러 파일(`video_maker.py`, `upload_youtube.py`, `instagram_reels.py`, `collect_50_jeju_hosts.py`), 배포 디버그 심볼(`*.symbols`, `*.map` 약 6.3MB) 삭제. 홈 화면을 `snapshots().limit(1000)` 실시간 스트림 대신 **초경량 정적 CDN 색인(`public_stays_index.json` 72% 축소) + `claimed` 단건 병합** 하이브리드 구조로 전환하고 카드 썸네일에 `cacheWidth` 메모리 최적화를 적용
  - **TourAPI(`KorService2`) 심화 보강**: 상위 숙소에 `detailCommon2`·`detailIntro2`·`locationBasedList2`를 연동해 공식 소개글·체크인 시간·취사/주차 정보 및 **반경 5km 주변 명소·맛집 TOP 4** 섹션 추가
  - **반값여행 · 축제 · 공공 매거진 탭**: 2026 대한민국 반값여행 25개 시·군 원클릭 합법숙소 연동, 외국인 디지털 관광주민증(최대 50% 즉시할인) 4개 국어 안내, 실시간 지역 축제(`searchFestival2`), 추천 여행코스(`contentTypeId=25`), 문체부 《K-공감》 및 광역지자체 공식 웹진/e-Book 무료 열람관 구축

### 2026-11-15 (추가) — 호스트 신청·승인 절차 전면 제거 & 사용자 별점(Score)·후기(Review) 시스템 구축

- **호스트 승인·입점 절차 및 Storage 파일 업로드 전면 폐지**:
  - `firebase/firestore.rules`: `host_applications` 컬렉션 규칙 삭제(기본 전면 차단으로 전환).
  - `firebase/storage.rules`: `licenses/...` 영업신고증 업로드 규칙 삭제 및 클라이언트 파일 업로드 전면 차단(`allow write: if false`).
  - `app/`: `HostOnboardingDialog`(약 315줄), `[호스트 입점·주인등록]` 버튼, `_HostClaimCtaCard` 및 `file_picker`·`firebase_storage` 패키지(하위 의존성 22종 포함) 완전 제거로 번들 추가 경량화 달성.
  - `backend/admin_app.py`: 신청서 승인/반려 화면을 제거하고 공개 숙소 관리 · 공공 API 수집 · 사용자 후기 스팸 삭제(Admin SDK) 전용 콘솔로 개편.
- **사용자 참여형 별점(`score` 1~5점) · 후기(`review`) 기능 추가**:
  - `listings/{listingId}/reviews/{reviewId}` 서브컬렉션 신설: 누구나 열람 가능하며, 별점 `1~5` 정수·닉네임 `1~24`자·후기 `4~600`자 검증 통과 및 부모 `listings` 문서의 `review_count`(+1)·`score_sum`(+score)·`last_review_id` 갱신이 단일 `WriteBatch`로 원자적으로 묶일 때만 생성 허용(수정·삭제 불가로 조작 원천 차단).
  - `app/lib/detail_page.dart` (`UserReviewsSection`): 평균 평점 요약 배지(`★ 4.8 / 5.0`), 1~5점 별점 선택기, 방문 유형 칩, 다국어(`ko`/`en`/`ja`/`zh`) 후기 작성 폼 및 후기 목록 UI 탑재.
  - `app/lib/main.dart` & `firebase/firestore.indexes.json`: 메인 숙소 카드 별점 표시, `평점 높은순`(`ListingSort.ratingDesc`) 정렬 추가, 정적 색인 위에 `review_count > 0` 숙소의 실시간 평점을 얹는 하이브리드 오버레이 및 복합 인덱스 추가.
  - `firebase/functions/index.js`: 사용자 별점 보유 숙소에 Google 검색 리치 결과용 `Schema.org/AggregateRating` JSON-LD 자동 주입.

### 2026-11-15 (전면 개편) — Zillow 스타일 로컬 디스커버리 지도 + 전국 17개 시·도 E-book·볼거리·먹거리·축제 실시간 피드 전환

- **제품 정체성 전환 (`에어비앤비식 숙소 예약앱` 탈피 → `방문 유도형 올인원 로컬 여행 플랫폼`)**:
  - 첫 화면에서 복잡한 숙소 전용 필터(1박/일주일/한달·인원·편의시설 탭)를 걷어내고, **좌측 Zillow 스타일 인터랙티브 지도(`app/lib/zillow_map_view.dart`) + 우측 대표 이벤트 하이라이트 & 실시간 연동 로컬 피드(`app/lib/main.dart`)** 분할 뷰로 개편.
  - 외부 지도 SDK 패키지 추가 없이 순수 Dart Web Mercator 타일(국토교통부 `VWorld` 한국어 기본지도 + `OpenStreetMap` 폴백 + 화면 충돌 방지 알약 마커)로 구현해 번들 증가 거의 0 유지.
- **전국 17개 시·도 지자체 공식 관광지도(PDF/E-book) 및 볼거리·먹거리 균등 통합 (`backend/build_travel_hub.py`)**:
  - 서울·부산·대구·인천·광주·대전·울산·세종·경기·강원·충북·충남·전북(무주·진안·장수·전북생태관광 포함)·전남·경북·경남·제주 **17개 전 시·도 공식 관광안내도 PDF & E-book 포털 20종** 회원가입 없이 원클릭 열람 연동.
  - 한국관광공사 `KorService2`로 17개 시·도 균등 **볼거리(`12`)·먹거리(`39`) 280곳 + 진행중 전국 축제(`searchFestival2`) 34건** 및 **합법 안심숙소 1,769곳 위경도(`lat`/`lng`)** 통합.
- **자연스러운 동선 연결 및 방문 혜택 쿠폰(CPC·월정액) 수익모델 (`app/lib/spot_detail_sheet.dart`, `firebase/firestore.rules`)**:
  - 지도 핀이나 피드 카드를 누르면 **지자체 공식 관광지도 열람 + `🎁 방문 혜택 쿠폰` 현장 제시 모달 + 지도 길찾기/전화(`outbound_clicks` +1 CPC 집계) + 반경 내 주변 먹거리·볼거리·축제·안심숙소 자동 연결(`buildConnectedBundle`) + 방문자 별점·한줄 후기(`spots/{spotId}/reviews`)**를 원스톱 제공.

### 2026-11-15 (마스터 전략 전체 반영 & 실서버 배포 완료) — 동적 포털 · 멀티맵 대중교통 · 원본 PDF · 2,015페이지 SEO · 전환 통계

- **Firebase 실서버(`jikstay-lkxu1`) 전체 반영 완료 (`firestore`, `storage`, `functions`, `hosting`)**:
  - 구버전 `host_applications` 및 `licenses/` 업로드 규칙을 실서버에서 완전히 제거하고, `listings`·`spots` 클릭 카운트(`outbound_clicks` +1) 및 방문자 별점·후기(`1~5`점 원자적 배치 검증) 보안 규칙과 복합 인덱스를 실서버 배포 완료.
  - 전국 17개 시·도 명소·맛집·축제 **314건**을 실서버 Firestore `spots` 컬렉션에 동기화 완료 (`backend/build_travel_hub.py --upload-spots`).
- **네이버 포털형 일일 동적 스마트 배너 & 전국 전통 5일장 자동 매칭 (`app/lib/main.dart`, `app/lib/discovery_models.dart`)**:
  - 우측 피드 최상단에 6초 자동 롤링 `_SmartPortalRollingBanner` 탑재: 접속 날짜(`끝자리 1·6 / 2·7 / 3·8 / 4·9 / 5·0`)에 맞춰 **오늘 장 서는 전국 전통 5일장(`TRADITIONAL_5DAY_MARKETS` 20선)** 자동 노출 + 마감 임박 축제(`⏰ 마감 D-N` / `🎊 지금 진행중`) + 지자체 공식 관광지도 PDF 바로가기 + 반값여행 50% 환급 슬라이드 자동 구성.
- **지자체 원본 PDF 직링크 다중 버튼 (`backend/build_travel_hub.py`, `app/lib/spot_detail_sheet.dart`, `app/lib/travel_hub.dart`)**:
  - 장수군청 공식 관광안내지도 원본(`tour_guide.pdf`), 《장수여행》 종합 가이드북 원본(`tourist.pdf`), 장수 문화관광 포털(`index.jangsu`), 무주·진안·전북생태관광 등 지자체 `pdf_links` 다중 버튼을 상세 시트와 공공 매거진 탭 양쪽에 탑재.
- **네이버지도 · 카카오맵 · 구글맵 3사 원클릭 대중교통·내비 길찾기 (`app/lib/spot_detail_sheet.dart`, `app/lib/detail_page.dart`)**:
  - 내국인용 **네이버지도 길찾기**·**카카오맵 대중교통/내비(`map.kakao.com/link/to/...`)** 및 외국인 FIT 관광객용 **Google Maps 대중교통(`travelmode=transit`)** 딥링크를 명소·식당·축제 시트와 숙소 상세페이지 모두에 탑재.
- **Programmatic SEO 2,015 URL 확장 & 방문·전환 분석 대시보드 (`firebase/functions/index.js`, `backend/admin_app.py`)**:
  - `serveApp` Cloud Function이 `?id=stay_...`뿐 아니라 `?spot=spot_...`(`Festival` / `Restaurant` / `TouristAttraction` JSON-LD) 및 `?region=전북` 등 17개 시·도(`TouristDestination` JSON-LD)까지 동적 OG 태그·다국어 `hreflang`을 서버 주입하며, `/sitemap.xml`이 실시간 **2,015개 URL**을 검색엔진에 노출.
  - 웹 클라이언트 전환 이벤트 브릿지(`jikstayTrackEvent` → GA4 `gtag`/`dataLayer`) 및 로컬 관리자 콘솔 `/analytics` B2G·광고주용 시·도별/장소별 전환 통계 대시보드 추가.

### 2026-11-15 (Story-First 고도화) — 선택 과부하 제거 · 하루 한 편 지자체 가이드북 스토리 배너 · 매거진형 상세 가독성 최적화

- **선택 피로(Choice Overload) 제거 UX (`app/lib/main.dart`)**:
  - 상단 2줄 24개 필터 칩 벽과 복수의 광고성 배너를 걷어내고, **단일 탐색 바(`[📍 지역 선택 토글]` + 핵심 테마 탭)**와 우측 **하루 단 한 편의 주인공 스토리 히어로 배너(`_DailyStoryHeroCard`)** 구조로 정돈.
- **지자체 공식 가이드북(PDF) 원문 무편집 일일 스토리 큐레이션 (`backend/build_travel_hub.py`, `app/lib/discovery_models.dart`)**:
  - 장수군청 공식 가이드북 《장수여행》 p.9 〈금강첫물, 뜬봉샘 발원지〉를 비롯해 무주 덕유산 가문비나무 숲길, 강진 백련사 동백숲, 영월 청령포, 순천만습지, 청송 주산지 등 지자체 책자 원문과 한국관광공사 고화질 다중 사진을 계절·월별 테마에 맞춰 하루 한 편씩 자동 추천.
- **매거진형 스토리 상세 페이지 & 핵심 탐방정보 박스 (`app/lib/story_detail_page.dart`, `/?story=...` SEO 연동)**:
  - 본문 폭 `760px` 제한 · 글자 크기 `16.5px` · 줄간격 `1.88` 에디토리얼 가독성 적용 + **《장수여행》 p.9 하단 스타일 초록 핵심 탐방정보 박스(코스·소요시간·해설시간·문의처·무장애 편의시설)** + 수록 가이드북 PDF 원본 직링크(`tourist.pdf#page=9`) + 3사 대중교통 길찾기 + 과하지 않은 주변 핵심 동선 추천 결합.
- **초기화면 지도 제거 — 순수 매거진형 Story-First 홈 레이아웃 (`app/lib/main.dart`)**:
  - 초기화면에서 지도(`ZillowMapView`)를 완전히 제거하여 Zillow/네이버지도형 정보 포털 느낌을 없애고 초기 타일 네트워크 요청 0건 달성.
  - 중앙 정렬(`maxWidth: 1040`) 와이드 2단 에디토리얼 스토리 히어로 카드 + 함께 읽어볼 지자체 가이드북 스토리 스트립 + 반응형 2열 로컬 큐레이션 피드 구조로 개편(길찾기는 상세 페이지/시트 내 네이버·카카오·구글맵 원클릭 딥링크로 연결).



