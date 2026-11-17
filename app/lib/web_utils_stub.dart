void syncListingUrl(String? listingId) {}

void syncPortalParams({String? region, String? spotId, String? storyId}) {}

void resetHomeUrl({String? region}) {}

void trackPortalEvent(String eventName, [Map<String, Object?> params = const {}]) {}

String currentSiteOrigin() => 'https://jikstay.app';

Future<Map<String, dynamic>?> fetchWebJson(String relativeUrl) async => null;

final Map<String, String> _memStore = {};

/// 브라우저 저장소(localStorage) — 테스트·비웹 환경에서는 메모리에만 보관한다.
String? storeGet(String key) => _memStore[key];

void storeSet(String key, String value) => _memStore[key] = value;

/// 기기의 공유 시트(Web Share API). 지원하지 않으면 false → 호출 측이 링크 복사로 대체한다.
Future<bool> nativeShare(String title, String url) async => false;

/// 현재 위치(위도, 경도). 권한 거부·미지원이면 null.
Future<(double, double)?> currentPosition() async => null;
