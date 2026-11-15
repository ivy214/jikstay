// 전국 17개 시·도 통합 로컬 디스커버리 데이터 모델 및 반경 동선 매칭 엔진.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'i18n.dart';

enum DiscoveryCategory {
  all('cat_all', Icons.auto_awesome_rounded, Color(0xFF1E293B)),
  event('cat_event', Icons.celebration_rounded, Color(0xFF7C3AED)),
  attraction('cat_attraction', Icons.landscape_rounded, Color(0xFF059669)),
  food('cat_food', Icons.restaurant_rounded, Color(0xFFD97706)),
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

  bool opensOnDay(int dayOfMonth) => days.contains(dayOfMonth % 10);
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
    this.enSummary = '',
  });

  String get heroImage => images.isNotEmpty ? images.first : '';

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
      subtitle: pullQuote.isNotEmpty ? pullQuote : subtitle,
      phone: phone,
      priorityScore: 150,
      pdfLinks: pdfLinks,
    );
  }
}

DateTime? _parseYmd(String raw) {
  if (raw.length != 8) return null;
  final y = int.tryParse(raw.substring(0, 4));
  final m = int.tryParse(raw.substring(4, 6));
  final d = int.tryParse(raw.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
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
  final String subtitle;
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
    this.subtitle = '',
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

  double get averageRating => reviewCount > 0 ? scoreSum / reviewCount : 0.0;

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
          return lang == AppLang.ko ? '⏰ 마감 D-$daysLeft' : '⏰ Ends in ${daysLeft}d';
        }
        if (sd != null && !today.isBefore(sd) && !today.isAfter(ed)) {
          return lang == AppLang.ko ? '🎊 지금 진행중' : '🎊 Live Now';
        }
      }
      if (sd != null) {
        final daysUntil = sd.difference(today).inDays;
        if (daysUntil > 0 && daysUntil <= 14) {
          return lang == AppLang.ko ? '📅 개막 D-$daysUntil' : '📅 In ${daysUntil}d';
        }
      }
    }
    if (outboundClicks >= 5 || reviewCount >= 2) {
      return lang == AppLang.ko ? '🔥 실시간 인기' : '🔥 Trending';
    }
    return null;
  }

  String get categoryEmoji => switch (category) {
    DiscoveryCategory.event => '🎉',
    DiscoveryCategory.attraction => '🏞️',
    DiscoveryCategory.food => '🍲',
    DiscoveryCategory.stay => '🏡',
    DiscoveryCategory.ebook => '📖',
    DiscoveryCategory.all => '✨',
  };

  String categoryBadgeText(AppLang lang) => switch (category) {
    DiscoveryCategory.event => lang == AppLang.ko ? '축제·행사' : 'Event',
    DiscoveryCategory.attraction => lang == AppLang.ko ? '볼거리' : 'Sight',
    DiscoveryCategory.food => lang == AppLang.ko ? '먹거리' : 'Food',
    DiscoveryCategory.stay => lang == AppLang.ko ? '안심숙소' : 'Stay',
    DiscoveryCategory.ebook => lang == AppLang.ko ? '공식 관광지도' : 'Guide PDF',
    DiscoveryCategory.all => '전체',
  };

  String pinShortLabel() {
    final shortTitle = title.length > 8 ? '${title.substring(0, 8)}…' : title;
    if (category == DiscoveryCategory.stay && priceKrw != null && priceKrw! > 0) {
      final man = (priceKrw! / 10000).round();
      return '$categoryEmoji ${man > 0 ? "₩$man만" : shortTitle}';
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
      subtitle: subtitle,
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

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

String inferProvinceFromRaw(Map<String, dynamic> m) {
  final explicit = (m['province'] ?? '').toString().trim();
  if (explicit.isNotEmpty) return explicit;
  final d1 = (m['region_depth1'] ?? m['region_label'] ?? m['addr'] ?? '').toString();
  final d2 = (m['region_depth2'] ?? '').toString();
  if (d1.contains('전남광주')) {
    if (d2.startsWith('동구') || d2.startsWith('서구') || d2.startsWith('남구') || d2.startsWith('북구') || d2.startsWith('광산구')) {
      return '광주';
    }
    return '전남';
  }
  const pairs = [
    ('서울', '서울'), ('부산', '부산'), ('대구', '대구'), ('인천', '인천'),
    ('광주', '광주'), ('대전', '대전'), ('울산', '울산'), ('세종', '세종'),
    ('경기', '경기'), ('강원', '강원'),
    ('충청북', '충북'), ('충북', '충북'),
    ('충청남', '충남'), ('충남', '충남'),
    ('전북', '전북'), ('전라북', '전북'),
    ('전남', '전남'), ('전라남', '전남'),
    ('경상북', '경북'), ('경북', '경북'),
    ('경상남', '경남'), ('경남', '경남'),
    ('제주', '제주'),
  ];
  for (final (prefix, norm) in pairs) {
    if (d1.contains(prefix)) return norm;
  }
  return '서울';
}

DiscoveryItem? parseSpotJson(Map<String, dynamic> m, {required DiscoveryCategory fallbackCategory}) {
  final kind = (m['kind'] ?? '').toString();
  final cat = switch (kind) {
    'event' => DiscoveryCategory.event,
    'attraction' => DiscoveryCategory.attraction,
    'food' => DiscoveryCategory.food,
    'ebook' => DiscoveryCategory.ebook,
    'stay' => DiscoveryCategory.stay,
    _ => fallbackCategory,
  };
  final lat = (m['lat'] as num?)?.toDouble();
  final lng = (m['lng'] as num?)?.toDouble();
  final prov = inferProvinceFromRaw(m);
  final fallbackMeta = kProvinceJumpList.firstWhere(
    (p) => p.key == prov,
    orElse: () => kProvinceJumpList.first,
  );
  final useLat = (lat != null && lat >= 32.0 && lat <= 39.5) ? lat : fallbackMeta.lat;
  final useLng = (lng != null && lng >= 124.0 && lng <= 132.0) ? lng : fallbackMeta.lng;
  final title = (m['title'] ?? '').toString().trim();
  if (title.isEmpty) return null;

  final cid = (m['content_id'] ?? '').toString();
  final id = (m['id'] ?? (cid.isNotEmpty ? 'spot_${cat.name}_$cid' : 'spot_${title.hashCode.abs()}')).toString();
  final isSponsored = m['is_sponsored'] == true;
  final coupon = (m['coupon_title'] ?? '').toString();
  final rCount = (m['review_count'] as num?)?.toInt() ?? 0;
  final sSum = (m['score_sum'] as num?)?.toInt() ?? 0;
  final clicks = (m['outbound_clicks'] as num?)?.toInt() ?? 0;

  double prio = switch (cat) {
    DiscoveryCategory.event => 120.0,
    DiscoveryCategory.ebook => 110.0,
    DiscoveryCategory.food => 90.0,
    DiscoveryCategory.attraction => 88.0,
    DiscoveryCategory.stay => 75.0,
    DiscoveryCategory.all => 50.0,
  };
  if (isSponsored) prio += 35.0;
  if (rCount > 0) prio += (sSum / rCount) * 8.0;
  if (clicks > 0) prio += math.min(20.0, clicks * 0.8);

  final sDate = (m['start_date'] ?? '').toString();
  final eDate = (m['end_date'] ?? '').toString();
  if (cat == DiscoveryCategory.event) {
    final ed = _parseYmd(eDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (ed != null) {
      final daysLeft = ed.difference(today).inDays;
      if (daysLeft >= 0 && daysLeft <= 7) {
        prio += 18.0; // 마감 임박 축제 상단 동적 부스팅
      }
    }
  }

  final parsedPdfLinks = <MunicipalPdfLink>[];
  if (m['pdf_links'] is List) {
    for (final rawLink in (m['pdf_links'] as List)) {
      if (rawLink is Map) {
        final lUrl = (rawLink['url'] ?? '').toString().trim();
        final lLabel = (rawLink['label'] ?? '').toString().trim();
        if (lUrl.isNotEmpty && lLabel.isNotEmpty) {
          parsedPdfLinks.add(MunicipalPdfLink(
            label: lLabel,
            labelEn: (rawLink['label_en'] ?? '').toString().trim(),
            url: lUrl,
          ));
        }
      }
    }
  }

  return DiscoveryItem(
    id: id,
    category: cat,
    title: title,
    province: prov,
    regionLabel: (m['region_label'] ?? m['city'] ?? prov).toString(),
    address: (m['addr'] ?? m['materials'] ?? '').toString(),
    lat: useLat,
    lng: useLng,
    imageUrl: (m['image_url'] ?? '').toString(),
    subtitle: (m['materials'] ?? m['overview'] ?? m['addr'] ?? '').toString(),
    externalUrl: (m['url'] ?? m['article_url'] ?? '').toString(),
    mapUrl: (m['map_url'] ?? 'https://map.naver.com/p/search/${Uri.encodeComponent('$prov $title')}').toString(),
    phone: (m['tel'] ?? '').toString(),
    startDate: sDate,
    endDate: eDate,
    isSponsored: isSponsored,
    couponTitle: coupon,
    outboundClicks: clicks,
    reviewCount: rCount,
    scoreSum: sSum,
    priorityScore: prio,
    pdfLinks: parsedPdfLinks,
    raw: m,
  );
}

DiscoveryItem? parseStayToDiscoveryItem(String docId, Map<String, dynamic> d) {
  final title = (d['title'] ?? '').toString().trim();
  if (title.isEmpty) return null;
  final prov = inferProvinceFromRaw(d);
  final loc = d['location_info'] is Map ? d['location_info'] as Map : const {};
  final lat = (d['lat'] as num?)?.toDouble() ?? (loc['lat'] as num?)?.toDouble();
  final lng = (d['lng'] as num?)?.toDouble() ?? (loc['lng'] as num?)?.toDouble();
  final fallbackMeta = kProvinceJumpList.firstWhere(
    (p) => p.key == prov,
    orElse: () => kProvinceJumpList.first,
  );
  final useLat = (lat != null && lat >= 32.0 && lat <= 39.5) ? lat : fallbackMeta.lat;
  final useLng = (lng != null && lng >= 124.0 && lng <= 132.0) ? lng : fallbackMeta.lng;

  final imgs = d['images'] is List ? (d['images'] as List) : const [];
  final firstImg = (imgs.isNotEmpty && imgs.first is Map) ? ((imgs.first as Map)['url'] ?? '').toString() : '';

  int? minPrice;
  if (d['pricing'] is Map) {
    final p = d['pricing'] as Map;
    final n = p['nightly_min'] ?? p['weekly_price'] ?? p['monthly_price'];
    if (n is num) minPrice = n.round();
  }

  final isSponsored = d['is_sponsored'] == true;
  final promo = (d['promo_title'] ?? '').toString();
  final rCount = (d['review_count'] as num?)?.toInt() ?? 0;
  final sSum = (d['score_sum'] as num?)?.toInt() ?? 0;
  final clicks = (d['outbound_clicks'] as num?)?.toInt() ?? 0;
  final cScore = (d['curated_score'] as num?)?.toDouble() ?? 50.0;
  final points = (d['summary_points'] as List?)?.map((e) => e.toString()).toList() ?? const [];

  double prio = 65.0 + (cScore * 0.18);
  if (isSponsored) prio += 35.0;
  if (firstImg.isNotEmpty) prio += 12.0;
  if (rCount > 0) prio += (sSum / rCount) * 8.0;

  final defaultNaverSearch =
      'https://map.naver.com/p/search/${Uri.encodeComponent('${d['region_depth2'] ?? prov} $title'.trim())}';
  final rawDirectUrl = (d['direct_booking_url'] ?? '').toString().trim();
  final rawMapUrl = (d['naver_map_url'] ?? '').toString().trim();

  return DiscoveryItem(
    id: docId,
    category: DiscoveryCategory.stay,
    title: title,
    province: prov,
    regionLabel: '${d['region_depth1'] ?? prov} ${d['region_depth2'] ?? ''}'.trim(),
    address: (loc['display_address'] ?? '${d['region_depth1'] ?? ''} ${d['region_depth2'] ?? ''}').toString().trim(),
    lat: useLat,
    lng: useLng,
    imageUrl: firstImg,
    subtitle: points.isNotEmpty ? points.first : (d['accommodation_type'] ?? '공공 인허가 확인 안심숙소').toString(),
    externalUrl: rawDirectUrl.isNotEmpty ? rawDirectUrl : defaultNaverSearch,
    mapUrl: rawMapUrl.isNotEmpty ? rawMapUrl : defaultNaverSearch,
    phone: (loc['public_phone'] ?? '').toString(),
    isSponsored: isSponsored,
    couponTitle: promo.isNotEmpty
        ? promo
        : (isSponsored ? '직거래 중개수수료 0원 · 반값여행 정산 영수증 가능' : ''),
    priceKrw: minPrice,
    licenseType: (d['license_type'] ?? '').toString(),
    outboundClicks: clicks,
    reviewCount: rCount,
    scoreSum: sSum,
    priorityScore: prio,
    raw: d,
  );
}

ConnectedBundle buildConnectedBundle(
  DiscoveryItem anchor,
  List<DiscoveryItem> allItems, {
  double maxRadiusKm = 45.0,
  int limitPerType = 4,
}) {
  final ebooks = <DiscoveryItem>[];
  final scoredEvents = <(double, DiscoveryItem)>[];
  final scoredAttractions = <(double, DiscoveryItem)>[];
  final scoredFoods = <(double, DiscoveryItem)>[];
  final scoredStays = <(double, DiscoveryItem)>[];

  for (final it in allItems) {
    if (it.id == anchor.id) continue;
    if (it.category == DiscoveryCategory.ebook) {
      if (it.province == anchor.province) {
        ebooks.add(it);
      }
      continue;
    }
    final dist = haversineKm(anchor.lat, anchor.lng, it.lat, it.lng);
    if (dist > maxRadiusKm && it.province != anchor.province) continue;
    // 스폰서 방문혜택 업장은 근거리 내에서 소폭 우선 노출 (CPC 전환 극대화)
    final effectiveDist = it.isSponsored ? math.max(0.1, dist - 3.5) : dist;
    switch (it.category) {
      case DiscoveryCategory.event:
        scoredEvents.add((effectiveDist, it));
      case DiscoveryCategory.attraction:
        scoredAttractions.add((effectiveDist, it));
      case DiscoveryCategory.food:
        scoredFoods.add((effectiveDist, it));
      case DiscoveryCategory.stay:
        scoredStays.add((effectiveDist, it));
      case DiscoveryCategory.ebook:
      case DiscoveryCategory.all:
        break;
    }
  }

  ebooks.sort((a, b) => haversineKm(anchor.lat, anchor.lng, a.lat, a.lng)
      .compareTo(haversineKm(anchor.lat, anchor.lng, b.lat, b.lng)));
  scoredEvents.sort((a, b) => a.$1.compareTo(b.$1));
  scoredAttractions.sort((a, b) => a.$1.compareTo(b.$1));
  scoredFoods.sort((a, b) => a.$1.compareTo(b.$1));
  scoredStays.sort((a, b) => a.$1.compareTo(b.$1));

  return ConnectedBundle(
    ebooks: ebooks.take(3).toList(),
    events: scoredEvents.take(limitPerType).map((e) => e.$2).toList(),
    attractions: scoredAttractions.take(limitPerType).map((e) => e.$2).toList(),
    foods: scoredFoods.take(limitPerType).map((e) => e.$2).toList(),
    stays: scoredStays.take(limitPerType).map((e) => e.$2).toList(),
  );
}

TraditionalMarketInfo? parseTraditionalMarketJson(Map<String, dynamic> m) {
  final title = (m['title'] ?? '').toString().trim();
  if (title.isEmpty) return null;
  final days = (m['days'] as List? ?? const [])
      .map((e) => (e as num?)?.toInt())
      .whereType<int>()
      .toList();
  if (days.isEmpty) return null;
  return TraditionalMarketInfo(
    id: (m['id'] ?? 'mkt_${title.hashCode.abs()}').toString(),
    province: (m['province'] ?? '전북').toString(),
    city: (m['city'] ?? '').toString(),
    title: title,
    days: days,
    lat: (m['lat'] as num?)?.toDouble() ?? 36.15,
    lng: (m['lng'] as num?)?.toDouble() ?? 127.75,
    specialty: (m['specialty'] ?? '').toString(),
  );
}

const List<TraditionalMarketInfo> kFallbackTraditional5DayMarkets = [
  TraditionalMarketInfo(
    id: 'mkt_muju',
    province: '전북',
    city: '무주군',
    title: '무주반딧불시장 5일장',
    days: [1, 6],
    lat: 36.0072,
    lng: 127.6615,
    specialty: '산채비빔밥·머루·어죽',
  ),
  TraditionalMarketInfo(
    id: 'mkt_danyang',
    province: '충북',
    city: '단양군',
    title: '단양구경시장 5일장',
    days: [1, 6],
    lat: 36.9839,
    lng: 128.3653,
    specialty: '흑마늘닭강정·마늘순대',
  ),
  TraditionalMarketInfo(
    id: 'mkt_jeongseon',
    province: '강원',
    city: '정선군',
    title: '정선아리랑시장 5일장',
    days: [2, 7],
    lat: 37.3812,
    lng: 128.6631,
    specialty: '곤드레밥·메밀전병',
  ),
  TraditionalMarketInfo(
    id: 'mkt_jeju_folk',
    province: '제주',
    city: '제주시',
    title: '제주민속오일시장',
    days: [2, 7],
    lat: 33.4979,
    lng: 126.4754,
    specialty: '제주 빙떡·몸국·한라봉',
  ),
  TraditionalMarketInfo(
    id: 'mkt_yangpyeong',
    province: '경기',
    city: '양평군',
    title: '양평물맑은시장 5일장',
    days: [3, 8],
    lat: 37.4897,
    lng: 127.4915,
    specialty: '양평해장국·로컬푸드',
  ),
  TraditionalMarketInfo(
    id: 'mkt_gochang',
    province: '전북',
    city: '고창군',
    title: '고창전통시장 5일장',
    days: [3, 8],
    lat: 35.4357,
    lng: 126.7019,
    specialty: '풍천장어·복분자',
  ),
  TraditionalMarketInfo(
    id: 'mkt_moran',
    province: '경기',
    city: '성남시',
    title: '성남 모란민속5일장',
    days: [4, 9],
    lat: 37.4310,
    lng: 127.1292,
    specialty: '손칼국수·수수부꾸미',
  ),
  TraditionalMarketInfo(
    id: 'mkt_jinan',
    province: '전북',
    city: '진안군',
    title: '진안고원시장 5일장',
    days: [4, 9],
    lat: 35.7908,
    lng: 127.4285,
    specialty: '진안 홍삼·흑돼지국밥',
  ),
  TraditionalMarketInfo(
    id: 'mkt_jangsu',
    province: '전북',
    city: '장수군',
    title: '장수전통시장 5일장',
    days: [5, 0],
    lat: 35.6484,
    lng: 127.5205,
    specialty: '장수 한우국밥·장수사과',
  ),
  TraditionalMarketInfo(
    id: 'mkt_pyeongchang',
    province: '강원',
    city: '평창군',
    title: '평창올림픽시장 5일장',
    days: [5, 0],
    lat: 37.3702,
    lng: 128.3924,
    specialty: '메밀부치기·올챙이국수',
  ),
];

List<TraditionalMarketInfo> marketsOpeningOn(
  DateTime date,
  List<TraditionalMarketInfo> markets, {
  String province = '전체',
}) {
  final source = markets.isNotEmpty ? markets : kFallbackTraditional5DayMarkets;
  final opened = source.where((m) => m.opensOnDay(date.day)).toList();
  if (province != '전체') {
    final inProv = opened.where((m) => m.province == province).toList();
    if (inProv.isNotEmpty) return inProv;
  }
  return opened;
}

/// 네이버 포털형 일일 동적 브리핑 슬라이드 배너 자동 생성기
List<PortalBannerSlide> buildDailyPortalSlides({
  required List<DiscoveryItem> allItems,
  required List<TraditionalMarketInfo> markets,
  required String selectedProvince,
  required AppLang lang,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final slides = <PortalBannerSlide>[];

  // 1. 오늘(날짜 끝자리 기준) 열리는 전통 5일장 동적 슬라이드
  final todayMarkets = marketsOpeningOn(today, markets, province: selectedProvince);
  if (todayMarkets.isNotEmpty) {
    final firstMkt = todayMarkets.first;
    final extraCnt = todayMarkets.length - 1;
    slides.add(PortalBannerSlide(
      id: 'slide_market_${today.month}_${today.day}_${firstMkt.id}',
      badge: lang == AppLang.ko ? '🧺 오늘(${today.month}/${today.day}) 열리는 5일장' : '🧺 Open Today · 5-Day Market',
      title: lang == AppLang.ko
          ? '[${firstMkt.province} ${firstMkt.city}] ${firstMkt.title}${extraCnt > 0 ? " 외 $extraCnt곳 개장" : " 장날!"}'
          : '[${firstMkt.province}] ${firstMkt.title} Traditional Market Day',
      subtitle: lang == AppLang.ko
          ? '대표 장터 먹거리: ${firstMkt.specialty} · 지도에서 주변 맛집·숙소 보기'
          : 'Local specialties: ${firstMkt.specialty} · Tap to jump on map',
      ctaLabel: lang == AppLang.ko ? '장터 위치 보기' : 'View Market',
      accentColor: const Color(0xFFD97706),
      targetMarket: firstMkt,
    ));
  }

  // 2. 선택 시도(또는 전국) 대표 축제 동적 슬라이드
  final eventCandidates = allItems.where((it) {
    if (it.category != DiscoveryCategory.event) return false;
    return selectedProvince == '전체' || it.province == selectedProvince;
  }).toList();
  if (eventCandidates.isNotEmpty) {
    final ev = eventCandidates.first;
    final fresh = ev.dynamicFreshnessBadge(lang, now: today) ?? (lang == AppLang.ko ? '🎉 시즌 추천 축제' : '🎉 Featured Festival');
    slides.add(PortalBannerSlide(
      id: 'slide_event_${ev.id}',
      badge: fresh,
      title: '[${ev.province}] ${ev.title}',
      subtitle: ev.subtitle.isNotEmpty ? ev.subtitle : ev.address,
      ctaLabel: lang == AppLang.ko ? '축제·주변코스' : 'Explore',
      accentColor: const Color(0xFF7C3AED),
      targetItem: ev,
    ));
  }

  // 3. 지자체 원본 PDF 직링크 가이드북 슬라이드 (선택 시도 우선, 기본 장수군 PDF 직링크 우선)
  final ebookCandidates = allItems.where((it) {
    if (it.category != DiscoveryCategory.ebook) return false;
    return selectedProvince == '전체' || it.province == selectedProvince;
  }).toList();
  ebookCandidates.sort((a, b) => b.pdfLinks.length.compareTo(a.pdfLinks.length));
  if (ebookCandidates.isNotEmpty) {
    final eb = ebookCandidates.first;
    final directPdfUrl = eb.pdfLinks.isNotEmpty ? eb.pdfLinks.first.url : eb.externalUrl;
    slides.add(PortalBannerSlide(
      id: 'slide_pdf_${eb.id}',
      badge: lang == AppLang.ko ? '📖 지자체 공식 PDF 직링크' : '📖 Official Direct PDF Map',
      title: '[${eb.province}] ${eb.title}',
      subtitle: lang == AppLang.ko ? '회원가입 없이 고화질 원본 관광지도·책자 PDF 1초 열람' : 'Instant high-res municipal PDF tourist map without sign-up',
      ctaLabel: lang == AppLang.ko ? '원본 PDF 열기' : 'Open PDF',
      accentColor: const Color(0xFF2563EB),
      targetItem: eb,
      directExternalUrl: directPdfUrl,
    ));
  }

  // 4. 2026 반값여행 50% 환급 & 디지털 관광주민증 혜택관 슬라이드
  slides.add(PortalBannerSlide(
    id: 'slide_half_price_2026',
    badge: lang == AppLang.ko ? '🎁 2026 정부·지자체 지원' : '🎁 2026 Official 50% Pass',
    title: lang == AppLang.ko
        ? '대한민국 반값여행(25개 시·군 50% 환급) & 디지털 관광주민증'
        : '2026 Korea 50% Cashback Towns & K-Tourism Digital Resident Pass',
    subtitle: lang == AppLang.ko
        ? '사전신청 가이드 확인 후 영수증 정산이 가능한 합법 인증 숙소·식당을 찾으세요'
        : 'Check eligible subsidy towns, free official magazines, and licensed stays',
    ctaLabel: lang == AppLang.ko ? '혜택관 열기' : 'Benefits Hub',
    accentColor: const Color(0xFF059669),
    openBenefitsHub: true,
  ));

  return slides;
}

/// 오프라인·테스트 환경에서도 Zillow형 지도+피드+동선 연결이 즉시 동작하도록 제공하는 기본 시드 항목.
const List<DiscoveryItem> kBuiltInSeedDiscoveryItems = [
  DiscoveryItem(
    id: 'ebook_jeonbuk_jangsu',
    category: DiscoveryCategory.ebook,
    title: '장수군청 공식 관광안내도 & 《장수여행》 PDF',
    province: '전북',
    regionLabel: '전북 장수군',
    address: '관광안내지도(tour_guide.pdf) · 종합안내책자(tourist.pdf) 원본 직링크 즉시 열람',
    lat: 35.6473,
    lng: 127.5215,
    subtitle: '회원가입 없이 고화질 관광안내지도 PDF와 안내책자 PDF를 바로 열람합니다.',
    externalUrl: 'https://www.jangsu.go.kr/images/tour/tour_guide.pdf',
    mapUrl: 'https://map.naver.com/p/search/%EC%9E%A5%EC%88%98%EA%B5%B0%20%EA%B4%80%EA%B4%91',
    priorityScore: 130,
    pdfLinks: [
      MunicipalPdfLink(
        label: '🗺️ 관광안내지도 PDF 원본',
        labelEn: '🗺️ Direct Tourist Map PDF',
        url: 'https://www.jangsu.go.kr/images/tour/tour_guide.pdf',
      ),
      MunicipalPdfLink(
        label: '📖 《장수여행》 안내책자 PDF',
        labelEn: '📖 Direct Guidebook PDF',
        url: 'https://www.jangsu.go.kr/images/tour/content/sub05/tourist.pdf',
      ),
      MunicipalPdfLink(
        label: '🏛️ 장수군 문화관광 포털',
        labelEn: '🏛️ Jangsu Tour Portal',
        url: 'https://www.jangsu.go.kr/tour/index.jangsu',
      ),
    ],
  ),
  DiscoveryItem(
    id: 'ebook_jeonbuk_muju',
    category: DiscoveryCategory.ebook,
    title: '자연특별시 무주군 공식 관광안내도 & 덕유산 트레킹 지도',
    province: '전북',
    regionLabel: '전북 무주군',
    address: '무주군 종합 관광안내도 PDF · 구천동 트레킹 지도',
    lat: 36.0068,
    lng: 127.6608,
    subtitle: '구천동 및 덕유산 트레킹 지도, 주요 명소 리플릿 무료 다운로드',
    externalUrl: 'https://tour.muju.go.kr/tour/contents.do?key=109',
    mapUrl: 'https://map.naver.com/p/search/%EB%AC%B4%EC%A3%BC%EA%B5%B0%20%EA%B4%80%EA%B4%91',
    priorityScore: 128,
    pdfLinks: [
      MunicipalPdfLink(
        label: '🗺️ 무주 관광안내도 PDF',
        labelEn: '🗺️ Muju Tourist Map PDF',
        url: 'https://tour.muju.go.kr/tour/contents.do?key=109',
      ),
      MunicipalPdfLink(
        label: '🏛️ 자연특별시 무주 포털',
        labelEn: '🏛️ Muju Tour Portal',
        url: 'https://tour.muju.go.kr/',
      ),
    ],
  ),
  DiscoveryItem(
    id: 'ebook_jeonbuk_jinan',
    category: DiscoveryCategory.ebook,
    title: '진안군 종합 가이드북 《진안고원여행》 E-book',
    province: '전북',
    regionLabel: '전북 진안군',
    address: '마이산·용담호·계곡·홍삼 등 12개 테마 수록 가이드북',
    lat: 35.7917,
    lng: 127.4248,
    subtitle: '웹 E-book 뷰어 및 PDF 관광지도 즉시 열람',
    externalUrl: 'https://tour.jinan.go.kr/index.jinan?menuCd=DOM_000000205003000000',
    mapUrl: 'https://map.naver.com/p/search/%EC%A7%84%EC%95%88%EA%B5%B0%20%EA%B4%80%EA%B4%91',
    priorityScore: 127,
  ),
  DiscoveryItem(
    id: 'spot_ev_seed_1',
    category: DiscoveryCategory.event,
    title: '무주 반딧불 & 덕유산 계절 트레킹 페스타',
    province: '전북',
    regionLabel: '전북 무주군',
    address: '전북특별자치도 무주군 설천면 구천동로',
    lat: 35.9912,
    lng: 127.7124,
    startDate: '20261101',
    endDate: '20261215',
    subtitle: '지자체 공식 생태 트레킹 및 야간 문화행사',
    mapUrl: 'https://map.naver.com/p/search/%EB%AC%B4%EC%A3%BC%20%EA%B5%AC%EC%B2%9C%EB%8F%99',
    priorityScore: 135,
  ),
  DiscoveryItem(
    id: 'spot_fo_seed_1',
    category: DiscoveryCategory.food,
    title: '장수 한우명가 로컬식당',
    province: '전북',
    regionLabel: '전북 장수군',
    address: '전북특별자치도 장수군 장수읍 장천로',
    lat: 35.6495,
    lng: 127.5190,
    subtitle: '장수 특산 한우 & 사과 후식 로컬 맛집',
    isSponsored: true,
    couponTitle: '직스테이 방문 혜택 · 화면 제시 시 음료/후식 서비스',
    mapUrl: 'https://map.naver.com/p/search/%EC%9E%A5%EC%88%98%20%ED%95%9C%EC%9A%B0',
    priorityScore: 125,
  ),
  DiscoveryItem(
    id: 'spot_at_seed_1',
    category: DiscoveryCategory.attraction,
    title: '진안 마이산 탑사 & 고원길',
    province: '전북',
    regionLabel: '전북 진안군',
    address: '전북특별자치도 진안군 마령면 마이산남로',
    lat: 35.7556,
    lng: 127.4122,
    subtitle: '진안군 대표 명승지 · 트레킹 명소',
    mapUrl: 'https://map.naver.com/p/search/%EB%A7%88%EC%9D%B4%EC%82%B0%20%ED%83%91%EC%82%AC',
    priorityScore: 118,
  ),
];

DailyStoryItem? parseDailyStoryFromJson(Map<String, dynamic> m) {
  final id = (m['id'] ?? '').toString().trim();
  final title = (m['title'] ?? '').toString().trim();
  if (id.isEmpty || title.isEmpty) return null;

  final months = (m['months'] is List)
      ? (m['months'] as List).map((e) => (e as num?)?.toInt() ?? 0).where((d) => d >= 1 && d <= 12).toList()
      : const <int>[];
  final paragraphs = (m['paragraphs'] is List)
      ? (m['paragraphs'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
      : const <String>[];
  final images = (m['images'] is List)
      ? (m['images'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
      : const <String>[];
  final pInfo = <PracticalInfoRow>[];
  if (m['practical_info'] is List) {
    for (final r in (m['practical_info'] as List)) {
      if (r is Map) {
        final l = (r['label'] ?? '').toString().trim();
        final v = (r['value'] ?? '').toString().trim();
        if (l.isNotEmpty && v.isNotEmpty) {
          pInfo.add(PracticalInfoRow(label: l, value: v));
        }
      }
    }
  }
  final pdfs = <MunicipalPdfLink>[];
  if (m['pdf_links'] is List) {
    for (final rawLink in (m['pdf_links'] as List)) {
      if (rawLink is Map) {
        final lUrl = (rawLink['url'] ?? '').toString().trim();
        final lLabel = (rawLink['label'] ?? '').toString().trim();
        if (lUrl.isNotEmpty && lLabel.isNotEmpty) {
          pdfs.add(MunicipalPdfLink(
            label: lLabel,
            labelEn: (rawLink['label_en'] ?? '').toString().trim(),
            url: lUrl,
          ));
        }
      }
    }
  }

  return DailyStoryItem(
    id: id,
    province: (m['province'] ?? '전북').toString(),
    city: (m['city'] ?? '').toString(),
    seasonBadge: (m['season_badge'] ?? '📖 지자체 공식 스토리').toString(),
    sourceBook: (m['source_book'] ?? '지자체 발행 관광 가이드북').toString(),
    months: months,
    title: title,
    subtitle: (m['subtitle'] ?? '').toString(),
    address: (m['address'] ?? '').toString(),
    lat: (m['lat'] as num?)?.toDouble() ?? 35.59214,
    lng: (m['lng'] as num?)?.toDouble() ?? 127.50133,
    phone: (m['phone'] ?? '').toString(),
    pullQuote: (m['pull_quote'] ?? '').toString(),
    paragraphs: paragraphs,
    images: images,
    practicalHeader: (m['practical_header'] ?? '').toString(),
    practicalInfo: pInfo,
    pdfLinks: pdfs,
    enSummary: (m['en_summary'] ?? '').toString(),
  );
}

const List<DailyStoryItem> kFallbackDailyMunicipalStories = [
  DailyStoryItem(
    id: 'spot_story_tteunbongsaem',
    province: '전북',
    city: '장수군',
    seasonBadge: '🍂 가을·초겨울 생태숲길 테마',
    sourceBook: '장수군청 공식 가이드북 《장수여행》 p.9 수록',
    months: [9, 10, 11, 4, 5],
    title: '금강첫물, 뜬봉샘 발원지',
    subtitle: '장수군 물뿌랭이길 10-18 (금강사랑물체험관)',
    address: '전북특별자치도 장수군 장수읍 물뿌랭이길 10-18',
    lat: 35.59214,
    lng: 127.50133,
    phone: '063-350-2550',
    pullQuote: '조선 개국조 이성계가 봉황새가 오색 무지개를 타고 하늘로 뜬 것을 보고 개국의 계시를 받은 곳 — 서해바다까지 397.25km를 흐르는 금강의 첫물',
    paragraphs: [
      '수분마을에 위치한 신무산은 계곡을 따라 1.5km 올라가면 금강의 발원천이 되는 뜬봉샘이 있다. 뜬봉샘은 금강의 발원지이며 조선 개국조 이성계가 봉황새가 무지개를 타고 하늘로 뜬 것을 보고 천지신명으로부터 개국의 계시를 받았다는 설화가 있는 곳이다.',
      '뜬봉샘부터 시작한 물줄기는 서해바다 하구까지 397.25km로 흐른다. 특히 뜬봉샘생태공원은 금강사랑물 체험관, 자생 야생화 군락지, 생태놀이터, 생태온실, 생태숲길 등 다양한 공간과 멸종위기 종을 비롯한 동물들과 양서 파충류 등을 전시하여 관광객들에게 다양한 볼거리를 제공하고, 생태체험과 교육의 장을 제공한다.',
    ],
    images: [
      'https://tong.visitkorea.or.kr/cms/resource/69/4098569_image2_1.jpg',
      'https://tong.visitkorea.or.kr/cms/resource/68/4098568_image2_1.jpg',
      'https://tong.visitkorea.or.kr/cms/resource/67/4098567_image2_1.jpg',
      'https://tong.visitkorea.or.kr/cms/resource/70/4098570_image2_1.jpg',
    ],
    practicalHeader: '생태관광해설사와 함께 하는 생태관광 프로그램 · 3~11월 사전예약 필수',
    practicalInfo: [
      PracticalInfoRow(label: '트레킹 코스', value: '뜬봉샘 탐방로 코스 (1시간 코스, 왕복 3km)'),
      PracticalInfoRow(label: '해설 시간', value: '10:00 ~ 16:00 (생태프로그램 진행 시 해설 불가)'),
      PracticalInfoRow(label: '문의 전화', value: '063-350-2550 / 063-353-7002'),
      PracticalInfoRow(label: '무장애 편의시설', value: '촉지·음성 종합안내도, 장애인 전용 주차구역, 접근가능한 화장실·휴게시설·체험시설, 장애인동선'),
    ],
    pdfLinks: [
      MunicipalPdfLink(
        label: '📖 《장수여행》 가이드북 원본 열람 (p.9)',
        labelEn: '📖 Open Jangsu Guidebook PDF (p.9)',
        url: 'https://www.jangsu.go.kr/images/tour/content/sub05/tourist.pdf#page=9',
      ),
      MunicipalPdfLink(
        label: '🗺️ 장수 관광안내지도 PDF',
        labelEn: '🗺️ Jangsu Tourist Map PDF',
        url: 'https://www.jangsu.go.kr/images/tour/tour_guide.pdf',
      ),
    ],
    enSummary: 'Tteunbongsaem Eco Park in Jangsu-gun is the sacred headwater of the 397.25km Geumgang River, featuring a gentle 3km (1-hour) forest boardwalk trail and Joseon founding legend.',
  ),
  DailyStoryItem(
    id: 'spot_story_baengnyeonsa',
    province: '전남',
    city: '강진군',
    seasonBadge: '🌺 초겨울~봄 동백숲 · 사색의 오솔길',
    sourceBook: '전남·강진 공식 가이드북 《남도여행길잡이》 수록',
    months: [11, 12, 1, 2, 3, 4],
    title: '강진 만덕산 백련사 동백나무 숲과 다산 오솔길',
    subtitle: '강진군 도암면 백련사길 145 (천연기념물 제151호)',
    address: '전라남도 강진군 도암면 백련사길 145',
    lat: 34.58764,
    lng: 126.74859,
    phone: '061-432-0837',
    pullQuote: '다산 정약용과 혜장선사가 차와 학문을 나누러 오가던 800m 비밀의 숲길, 천연기념물 토종 동백 1,500그루의 군락',
    paragraphs: [
      '고려 시대 원묘국사가 백련결사를 일으켰던 유서 깊은 사찰 백련사 주변으로는 천연기념물 제151호로 지정된 약 1,500여 그루의 토종 동백나무가 울창한 푸른 숲을 이루고 있다.',
      '약 7m 높이의 동백나무 터널을 지나 다산초당으로 이어지는 호젓한 산허리 오솔길은 유배 시절 다산 정약용 선생이 날마다 걸었던 사색의 길로, 남도 강진만의 바다 풍경까지 한눈에 내려다보인다.',
    ],
    images: [
      'https://tong.visitkorea.or.kr/cms/resource/36/4065236_image2_1.jpg',
      'https://tong.visitkorea.or.kr/cms/resource/39/4065239_image2_1.jpg',
    ],
    practicalHeader: '백련사 ~ 다산초당 연결 사색 산책로 · 강진 반값여행(50% 환급) 대표 코스',
    practicalInfo: [
      PracticalInfoRow(label: '탐방 코스', value: '백련사 동백숲 ~ 다산초당 오솔길 (편도 약 800m, 도보 30분)'),
      PracticalInfoRow(label: '입장 및 관람', value: '상시 개방 · 입장료 무료'),
      PracticalInfoRow(label: '문의 전화', value: '061-432-0837'),
    ],
    pdfLinks: [
      MunicipalPdfLink(
        label: '📖 남도여행 공식 e-가이드북 열람',
        labelEn: '📖 Open Namdo Official Travel E-book',
        url: 'https://www.namdokorea.com',
      ),
    ],
    enSummary: 'A Natural Monument camellia forest of 1,500 native trees surrounding historic Baengnyeonsa Temple in Gangjin.',
  ),
];

/// 계절(월)·선택 지역·오늘 날짜에 맞춰 '하루 단 한 편' 주인공 로컬 스토리를 선정한다.
DailyStoryItem pickTodayMunicipalStory({
  required List<DailyStoryItem> stories,
  required List<DiscoveryItem> allItems,
  String selectedProvince = '전체',
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final source = stories.isNotEmpty ? stories : kFallbackDailyMunicipalStories;

  // 1. 특정 시·도를 선택한 경우 해당 시·도 스토리 우선
  if (selectedProvince != '전체') {
    final inProv = source.where((s) => s.province == selectedProvince).toList();
    if (inProv.isNotEmpty) {
      final seasonalProv = inProv.where((s) => s.months.isEmpty || s.months.contains(today.month)).toList();
      final pool = seasonalProv.isNotEmpty ? seasonalProv : inProv;
      final idx = today.difference(DateTime(2026, 11, 15)).inDays.abs() % pool.length;
      return pool[idx];
    }
    // 해당 시·도의 전용 가이드북 스토리가 아직 없으면 지자체 E-book + 대표 명소/축제를 결합해 즉시 생성
    final provEbooks = allItems.where((e) => e.category == DiscoveryCategory.ebook && e.province == selectedProvince).toList();
    final provSpots = allItems
        .where((e) =>
            (e.category == DiscoveryCategory.event || e.category == DiscoveryCategory.attraction) &&
            e.province == selectedProvince)
        .toList();
    if (provSpots.isNotEmpty) {
      final topSpot = provSpots.first;
      final eb = provEbooks.isNotEmpty ? provEbooks.first : null;
      return DailyStoryItem(
        id: topSpot.id,
        province: selectedProvince,
        city: topSpot.regionLabel,
        seasonBadge: topSpot.category == DiscoveryCategory.event ? '🎉 지금 주목할 지역 축제 스토리' : '🏞️ 계절 테마 로컬 명소 이야기',
        sourceBook: eb != null ? eb.title : '$selectedProvince 공식 문화관광 자료',
        months: const [],
        title: topSpot.title,
        subtitle: topSpot.address,
        address: topSpot.address,
        lat: topSpot.lat,
        lng: topSpot.lng,
        phone: topSpot.phone,
        pullQuote: topSpot.subtitle.isNotEmpty ? topSpot.subtitle : '$selectedProvince에서 만나는 특별한 계절 여행지',
        paragraphs: [
          if (topSpot.subtitle.isNotEmpty) topSpot.subtitle,
          if (eb != null) '${eb.title}(${eb.address})을 함께 열람하시면 주변 추천 산책코스와 로컬 먹거리 지도를 한눈에 확인하실 수 있습니다.',
        ],
        images: topSpot.imageUrl.isNotEmpty ? [topSpot.imageUrl] : const [],
        practicalHeader: '$selectedProvince 추천 방문지 · 대중교통 및 자차 길찾기 바로 연결',
        practicalInfo: [
          if (topSpot.address.isNotEmpty) PracticalInfoRow(label: '위치 주소', value: topSpot.address),
          if (topSpot.phone.isNotEmpty) PracticalInfoRow(label: '문의 전화', value: topSpot.phone),
        ],
        pdfLinks: eb != null
            ? (eb.pdfLinks.isNotEmpty
                ? eb.pdfLinks
                : [MunicipalPdfLink(label: '📖 ${eb.province} 공식 관광지도 열람', url: eb.externalUrl)])
            : const [],
      );
    }
  }

  // 2. 전체 보기: 현재 계절(월)에 어울리는 스토리를 필터링한 뒤 날짜별로 하루 한 편씩 순환 추천
  final seasonal = source.where((s) => s.months.isEmpty || s.months.contains(today.month)).toList();
  final pool = seasonal.isNotEmpty ? seasonal : source;
  final dayOffset = DateTime(today.year, today.month, today.day).difference(DateTime(2026, 11, 15)).inDays.abs();
  return pool[dayOffset % pool.length];
}

