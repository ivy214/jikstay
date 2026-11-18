// Firebase 지연 초기화: 첫 화면은 정적 JSON만 쓰므로 runApp 을 막지 않고 뒤에서 병렬로 초기화한다.
// Firestore·Auth 를 쓰는 곳은 사용 직전에 `await firebaseReady();` 를 호출한다.
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

/// reCAPTCHA Enterprise 사이트 키: flutter build web --dart-define=RECAPTCHA_SITE_KEY=...
const kRecaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

Future<void>? _ready;

/// Firebase·App Check 초기화를 1회만 수행한다. 실패하면 다음 호출에서 다시 시도한다.
Future<void> firebaseReady() {
  return _ready ??= _init().catchError((Object e) {
    _ready = null;
    throw e;
  });
}

Future<void> _init() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kRecaptchaSiteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(providerWeb: ReCaptchaEnterpriseProvider(kRecaptchaSiteKey));
  } else {
    debugPrint('경고: RECAPTCHA_SITE_KEY 미설정 — App Check 비활성');
  }
}
