// 전국 17개 시·도 통합 로컬 디스커버리 데이터 모델 및 반경 동선 매칭 엔진.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'i18n.dart';
import 'translation_store.dart';

part 'discovery/parsing.dart';
part 'discovery/markets_banners.dart';
part 'discovery/seed_items.dart';
part 'discovery/daily_stories.dart';

enum DiscoveryCategory {
  all('cat_all', Icons.auto_awesome_rounded, Color(0xFF1E293B)),
  event('cat_event', Icons.celebration_rounded, Color(0xFF7C3AED)),
  attraction('cat_attraction', Icons.landscape_rounded, Color(0xFF059669)),
  food('cat_food', Icons.restaurant_rounded, Color(0xFFD97706)),
  market('cat_market', Icons.storefront_rounded, Color(0xFF92400E)),
  stay('cat_stay', Icons.cottage_rounded, Color(0xFFE11D48)),
  ebook('cat_ebook', Icons.menu_book_rounded, Color(0xFF2563EB));

  final String i18nKey;
  final IconData icon;
  final Color color;
  const DiscoveryCategory(this.i18nKey, this.icon, this.color);
}

class ProvinceMeta {
  final String key;
  final double lat;
  final double lng;
  final double zoom;

  const ProvinceMeta(this.key, this.lat, this.lng, this.zoom);
}

const List<ProvinceMeta> kProvinceJumpList = [
  ProvinceMeta('전체', 36.15, 127.75, 6.8),
  ProvinceMeta('서울', 37.5665, 126.9780, 11.2),
  ProvinceMeta('부산', 35.1796, 129.0756, 11.0),
  ProvinceMeta('대구', 35.8714, 128.6014, 11.0),
  ProvinceMeta('인천', 37.4563, 126.7052, 10.5),
  ProvinceMeta('광주', 35.1595, 126.8526, 11.2),
  ProvinceMeta('대전', 36.3504, 127.3845, 11.2),
  ProvinceMeta('울산', 35.5384, 129.3114, 10.8),
  ProvinceMeta('세종', 36.4800, 127.2890, 11.3),
  ProvinceMeta('경기', 37.4138, 127.5183, 9.2),
  ProvinceMeta('강원', 37.8228, 128.1555, 8.8),
  ProvinceMeta('충북', 36.6357, 127.4914, 9.2),
  ProvinceMeta('충남', 36.6588, 126.6728, 9.2),
  ProvinceMeta('전북', 35.8203, 127.2588, 9.2),
  ProvinceMeta('전남', 34.8161, 126.6629, 8.9),
  ProvinceMeta('경북', 36.4919, 128.8889, 8.8),
  ProvinceMeta('경남', 35.2383, 128.4922, 9.0),
  ProvinceMeta('제주', 33.3846, 126.5535, 10.0),
];

class MapViewportBounds {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final double zoom;

  const MapViewportBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.zoom,
  });

  bool contains(double lat, double lng) {
    return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
  }
}

class MunicipalPdfLink {
  final String label;
  final String labelEn;
  final String url;

  const MunicipalPdfLink({
    required this.label,
    required this.url,
    this.labelEn = '',
  });

  String localizedLabel(AppLang lang) =>
      lang == AppLang.ko ? label : (labelEn.isNotEmpty ? labelEn : label);
}

class TraditionalMarketInfo {
  final String id;
  final String province;
  final String city;
  final String title;
  final List<int> days;
  final double lat;
  final double lng;
  final String specialty;

  const TraditionalMarketInfo({
    required this.id,
    required this.province,
    required this.city,
    required this.title,
    required this.days,
    required this.lat,
    required this.lng,
    required this.specialty,
  });

  // 5일장은 31일에는 서지 않는다 (1·6일장도 31일은 쉼)
  bool opensOnDay(int dayOfMonth) => dayOfMonth <= 30 && days.contains(dayOfMonth % 10);

  String tTitle(AppLang lang) => TranslationStore.field(lang, 'markets', id, 'title', title);
  String tCity(AppLang lang) => TranslationStore.field(lang, 'markets', id, 'city', city);
  String tSpecialty(AppLang lang) => TranslationStore.field(lang, 'markets', id, 'specialty', specialty);
}

class PortalBannerSlide {
  final String id;
  final String badge;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final Color accentColor;
  final DiscoveryItem? targetItem;
  final TraditionalMarketInfo? targetMarket;
  final String? directExternalUrl;
  final bool openBenefitsHub;

  const PortalBannerSlide({
    required this.id,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.accentColor,
    this.targetItem,
    this.targetMarket,
    this.directExternalUrl,
    this.openBenefitsHub = false,
  });
}

class PracticalInfoRow {
  final String label;
  final String value;

  const PracticalInfoRow({required this.label, required this.value});
}

class NaverPlaceReviewSnippet {
  final String title;
  final String summary;
  final String blogger;
  final String postdate;
  final String link;

  const NaverPlaceReviewSnippet({
    required this.title,
    required this.summary,
    this.blogger = '',
    this.postdate = '',
    required this.link,
  });
}

class ChapterMediaItem {
  final String imageUrl;
  final String label;

  const ChapterMediaItem({required this.imageUrl, this.label = ''});
}

/// 지자체 발행 PDF 가이드북·문화관광 페이지 원문 기반 '하루 한 편 로컬 스토리' 모델
class DailyStoryItem {
  final String id;
  final String province;
  final String city;
  final String seasonBadge;
  final String sourceBook;
  final List<int> months;
  final String title;
  final String subtitle;
  final String address;
  final double lat;
  final double lng;
  final String phone;
  final String pullQuote;
  final List<String> paragraphs;
  final List<String> images;
  final String practicalHeader;
  final List<PracticalInfoRow> practicalInfo;
  final List<MunicipalPdfLink> pdfLinks;
  final List<ChapterMediaItem> chapterMedia;
  final String enSummary;

  const DailyStoryItem({
    required this.id,
    required this.province,
    required this.city,
    required this.seasonBadge,
    required this.sourceBook,
    required this.months,
    required this.title,
    required this.subtitle,
    required this.address,
    required this.lat,
    required this.lng,
    this.phone = '',
    this.pullQuote = '',
    this.paragraphs = const [],
    this.images = const [],
    this.practicalHeader = '',
    this.practicalInfo = const [],
    this.pdfLinks = const [],
    this.chapterMedia = const [],
    this.enSummary = '',
  });

  String get heroImage => images.isNotEmpty ? images.first : '';

  String _lookup(AppLang lang, String key, String fallback, {String? itemAltKey}) {
    if (lang == AppLang.ko) return fallback;
    final fromStory = TranslationStore.field(lang, 'stories', id, key, '');
    if (fromStory.isNotEmpty) return fromStory;
    final fromItem = TranslationStore.field(lang, 'items', id, itemAltKey ?? key, '');
    if (fromItem.isNotEmpty) return fromItem;
    return fallback;
  }

  String tSeasonBadge(AppLang lang) {
    final v = _lookup(lang, 'season_badge', '');
    if (v.isNotEmpty) return v;
    if (lang == AppLang.ko) return seasonBadge;
    return pickLangText(
      lang,
      ko: seasonBadge,
      en: '📖 Featured Local Story',
      ja: '📖 今注目のローカルストーリー',
      zh: '📖 精選在地旅遊故事',
    );
  }

  String tSourceBook(AppLang lang) {
    final v = _lookup(lang, 'source_book', '');
    if (v.isNotEmpty) return v;
    if (lang == AppLang.ko) return sourceBook;
    final prov = trProvince(province, lang);
    return pickLangText(
      lang,
      ko: sourceBook,
      en: '$prov Official Tourism Guide',
      ja: '$prov 公式観光ガイド',
      zh: '$prov 官方旅遊指南',
    );
  }

  String tTitle(AppLang lang) => _lookup(lang, 'title', title);

  String tSubtitle(AppLang lang) {
    final v = _lookup(lang, 'subtitle', '', itemAltKey: 'addr');
    if (v.isNotEmpty) return v;
    if (lang == AppLang.en && enSummary.isNotEmpty) return enSummary;
    return subtitle;
  }

  String tAddress(AppLang lang) => _lookup(lang, 'address', address, itemAltKey: 'addr');

  String tPullQuote(AppLang lang) {
    final v = _lookup(lang, 'pull_quote', '');
    if (v.isNotEmpty) return v;
    if (lang == AppLang.en && enSummary.isNotEmpty) return enSummary;
    return pullQuote;
  }

  List<String> tParagraphs(AppLang lang) {
    if (lang == AppLang.ko) return paragraphs;
    final fromStory = TranslationStore.stringList(lang, 'stories', id, 'paragraphs', const []);
    if (fromStory.isNotEmpty) return fromStory;
    final fromItem = TranslationStore.stringList(lang, 'items', id, 'paragraphs', const []);
    if (fromItem.isNotEmpty) return fromItem;
    if (lang == AppLang.en && enSummary.isNotEmpty) return [enSummary];
    return paragraphs;
  }

  String tPracticalHeader(AppLang lang) {
    final v = _lookup(lang, 'practical_header', '');
    if (v.isNotEmpty) return v;
    if (lang == AppLang.ko) return practicalHeader;
    return pickLangText(
      lang,
      ko: practicalHeader,
      en: 'Essential Visitor Info · Hours · Access · Contact',
      ja: '訪問前の確認事項・営業時間・アクセス・お問い合わせ',
      zh: '行前必看資訊・開放時間・交通・聯絡方式',
    );
  }

  List<PracticalInfoRow> tPracticalInfo(AppLang lang) {
    if (lang == AppLang.ko) return practicalInfo;
    final rows = TranslationStore.practicalRows(lang, 'stories', id);
    final chosen = rows.isNotEmpty ? rows : TranslationStore.practicalRows(lang, 'items', id);
    if (chosen.isNotEmpty) {
      return chosen
          .map((r) => PracticalInfoRow(label: r['label'] ?? '', value: r['value'] ?? ''))
          .toList();
    }
    return practicalInfo;
  }

  String tPdfLabel(AppLang lang, int index, String fallback) {
    if (lang == AppLang.ko) return fallback;
    final list = TranslationStore.stringList(lang, 'stories', id, 'pdf_labels', const []);
    if (index >= 0 && index < list.length && list[index].isNotEmpty) {
      return list[index];
    }
    return fallback;
  }

  String tRegionLabel(AppLang lang) {
    if (lang == AppLang.ko) return '$province $city'.trim();
    final prov = trProvince(province, lang);
    final c = tCity(lang);
    return c.isNotEmpty ? '$prov · $c' : prov;
  }

  String tCity(AppLang lang) {
    if (lang == AppLang.ko) return city;
    final reg = TranslationStore.field(lang, 'items', id, 'region_label', '');
    return reg;
  }

  DiscoveryItem toDiscoveryItem() {
    return DiscoveryItem(
      id: id,
      category: DiscoveryCategory.attraction,
      title: title,
      province: province,
      regionLabel: '$province $city'.trim(),
      address: address,
      lat: lat,
      lng: lng,
      imageUrl: heroImage,
      galleryImages: images,
      subtitle: pullQuote.isNotEmpty ? pullQuote : subtitle,
      pullQuote: pullQuote,
      paragraphs: paragraphs,
      practicalHeader: practicalHeader,
      practicalInfo: practicalInfo,
      phone: phone,
      priorityScore: 150,
      pdfLinks: pdfLinks,
    );
  }
}

DateTime? parseYmdDate(String raw) {
  if (raw.length != 8) return null;
  final y = int.tryParse(raw.substring(0, 4));
  final m = int.tryParse(raw.substring(4, 6));
  final d = int.tryParse(raw.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

DateTime? _parseYmd(String raw) => parseYmdDate(raw);

/// 이번 주말(토, 일). 오늘이 토·일이면 오늘이 속한 주말을 돌려준다.
(DateTime, DateTime) upcomingWeekend(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final sat = today.weekday == DateTime.sunday
      ? today.subtract(const Duration(days: 1))
      : today.add(Duration(days: DateTime.saturday - today.weekday));
  return (sat, sat.add(const Duration(days: 1)));
}

/// 기간이 있는 항목(축제·행사)이 [from]~[to] 사이에 하루라도 열리는지. 기간 정보가 없으면 false.
bool isOpenDuring(DiscoveryItem it, DateTime from, DateTime to) {
  final start = parseYmdDate(it.startDate);
  if (start == null) return false;
  final end = parseYmdDate(it.endDate) ?? start;
  return !start.isAfter(to) && !end.isBefore(from);
}

class DiscoveryItem {
  final String id;
  final DiscoveryCategory category;
  final String title;
  final String province;
  final String regionLabel;
  final String address;
  final double lat;
  final double lng;
  final String imageUrl;
  final List<String> galleryImages;
  final String subtitle;
  final String pullQuote;
  final List<String> paragraphs;
  final String practicalHeader;
  final List<PracticalInfoRow> practicalInfo;
  final List<NaverPlaceReviewSnippet> naverReviews;
  final String externalUrl;
  final String mapUrl;
  final String phone;
  final String startDate;
  final String endDate;
  final bool isSponsored;
  final String couponTitle;
  final int? priceKrw;
  final String licenseType;
  final int outboundClicks;
  final int reviewCount;
  final int scoreSum;
  final double priorityScore;
  final List<MunicipalPdfLink> pdfLinks;
  final Map<String, dynamic> raw;

  const DiscoveryItem({
    required this.id,
    required this.category,
    required this.title,
    required this.province,
    required this.regionLabel,
    required this.address,
    required this.lat,
    required this.lng,
    this.imageUrl = '',
    this.galleryImages = const [],
    this.subtitle = '',
    this.pullQuote = '',
    this.paragraphs = const [],
    this.practicalHeader = '',
    this.practicalInfo = const [],
    this.naverReviews = const [],
    this.externalUrl = '',
    this.mapUrl = '',
    this.phone = '',
    this.startDate = '',
    this.endDate = '',
    this.isSponsored = false,
    this.couponTitle = '',
    this.priceKrw,
    this.licenseType = '',
    this.outboundClicks = 0,
    this.reviewCount = 0,
    this.scoreSum = 0,
    this.priorityScore = 0,
    this.pdfLinks = const [],
    this.raw = const {},
  });

  List<String> get effectiveGallery =>
      galleryImages.isNotEmpty ? galleryImages : (imageUrl.isNotEmpty ? [imageUrl] : const []);

  double get averageRating => reviewCount > 0 ? scoreSum / reviewCount : 0.0;

  /// 전통시장·5일장 (지역시장 분류).
  /// - spot_mk_… : 한국관광공사 전국 전통시장 (Firestore 문서 있음 → 후기·찜·클릭 집계)
  /// - mkt_…     : 손으로 정리한 대표 5일장을 검색 결과용으로만 만든 항목 (Firestore 문서 없음)
  bool get isMarket => category == DiscoveryCategory.market || raw['kind'] == 'market' || id.startsWith('mkt_');

  /// Firestore spots/listings 문서가 있어 후기 작성·클릭 집계가 가능한 항목
  bool get hasFirestoreDoc => category != DiscoveryCategory.ebook && !id.startsWith('mkt_');

  String get _searchLocationPrefix => (regionLabel.isNotEmpty ? regionLabel : province).trim();

  /// 카카오 플레이스(카카오맵 장소 상세·방문자 별점·사진·메뉴) 검색 직결 링크
  String get kakaoPlaceUrl =>
      'https://map.kakao.com/?q=${Uri.encodeComponent('$_searchLocationPrefix $title'.trim())}';

  /// 네이버 플레이스(영업시간·메뉴판·방문자 영수증 리뷰) 직결 링크
  String get naverPlaceUrl =>
      'https://map.naver.com/p/search/${Uri.encodeComponent('$_searchLocationPrefix $title'.trim())}';

  /// 네이버 통합검색(블로그 방문기·최신 소식·상세 안내) 직결 링크
  String get naverSearchUrl {
    final suffix = switch (category) {
      DiscoveryCategory.food => '메뉴 영업시간 후기',
      DiscoveryCategory.event => '일정 주차 후기',
      _ => '방문기 코스 정보',
    };
    return 'https://search.naver.com/search.naver?query=${Uri.encodeComponent('$_searchLocationPrefix $title $suffix'.trim())}';
  }

  /// 네이버지도 검색·길찾기 링크 (PC·모바일 겸용)
  String get naverRouteUrl => mapUrl.isNotEmpty
      ? mapUrl
      : 'https://map.naver.com/p/search/${Uri.encodeComponent('$province $title')}';

  /// 카카오맵 도착지 직결 대중교통·자동차·도보 길찾기 딥링크 (유료 API 호출 0원)
  String get kakaoRouteUrl =>
      'https://map.kakao.com/link/to/${Uri.encodeComponent(title)},${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  /// 구글맵 대중교통(버스·기차·도보 환승) 직결 링크 (내·외국인 공통 지원)
  String get googleTransitUrl =>
      'https://www.google.com/maps/dir/?api=1&destination=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}&travelmode=transit';

  String _tSection() =>
      category == DiscoveryCategory.stay
          ? 'stays'
          : (raw['is_story'] == true ? 'stories' : 'items');

  String _fromRawOrStore(AppLang lang, String key, String fallback, {String? storeKey}) {
    if (lang == AppLang.ko) return fallback;
    final i18n = raw['i18n'];
    if (i18n is Map && i18n[lang.code] is Map) {
      final v = (i18n[lang.code][key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return TranslationStore.field(lang, _tSection(), id, storeKey ?? key, fallback);
  }

  String tTitle(AppLang lang) => _fromRawOrStore(lang, 'title', title);

  String tRegionLabel(AppLang lang) {
    if (lang == AppLang.ko) return regionLabel;
    final sec = _tSection();
    final v = TranslationStore.field(
      lang,
      sec,
      id,
      sec == 'stays' ? 'region' : 'region_label',
      '',
    );
    if (v.isNotEmpty) return v;
    return trProvince(province, lang);
  }

  String tAddress(AppLang lang) {
    if (lang == AppLang.ko) return address;
    final sec = _tSection();
    final storeKey = sec == 'stories' ? 'address' : (sec == 'stays' ? 'region' : 'addr');
    return _fromRawOrStore(lang, 'addr', address, storeKey: storeKey);
  }

  String tSubtitle(AppLang lang) {
    if (lang == AppLang.ko) return subtitle;
    final i18n = raw['i18n'];
    if (i18n is Map && i18n[lang.code] is Map) {
      final ov = (i18n[lang.code]['overview'] ?? i18n[lang.code]['summary'] ?? '').toString().trim();
      if (ov.isNotEmpty) return ov;
    }
    final sec = _tSection();
    if (sec == 'stays') {
      return TranslationStore.field(lang, 'stays', id, 'summary', subtitle);
    }
    final ov = TranslationStore.field(lang, sec, id, 'overview', '');
    if (ov.isNotEmpty) return ov;
    final pq = TranslationStore.field(lang, sec, id, 'pull_quote', '');
    if (pq.isNotEmpty) return pq;
    return subtitle;
  }

  String tPullQuote(AppLang lang) =>
      TranslationStore.field(lang, _tSection(), id, 'pull_quote', pullQuote);

  List<String> tParagraphs(AppLang lang) =>
      TranslationStore.stringList(lang, _tSection(), id, 'paragraphs', paragraphs);

  String tPracticalHeader(AppLang lang) {
    if (lang == AppLang.ko) return practicalHeader;
    final v = TranslationStore.field(lang, _tSection(), id, 'practical_header', '');
    if (v.isNotEmpty) return v;
    return pickLangText(
      lang,
      ko: practicalHeader,
      en: 'Essential Info · Hours · Access · Contact',
      ja: '訪問前の確認事項・営業時間・アクセス',
      zh: '行前必看資訊・營業時間・交通方式',
    );
  }

  List<PracticalInfoRow> tPracticalInfo(AppLang lang) {
    if (lang == AppLang.ko) return practicalInfo;
    final rows = TranslationStore.practicalRows(lang, _tSection(), id);
    if (rows.isNotEmpty) {
      return rows
          .map((r) => PracticalInfoRow(label: r['label'] ?? '', value: r['value'] ?? ''))
          .toList();
    }
    return practicalInfo;
  }

  String tCouponTitle(AppLang lang) =>
      TranslationStore.field(lang, _tSection(), id, 'coupon_title', couponTitle);

  /// 포털 동적 선도(Freshness) 배지: 마감임박 축제 / 진행중 축제 / 실시간 인기 업장 자동 산출
  String? dynamicFreshnessBadge(AppLang lang, {DateTime? now}) {
    final todayDate = now ?? DateTime.now();
    final today = DateTime(todayDate.year, todayDate.month, todayDate.day);
    if (category == DiscoveryCategory.event) {
      final sd = _parseYmd(startDate);
      final ed = _parseYmd(endDate);
      if (ed != null) {
        final daysLeft = ed.difference(today).inDays;
        if (daysLeft >= 0 && daysLeft <= 5) {
          return pickLangText(
            lang,
            ko: '⏰ 마감 D-$daysLeft',
            en: '⏰ Ends in ${daysLeft}d',
            ja: '⏰ 終了まで$daysLeft日',
            zh: '⏰ 倒數 $daysLeft 天結束',
          );
        }
        if (sd != null && !today.isBefore(sd) && !today.isAfter(ed)) {
          return pickLangText(
            lang,
            ko: '🎊 지금 진행중',
            en: '🎊 Live Now',
            ja: '🎊 開催中',
            zh: '🎊 現正舉辦中',
          );
        }
      }
      if (sd != null) {
        final daysUntil = sd.difference(today).inDays;
        if (daysUntil > 0 && daysUntil <= 14) {
          return pickLangText(
            lang,
            ko: '📅 개막 D-$daysUntil',
            en: '📅 Opens in ${daysUntil}d',
            ja: '📅 開幕まで$daysUntil日',
            zh: '📅 距開幕 $daysUntil 天',
          );
        }
      }
    }
    if (outboundClicks >= 5 || reviewCount >= 2) {
      return pickLangText(
        lang,
        ko: '🔥 인기',
        en: '🔥 Trending',
        ja: '🔥 人気上昇中',
        zh: '🔥 熱門',
      );
    }
    return null;
  }

  /// 실제 좌표가 없어 시·군 중심 근처 근사값을 쓰는 항목 (backend: approx_coord)
  bool get hasApproxLocation => raw['approx_coord'] == true;

  /// 기준점으로부터의 거리 표시. 근사 좌표 항목은 거리 숫자 대신 '시·군 단위 위치'로 정직하게 표기한다.
  String distanceLabel(double km, AppLang lang) {
    if (hasApproxLocation) {
      return pickLangText(lang, ko: '시·군 단위 위치', en: 'Approx. area', ja: '市郡単位の位置', zh: '大致區域');
    }
    final v = km < 1.0 ? '${(km * 1000).round()}m' : '${km.toStringAsFixed(1)}km';
    return pickLangText(lang, ko: '약 $v', en: '$v away', ja: '約$v', zh: '約 $v');
  }

  String get categoryEmoji => isMarket ? '🧺' : switch (category) {
    DiscoveryCategory.event => '🎉',
    DiscoveryCategory.attraction => '🏞️',
    DiscoveryCategory.food => '🍲',
    DiscoveryCategory.market => '🧺',
    DiscoveryCategory.stay => '🏡',
    DiscoveryCategory.ebook => '📖',
    DiscoveryCategory.all => '✨',
  };

  String categoryBadgeText(AppLang lang) => isMarket
      ? pickLangText(lang, ko: '전통시장', en: 'Market', ja: '伝統市場', zh: '傳統市場')
      : switch (category) {
    DiscoveryCategory.event => pickLangText(lang, ko: '축제·행사', en: 'Event', ja: '祭り・イベント', zh: '慶典活動'),
    DiscoveryCategory.attraction => pickLangText(lang, ko: '볼거리', en: 'Sight', ja: '観光名所', zh: '必訪景點'),
    DiscoveryCategory.food => pickLangText(lang, ko: '먹거리', en: 'Food', ja: 'グルメ', zh: '在地美食'),
    DiscoveryCategory.market => pickLangText(lang, ko: '전통시장', en: 'Market', ja: '伝統市場', zh: '傳統市場'),
    DiscoveryCategory.stay => pickLangText(lang, ko: '숙소', en: 'Stay', ja: '宿泊', zh: '住宿'),
    DiscoveryCategory.ebook => pickLangText(lang, ko: '공식 관광지도', en: 'Guide PDF', ja: '公式ガイド', zh: '官方指南'),
    DiscoveryCategory.all => pickLangText(lang, ko: '전체', en: 'All', ja: 'すべて', zh: '全部'),
  };

  String pinShortLabel([AppLang lang = AppLang.ko]) {
    final name = tTitle(lang);
    final shortTitle = name.length > 8 ? '${name.substring(0, 8)}…' : name;
    if (category == DiscoveryCategory.stay && priceKrw != null && priceKrw! > 0) {
      final man = (priceKrw! / 10000).round();
      if (lang == AppLang.ko && man > 0) {
        return '$categoryEmoji ₩$man만';
      }
      return '$categoryEmoji $shortTitle';
    }
    if (isSponsored && couponTitle.isNotEmpty) {
      return '🎁 $shortTitle';
    }
    return '$categoryEmoji $shortTitle';
  }

  DiscoveryItem copyWithStats({
    int? outboundClicks,
    int? reviewCount,
    int? scoreSum,
    bool? isSponsored,
    String? couponTitle,
  }) {
    return DiscoveryItem(
      id: id,
      category: category,
      title: title,
      province: province,
      regionLabel: regionLabel,
      address: address,
      lat: lat,
      lng: lng,
      imageUrl: imageUrl,
      galleryImages: galleryImages,
      subtitle: subtitle,
      pullQuote: pullQuote,
      paragraphs: paragraphs,
      practicalHeader: practicalHeader,
      practicalInfo: practicalInfo,
      naverReviews: naverReviews,
      externalUrl: externalUrl,
      mapUrl: mapUrl,
      phone: phone,
      startDate: startDate,
      endDate: endDate,
      isSponsored: isSponsored ?? this.isSponsored,
      couponTitle: couponTitle ?? this.couponTitle,
      priceKrw: priceKrw,
      licenseType: licenseType,
      outboundClicks: outboundClicks ?? this.outboundClicks,
      reviewCount: reviewCount ?? this.reviewCount,
      scoreSum: scoreSum ?? this.scoreSum,
      priorityScore: priorityScore,
      pdfLinks: pdfLinks,
      raw: raw,
    );
  }
}

class ConnectedBundle {
  final List<DiscoveryItem> ebooks;
  final List<DiscoveryItem> events;
  final List<DiscoveryItem> attractions;
  final List<DiscoveryItem> foods;
  final List<DiscoveryItem> stays;

  const ConnectedBundle({
    this.ebooks = const [],
    this.events = const [],
    this.attractions = const [],
    this.foods = const [],
    this.stays = const [],
  });

  int get totalNearbyCount => events.length + attractions.length + foods.length + stays.length;
}
