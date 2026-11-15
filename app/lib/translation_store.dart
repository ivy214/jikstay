// 온디맨드 다국어 콘텐츠 번들(EN / JA / ZH) 로더 및 캐시 스토어.
// 한국어(AppLang.ko)일 때는 네트워크 요청 없이 0ms로 동작하고,
// 외국어 전환 시 `data/i18n/{lang}/core.json`(목록용)을 1회 로드하고, 상세 화면을 열면 그 시·도의
// `details_{code}.json`(본문·탐방정보)만 추가로 받아 합친다. 분할 파일이 없으면 원본 번들 전체로 대체한다.
import 'package:flutter/foundation.dart';

import 'i18n.dart';
import 'web_utils.dart';

final ValueNotifier<int> translationRevisionNotifier = ValueNotifier<int>(0);

class TranslationStore {
  TranslationStore._();

  static final Map<AppLang, Map<String, dynamic>> _cache = {};
  static final Set<AppLang> _inFlight = {};
  static final Map<AppLang, bool> _split = {};
  static final Map<AppLang, Set<String>> _detailLoaded = {};
  // 지금까지 상세를 연 시·도 — 언어를 바꾸면 이 시·도들의 상세 번역도 함께 받는다
  static final Set<String> _wantedCodes = {};

  static bool isLoaded(AppLang lang) =>
      lang == AppLang.ko || _cache.containsKey(lang);

  static Future<void> ensureLoaded(AppLang lang) async {
    if (lang == AppLang.ko) return;
    if (_cache.containsKey(lang) || _inFlight.contains(lang)) return;
    _inFlight.add(lang);
    try {
      var data = await fetchWebJson('data/i18n/${lang.code}/core.json');
      final split = data != null && data.isNotEmpty;
      if (!split) data = await fetchWebJson('data/translations_${lang.code}.json');
      if (data != null && data.isNotEmpty) {
        _cache[lang] = data;
        _split[lang] = split;
        translationRevisionNotifier.value++;
        for (final code in _wantedCodes.toList()) {
          await ensureDetails(lang, code);
        }
      }
    } finally {
      _inFlight.remove(lang);
    }
  }

  /// 상세 화면용 번역(본문·탐방정보·전체 개요)을 해당 시·도 파일에서 받아 items 에 합친다.
  static Future<void> ensureDetails(AppLang lang, String provinceCode) async {
    _wantedCodes.add(provinceCode);
    if (lang == AppLang.ko || _split[lang] != true || !_cache.containsKey(lang)) return;
    final loaded = _detailLoaded.putIfAbsent(lang, () => <String>{});
    if (!loaded.add(provinceCode)) return;
    final details = await fetchWebJson('data/i18n/${lang.code}/details_$provinceCode.json');
    if (details == null) {
      loaded.remove(provinceCode);
      return;
    }
    mergeDetailsForTest(lang, details);
  }

  /// 시·도 상세 번역을 items 섹션에 합친다 (테스트에서도 직접 사용).
  @visibleForTesting
  static void mergeDetailsForTest(AppLang lang, Map<String, dynamic> details) {
    final bundle = _cache[lang];
    if (bundle == null) return;
    final items = bundle['items'] is Map ? Map<String, dynamic>.from(bundle['items'] as Map) : <String, dynamic>{};
    details.forEach((id, v) {
      if (v is! Map) return;
      final cur = items[id];
      items[id] = <String, dynamic>{
        if (cur is Map) ...Map<String, dynamic>.from(cur),
        ...Map<String, dynamic>.from(v),
      };
    });
    bundle['items'] = items;
    translationRevisionNotifier.value++;
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
    _split.clear();
    _detailLoaded.clear();
    _wantedCodes.clear();
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
