part of '../discovery_models.dart';

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

  final parsedImages = <String>[];
  if (m['images'] is List) {
    for (final rawImg in (m['images'] as List)) {
      final s = rawImg.toString().trim();
      if (s.isNotEmpty && !parsedImages.contains(s)) parsedImages.add(s);
    }
  }
  final primaryImg = (m['image_url'] ?? m['image'] ?? (parsedImages.isNotEmpty ? parsedImages.first : '')).toString();
  if (primaryImg.isNotEmpty && !parsedImages.contains(primaryImg)) {
    parsedImages.insert(0, primaryImg);
  }

  final parsedParagraphs = <String>[];
  if (m['paragraphs'] is List) {
    for (final p in (m['paragraphs'] as List)) {
      final s = p.toString().trim();
      if (s.isNotEmpty) parsedParagraphs.add(s);
    }
  }

  final parsedPracticalInfo = <PracticalInfoRow>[];
  if (m['practical_info'] is List) {
    for (final r in (m['practical_info'] as List)) {
      if (r is Map) {
        final l = (r['label'] ?? '').toString().trim();
        final v = (r['value'] ?? '').toString().trim();
        if (l.isNotEmpty && v.isNotEmpty) {
          parsedPracticalInfo.add(PracticalInfoRow(label: l, value: v));
        }
      }
    }
  }

  final parsedNaverReviews = <NaverPlaceReviewSnippet>[];
  if (m['naver_reviews'] is List) {
    for (final rv in (m['naver_reviews'] as List)) {
      if (rv is Map) {
        final link = (rv['link'] ?? '').toString().trim();
        final rTitle = (rv['title'] ?? '').toString().trim();
        final rSum = (rv['summary'] ?? '').toString().trim();
        if (link.isNotEmpty && rTitle.isNotEmpty) {
          parsedNaverReviews.add(NaverPlaceReviewSnippet(
            title: rTitle,
            summary: rSum,
            blogger: (rv['blogger'] ?? '').toString().trim(),
            postdate: (rv['postdate'] ?? '').toString().trim(),
            link: link,
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
    address: (m['addr'] ?? m['address'] ?? m['materials'] ?? '').toString(),
    lat: useLat,
    lng: useLng,
    imageUrl: primaryImg,
    galleryImages: parsedImages,
    subtitle: (m['materials'] ?? m['overview'] ?? m['summary'] ?? m['addr'] ?? '').toString(),
    pullQuote: (m['pull_quote'] ?? m['summary'] ?? '').toString(),
    paragraphs: parsedParagraphs,
    practicalHeader: (m['practical_header'] ?? '').toString(),
    practicalInfo: parsedPracticalInfo,
    naverReviews: parsedNaverReviews,
    externalUrl: (m['url'] ?? m['article_url'] ?? '').toString(),
    mapUrl: (m['map_url'] ?? m['naver_map_url'] ?? 'https://map.naver.com/p/search/${Uri.encodeComponent('$prov $title')}').toString(),
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
    // 스폰서 방문혜택 업장은 근거리 내에서 소폭 우선 노출
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
