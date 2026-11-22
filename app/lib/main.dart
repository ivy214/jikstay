// 직스테이 로컬 (하루 한 편 지자체 가이드북 스토리 + 로컬 동선 연결 매거진 플랫폼)
// - 첫 화면: 지도 없이 가볍고 몰입감 있는 '오늘의 계절·테마 로컬 스토리' 히어로 + 계절 스토리 모음 + 연동 로컬 피드
// - 배너 클릭 시: 지자체 공식 책자(PDF) 원문·사진·필수 탐방정보 박스를 담은 매거진형 스토리 상세 페이지 이동
// - ?id=stay_xxx / ?story=spot_story_xxx / ?spot=... / ?region=... 딥링크 호환
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'amenities.dart';
import 'demo_data.dart';
import 'detail_page.dart';
import 'discovery_models.dart';
import 'event_banner.dart';
import 'firebase_boot.dart';
import 'hub_details.dart';
import 'i18n.dart';
import 'legal.dart';
import 'local_calendar_view.dart';
import 'naver_map_view.dart';
import 'search_query.dart';
import 'spot_detail_sheet.dart';
import 'story_detail_page.dart';
import 'translation_store.dart';
import 'travel_hub.dart';
import 'trip_planner.dart';
import 'ux_widgets.dart';
import 'web_utils.dart';

part 'home/feed_panel.dart';
part 'home/story_hero_card.dart';
part 'home/feed_cards.dart';

enum HomeViewMode { feed, calendar, map }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Noto Color Emoji'], await rootBundle.loadString('assets/fonts/OFL-NotoColorEmoji.txt'));
    yield LicenseEntryWithLineBreaks(['Noto Sans KR'], await rootBundle.loadString('assets/fonts/OFL-NotoSansKR.txt'));
  });
  // 첫 화면은 정적 JSON만 쓰므로 Firebase(SDK·reCAPTCHA 다운로드)를 기다리지 않고 바로 그린다.
  unawaited(firebaseReady().catchError((Object e) => debugPrint('Firebase 초기화 실패: $e')));
  appLangNotifier.value = resolveStartLang(
    urlLang: Uri.base.queryParameters['lang'],
    storedLang: storeGet(kLangStoreKey),
    browserLangs: browserLanguages(),
  );
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

    final linkedId = params['id'];
    final initialRegion = params['region'];
    final initialSpotId = params['spot'];
    final initialStoryId = params['story'];
    final initialPlanParam = params['plan'];
    final initialTopic = params['topic'];
    final demoMode = params['demo'] == '1' || params['demo'] == 'true';

    Widget homeBuilder(BuildContext _) => HomePage(initialDemoMode: demoMode);

    return MaterialApp(
      title: '직스테이 로컬 · 오늘 떠나고 싶은 한국의 로컬 스토리',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [homeUrlSyncObserver],
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F172A),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        // 내장 한글·이모지 서브셋을 먼저 쓰게 해 gstatic 폰트 조각 다운로드를 없앤다.
        // 라틴 문자는 기본 Roboto 그대로, 한글은 AppKR, 이모지는 AppEmoji (AppKR 에는 이모지 글자를 넣지 않는다)
        fontFamilyFallback: const ['AppKR', 'AppEmoji'],
      ),
      home: (linkedId != null && RegExp(r'^stay_[a-zA-Z0-9_-]{4,32}$').hasMatch(linkedId))
          ? ListingDetailPage(listingId: linkedId, homeBuilder: homeBuilder)
          : HomePage(
              initialDemoMode: demoMode,
              initialRegion: initialRegion,
              initialSpotId: initialSpotId,
              initialStoryId: initialStoryId,
              initialPlanParam: initialPlanParam,
              initialTopic: initialTopic,
            ),
    );
  }
}

/// 상세 화면을 닫고 홈으로 돌아오면 주소창의 ?spot= ?story= ?id= ?plan= ?topic= 를 지운다.
/// (브라우저 뒤로가기·앱 안 뒤로가기 모두. 남겨 두면 새로고침·주소 공유 때 닫은 상세가 다시 열린다)
class HomeUrlSyncObserver extends NavigatorObserver {
  /// 홈 화면이 지금 지역으로 주소를 다시 맞추는 함수 (HomePage 가 등록)
  static VoidCallback? onReturnHome;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && previousRoute.isFirst) onReturnHome?.call();
  }
}

final homeUrlSyncObserver = HomeUrlSyncObserver();

class HomePage extends StatefulWidget {
  final bool initialDemoMode;
  final List<DiscoveryItem>? seedItemsOverride;
  final String? initialRegion;
  final String? initialSpotId;
  final String? initialStoryId;
  final String? initialPlanParam;

  /// 검색 유입용 주제 페이지(?topic=festival|market) → 축제·장날 달력 화면으로 연다
  final String? initialTopic;

  const HomePage({
    super.key,
    this.initialDemoMode = false,
    this.seedItemsOverride,
    this.initialRegion,
    this.initialSpotId,
    this.initialStoryId,
    this.initialPlanParam,
    this.initialTopic,
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
  // 진행 중인 이벤트가 여럿이면 홈 화면을 열 때 하나를 무작위로 골라 상단 배너로 노출
  final PromoEvent? _bannerEvent = pickPromoEvent(DateTime.now());
  bool _showProvincePicker = false;
  // 빠른 필터: 내 주변(거리순) · 이번 주말 축제 · 찜한 곳만
  (double, double)? _userPos;
  bool _locating = false;
  bool _weekendOnly = false;
  bool _savedOnly = false;
  bool _offlineSeedMode = false;

  // 첫 프레임부터 빈 스피너 없이 오늘의 로컬 스토리와 기본 큐레이션을 즉시 렌더링
  List<DiscoveryItem> _allItems = kBuiltInSeedDiscoveryItems;
  List<DailyStoryItem> _dailyStories = kFallbackDailyMunicipalStories;
  List<TraditionalMarketInfo> _markets = kFallbackTraditional5DayMarkets;
  bool _marketDeepLinkHandled = false;
  String? _selectedItemId;
  int _feedVisibleCount = _feedPageSize;
  bool _initialDeepLinkHandled = false;

  @override
  void initState() {
    super.initState();
    SavedPlaces.ids.addListener(_onSavedChanged);
    HomeUrlSyncObserver.onReturnHome = _resetHomeUrl;
    onAppLangSelected = (next) {
      storeSet(kLangStoreKey, next.code); // 직접 고른 언어는 다음 방문에도 유지
      TranslationStore.ensureLoaded(next);
    };
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
    SavedPlaces.ids.removeListener(_onSavedChanged);
    _searchTrackTimer?.cancel();
    if (HomeUrlSyncObserver.onReturnHome == _resetHomeUrl) HomeUrlSyncObserver.onReturnHome = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUnifiedDiscovery() async {
    final itemsById = <String, DiscoveryItem>{};

    // 1단계 (초고속 즉시 반영): preload 된 가벼운 스토리·축제·E-book 허브 JSON 먼저 파싱·렌더링
    final parsedStories = <DailyStoryItem>[];
    final parsedMarkets = <TraditionalMarketInfo>[];
    final hubJson = await fetchHubCore();
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
        if (raw is Map && !isEndedEventJson(raw)) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.event);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
      for (final raw in (hubJson['spots'] as List? ?? const [])) {
        if (raw is Map && !isEndedEventJson(raw)) {
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

    // 프레임 양보 후 2단계 (백그라운드 비차단 로드): 전국 합법 숙소 경량 색인 병합
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    // 전국 전통시장·5일장 (약 800곳, 첫 화면에는 필요 없어 따로 받는다)
    final marketsJson = await fetchWebJson('data/hub/markets.json');
    if (marketsJson != null && marketsJson['markets'] is List) {
      for (final raw in (marketsJson['markets'] as List)) {
        if (raw is Map) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.market);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
      if (mounted) {
        setState(() => _allItems = itemsById.values.toList());
        _openPendingMarketDeepLink();
      }
    }

    // 공연·전시 (한국문화정보원, 약 900건). 끝난 것은 종료일로 바로 뺀다.
    final cultureJson = await fetchWebJson('data/hub/culture.json');
    if (cultureJson != null && cultureJson['culture'] is List) {
      for (final raw in (cultureJson['culture'] as List)) {
        if (raw is Map && !isEndedEventJson(raw)) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.culture);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
      if (mounted) {
        setState(() => _allItems = itemsById.values.toList());
        _openPendingMarketDeepLink();
      }
    }
    _noticeEndedDeepLink();

    // 캠핑장(고캠핑)·자연휴양림 (약 2,400곳). 기본 피드에는 넣지 않고 '자연·액티비티'·검색·지도에서만 보인다.
    final campingJson = await fetchWebJson('data/hub/camping.json');
    if (campingJson != null && campingJson['camping'] is List) {
      for (final raw in (campingJson['camping'] as List)) {
        if (raw is Map) {
          final parsed = parseSpotJson(Map<String, dynamic>.from(raw), fallbackCategory: DiscoveryCategory.outdoor);
          if (parsed != null) itemsById[parsed.id] = parsed;
        }
      }
      if (mounted) {
        setState(() => _allItems = itemsById.values.toList());
        _openPendingMarketDeepLink();
      }
    }

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
        await firebaseReady().timeout(const Duration(seconds: 10));
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

  void _openTripPlanner({TripPlan? initialPlan}) {
    showDialog<void>(
      context: context,
      builder: (_) => TripPlannerDialog(
        allItems: _allItems,
        initialProvince: _selectedProvince,
        initialPlan: initialPlan,
        onOpenItem: _openItemSheet,
      ),
    );
  }

  Widget _buildTripPlannerPill(AppLang lang) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: const Key('trip_planner_btn'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openTripPlanner(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF0F766E),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.route_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                pickLangText(
                  lang,
                  ko: '여행코스',
                  en: 'Trip Planner',
                  ja: '旅行プラン',
                  zh: '行程规划',
                ),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyInitialPortalDeepLink() {
    if (_initialDeepLinkHandled || !mounted) return;
    _initialDeepLinkHandled = true;

    final initReg = (widget.initialRegion ?? '').trim();
    if (initReg.isNotEmpty && kProvinceJumpList.any((p) => p.key == initReg)) {
      _selectProvince(initReg);
    }

    final initTopic = (widget.initialTopic ?? '').trim();
    if (initTopic == 'festival' || initTopic == 'market') {
      setState(() => _viewMode = HomeViewMode.calendar);
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

    final initPlan = (widget.initialPlanParam ?? '').trim();
    if (initPlan.isNotEmpty) {
      final decoded = decodeTripPlanParam(initPlan, _allItems);
      if (decoded != null) {
        _openTripPlanner(initialPlan: decoded);
        return;
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

  /// 시장·공연·전시·캠핑장 상세 링크(?spot=spot_mk_… / spot_cu_… / spot_cp_… / spot_fr_…)는 2단계에서 목록을 받은 뒤에야 열 수 있다.
  void _openPendingMarketDeepLink() {
    final id = (widget.initialSpotId ?? '').trim();
    if (!(id.startsWith('spot_mk_') || id.startsWith('spot_cu_') || DiscoveryItem.isCampingSectionId(id)) ||
        _marketDeepLinkHandled) {
      return;
    }
    for (final it in _allItems) {
      if (it.id == id) {
        _marketDeepLinkHandled = true;
        _openItemSheet(it);
        return;
      }
    }
  }

  /// 검색어 측정 (GA4 'search' + 결과 0건이면 'search_no_results'). 입력이 1.5초 멈추면 한 번만 보낸다.
  Timer? _searchTrackTimer;
  void _scheduleSearchTrack() {
    _searchTrackTimer?.cancel();
    _searchTrackTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      final term = _query.trim();
      if (term.length < 2) return;
      final results = _filteredItems().length;
      final params = {
        'search_term': term,
        'results': results,
        'province': _selectedProvince,
        'category': _category.name,
      };
      trackPortalEvent('search', params);
      if (results == 0) trackPortalEvent('search_no_results', params);
    });
  }

  void _resetHomeUrl() {
    if (!mounted) return;
    resetHomeUrl(region: _selectedProvince);
  }

  /// 끝난 축제·공연·전시 링크로 들어온 경우 (목록에서 이미 빠짐) 안내만 띄운다.
  void _noticeEndedDeepLink() {
    final id = (widget.initialSpotId ?? '').trim();
    if (!mounted || id.isEmpty || !(id.startsWith('spot_ev_') || id.startsWith('spot_cu_'))) return;
    if (_allItems.any((it) => it.id == id)) return;
    final lang = appLangNotifier.value;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(pickLangText(lang,
          ko: '이미 끝난 축제·공연·전시입니다. 지금 열리는 일정을 확인해 보세요.',
          en: 'This event has ended. Check what is on now.',
          ja: 'このイベントは終了しました。開催中の日程をご覧ください。',
          zh: '此活動已結束，看看正在舉行的活動吧。')),
    ));
    trackPortalEvent('open_ended_link', {'item_id': id});
  }

  void _onSavedChanged() {
    if (mounted) setState(() {});
  }

  /// [includeMarkets]: 지도는 겹치는 핀을 숨기고 화면당 핀 수가 정해져 있어 전통시장을 항상 함께 보여 준다.
  List<DiscoveryItem> _filteredItems({bool includeMarkets = false}) {
    // "전북 남원" "남원여행" "남원 숙소" 처럼 입력해도 낱말·시도·분류로 나눠 찾는다 (search_query.dart)
    final q = parseSearchQuery(_query);
    final saved = SavedPlaces.ids.value.toSet();
    final weekend = upcomingWeekend(DateTime.now());
    final relevance = <String, int>{};
    // 전통시장·5일장은 기본 피드에는 넣지 않고 검색할 때만 결과에 포함 ("강진" → 강진오일시장)
    final pool = q.isEmpty
        ? (includeMarkets
            ? _allItems
            : _allItems
                .where((it) =>
                    (!it.isMarket || _category == DiscoveryCategory.market) &&
                    (it.category != DiscoveryCategory.culture || _category == DiscoveryCategory.culture) &&
                    (!it.isCampingSection || _category == DiscoveryCategory.outdoor))
                .toList())
        : [..._allItems, ..._markets.where((m) => !_allItems.any((it) => it.id == m.id)).map(marketToDiscoveryItem)];
    bool keep(DiscoveryItem it) {
      if (_savedOnly && !saved.contains(it.id)) return false;
      if (_weekendOnly && !isOpenDuring(it, weekend.$1, weekend.$2)) return false;
      if (_category != DiscoveryCategory.all && it.category != _category) return false;
      if (_selectedProvince != '전체' && it.province != _selectedProvince) return false;
      if (q.isEmpty) return true;
      final score = searchRelevance(it, q);
      if (score == null) return false;
      relevance[it.id] = score;
      return true;
    }

    final out = pool.where(keep).toList();
    // 기본 피드(검색·분류 선택 없음)에는 이번 주 공연·전시를 5칸마다 1개씩 끼운다 (지역·찜·주말 필터는 똑같이 적용)
    final culture = (q.isEmpty && !includeMarkets && _category == DiscoveryCategory.all)
        ? thisWeekCulture(_allItems.where(keep), DateTime.now())
        : <DiscoveryItem>[];

    final pos = _userPos;
    if (pos != null) {
      // 내 주변: 거리순 (근사 좌표 숙소는 실제 위치를 몰라 뒤로)
      double d(DiscoveryItem it) => haversineKm(pos.$1, pos.$2, it.lat, it.lng) + (it.hasApproxLocation ? 1000 : 0);
      out.sort((a, b) => d(a).compareTo(d(b)));
      culture.sort((a, b) => d(a).compareTo(d(b)));
    } else {
      // 검색 중이면 관련도(시·군 이름 일치 > 제목 > 그 밖) 먼저, 같으면 기존 우선순위
      out.sort((a, b) {
        final r = (relevance[b.id] ?? 0).compareTo(relevance[a.id] ?? 0);
        if (r != 0) return r;
        return b.priorityScore.compareTo(a.priorityScore);
      });
    }
    return interleaveEvery(out, culture);
  }

  Future<void> _toggleNearMe(AppLang lang) async {
    if (_userPos != null) {
      setState(() => _userPos = null);
      return;
    }
    setState(() => _locating = true);
    final pos = await currentPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _userPos = pos;
      _feedVisibleCount = _feedPageSize;
    });
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pickLangText(lang,
            ko: '위치를 확인할 수 없습니다. 브라우저의 위치 권한을 허용하거나 지역을 직접 선택해 주세요.',
            en: 'Could not get your location. Allow location access or pick a region.',
            ja: '現在地を取得できません。位置情報を許可するか地域を選んでください。',
            zh: '無法取得位置，請允許定位或直接選擇地區。')),
      ));
    } else {
      _selectProvince('전체');
      trackPortalEvent('sort_near_me', const {});
    }
  }

  Widget _quickFilterChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? color : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? color : const Color(0xFFCBD5E1)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
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

    // 2) 공공데이터 등록 숙소 항목이면 숙소 전체 상세 페이지로 직행
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

  /// 상단 이벤트 배너 → 이벤트 상세 (반값여행은 지원 지역·신청 방법·지역별 숙소 연결 화면)
  void _openPromoEvent(PromoEvent event) {
    trackPortalEvent('open_promo_event', {'event_id': event.id});
    switch (event.action) {
      case PromoEventAction.externalUrl:
        _openExternalUrl(event.externalUrl);
      case PromoEventAction.halfPriceTravel:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
            backgroundColor: const Color(0xFFF8FAF9),
            appBar: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              title: Text(
                event.titleFor(appLangNotifier.value),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            body: PublicTravelHubView(
              lang: appLangNotifier.value,
              onOpenSpot: (spot) {
                final known = _allItems.where((e) => e.id == spot.id);
                _openItemSheet(known.isNotEmpty ? known.first : spot);
              },
              onSelectCityForStays: (_, cityKeyword) {
                Navigator.of(ctx).pop();
                setState(() {
                  _viewMode = HomeViewMode.feed;
                  _category = DiscoveryCategory.all;
                  _searchCtrl.text = cityKeyword;
                  _query = cityKeyword;
                  _feedVisibleCount = _feedPageSize;
                });
              },
            ),
          ),
        ));
    }
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

        // 검색 중이면 오늘의 스토리도 검색한 지역(검색어의 시·도 또는 결과에 가장 많은 시·도)에 맞춘다
        final searchedProvince = _query.trim().isEmpty
            ? null
            : (parseSearchQuery(_query).province ?? dominantProvince(feedItems));
        final storyProvince = _selectedProvince != '전체' ? _selectedProvince : (searchedProvince ?? '전체');
        // 홈(전국·검색 없음)은 서버가 스플래시에 넣은 스토리를 그대로 쓴다 → 스플래시와 첫 화면이 같다
        final hint = storyProvince == '전체' ? todayStoryHint() : null;
        final todayStory = (hint == null ? null : storyFromServerHint(hint.$1, hint.$2, _dailyStories, _allItems)) ??
            pickTodayMunicipalStory(
              stories: _dailyStories,
              allItems: _allItems,
              selectedProvince: storyProvince,
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
                          onChanged: (v) {
                            setState(() {
                              _query = v;
                              _feedVisibleCount = _feedPageSize;
                            });
                            _scheduleSearchTrack();
                          },
                          decoration: InputDecoration(
                            hintText: trUi('search_hint', lang),
                            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    tooltip: pickLangText(lang, ko: '검색어 지우기', en: 'Clear', ja: 'クリア', zh: '清除'),
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
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: LangSelectorButton(),
              ),
            ],
            bottom: PreferredSize(
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
                                _quickFilterChip(
                                  key: const Key('near_me_chip'),
                                  label: _locating
                                      ? pickLangText(lang, ko: '📍 위치 확인 중…', en: '📍 Locating…', ja: '📍 取得中…', zh: '📍 定位中…')
                                      : pickLangText(lang, ko: '📍 내 주변', en: '📍 Near me', ja: '📍 現在地周辺', zh: '📍 我附近'),
                                  selected: _userPos != null,
                                  color: const Color(0xFF2563EB),
                                  onTap: () => _toggleNearMe(lang),
                                ),
                                _quickFilterChip(
                                  key: const Key('weekend_chip'),
                                  label: pickLangText(lang, ko: '🗓 이번 주말', en: '🗓 This weekend', ja: '🗓 今週末', zh: '🗓 本週末'),
                                  selected: _weekendOnly,
                                  color: const Color(0xFFEA580C),
                                  onTap: () => setState(() {
                                    _weekendOnly = !_weekendOnly;
                                    _feedVisibleCount = _feedPageSize;
                                  }),
                                ),
                                _quickFilterChip(
                                  key: const Key('saved_chip'),
                                  label: pickLangText(lang,
                                      ko: '❤️ 찜 ${SavedPlaces.ids.value.length}',
                                      en: '❤️ Saved ${SavedPlaces.ids.value.length}',
                                      ja: '❤️ 保存 ${SavedPlaces.ids.value.length}',
                                      zh: '❤️ 收藏 ${SavedPlaces.ids.value.length}'),
                                  selected: _savedOnly,
                                  color: const Color(0xFFE11D48),
                                  onTap: () => setState(() {
                                    _savedOnly = !_savedOnly;
                                    _feedVisibleCount = _feedPageSize;
                                  }),
                                ),
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
                                  _buildTripPlannerPill(lang),
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
                                            cat != DiscoveryCategory.event &&
                                            cat != DiscoveryCategory.market) {
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
                          _buildTripPlannerPill(lang),
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
                                      fontSize: 12,
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
          body: Column(
            children: [
              if (screenW < 560)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        setState(() {
                          _query = v;
                          _feedVisibleCount = _feedPageSize;
                        });
                        _scheduleSearchTrack();
                      },
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
                      items: _filteredItems(includeMarkets: true),
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
                      promoEvent: _bannerEvent,
                      onOpenPromoEvent: _openPromoEvent,
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
