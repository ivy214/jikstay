# 직스테이 로컬 (JikStay Local)

> **하루 한 편, 떠나고 싶은 한국의 숨은 로컬 스토리 & 지자체 공식 관광지도·동선 연결 플랫폼**
> - 실서비스 URL: https://jikstay-lkxu1.web.app
> - 마스터 전략서: [docs/JIKSTAY_MASTER_STRATEGY.md](docs/JIKSTAY_MASTER_STRATEGY.md)
> - 상세 구현 노트: [NOTES.md](NOTES.md)

## 핵심 특징
- **선택 과부하 제거 & Story-First 매거진 UX**: 복잡한 필터 대신 계절·테마에 맞춰 지자체 공식 가이드북(PDF)·문화관광 자료 원문을 하루 한 편 추천하고, 클릭 시 가독성이 최적화된 매거진형 스토리 상세 페이지(`/?story=...`)로 안내합니다.
- **전국 17개 시·도 공공데이터 통합**: 한국관광공사 `KorService2`(축제·볼거리·먹거리·여행코스), 행정안전부 4대 합법 숙박 인허가 데이터(1,769곳), 지자체 공식 관광지도 원본 PDF 직링크를 외부 무거운 지도 SDK 없이 경량 지도로 연결합니다.
- **원클릭 대중교통·내비 & 주변 동선 추천**: 네이버지도 · 카카오맵 대중교통/내비 · Google Maps 대중교통(`KO·EN·JA·ZH` 4개 국어 대응) 딥링크와 반경 내 로컬 식당·명소·안심숙소 동선을 자연스럽게 이어줍니다.
- **Programmatic SEO**: Firebase Cloud Functions(`serveApp`, `serveSitemap`)를 통해 스토리(`?story=`), 명소·축제(`?spot=`), 17개 시·도(`?region=`), 합법숙소(`?id=`) 2,000여 개 URL에 `Schema.org` JSON-LD 및 다국어 `hreflang` 메타데이터를 동적 주입합니다.

## 디렉토리 구조
- `app/` — Flutter Web 프론트엔드 (`lib/main.dart`, `lib/story_detail_page.dart`, `lib/spot_detail_sheet.dart`, `lib/zillow_map_view.dart`)
- `backend/` — 공공 API 수집·큐레이션 파이프라인 및 로컬 관리자 콘솔 (`build_travel_hub.py`, `curate_public_stays.py`, `admin_app.py`)
- `firebase/` — Firestore/Storage 보안 규칙, 복합 인덱스, Cloud Functions(Node.js 22, `asia-northeast3`)
- `deploy.ps1` — Flutter Web 프로덕션 빌드 · 경량화 동기화 · Firebase 전체 배포 자동화 스크립트

## 빌드 및 배포
```powershell
# 테스트 실행
Push-Location app
flutter test
Pop-Location

# 프로덕션 빌드 및 Firebase 배포
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -Deploy
```
