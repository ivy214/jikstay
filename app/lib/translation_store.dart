// 온디맨드 다국어 콘텐츠 번들(EN / JA / ZH) 로더 및 캐시 스토어.
// 한국어(AppLang.ko)일 때는 네트워크 요청 없이 0ms로 동작하고,
// 외국어 전환 시 `data/translations_{lang}.json`을 1회 비동기 로드해 UI를 즉시 갱신한다.
import 'package:flutter/foundation.dart';

import 'i18n.dart';
import 'web_utils.dart';

final ValueNotifier<int> translationRevisionNotifier = ValueNotifier<int>(0);

class TranslationStore {
  TranslationStore._();

  static final Map<AppLang, Map<String, dynamic>> _cache = {};
  static final Set<AppLang> _inFlight = {};

  static bool isLoaded(AppLang lang) =>
      lang == AppLang.ko || _cache.containsKey(lang);

  static Future<void> ensureLoaded(AppLang lang) async {
    if (lang == AppLang.ko) return;
    if (_cache.containsKey(lang) || _inFlight.contains(lang)) return;
    _inFlight.add(lang);
    try {
      final data = await fetchWebJson('data/translations_${lang.code}.json');
      if (data != null && data.isNotEmpty) {
        _cache[lang] = data;
        translationRevisionNotifier.value++;
      }
    } finally {
      _inFlight.remove(lang);
    }
  }

  @visibleForTesting
  static void seedForTest(AppLang lang, Map<String, dynamic> bundle) {
    _cache[lang] = bundle;
    translationRevisionNotifier.value++;
  }

  @visibleForTesting
  static void clearForTest() {
    _cache.clear();
    _inFlight.clear();
    translationRevisionNotifier.value++;
  }

  static Map<String, dynamic>? _entry(AppLang lang, String section, String id) {
    if (lang == AppLang.ko || id.isEmpty) return null;
    final bundle = _cache[lang];
    if (bundle == null) return null;
    final sec = bundle[section];
    if (sec is Map) {
      final item = sec[id];
      if (item is Map<String, dynamic>) return item;
      if (item is Map) return Map<String, dynamic>.from(item);
    }
    return null;
  }

  static String field(AppLang lang, String section, String id, String key, String fallback) {
    if (lang == AppLang.ko) return fallback;
    final e = _entry(lang, section, id);
    if (e == null) return fallback;
    final v = e[key]?.toString().trim() ?? '';
    return v.isNotEmpty ? v : fallback;
  }

  static List<String> stringList(
    AppLang lang,
    String section,
    String id,
    String key,
    List<String> fallback,
  ) {
    if (lang == AppLang.ko) return fallback;
    final e = _entry(lang, section, id);
    if (e == null) return fallback;
    final raw = e[key];
    if (raw is List && raw.isNotEmpty) {
      final list = raw.map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList();
      if (list.isNotEmpty) return list;
    }
    return fallback;
  }

  static List<Map<String, String>> practicalRows(
    AppLang lang,
    String section,
    String id,
  ) {
    if (lang == AppLang.ko) return const [];
    final e = _entry(lang, section, id);
    if (e == null) return const [];
    final raw = e['practical_info'];
    if (raw is! List) return const [];
    final out = <Map<String, String>>[];
    for (final row in raw) {
      if (row is Map) {
        final label = (row['label'] ?? '').toString().trim();
        final value = (row['value'] ?? '').toString().trim();
        if (label.isNotEmpty && value.isNotEmpty) {
          out.add({'label': label, 'value': value});
        }
      }
    }
    return out;
  }
}
