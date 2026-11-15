// 직스테이 로컬 (하루 한 편 지자체 가이드북 스토리 + 인터랙티브 로컬 지도 · 동선 연결 플랫폼)
// - 첫 화면: 선택 과부하를 없앤 단일 테마 바 + '오늘의 계절·테마 로컬 스토리' 히어로 배너 + 연동 로컬 피드
// - 배너 클릭 시: 지자체 공식 책자(PDF) 원문·사진·필수 탐방정보 박스를 담은 매거진형 스토리 상세 페이지 이동
// - ?id=stay_xxx / ?story=spot_story_xxx / ?spot=... / ?region=... 딥링크 호환
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'amenities.dart';
import 'demo_data.dart';
import 'detail_page.dart';
import 'discovery_models.dart';
import 'firebase_options.dart';
import 'i18n.dart';
import 'legal.dart';
import 'spot_detail_sheet.dart';
import 'story_detail_page.dart';
import 'travel_hub.dart';
import 'web_utils.dart';
import 'zillow_map_view.dart';

/// reCAPTCHA Enterprise 사이트 키: flutter build web --dart-define=RECAPTCHA_SITE_KEY=...
const kRecaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kRecaptchaSiteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.activate(providerWeb: ReCaptchaEnterpriseProvider(kRecaptchaSiteKey));
  } else {
    debugPrint('경고: RECAPTCHA_SITE_KEY 미설정 — App Check 비활성');
  }
  runApp(const DirectStayApp());
}

/// 5대 광역권 매칭 헬퍼 (혜택관 연동 및 하위 호환)
const Map<String, List<String>> kRegionKeywords = {
  '전체': [],
  '제주': ['제주'],
  '강원': ['강원'],
  '부산/경상': ['부산', '대구', '울산', '경상', '경북', '경남'],
  '전라/충청': ['광주', '전라', '전북', '전남', '대전', '세종', '충청', '충북', '충남'],
  '서울/경기': ['서울', '인천', '경기'],
};

bool matchesRegion(String region1, String chip) {
  final keys = kRegionKeywords[chip] ?? const [];
  return keys.isEmpty || keys.any(region1.contains);
}

enum ListingSort {
  newest('추천·최신순'),
  ratingDesc('평점 높은순'),
  priceAsc('낮은 요금순'),
  clicksDesc('인기순');

  final String label;
  const ListingSort(this.label);
}

int? listingMinPrice(Map<String, dynamic> data, {StayPeriod period = StayPeriod.all}) {
  final p = data['pricing'];
  if (p is! Map) return null;
  final keys = switch (period) {
    StayPeriod.nightly => const ['nightly_min'],
    StayPeriod.weekly => const ['weekly_price'],
    StayPeriod.monthly => const ['monthly_price'],
    StayPeriod.all => const ['monthly_price', 'weekly_price', 'nightly_min'],
  };
  for (final key in keys) {
    final v = p[key];
    if (v is num) return v.round();
  }
  return null;
}

bool matchesPeriod(Map<String, dynamic> data, StayPeriod period) {
  if (period == StayPeriod.all) return true;
  return listingMinPrice(data, period: period) != null;
}

bool matchesMinGuests(Map<String, dynamic> data, int minGuests) {
  if (minGuests <= 1) return true;
  final maxCap = (data['capacity_max'] as num?)?.toInt() ?? (data['capacity_standard'] as num?)?.toInt();
  if (maxCap == null) return true;
  return maxCap >= minGuests;
}

int _timestampMillis(dynamic ts) {
  if (ts is Timestamp) return ts.millisecondsSinceEpoch;
  if (ts is DateTime) return ts.millisecondsSinceEpoch;
  if (ts is int) return ts;
  return 0;
}

List<MapEntry<String, Map<String, dynamic>>> filterAndSortListings(
  List<MapEntry<String, Map<String, dynamic>>> items, {
  required String region,
  String licenseType = '전체',
  StayPeriod period = StayPeriod.all,
  String amenityTab = '전체',
  int minGuests = 1,
  String query = '',
  ListingSort sort = ListingSort.newest,
}) {
  final q = query.trim().toLowerCase();
  final filtered = items.where((entry) {
    final d = entry.value;
    if (!matchesRegion((d['region_depth1'] ?? '').toString(), region)) return false;
    if (licenseType != '전체' && (d['license_type'] ?? '').toString() != licenseType) return false;
    if (!matchesPeriod(d, period)) return false;
    if (!matchesMinGuests(d, minGuests)) return false;
    if (!matchesAmenityTab(d, amenityTab)) return false;
    if (q.isEmpty) return true;
    final amenityWords = resolveAmenityGroups(d).expand((g) => g.items);
    final i18nTitles = <Object?>[];
    if (d['i18n'] is Map) {
      for (final v in (d['i18n'] as Map).values) {
        if (v is Map) {
          i18nTitles.add(v['title']);
          i18nTitles.add(v['subtitle']);
        }
      }
    }
    final haystack = [
      d['title'],
      d['region_depth1'],
      d['region_depth2'],
      d['accommodation_type'],
      d['license_type'],
      d['promo_title'],
      ...i18nTitles,
      ...(d['options'] as List? ?? const []),
      ...(d['summary_points'] as List? ?? const []),
      ...amenityWords,
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
    return haystack.contains(q);
  }).toList();

  filtered.sort((a, b) {
    switch (sort) {
      case ListingSort.newest:
        final sa = a.value['is_sponsored'] == true ? 1 : 0;
        final sb = b.value['is_sponsored'] == true ? 1 : 0;
        if (sa != sb) return sb.compareTo(sa);
        final csa = (a.value['curated_score'] as num?)?.toDouble() ?? 0;
        final csb = (b.value['curated_score'] as num?)?.toDouble() ?? 0;
        if (csa != csb) return csb.compareTo(csa);
        return _timestampMillis(b.value['created_at']).compareTo(_timestampMillis(a.value['created_at']));
      case ListingSort.ratingDesc:
        final ra = extractListingRating(a.value);
        final rb = extractListingRating(b.value);
        if (ra.count == 0 && rb.count == 0) {
          final csa = (a.value['curated_score'] as num?)?.toDouble() ?? 0;
          final csb = (b.value['curated_score'] as num?)?.toDouble() ?? 0;
          return csb.compareTo(csa);
        }
        if (ra.count == 0) return 1;
        if (rb.count == 0) return -1;
        final avgCmp = rb.average.compareTo(ra.average);
        if (avgCmp != 0) return avgCmp;
        return rb.count.compareTo(ra.count);
      case ListingSort.priceAsc:
        final pa = listingMinPrice(a.value, period: period);
        final pb = listingMinPrice(b.value, period: period);
        if (pa == null && pb == null) return 0;
        if (pa == null) return 1;
        if (pb == null) return -1;
        return pa.compareTo(pb);
      case ListingSort.clicksDesc:
        final ca = (a.value['outbound_clicks'] as num?)?.toInt() ?? 0;
        final cb = (b.value['outbound_clicks'] as num?)?.toInt() ?? 0;
        return cb.compareTo(ca);
    }
  });
  return filtered;
}

class DirectStayApp extends StatelessWidget {
  const DirectStayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final params = Uri.base.queryParameters;
    if (params.containsKey('lang')) {
      appLangNotifier.value = parseAppLang(params['lang']);
    }

    final linkedId = params['id'];
    final initialRegion = params['region'];
    final initialSpotId = params['spot'];
    final initialStoryId = params['story'];
    final demoMode = params['demo'] == '1' || params['demo'] == 'true';

    Widget homeBuilder(BuildContext _) => HomePage(initialDemoMode: demoMode);

    return MaterialApp(
      title: '직스테이 로컬 · 오늘 떠나고 싶은 한국의 로컬 스토리',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F172A),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: (linkedId != null && RegExp(r'^stay_[a-zA-Z0-9_-]{4,32}$').hasMatch(linkedId))
          ? ListingDetailPage(listingId: linkedId, homeBuilder: homeBuilder)
          : HomePage(
              initialDemoMode: demoMode,
              initialRegion: initialRegion,
              initialSpotId: initialSpotId,
              initialStoryId: initialStoryId,
            ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool initialDemoMode;
  final List<DiscoveryItem>? seedItemsOverride;
  final String? initialRegion;
  final String? initialSpotId;
  final String? initialStoryId;

  const HomePage({
    super.key,
    this.initialDemoMode = false,
    this.seedItemsOverride,
    this.initialRegion,
    this.initialSpotId,
    this.initialStoryId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _feedPageSize = 18;

  final ZillowMapController _mapCtrl = ZillowMapController();
  final TextEditingController _searchCtrl = TextEditingController();

  DiscoveryCategory _category = DiscoveryCategory.all;
  String _selectedProvince = '전체';
  String _query = '';
  bool _showBenefitsHub = false;
  bool _showProvincePicker = false;
  bool _mobileFullMap = false;
  bool _loading = true;
  bool _offlineSeedMode = false;

  List<DiscoveryItem> _allItems = const [];
  List<DailyStoryItem> _dailyStories = kFallbackDailyMunicipalStories;
  MapViewportBounds? _viewport;
  String? _selectedItemId;
  String? _hoveredItemId;
  int _feedVisibleCount = _feedPageSize;
  bool _initialDeepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    if (widget.seedItemsOverride != null) {
      _allItems = widget.seedItemsOverride!;
      _offlineSeedMode = true;
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialPortalDeepLink());
    } else {
      _loadUnifiedDiscovery();
    }
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUnifiedDiscovery() async {
    final itemsById = <String, DiscoveryItem>{};

    // 1) 일일 지자체 스토리 + 전국 17개 시·도 E-book + 축제 + 볼거리 + 먹거리 로드
    final parsedStories = <DailyStoryItem>[];
    final hubJson = await fetchWebJson('data/public_travel_hub.json');
    if (hubJson != null) {
      for (final raw in (hubJson['daily_stories'] as List? ?? const [])) {
        if (raw is Map) {
          final st = parseDailyStoryFromJson(Map<String, dynamic>.from(raw));
          if (st != null) {
            parsedStories.add(st);
            final disc = st.toDiscoveryItem();
            itemsById[disc.id] = DiscoveryItem(
              id: disc.id,
              category: disc.category,
              title: disc.title,
              province: disc.province,
              regionLabel: disc.regionLabel,
              address: disc.address,
              lat: disc.lat,
              lng: disc.lng,
              imageUrl: disc.imageUrl,
              subtitle: disc.subtitle,
              phone: disc.phone,
              priorityScore: disc.priorityScore,
              pdfLinks: disc.pdfLinks,
              raw: const {'is_story': true},
            );
          }
        }
      }
      for (final raw in (hubJson['municipal_ebooks'] as List? ?? const [])) {
        if (raw is Map) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.ebook);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
      for (final raw in (hubJson['festivals'] as List? ?? const [])) {
        if (raw is Map) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.event);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
      for (final raw in (hubJson['spots'] as List? ?? const [])) {
        if (raw is Map) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.attraction);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
    }

    // 2) 전국 17개 시·도 합법 안심숙소 색인 로드
    final staysJson = await fetchWebJson('data/public_stays_index.json');
    if (staysJson != null && staysJson['items'] is List) {
      for (final raw in (staysJson['items'] as List)) {
        if (raw is Map) {
          final m = Map<String, dynamic>.from(raw);
          final id = (m['listing_id'] ?? '').toString();
          final parsed = parseStayToDiscoveryItem(id, m);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
    }

    // 오프라인/로컬 테스트 폴백
    if (itemsById.isEmpty || widget.initialDemoMode) {
      _offlineSeedMode = itemsById.isEmpty;
      for (final seed in kBuiltInSeedDiscoveryItems) {
        itemsById[seed.id] = seed;
      }
      for (final entry in demoListingEntries()) {
        final parsed = parseStayToDiscoveryItem(entry.key, entry.value);
        if (parsed != null) itemsById[parsed.id] = parsed;
      }
    }

    // 3) Firestore 실시간 별점·클릭 오버레이 (가볍게 평점 보유 항목만 조회)
    if (!widget.initialDemoMode && !_offlineSeedMode) {
      try {
        final staySnap = await FirebaseFirestore.instance
            .collection('listings')
            .where('status', isEqualTo: 'active')
            .where('review_count', isGreaterThan: 0)
            .limit(150)
            .get();
        for (final doc in staySnap.docs) {
          final prev = itemsById[doc.id];
          if (prev != null) {
            final d = doc.data();
            itemsById[doc.id] = prev.copyWithStats(
              reviewCount: (d['review_count'] as num?)?.toInt(),
              scoreSum: (d['score_sum'] as num?)?.toInt(),
              outboundClicks: (d['outbound_clicks'] as num?)?.toInt(),
            );
          }
        }
      } catch (_) {}

      try {
        final spotSnap = await FirebaseFirestore.instance
            .collection('spots')
            .where('status', isEqualTo: 'active')
            .where('review_count', isGreaterThan: 0)
            .limit(150)
            .get();
        for (final doc in spotSnap.docs) {
          final prev = itemsById[doc.id];
          if (prev != null) {
            final d = doc.data();
            itemsById[doc.id] = prev.copyWithStats(
              reviewCount: (d['review_count'] as num?)?.toInt(),
              scoreSum: (d['score_sum'] as num?)?.toInt(),
              outboundClicks: (d['outbound_clicks'] as num?)?.toInt(),
              isSponsored: d['is_sponsored'] as bool?,
              couponTitle: (d['coupon_title'] ?? '').toString(),
            );
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _allItems = itemsById.values.toList();
      if (parsedStories.isNotEmpty) {
        _dailyStories = parsedStories;
      }
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialPortalDeepLink());
  }

  void _openStoryDetail(DailyStoryItem story) {
    trackPortalEvent('open_daily_story', {
      'story_id': story.id,
      'province': story.province,
      'title': story.title,
    });
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoryDetailPage(
        story: story,
        allStories: _dailyStories,
        allItems: _allItems,
        lang: appLangNotifier.value,
        offlineMode: _offlineSeedMode || widget.initialDemoMode,
        homeBuilder: (_) => HomePage(initialDemoMode: widget.initialDemoMode),
      ),
    ));
  }

  void _openStoryById(String storyId) {
    for (final st in _dailyStories) {
      if (st.id == storyId) {
        _openStoryDetail(st);
        return;
      }
    }
  }

  void _applyInitialPortalDeepLink() {
    if (_initialDeepLinkHandled || !mounted) return;
    _initialDeepLinkHandled = true;

    final initReg = (widget.initialRegion ?? '').trim();
    if (initReg.isNotEmpty && kProvinceJumpList.any((p) => p.key == initReg)) {
      _selectProvince(initReg);
    }

    final initStory = (widget.initialStoryId ?? '').trim();
    if (initStory.isNotEmpty) {
      for (final st in _dailyStories) {
        if (st.id == initStory) {
          _openStoryDetail(st);
          return;
        }
      }
    }

    final initSpot = (widget.initialSpotId ?? '').trim();
    if (initSpot.isNotEmpty) {
      for (final st in _dailyStories) {
        if (st.id == initSpot) {
          _openStoryDetail(st);
          return;
        }
      }
      for (final it in _allItems) {
        if (it.id == initSpot) {
          _openItemSheet(it);
          break;
        }
      }
    }
  }

  List<DiscoveryItem> _filteredItems({bool applyViewport = false}) {
    final q = _query.trim().toLowerCase();
    final out = _allItems.where((it) {
      if (_category != DiscoveryCategory.all && it.category != _category) return false;
      if (_selectedProvince != '전체' && it.province != _selectedProvince) return false;
      if (applyViewport && _viewport != null && !_viewport!.contains(it.lat, it.lng)) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = '${it.title} ${it.province} ${it.regionLabel} ${it.address} ${it.subtitle} ${it.couponTitle}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();

    out.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return out;
  }

  void _selectProvince(String provKey) {
    final meta = kProvinceJumpList.firstWhere(
      (p) => p.key == provKey,
      orElse: () => kProvinceJumpList.first,
    );
    setState(() {
      _selectedProvince = provKey;
      _showProvincePicker = false;
      _selectedItemId = null;
      _feedVisibleCount = _feedPageSize;
    });
    _mapCtrl.moveTo(meta.lat, meta.lng, zoom: meta.zoom);
    syncPortalParams(region: provKey, spotId: null);
    trackPortalEvent('select_province', {'province': provKey});
  }

  void _openItemSheet(DiscoveryItem item) {
    setState(() => _selectedItemId = item.id);
    _mapCtrl.moveTo(item.lat, item.lng, zoom: math.max(_mapCtrl.zoom, 10.6));
    syncPortalParams(
      region: _selectedProvince,
      spotId: item.category == DiscoveryCategory.stay ? null : item.id,
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SpotDetailSheet(
        item: item,
        allItems: _allItems,
        lang: appLangNotifier.value,
        offlineMode: _offlineSeedMode || widget.initialDemoMode,
        onSelectConnectedItem: (next) {
          setState(() => _selectedItemId = next.id);
          _mapCtrl.moveTo(next.lat, next.lng, zoom: math.max(_mapCtrl.zoom, 11.0));
        },
        onOpenFullStayPage: (stayId) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ListingDetailPage(
              listingId: stayId,
              homeBuilder: (_) => HomePage(initialDemoMode: widget.initialDemoMode),
            ),
          ));
        },
        onOpenStoryPage: _openStoryById,
        onStatsUpdated: (itemId, rCount, sSum) {
          setState(() {
            _allItems = _allItems
                .map((e) => e.id == itemId ? e.copyWithStats(reviewCount: rCount, scoreSum: sSum) : e)
                .toList();
          });
        },
      ),
    );
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLangNotifier,
      builder: (context, lang, _) {
        final screenW = MediaQuery.sizeOf(context).width;
        final isDesktop = screenW >= 920;

        final mapCandidates = _filteredItems(applyViewport: false);
        var feedItems = _filteredItems(applyViewport: true);
        if (feedItems.isEmpty && mapCandidates.isNotEmpty) {
          feedItems = mapCandidates;
        }

        final todayStory = pickTodayMunicipalStory(
          stories: _dailyStories,
          allItems: _allItems,
          selectedProvince: _selectedProvince,
        );

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            toolbarHeight: 58,
            shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            titleSpacing: 16,
            title: Row(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _showBenefitsHub = false;
                      _category = DiscoveryCategory.all;
                      _searchCtrl.clear();
                      _query = '';
                    });
                    _selectProvince('전체');
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.explore_rounded, color: Color(0xFF0F172A), size: 25),
                      const SizedBox(width: 7),
                      Text(
                        trUi('brand_name', lang),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                if (screenW >= 560)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: SizedBox(
                        height: 38,
                        child: TextField(
                          key: const Key('top_search_input'),
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() {
                            _query = v;
                            _feedVisibleCount = _feedPageSize;
                          }),
                          decoration: InputDecoration(
                            hintText: trUi('search_hint', lang),
                            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    onPressed: () => setState(() {
                                      _searchCtrl.clear();
                                      _query = '';
                                    }),
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    key: const Key('toggle_benefits_hub_btn'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _showBenefitsHub = !_showBenefitsHub),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showBenefitsHub ? const Color(0xFF0F172A) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _showBenefitsHub ? const Color(0xFF0F172A) : const Color(0xFFFCD34D),
                        ),
                      ),
                      child: Text(
                        lang == AppLang.ko
                            ? (_showBenefitsHub ? '🗺️ 스토리·지도로' : '🎁 반값여행·E-book관')
                            : (_showBenefitsHub ? '🗺️ Story & Map' : '🎁 50% Pass & PDFs'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _showBenefitsHub ? Colors.white : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: LangSelectorButton(),
              ),
            ],
            bottom: _showBenefitsHub
                ? null
                : PreferredSize(
                    preferredSize: Size.fromHeight(_showProvincePicker ? 84 : 46),
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 단일 깔끔한 탐색 바: [📍 지역 선택 토글] + 핵심 테마 탭 (선택 피로 최소화)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InkWell(
                                    key: const Key('region_picker_btn'),
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => setState(() => _showProvincePicker = !_showProvincePicker),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _selectedProvince == '전체'
                                            ? const Color(0xFFF1F5F9)
                                            : const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: _selectedProvince == '전체'
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            lang == AppLang.ko
                                                ? '📍 지역: ${trProvince(_selectedProvince, lang)}'
                                                : '📍 ${trProvince(_selectedProvince, lang)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: _selectedProvince == '전체'
                                                  ? const Color(0xFF0F172A)
                                                  : Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Icon(
                                            _showProvincePicker
                                                ? Icons.keyboard_arrow_up_rounded
                                                : Icons.keyboard_arrow_down_rounded,
                                            size: 16,
                                            color: _selectedProvince == '전체'
                                                ? const Color(0xFF475569)
                                                : Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                ...DiscoveryCategory.values.map((cat) {
                                  final sel = _category == cat;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: InkWell(
                                      key: Key('cat_chip_${cat.name}'),
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => setState(() {
                                        _category = cat;
                                        _feedVisibleCount = _feedPageSize;
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: sel ? cat.color : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: sel ? cat.color : const Color(0xFFCBD5E1),
                                          ),
                                        ),
                                        child: Text(
                                          trUi(cat.i18nKey, lang),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: sel ? Colors.white : const Color(0xFF334155),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          if (_showProvincePicker) ...[
                            const SizedBox(height: 6),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: kProvinceJumpList.map((p) {
                                  final sel = _selectedProvince == p.key;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 5),
                                    child: InkWell(
                                      key: Key('prov_chip_${p.key}'),
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => _selectProvince(p.key),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: sel ? const Color(0xFF0F172A) : Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: sel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Text(
                                          trProvince(p.key, lang),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: sel ? Colors.white : const Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          body: _showBenefitsHub
              ? PublicTravelHubView(
                  lang: lang,
                  onSelectCityForStays: (_, cityKeyword) {
                    setState(() {
                      _showBenefitsHub = false;
                      _category = DiscoveryCategory.all;
                      _searchCtrl.text = cityKeyword;
                      _query = cityKeyword;
                    });
                  },
                )
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : isDesktop
                      ? Row(
                          children: [
                            // 좌측 56%: 로컬 동선 지도
                            Expanded(
                              flex: 56,
                              child: ZillowMapView(
                                controller: _mapCtrl,
                                items: mapCandidates,
                                selectedItemId: _selectedItemId,
                                hoveredItemId: _hoveredItemId,
                                lang: lang,
                                onViewportChanged: (b) => setState(() => _viewport = b),
                                onPinTapped: (it) => setState(() => _selectedItemId = it.id),
                                onOpenDetailSheet: _openItemSheet,
                              ),
                            ),
                            Container(width: 1, color: const Color(0xFFE2E8F0)),
                            // 우측 44%: 하루 한 편 '오늘의 로컬 스토리' 히어로 배너 + 연동 피드
                            Expanded(
                              flex: 44,
                              child: _LiveLocalFeedPanel(
                                lang: lang,
                                selectedProvince: _selectedProvince,
                                todayStory: todayStory,
                                onOpenTodayStory: () => _openStoryDetail(todayStory),
                                feedItems: feedItems,
                                totalAreaCount: feedItems.length,
                                visibleLimit: _feedVisibleCount,
                                selectedItemId: _selectedItemId,
                                onHoverItem: (id) => setState(() => _hoveredItemId = id),
                                onTapItem: _openItemSheet,
                                onOpenEbookDirect: _openExternalUrl,
                                onLoadMore: () => setState(() => _feedVisibleCount += _feedPageSize),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            if (screenW < 560)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                                child: SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _searchCtrl,
                                    onChanged: (v) => setState(() => _query = v),
                                    decoration: InputDecoration(
                                      hintText: trUi('search_hint', lang),
                                      hintStyle: const TextStyle(fontSize: 12),
                                      prefixIcon: const Icon(Icons.search_rounded, size: 17),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              flex: _mobileFullMap ? 85 : 42,
                              child: Stack(
                                children: [
                                  ZillowMapView(
                                    controller: _mapCtrl,
                                    items: mapCandidates,
                                    selectedItemId: _selectedItemId,
                                    hoveredItemId: _hoveredItemId,
                                    lang: lang,
                                    onViewportChanged: (b) => setState(() => _viewport = b),
                                    onPinTapped: (it) => setState(() => _selectedItemId = it.id),
                                    onOpenDetailSheet: _openItemSheet,
                                  ),
                                  Positioned(
                                    bottom: 10,
                                    right: 12,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () => setState(() => _mobileFullMap = !_mobileFullMap),
                                      icon: Icon(_mobileFullMap ? Icons.view_list_rounded : Icons.map_rounded, size: 16),
                                      label: Text(_mobileFullMap ? '스토리·피드 보기' : '지도 크게'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_mobileFullMap) ...[
                              Container(height: 1, color: const Color(0xFFE2E8F0)),
                              Expanded(
                                flex: 58,
                                child: _LiveLocalFeedPanel(
                                  lang: lang,
                                  selectedProvince: _selectedProvince,
                                  todayStory: todayStory,
                                  onOpenTodayStory: () => _openStoryDetail(todayStory),
                                  feedItems: feedItems,
                                  totalAreaCount: feedItems.length,
                                  visibleLimit: _feedVisibleCount,
                                  selectedItemId: _selectedItemId,
                                  onHoverItem: (id) => setState(() => _hoveredItemId = id),
                                  onTapItem: _openItemSheet,
                                  onOpenEbookDirect: _openExternalUrl,
                                  onLoadMore: () => setState(() => _feedVisibleCount += _feedPageSize),
                                ),
                              ),
                            ],
                          ],
                        ),
        );
      },
    );
  }
}

class _LiveLocalFeedPanel extends StatelessWidget {
  final AppLang lang;
  final String selectedProvince;
  final DailyStoryItem todayStory;
  final VoidCallback onOpenTodayStory;
  final List<DiscoveryItem> feedItems;
  final int totalAreaCount;
  final int visibleLimit;
  final String? selectedItemId;
  final ValueChanged<String?> onHoverItem;
  final ValueChanged<DiscoveryItem> onTapItem;
  final ValueChanged<String> onOpenEbookDirect;
  final VoidCallback onLoadMore;

  const _LiveLocalFeedPanel({
    required this.lang,
    required this.selectedProvince,
    required this.todayStory,
    required this.onOpenTodayStory,
    required this.feedItems,
    required this.totalAreaCount,
    required this.visibleLimit,
    required this.selectedItemId,
    required this.onHoverItem,
    required this.onTapItem,
    required this.onOpenEbookDirect,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final shownCount = math.min(feedItems.length, visibleLimit);
    final hasMore = feedItems.length > shownCount;

    return CustomScrollView(
      key: const Key('live_feed_scroll'),
      slivers: [
        // 1. 하루 단 한 편 — 지자체 공식 가이드북·행사 기반 '오늘의 로컬 스토리' 히어로 카드
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: _DailyStoryHeroCard(
              story: todayStory,
              lang: lang,
              onTap: onOpenTodayStory,
            ),
          ),
        ),

        // 2. 실시간 피드 헤더 카운트
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${trUi('live_feed_title', lang)} (${selectedProvince == '전체' ? (lang == AppLang.ko ? '현재 지도 영역' : 'Map Area') : trProvince(selectedProvince, lang)})',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                Text(
                  lang == AppLang.ko ? '$totalAreaCount곳 연결됨' : '$totalAreaCount places',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),

        // 3. 실시간 로컬 피드 카드 스트림
        if (feedItems.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Center(
                child: Text(
                  lang == AppLang.ko
                      ? '현재 지도 영역에 일치하는 장소가 없습니다.\n지도를 축소하거나 다른 지역을 선택해 보세요.'
                      : 'No matching places in this map view. Zoom out or pick another province.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B), height: 1.5),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            sliver: SliverList.separated(
              itemCount: shownCount,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, idx) {
                final it = feedItems[idx];
                final isSelected = it.id == selectedItemId;
                return MouseRegion(
                  onEnter: (_) => onHoverItem(it.id),
                  onExit: (_) => onHoverItem(null),
                  child: _LiveFeedItemCard(
                    key: ValueKey('feed_card_${it.id}'),
                    item: it,
                    lang: lang,
                    isSelected: isSelected,
                    onTap: () => onTapItem(it),
                    onOpenEbookDirect: onOpenEbookDirect,
                  ),
                );
              },
            ),
          ),

        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(
                    lang == AppLang.ko
                        ? '더 보기 ($shownCount / ${feedItems.length})'
                        : 'Load More ($shownCount / ${feedItems.length})',
                  ),
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        const SliverToBoxAdapter(child: LegalFooter()),
      ],
    );
  }
}

class _DailyStoryHeroCard extends StatelessWidget {
  final DailyStoryItem story;
  final AppLang lang;
  final VoidCallback onTap;

  const _DailyStoryHeroCard({
    required this.story,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateTag = '${now.month}월 ${now.day}일 오늘의 로컬 스토리';

    return Container(
      key: const Key('daily_story_banner'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0x0D0F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: InkWell(
        key: const Key('open_daily_story_btn'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 풍경 사진 + 오늘의 스토리 태그 오버레이
            if (story.heroImage.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16.5)),
                child: SizedBox(
                  height: 175,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      StorageImage(url: story.heroImage, cacheWidth: 720),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.28),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.58),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF065F46).withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                lang == AppLang.ko ? '📖 $dateTag' : '📖 Today’s Local Story',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                story.seasonBadge,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 14,
                        right: 14,
                        child: Text(
                          '${story.province} ${story.city} · ${story.sourceBook}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 하단 스토리 헤드라인 & 설화 발췌문 & 상세 안내 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (story.heroImage.isEmpty) ...[
                    Text(
                      '📖 $dateTag · ${story.seasonBadge}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    story.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lang != AppLang.ko && story.enSummary.isNotEmpty
                        ? story.enSummary
                        : (story.pullQuote.isNotEmpty
                            ? story.pullQuote
                            : (story.paragraphs.isNotEmpty ? story.paragraphs.first : story.subtitle)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF334155),
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lang == AppLang.ko ? '📍 ${story.subtitle}' : '📍 ${story.address}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              lang == AppLang.ko ? '스토리 상세 보기' : 'Read Story',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF065F46),
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF065F46)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveFeedItemCard extends StatelessWidget {
  final DiscoveryItem item;
  final AppLang lang;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<String> onOpenEbookDirect;

  const _LiveFeedItemCard({
    super.key,
    required this.item,
    required this.lang,
    required this.isSelected,
    required this.onTap,
    required this.onOpenEbookDirect,
  });

  @override
  Widget build(BuildContext context) {
    final freshBadge = item.dynamicFreshnessBadge(lang);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0F172A)
                : (item.isSponsored ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 88,
                height: 88,
                child: item.imageUrl.isNotEmpty
                    ? StorageImage(url: item.imageUrl, cacheWidth: 280)
                    : Container(
                        color: item.category.color.withValues(alpha: 0.1),
                        alignment: Alignment.center,
                        child: Icon(item.category.icon, color: item.category.color, size: 30),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.category.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.categoryEmoji} ${item.province} · ${item.categoryBadgeText(lang)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: item.category.color),
                        ),
                      ),
                      if (freshBadge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            freshBadge,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C)),
                          ),
                        ),
                      if (item.isSponsored)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🎁 방문혜택 쿠폰',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                          ),
                        ),
                      if (item.reviewCount > 0)
                        Text(
                          '★ ${item.averageRating.toStringAsFixed(1)} (${item.reviewCount})',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.couponTitle.isNotEmpty
                        ? item.couponTitle
                        : (item.subtitle.isNotEmpty ? item.subtitle : item.address),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.couponTitle.isNotEmpty ? const Color(0xFF92400E) : const Color(0xFF475569),
                      fontWeight: item.couponTitle.isNotEmpty ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          lang == AppLang.ko ? '주변 맛집·명소·숙소 연결 보기' : 'Connected nearby places',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                        ),
                      ),
                      if (item.category == DiscoveryCategory.ebook && item.externalUrl.isNotEmpty)
                        InkWell(
                          onTap: () => onOpenEbookDirect(item.externalUrl),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '즉시 열람 ↗',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 개별 숙소 카드 위젯 (상세페이지·데모 호환 유지)
class ListingCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final StayPeriod period;
  final bool demoMode;

  const ListingCard({
    super.key,
    required this.docId,
    required this.data,
    this.period = StayPeriod.all,
    this.demoMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final images = (data['images'] as List?) ?? [];
    final firstImg = images.isNotEmpty ? Map<String, dynamic>.from(images.first as Map) : const <String, dynamic>{};
    final thumbUrl = (firstImg['url'] ?? '').toString();
    final thumbPath = (firstImg['path'] ?? '').toString();
    final points = List<String>.from(data['summary_points'] ?? []);
    final topAm = extractTopAmenities(data, limit: 3);
    final isForeignOnly = data['license_type'] == kForeignOnly;
    final publicTier = isPublicUnclaimed(data);
    final isSponsored = data['is_sponsored'] == true;
    final promoTitle = (data['promo_title'] ?? '').toString().trim();
    final rawBookingUrl = (data['direct_booking_url'] ?? data['naver_map_url'] ?? '').toString();
    final channelName = bookingChannelName(rawBookingUrl);
    final ctaText = publicTier
        ? (lang == AppLang.ko ? '네이버 정보·지도' : 'Map & Reviews')
        : (channelName == '네이버 예약' ? '네이버 예약 직거래' : '수수료 0원 직거래');

    final capMax = data['capacity_max'];
    final blogTotal = (data['naver_blog_total'] as num?)?.toInt() ?? 0;
    final specs = data['room_specs'] is Map ? Map<String, dynamic>.from(data['room_specs'] as Map) : const {};
    final rating = extractListingRating(data);
    final specBadge = [
      if (capMax != null) '최대 $capMax명',
      if (specs['bedrooms'] != null) '침실 ${specs['bedrooms']}',
      if (capMax == null && blogTotal > 0) '블로그 $blogTotal건',
    ].join(' · ');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isSponsored ? const Color(0xFFFFCCD5) : const Color(0xFFEBEBEB), width: isSponsored ? 1.4 : 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ListingDetailPage(
            listingId: docId,
            homeBuilder: (_) => HomePage(initialDemoMode: demoMode),
          ),
        )),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            SizedBox(
              height: 192,
              width: double.infinity,
              child: StorageImage(
                path: thumbPath,
                url: thumbUrl,
                cacheWidth: 560,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      publicTier ? Icons.assured_workload_rounded : Icons.verified_rounded,
                      size: 14,
                      color: const Color(0xFF198754),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      publicTier ? '${data['license_type']} 영업확인' : '${data['license_type']} 신고 확인',
                      style: const TextStyle(color: Color(0xFF222222), fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            if (promoTitle.isNotEmpty || isSponsored)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    promoTitle.isNotEmpty ? '🎁 이벤트' : '⚡ 공식 직거래',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (isForeignOnly)
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                  child: const Text('외국인 전용 숙소', style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
          ]),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${data['region_depth1']} ${data['region_depth2']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (rating.count > 0) ...[
                      const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 2),
                      Text(
                        '${rating.average.toStringAsFixed(1)} (${rating.count})',
                        style: const TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ] else if (specBadge.isNotEmpty)
                      Text(specBadge, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  localizedListingTitle(data, lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 5),
                if (points.isNotEmpty)
                  Text(
                    '· ${points.first}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                if (topAm.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    topAm.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF6C757D)),
                  ),
                ],
                const Spacer(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shortPrice(
                            data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : null,
                            period: period,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF222222)),
                        ),
                        const Text('중개수수료 0원', style: TextStyle(fontSize: 11, color: kBrand, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrand,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => goDirectBooking(context, docId, data),
                    child: Text(ctaText, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
