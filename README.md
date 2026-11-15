# 직스테이 로컬 (JikStay Local)

> **하루 한 편, 떠나고 싶은 한국의 숨은 로컬 스토리 & 지자체 공식 관광지도·동선 연결 플랫폼**
> - 실서비스 URL: <https://jikstay-lkxu1.web.app>
> - 마스터 전략서: [docs/JIKSTAY_MASTER_STRATEGY.md](docs/JIKSTAY_MASTER_STRATEGY.md)
> - 상세 구현 노트: [NOTES.md](NOTES.md)

## 핵심 특징

- **선택 과부하 제거 & 지도 없는 Story-First 매거진 첫 화면**: 복잡한 지도·필터 대신 계절·테마에 맞춰 지자체 공식 가이드북(PDF)·문화관광 자료 원문을 하루 한 편 와이드 매거진 카드로 추천하고, 클릭 시 가독성이 최적화된 스토리 상세 페이지(`/?story=...`)로 안내합니다.
- **전국 17개 시·도 공공데이터 통합**: 한국관광공사 `KorService2`(축제·볼거리·먹거리·여행코스), 행정안전부 4대 합법 숙박 인허가 데이터(1,769곳), 지자체 공식 관광지도 원본 PDF 직링크를 초경량 매거진 피드로 통합합니다.
- **원클릭 대중교통·내비 & 주변 동선 추천**: 네이버지도 · 카카오맵 대중교통/내비 · Google Maps 대중교통(`KO·EN·JA·ZH` 4개 국어 대응) 딥링크와 반경 내 로컬 식당·명소·안심숙소 동선을 자연스럽게 이어줍니다.
- **Programmatic SEO**: Firebase Cloud Functions(`serveApp`, `serveSitemap`)를 통해 스토리(`?story=`), 명소·축제(`?spot=`), 17개 시·도(`?region=`), 합법숙소(`?id=`) 2,000여 개 URL에 `Schema.org` JSON-LD 및 다국어 `hreflang` 메타데이터를 동적 주입합니다.

## 디렉토리 구조

- `app/` — Flutter Web 프론트엔드. 화면별 코드는 `lib/home/`(홈 카드), `lib/detail/`(숙소 상세), `lib/discovery/`(파싱·시드 데이터), 그 외 `lib/spot_detail_sheet.dart`·`lib/story_detail_page.dart`·`lib/trip_planner.dart`
- `backend/` — 공공 API 수집·큐레이션·번역·네이버 보강 파이프라인과 로컬 관리자 콘솔 (`curate_public_stays.py`, `build_travel_hub.py`, `translate_hub.py`, `enrich_naver_local.py`, `admin_app.py`)
- `firebase/` — Firestore/Storage 보안 규칙, 복합 인덱스, Cloud Functions(Node.js 22, `asia-northeast3`), 규칙·함수 테스트
- `deploy.ps1` — 허브 데이터 분할 → Flutter Web 빌드 → Firebase 배포 자동화
- 현재 구조·데이터 흐름·남은 일: [NOTES.md](NOTES.md) · 지난 이력: [docs/CHANGELOG.md](docs/CHANGELOG.md)

## 테스트

push·PR 마다 GitHub Actions `CI`가 아래를 모두 실행합니다.

```powershell
cd app; flutter analyze; flutter test
cd firebase; npm run test:functions; npm run test:rules   # 규칙 테스트는 Firebase 에뮬레이터(Java) 필요
backend\.venv\Scripts\python backend\tests\smoke_test.py   # admin_test / curate_test / naver_filters_test / split_hub_test
```

## 빌드 및 배포

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Deploy
```
