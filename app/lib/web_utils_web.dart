import 'dart:convert';
import 'dart:js_interop';

@JS('jikstaySyncUrl')
external void _jikstaySyncUrl(JSString? listingId);

@JS('jikstaySyncPortalParams')
external void _jikstaySyncPortalParams(JSString? region, JSString? spotId, JSString? storyId);

@JS('jikstayResetHomeUrl')
external void _jikstayResetHomeUrl(JSString? region);

@JS('jikstayTrackEvent')
external void _jikstayTrackEvent(JSString eventName, JSString payloadJson);

@JS('jikstayCurrentOrigin')
external JSString _jikstayCurrentOrigin();

@JS('jikstayFetchText')
external JSPromise<JSString> _jikstayFetchText(JSString url);

void syncListingUrl(String? listingId) {
  _jikstaySyncUrl(listingId?.toJS);
}

void syncPortalParams({String? region, String? spotId, String? storyId}) {
  _jikstaySyncPortalParams(region?.toJS, spotId?.toJS, storyId?.toJS);
}

/// 홈으로 돌아왔을 때 주소를 홈 상태로 (상세·여행코스·주제 파라미터 제거, 지역·언어는 유지)
void resetHomeUrl({String? region}) {
  try {
    _jikstayResetHomeUrl(region?.toJS);
  } catch (_) {}
}

void trackPortalEvent(String eventName, [Map<String, Object?> params = const {}]) {
  try {
    _jikstayTrackEvent(eventName.toJS, jsonEncode(params).toJS);
  } catch (_) {}
}

String currentSiteOrigin() {
  final origin = _jikstayCurrentOrigin().toDart;
  return origin.isEmpty ? 'https://jikstay.app' : origin;
}

Future<Map<String, dynamic>?> fetchWebJson(String relativeUrl) async {
  try {
    final raw = (await _jikstayFetchText(relativeUrl.toJS).toDart).toDart;
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

@JS('jikstayStoreGet')
external JSString? _jikstayStoreGet(JSString key);

@JS('jikstayStoreSet')
external void _jikstayStoreSet(JSString key, JSString value);

@JS('jikstayShare')
external JSPromise<JSBoolean> _jikstayShare(JSString title, JSString url);

/// 브라우저 저장소(localStorage). 사생활 보호 모드 등으로 막혀 있으면 null.
String? storeGet(String key) {
  try {
    return _jikstayStoreGet(key.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

void storeSet(String key, String value) {
  try {
    _jikstayStoreSet(key.toJS, value.toJS);
  } catch (_) {}
}

/// 기기의 공유 시트(Web Share API). 지원하지 않거나 취소되면 false.
Future<bool> nativeShare(String title, String url) async {
  try {
    return (await _jikstayShare(title.toJS, url.toJS).toDart).toDart;
  } catch (_) {
    return false;
  }
}

@JS('jikstayGeo')
external JSPromise<JSString> _jikstayGeo();

/// 현재 위치(위도, 경도). 권한 거부·미지원·시간 초과면 null.
Future<(double, double)?> currentPosition() async {
  try {
    final raw = (await _jikstayGeo().toDart).toDart;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    return (lat == null || lng == null) ? null : (lat, lng);
  } catch (_) {
    return null;
  }
}
