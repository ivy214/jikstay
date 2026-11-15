// 웹 브라우저 전용 기능(URL 동기화·이미지 클라이언트 압축)의 플랫폼 분기 진입점.
export 'web_utils_stub.dart' if (dart.library.js_interop) 'web_utils_web.dart';
