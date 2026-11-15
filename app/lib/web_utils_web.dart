import 'dart:convert';
import 'dart:js_interop';

@JS('jikstaySyncUrl')
external void _jikstaySyncUrl(JSString? listingId);

@JS('jikstaySyncPortalParams')
external void _jikstaySyncPortalParams(JSString? region, JSString? spotId, JSString? storyId);

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

void trackPortalEvent(String eventName, [Map<String, Object?> params = const {}]) {
  try {
    _jikstayTrackEvent(eventName.toJS, jsonEncode(params).toJS);
  } catch (_) {}
}

String currentSiteOrigin() {
  final origin = _jikstayCurrentOrigin().toDart;
  return origin.isEmpty ? 'https://jikstay-lkxu1.web.app' : origin;
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
