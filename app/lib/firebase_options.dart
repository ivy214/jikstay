// Firebase 웹앱 설정 (firebase apps:sdkconfig WEB 로 받은 값, 2026-11-12).
// 웹 apiKey 는 비밀 값이 아니며 브라우저에 공개되는 식별자다. 접근 통제는 보안 규칙과 App Check 가 담당한다.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyClwKbdh3T3UPB518aiSXqxoPjesf4JaPc',
    appId: '1:872614648182:web:00315b99dce0d343544257',
    messagingSenderId: '872614648182',
    projectId: 'jikstay-lkxu1',
    authDomain: 'jikstay-lkxu1.firebaseapp.com',
    storageBucket: 'jikstay-lkxu1.firebasestorage.app',
  );
}
