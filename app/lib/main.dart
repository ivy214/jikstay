// 직스테이 로컬 (하루 한 편 지자체 가이드북 스토리 + 로컬 동선 연결 매거진 플랫폼)
// - 첫 화면: 지도 없이 가볍고 몰입감 있는 '오늘의 계절·테마 로컬 스토리' 히어로 + 계절 스토리 모음 + 연동 로컬 피드
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
import 'local_calendar_view.dart';
import 'naver_map_view.dart';
import 'spot_detail_sheet.dart';
import 'story_detail_page.dart';
import 'translation_store.dart';
import 'travel_hub.dart';
import 'web_utils.dart';

enum HomeViewMode { feed, calendar, map }

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

  final TextEditingController _searchCtrl = TextEditingController();

  DiscoveryCategory _category = DiscoveryCategory.all;
  HomeViewMode _viewMode = HomeViewMode.feed;
  String _selectedProvince = '전체';
  String _query = '';
  bool _showBenefitsHub = false;
  bool _showProvincePicker = false;
  bool _offlineSeedMode = false;

  // 첫 프레임부터 빈 스피너 없이 오늘의 로컬 스토리와 기본 큐레이션을 즉시 렌더링
  List<DiscoveryItem> _allItems = kBuiltInSeedDiscoveryItems;
  List<DailyStoryItem> _dailyStories = kFallbackDailyMunicipalStories;
  List<TraditionalMarketInfo> _markets = kFallbackTraditional5DayMarkets;
  String? _selectedItemId;
  int _feedVisibleCount = _feedPageSize;
  bool _initialDeepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    onAppLangSelected = (next) => TranslationStore.ensureLoaded(next);
    if (appLangNotifier.value != AppLang.ko) {
      TranslationStore.ensureLoaded(appLangNotifier.value);
    }
    if (widget.seedItemsOverride != null) {
      _allItems = widget.seedItemsOverride!;
      _offlineSeedMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialPortalDeepLink());
    } else {
      _loadUnifiedDiscovery();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUnifiedDiscovery() async {
    final itemsById = <String, DiscoveryItem>{};

    // 1단계 (초고속 즉시 반영): preload 된 가벼운 스토리·축제·E-book 허브 JSON 먼저 파싱·렌더링
    final parsedStories = <DailyStoryItem>[];
    final parsedMarkets = <TraditionalMarketInfo>[];
    final hubJson = await fetchWebJson('data/public_travel_hub.json');
    if (hubJson != null) {
      for (final raw in (hubJson['traditional_markets'] as List? ?? const [])) {
        if (raw is Map) {
          final mkt = parseTraditionalMarketJson(Map<String, dynamic>.from(raw));
          if (mkt != null) parsedMarkets.add(mkt);
        }
      }
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
              galleryImages: disc.galleryImages,
              subtitle: disc.subtitle,
              pullQuote: disc.pullQuote,
              paragraphs: disc.paragraphs,
              practicalHeader: disc.practicalHeader,
              practicalInfo: disc.practicalInfo,
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

    if (!mounted) return;
    if (itemsById.isNotEmpty || parsedStories.isNotEmpty || parsedMarkets.isNotEmpty) {
      setState(() {
        if (itemsById.isNotEmpty) _allItems = itemsById.values.toList();
        if (parsedStories.isNotEmpty) _dailyStories = parsedStories;
        if (parsedMarkets.isNotEmpty) _markets = parsedMarkets;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialPortalDeepLink());

    // 프레임 양보 후 2단계 (백그라운드 비차단 로드): 전국 합법 안심숙소 경량 색인 병합
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

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

    // 오프라인/데모 폴백
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

    if (!mounted) return;
    setState(() {
      _allItems = itemsById.values.toList();
    });

    // 3단계 (백그라운드 병렬 오버레이): 평점 보유 항목만 비차단 병렬 조회
    if (!widget.initialDemoMode && !_offlineSeedMode) {
      try {
        final results = await Future.wait([
          FirebaseFirestore.instance
              .collection('listings')
              .where('status', isEqualTo: 'active')
              .where('review_count', isGreaterThan: 0)
              .limit(120)
              .get(),
          FirebaseFirestore.instance
              .collection('spots')
              .where('status', isEqualTo: 'active')
              .where('review_count', isGreaterThan: 0)
              .limit(120)
              .get(),
        ]).timeout(const Duration(seconds: 3));

        bool updated = false;
        for (final doc in results[0].docs) {
          final prev = itemsById[doc.id];
          if (prev != null) {
            final d = doc.data();
            itemsById[doc.id] = prev.copyWithStats(
              reviewCount: (d['review_count'] as num?)?.toInt(),
              scoreSum: (d['score_sum'] as num?)?.toInt(),
              outboundClicks: (d['outbound_clicks'] as num?)?.toInt(),
            );
            updated = true;
          }
        }
        for (final doc in results[1].docs) {
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
            updated = true;
          }
        }
        if (updated && mounted) {
          setState(() => _allItems = itemsById.values.toList());
        }
      } catch (_) {}
    }
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

  List<DiscoveryItem> _filteredItems() {
    final q = _query.trim().toLowerCase();
    final out = _allItems.where((it) {
      if (_category != DiscoveryCategory.all && it.category != _category) return false;
      if (_selectedProvince != '전체' && it.province != _selectedProvince) return false;
      if (q.isEmpty) return true;
      final hay = '${it.title} ${it.province} ${it.regionLabel} ${it.address} ${it.subtitle} ${it.couponTitle}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();

    out.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return out;
  }

  void _selectProvince(String provKey) {
    setState(() {
      _selectedProvince = provKey;
      _showProvincePicker = false;
      _selectedItemId = null;
      _feedVisibleCount = _feedPageSize;
    });
    syncPortalParams(region: provKey, spotId: null);
    trackPortalEvent('select_province', {'province': provKey});
  }

  void _openItemSheet(DiscoveryItem item) {
    setState(() => _selectedItemId = item.id);

    // 1) 일일 공식 가이드북 스토리 항목이면 매거진 스토리 상세 페이지로 직행
    for (final st in _dailyStories) {
      if (st.id == item.id) {
        _openStoryDetail(st);
        return;
      }
    }

    // 2) 합법 인증 숙소 항목이면 숙소 전체 상세 페이지로 직행
    if (item.category == DiscoveryCategory.stay) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ListingDetailPage(
          listingId: item.id,
          homeBuilder: (_) => HomePage(initialDemoMode: widget.initialDemoMode),
        ),
      ));
      return;
    }

    // 3) 축제·식당·볼거리·E-book 모두 팝업 없이 StoryDetailPage와 동일한 매거진 전체 페이지로 전환
    syncPortalParams(region: _selectedProvince, spotId: item.id);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SpotDetailSheet(
        item: item,
        allItems: _allItems,
        lang: appLangNotifier.value,
        offlineMode: _offlineSeedMode || widget.initialDemoMode,
        homeBuilder: (_) => HomePage(initialDemoMode: widget.initialDemoMode),
        onSelectConnectedItem: (next) {
          if (mounted) {
            setState(() => _selectedItemId = next.id);
          }
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
          if (!mounted) return;
          setState(() {
            _allItems = _allItems
                .map((e) => e.id == itemId ? e.copyWithStats(reviewCount: rCount, scoreSum: sSum) : e)
                .toList();
          });
        },
      ),
    ));
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildViewModePill({
    required Key key,
    required HomeViewMode mode,
    required String label,
    required Color activeColor,
  }) {
    final sel = _viewMode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          setState(() => _viewMode = mode);
          trackPortalEvent('switch_view_mode', {
            'mode': mode.name,
            'province': _selectedProvince,
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: sel ? activeColor : const Color(0xFFCBD5E1),
              width: sel ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: sel ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appLangNotifier, translationRevisionNotifier]),
      builder: (context, _) {
        final lang = appLangNotifier.value;
        final screenW = MediaQuery.sizeOf(context).width;
        final feedItems = _filteredItems();

        final todayStory = pickTodayMunicipalStory(
          stories: _dailyStories,
          allItems: _allItems,
          selectedProvince: _selectedProvince,
        );
        final moreStories = (_query.trim().isEmpty && _category == DiscoveryCategory.all)
            ? _dailyStories.where((s) => s.id != todayStory.id).take(4).toList()
            : const <DailyStoryItem>[];

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAF9),
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
                      _viewMode = HomeViewMode.feed;
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
                        _showBenefitsHub
                            ? pickLangText(
                                lang,
                                ko: '📖 로컬 스토리로',
                                en: '📖 Local Stories',
                                ja: '📖 ローカルストーリーへ',
                                zh: '📖 回到在地故事',
                              )
                            : pickLangText(
                                lang,
                                ko: '🎁 반값여행·E-book관',
                                en: '🎁 50% Pass & PDFs',
                                ja: '🎁 半額支援・PDFガイド',
                                zh: '🎁 半價補助・官方指南',
                              ),
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
                          // 단일 깔끔한 탐색 바: [📍 지역 선택] + [카테고리 칩] + [보기 전환: 스토리 / 캘린더 / 네이버 지도]
                          Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
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
                                      if (screenW < 1040) ...[
                                        _buildViewModePill(
                                          key: const Key('view_mode_feed'),
                                          mode: HomeViewMode.feed,
                                          label: trUi('view_story_feed', lang),
                                          activeColor: const Color(0xFF0F172A),
                                        ),
                                        _buildViewModePill(
                                          key: const Key('view_mode_calendar'),
                                          mode: HomeViewMode.calendar,
                                          label: trUi('view_calendar', lang),
                                          activeColor: const Color(0xFF7C3AED),
                                        ),
                                        _buildViewModePill(
                                          key: const Key('view_mode_map'),
                                          mode: HomeViewMode.map,
                                          label: trUi('view_naver_map', lang),
                                          activeColor: const Color(0xFF03C75A),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 18,
                                          margin: const EdgeInsets.only(right: 8, left: 2),
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ],
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
                                              if (_viewMode == HomeViewMode.calendar &&
                                                  cat != DiscoveryCategory.all &&
                                                  cat != DiscoveryCategory.event) {
                                                _viewMode = HomeViewMode.feed;
                                              }
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
                              ),
                              if (screenW >= 1040) ...[
                                Container(
                                  width: 1,
                                  height: 20,
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  color: const Color(0xFFE2E8F0),
                                ),
                                _buildViewModePill(
                                  key: const Key('view_mode_feed'),
                                  mode: HomeViewMode.feed,
                                  label: trUi('view_story_feed', lang),
                                  activeColor: const Color(0xFF0F172A),
                                ),
                                _buildViewModePill(
                                  key: const Key('view_mode_calendar'),
                                  mode: HomeViewMode.calendar,
                                  label: trUi('view_calendar', lang),
                                  activeColor: const Color(0xFF7C3AED),
                                ),
                                _buildViewModePill(
                                  key: const Key('view_mode_map'),
                                  mode: HomeViewMode.map,
                                  label: trUi('view_naver_map', lang),
                                  activeColor: const Color(0xFF03C75A),
                                ),
                              ],
                            ],
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
              : Column(
                      children: [
                        if (screenW < 560)
                          Container(
                            color: Colors.white,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: SizedBox(
                              height: 36,
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() {
                                  _query = v;
                                  _feedVisibleCount = _feedPageSize;
                                }),
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
                          child: switch (_viewMode) {
                            HomeViewMode.calendar => LocalCalendarView(
                                allItems: _allItems,
                                markets: _markets,
                                selectedProvince: _selectedProvince,
                                query: _query,
                                lang: lang,
                                onSelectItem: _openItemSheet,
                                onOpenExternalUrl: _openExternalUrl,
                              ),
                            HomeViewMode.map => NaverLocalMapView(
                                items: feedItems,
                                selectedProvince: _selectedProvince,
                                selectedCategory: _category,
                                query: _query,
                                lang: lang,
                                offlineMode: _offlineSeedMode || widget.initialDemoMode,
                                onOpenDetailPage: _openItemSheet,
                                onOpenExternalUrl: _openExternalUrl,
                              ),
                            HomeViewMode.feed => _LiveLocalFeedPanel(
                                lang: lang,
                                selectedProvince: _selectedProvince,
                                todayStory: todayStory,
                                moreStories: moreStories,
                                onOpenTodayStory: () => _openStoryDetail(todayStory),
                                onOpenStory: _openStoryDetail,
                                feedItems: feedItems,
                                totalAreaCount: feedItems.length,
                                visibleLimit: _feedVisibleCount,
                                selectedItemId: _selectedItemId,
                                onTapItem: _openItemSheet,
                                onOpenEbookDirect: _openExternalUrl,
                                onLoadMore: () => setState(() => _feedVisibleCount += _feedPageSize),
                              ),
                          },
                        ),
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
  final List<DailyStoryItem> moreStories;
  final VoidCallback onOpenTodayStory;
  final ValueChanged<DailyStoryItem> onOpenStory;
  final List<DiscoveryItem> feedItems;
  final int totalAreaCount;
  final int visibleLimit;
  final String? selectedItemId;
  final ValueChanged<DiscoveryItem> onTapItem;
  final ValueChanged<String> onOpenEbookDirect;
  final VoidCallback onLoadMore;

  const _LiveLocalFeedPanel({
    required this.lang,
    required this.selectedProvince,
    required this.todayStory,
    required this.moreStories,
    required this.onOpenTodayStory,
    required this.onOpenStory,
    required this.feedItems,
    required this.totalAreaCount,
    required this.visibleLimit,
    required this.selectedItemId,
    required this.onTapItem,
    required this.onOpenEbookDirect,
    required this.onLoadMore,
  });

  Widget _centered(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final twoCol = screenW >= 840;
    final shownCount = math.min(feedItems.length, visibleLimit);
    final hasMore = feedItems.length > shownCount;
    final rowCount = twoCol ? ((shownCount + 1) ~/ 2) : shownCount;

    return CustomScrollView(
      key: const Key('live_feed_scroll'),
      slivers: [
        // 1. 하루 단 한 편 — 지자체 공식 가이드북·행사 기반 '오늘의 로컬 스토리' 히어로 배너
        SliverToBoxAdapter(
          child: _centered(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: _DailyStoryHeroCard(
                story: todayStory,
                lang: lang,
                onTap: onOpenTodayStory,
              ),
            ),
          ),
        ),

        // 2. 계절·테마별 지자체 공식 가이드북 스토리 셀프 (선택 과부하 없이 이야기로 탐색)
        if (moreStories.isNotEmpty)
          SliverToBoxAdapter(
            child: _centered(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trUi('more_stories_title', lang),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: moreStories.map((st) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => onOpenStory(st),
                              child: Container(
                                width: 236,
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${st.tRegionLabel(lang)} · ${st.tSeasonBadge(lang)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      st.tTitle(lang),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      st.tSourceBook(lang),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 3. 실시간 피드 헤더 카운트
        SliverToBoxAdapter(
          child: _centered(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${trUi('live_feed_title', lang)} (${selectedProvince == '전체' ? trUi('all_korea_curated', lang) : trProvince(selectedProvince, lang)})',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    pickLangText(
                      lang,
                      ko: '$totalAreaCount곳 연결됨',
                      en: '$totalAreaCount places',
                      ja: '$totalAreaCount件掲載',
                      zh: '共 $totalAreaCount 處',
                    ),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 4. 실시간 로컬 피드 카드 스트림 (데스크톱 2열 매거진 그리드 / 모바일 1열)
        if (feedItems.isEmpty)
          SliverToBoxAdapter(
            child: _centered(
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    pickLangText(
                      lang,
                      ko: '선택한 조건에 일치하는 장소가 없습니다.\n검색어를 지우거나 다른 지역·테마를 선택해 보세요.',
                      en: 'No matching places found. Clear your search or try another province.',
                      ja: '条件に一致するスポットが見つかりませんでした。検索条件を変更してみてください。',
                      zh: '找不到符合條件的地點，請清除搜尋關鍵字或切換其他地區與主題。',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B), height: 1.5),
                  ),
                ),
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: rowCount,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, rowIdx) {
              if (!twoCol) {
                final it = feedItems[rowIdx];
                return _centered(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _LiveFeedItemCard(
                      key: ValueKey('feed_card_${it.id}'),
                      item: it,
                      lang: lang,
                      isSelected: it.id == selectedItemId,
                      onTap: () => onTapItem(it),
                      onOpenEbookDirect: onOpenEbookDirect,
                    ),
                  ),
                );
              }
              final leftIdx = rowIdx * 2;
              final rightIdx = leftIdx + 1;
              final leftItem = feedItems[leftIdx];
              final rightItem = rightIdx < shownCount ? feedItems[rightIdx] : null;
              return _centered(
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _LiveFeedItemCard(
                          key: ValueKey('feed_card_${leftItem.id}'),
                          item: leftItem,
                          lang: lang,
                          isSelected: leftItem.id == selectedItemId,
                          onTap: () => onTapItem(leftItem),
                          onOpenEbookDirect: onOpenEbookDirect,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: rightItem != null
                            ? _LiveFeedItemCard(
                                key: ValueKey('feed_card_${rightItem.id}'),
                                item: rightItem,
                                lang: lang,
                                isSelected: rightItem.id == selectedItemId,
                                onTap: () => onTapItem(rightItem),
                                onOpenEbookDirect: onOpenEbookDirect,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        if (hasMore)
          SliverToBoxAdapter(
            child: _centered(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(
                      pickLangText(
                        lang,
                        ko: '더 보기 ($shownCount / ${feedItems.length})',
                        en: 'Load More ($shownCount / ${feedItems.length})',
                        ja: 'もっと見る ($shownCount / ${feedItems.length})',
                        zh: '載入更多 ($shownCount / ${feedItems.length})',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        SliverToBoxAdapter(child: _centered(const LegalFooter())),
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

  Widget _buildImagePanel({required double height, required BorderRadius borderRadius, required String dateTag}) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StorageImage(url: story.heroImage, cacheWidth: 960),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.26),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF065F46).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      lang == AppLang.ko ? '📖 $dateTag' : trUi('today_local_story', lang),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      story.tSeasonBadge(lang),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: Text(
                '${story.tRegionLabel(lang)} · ${story.tSourceBook(lang)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextPanel({required bool isWide, required String dateTag}) {
    final pq = story.tPullQuote(lang);
    final ps = story.tParagraphs(lang);
    final sub = story.tSubtitle(lang);
    final summaryText = pq.isNotEmpty ? pq : (ps.isNotEmpty ? ps.first : sub);

    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, isWide ? 22 : 14, isWide ? 24 : 16, isWide ? 22 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (story.heroImage.isEmpty || isWide) ...[
            Text(
              isWide
                  ? '${story.tRegionLabel(lang)} · ${story.tSourceBook(lang)}'
                  : '${lang == AppLang.ko ? '📖 $dateTag' : trUi('today_local_story', lang)} · ${story.tSeasonBadge(lang)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            story.tTitle(lang),
            style: TextStyle(
              fontSize: isWide ? 23 : 19,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
              height: 1.3,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summaryText,
            maxLines: isWide ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isWide ? 14.5 : 13.5,
              color: const Color(0xFF334155),
              height: 1.62,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  lang == AppLang.ko ? '📍 ${story.subtitle}' : '📍 ${story.tAddress(lang)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF065F46),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      trUi('read_story_btn', lang),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateTag = '${now.month}월 ${now.day}일 오늘의 로컬 스토리';
    final isWide = MediaQuery.sizeOf(context).width >= 760 && story.heroImage.isNotEmpty;

    return Container(
      key: const Key('daily_story_banner'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0x0D0F172A), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: InkWell(
        key: const Key('open_daily_story_btn'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: isWide
            ? Row(
                children: [
                  Expanded(
                    flex: 53,
                    child: _buildImagePanel(
                      height: 270,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(18.5)),
                      dateTag: dateTag,
                    ),
                  ),
                  Expanded(
                    flex: 47,
                    child: _buildTextPanel(isWide: true, dateTag: dateTag),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (story.heroImage.isNotEmpty)
                    _buildImagePanel(
                      height: 190,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18.5)),
                      dateTag: dateTag,
                    ),
                  _buildTextPanel(isWide: false, dateTag: dateTag),
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
                          '${item.categoryEmoji} ${trProvince(item.province, lang)} · ${item.categoryBadgeText(lang)}',
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
                          child: Text(
                            pickLangText(
                              lang,
                              ko: '🎁 방문혜택 쿠폰',
                              en: '🎁 Visit Perk',
                              ja: '🎁 来店特典',
                              zh: '🎁 造訪優惠',
                            ),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
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
                    item.tTitle(lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.couponTitle.isNotEmpty
                        ? item.tCouponTitle(lang)
                        : (item.tSubtitle(lang).isNotEmpty ? item.tSubtitle(lang) : item.tAddress(lang)),
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
                          trUi('connected_nearby_hint', lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                        ),
                      ),
                      if (item.category == DiscoveryCategory.ebook && item.externalUrl.isNotEmpty)
                        InkWell(
                          onTap: () => onOpenEbookDirect(item.externalUrl),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              pickLangText(
                                lang,
                                ko: '즉시 열람 ↗',
                                en: 'Open PDF ↗',
                                ja: '今すぐ開く ↗',
                                zh: '立即開啟 ↗',
                              ),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
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
