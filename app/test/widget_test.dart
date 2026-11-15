// Firebase 없이 검증 가능한 순수 로직 및 위젯 테스트.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikstay/amenities.dart';
import 'package:jikstay/demo_data.dart';
import 'package:jikstay/detail_page.dart';
import 'package:jikstay/discovery_models.dart';
import 'package:jikstay/hub_details.dart';
import 'package:jikstay/i18n.dart';
import 'package:jikstay/main.dart';
import 'package:jikstay/naver_place_info.dart';
import 'package:jikstay/spot_detail_sheet.dart';
import 'package:jikstay/translation_store.dart';
import 'package:jikstay/travel_hub.dart';
import 'package:jikstay/trip_planner.dart';

void main() {
  group('지역 필터', () {
    test('부산/경상 칩은 경상남도·대구도 포함', () {
      expect(matchesRegion('경상남도', '부산/경상'), isTrue);
      expect(matchesRegion('대구광역시', '부산/경상'), isTrue);
      expect(matchesRegion('부산광역시', '부산/경상'), isTrue);
    });
    test('경기와 경상은 섞이지 않음', () {
      expect(matchesRegion('경기도', '부산/경상'), isFalse);
      expect(matchesRegion('경상북도', '서울/경기'), isFalse);
    });
    test('제주·강원·전라/충청', () {
      expect(matchesRegion('제주특별자치도', '제주'), isTrue);
      expect(matchesRegion('강원특별자치도', '강원'), isTrue);
      expect(matchesRegion('전북특별자치도', '전라/충청'), isTrue);
      expect(matchesRegion('세종특별자치시', '전라/충청'), isTrue);
      expect(matchesRegion('제주특별자치도', '강원'), isFalse);
    });
    test('전체는 모두 통과', () {
      expect(matchesRegion('아무거나', '전체'), isTrue);
    });
  });

  group('사용자 별점(Score) 및 후기(Review) 검증 로직', () {
    test('누적 별점 평균 및 후기 수 계산', () {
      final r0 = extractListingRating({});
      expect(r0.count, 0);
      expect(r0.average, 0.0);

      final r1 = extractListingRating({'review_count': 4, 'score_sum': 19});
      expect(r1.count, 4);
      expect(r1.average, 4.75);
    });

    test('보안 규칙과 동일한 리뷰 입력값 검증 (별점 1~5, 닉네임 1~24자, 본문 4~600자)', () {
      expect(validateUserReviewInput(nickname: '제주여행러', score: 5, comment: '깨끗하고 조용해요!'), isNull);
      expect(validateUserReviewInput(nickname: '', score: 5, comment: '깨끗하고 조용해요!'), 'nickname_length');
      expect(validateUserReviewInput(nickname: 'a' * 25, score: 5, comment: '깨끗하고 조용해요!'), 'nickname_length');
      expect(validateUserReviewInput(nickname: '여행자', score: 0, comment: '깨끗하고 조용해요!'), 'score_range');
      expect(validateUserReviewInput(nickname: '여행자', score: 6, comment: '깨끗하고 조용해요!'), 'score_range');
      expect(validateUserReviewInput(nickname: '여행자', score: 4, comment: '짧음'), 'comment_length');
    });
  });

  group('요금 표시 및 직거래 절감액 계산', () {
    test('원 단위 천 단위 구분', () {
      expect(formatWon(1500000), '1,500,000원');
      expect(formatWon(90000), '90,000원');
    });
    test('한달 > 일주일 > 1박 우선순위', () {
      expect(shortPrice({'monthly_price': 1500000, 'weekly_price': 500000}), '한달 150만 원');
      expect(shortPrice({'weekly_price': 500000}), '일주일 50만 원');
      expect(shortPrice({'nightly_min': 120000}), '1박 12만 원~');
      expect(shortPrice({}), '요금 직접 문의');
      expect(shortPrice(null), '요금 직접 문의');
    });
    test('일정별 예상 요금 및 플랫폼 수수료 절감액 산출', () {
      final range = DateTimeRange(start: DateTime(2026, 12, 4), end: DateTime(2026, 12, 6));
      final est = calculateStayEstimate({'nightly_min': 249600}, dateRange: range);
      expect(est.estimatedAmount, 499200);
      expect(est.estimatedFeeSaved, isNotNull);
      expect(est.estimatedFeeSaved!, greaterThanOrEqualTo(60000));
    });
    test('직거래 문의 메시지 템플릿 생성', () {
      final range = DateTimeRange(start: DateTime(2026, 12, 4), end: DateTime(2026, 12, 6));
      final msg = buildBookingInquiryTemplate(
        {'title': '해운대 오션뷰', 'promo_title': '선착순 온수욕조 무료 이벤트'},
        dateRange: range,
        adults: 3,
        children: 1,
      );
      expect(msg, contains('2026.12.04 ~ 2026.12.06 (2박)'));
      expect(msg, contains('성인 3명, 어린이 1명'));
      expect(msg, contains('선착순 온수욕조 무료 이벤트'));
    });
  });

  group('표준 Amenity 분류 및 필터', () {
    test('해운대 레퍼런스 데모 숙소 편의시설 및 미제공 시설 파싱', () {
      final haeundae = kDemoListingsMap[kDemoHaeundaeId]!;
      final groups = resolveAmenityGroups(haeundae);
      expect(groups.length, greaterThanOrEqualTo(8));
      expect(totalAmenityCount(haeundae), greaterThan(35));
      expect(extractUnavailableAmenities(haeundae), contains('세탁기 없음'));
      expect(matchesAmenityTab(haeundae, '오션뷰·해변'), isTrue);
      expect(matchesAmenityTab(haeundae, '자쿠지·욕조'), isTrue);
      expect(matchesAmenityTab(haeundae, '가족·키즈'), isTrue);
    });

    test('레거시 options 배열만 있는 문서도 카테고리로 안전 변환', () {
      final legacy = {'options': ['오션뷰', '세탁기', '무료 주차']};
      final groups = resolveAmenityGroups(legacy);
      expect(groups.map((g) => g.category), containsAll(['전망 및 입지', '세탁 및 다림질', '주차 및 출입']));
    });
  });

  group('검색 및 정렬', () {
    final sampleItems = <MapEntry<String, Map<String, dynamic>>>[
      MapEntry('a', {
        'title': '애월 돌담 독채',
        'region_depth1': '제주특별자치도',
        'region_depth2': '제주시 애월읍',
        'accommodation_type': '독채 민박',
        'capacity_max': 4,
        'options': ['오션뷰', '주차'],
        'summary_points': ['바다 도보 5분'],
        'pricing': {'nightly_min': 140000},
        'outbound_clicks': 3,
        'created_at': 1000,
      }),
      MapEntry('b', {
        'title': '양양 서핑 하우스',
        'region_depth1': '강원특별자치도',
        'region_depth2': '양양군 현남면',
        'accommodation_type': '독채 펜션',
        'capacity_max': 6,
        'options': ['바비큐', '자쿠지'],
        'summary_points': ['서핑 최적'],
        'pricing': {'nightly_min': 95000},
        'outbound_clicks': 10,
        'created_at': 3000,
      }),
      MapEntry('c', {
        'title': '경주 한옥',
        'region_depth1': '경상북도',
        'region_depth2': '경주시 황남동',
        'accommodation_type': '한옥',
        'capacity_max': 2,
        'options': ['조식포함'],
        'summary_points': ['대릉원 인근'],
        'pricing': {},
        'outbound_clicks': 1,
        'created_at': 2000,
      }),
    ];

    test('키워드·인원·편의시설 탭 필터', () {
      expect(filterAndSortListings(sampleItems, region: '전체', query: '오션뷰').map((e) => e.key), ['a']);
      expect(filterAndSortListings(sampleItems, region: '전체', amenityTab: '자쿠지·욕조').map((e) => e.key), ['b']);
      expect(filterAndSortListings(sampleItems, region: '전체', minGuests: 6).map((e) => e.key), ['b']);
      expect(filterAndSortListings(sampleItems, region: '강원', query: '돌담'), isEmpty);
    });

    test('정렬 (최신순 / 낮은 요금순 / 인기순)', () {
      expect(
        filterAndSortListings(sampleItems, region: '전체', sort: ListingSort.newest).map((e) => e.key).toList(),
        ['b', 'c', 'a'],
      );
      expect(
        filterAndSortListings(sampleItems, region: '전체', sort: ListingSort.priceAsc).map((e) => e.key).toList(),
        ['b', 'a', 'c'],
      );
      expect(
        filterAndSortListings(sampleItems, region: '전체', sort: ListingSort.clicksDesc).map((e) => e.key).toList(),
        ['b', 'a', 'c'],
      );
    });

    test('숙박 기간 필터 및 카드 표시 가격과 정렬 기준 일치', () {
      final mixed = <MapEntry<String, Map<String, dynamic>>>[
        MapEntry('m1', {
          'title': '한달 200',
          'region_depth1': '제주특별자치도',
          'pricing': {'nightly_min': 80000, 'monthly_price': 2000000},
        }),
        MapEntry('m2', {
          'title': '한달 120',
          'region_depth1': '제주특별자치도',
          'pricing': {'nightly_min': 110000, 'monthly_price': 1200000},
        }),
        MapEntry('n_only', {
          'title': '1박 전용',
          'region_depth1': '제주특별자치도',
          'pricing': {'nightly_min': 90000},
        }),
      ];
      expect(
        filterAndSortListings(mixed, region: '전체', sort: ListingSort.priceAsc).map((e) => e.key).toList(),
        ['n_only', 'm2', 'm1'],
      );
      expect(
        filterAndSortListings(mixed, region: '전체', period: StayPeriod.monthly, sort: ListingSort.priceAsc)
            .map((e) => e.key)
            .toList(),
        ['m2', 'm1'],
      );
      expect(shortPrice(mixed[1].value['pricing'] as Map<String, dynamic>, period: StayPeriod.nightly), '1박 11만 원~');
    });

    test('예약 창구 채널 판별 및 평점 높은순 정렬', () {
      expect(bookingChannelName('https://booking.naver.com/booking/3/bizes/123'), '네이버 예약');
      expect(bookingChannelName('https://pf.kakao.com/_abcde'), '카카오톡 채널');
      expect(bookingChannelName('https://instagram.com/stay_jeju'), '인스타그램');
      expect(bookingChannelName('https://my-stay.kr'), '호스트 직거래');

      final rated = <MapEntry<String, Map<String, dynamic>>>[
        MapEntry('no_rev', {'title': '무후기', 'region_depth1': '제주특별자치도', 'curated_score': 99}),
        MapEntry('r_45', {'title': '평점4.5', 'region_depth1': '제주특별자치도', 'review_count': 2, 'score_sum': 9}),
        MapEntry('r_50', {'title': '평점5.0', 'region_depth1': '제주특별자치도', 'review_count': 3, 'score_sum': 15}),
      ];
      expect(
        filterAndSortListings(rated, region: '전체', sort: ListingSort.ratingDesc).map((e) => e.key).toList(),
        ['r_50', 'r_45', 'no_rev'],
      );
    });
  });

  group('위젯 렌더링 및 전환 UX 검증', () {
    testWidgets('ListingCard 렌더링: 외국인 전용 배지 및 방문자 별점 배지 표시', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 430,
            child: ListingCard(
              docId: 'stay_test01',
              data: {
                'title': '연남동 테라스',
                'region_depth1': '서울특별시',
                'region_depth2': '마포구 연남동',
                'license_type': kForeignOnly,
                'summary_points': ['홍대입구역 도보 6분'],
                'pricing': {'monthly_price': 1650000},
                'review_count': 3,
                'score_sum': 14,
                'images': [],
                // 운영자 직거래 링크가 있어야 '수수료 0원 직거래' CTA가 나온다 (네이버 지도 URL은 제외)
                'direct_booking_url': 'https://yeonnam-terrace.example.com/booking',
              },
            ),
          ),
        ),
      ));

      expect(find.text('연남동 테라스'), findsOneWidget);
      expect(find.text('서울특별시 마포구 연남동'), findsOneWidget);
      expect(find.text('4.7 (3)'), findsOneWidget);
      expect(find.text('외국인 전용 숙소'), findsOneWidget);
      expect(find.text('한달 165만 원'), findsOneWidget);
      expect(find.text('수수료 0원 직거래'), findsOneWidget);
    });

    testWidgets('해운대 레퍼런스 상세페이지 2단 레이아웃·편의시설 모달·신청 위젯 렌더링', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final demoData = Map<String, dynamic>.from(kDemoListingsMap[kDemoHaeundaeId]!);
      demoData['images'] = <Map<String, dynamic>>[]; // 테스트 환경 네트워크 이미지 요청 생략

      await tester.pumpWidget(MaterialApp(
        home: ListingDetailPage(
          listingId: kDemoHaeundaeId,
          homeBuilder: (_) => const SizedBox.shrink(),
          initialData: demoData,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('5층 파노라마 오션뷰'), findsWidgets);
      expect(find.textContaining('침실 1개'), findsOneWidget);
      expect(find.textContaining('선착순 온수욕조 무료 이벤트'), findsWidgets);
      expect(find.text('예약 확정 전에는 요금이 청구되지 않습니다.'), findsOneWidget);

      final allAmenitiesBtn = find.text('편의시설 48개 모두 보기');
      await tester.scrollUntilVisible(allAmenitiesBtn, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(allAmenitiesBtn);
      await tester.pumpAndSettle();

      final dialogScrollable = find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(find.text('숙소에 없는 시설 · 제한 사항'), 300, scrollable: dialogScrollable);
      await tester.pumpAndSettle();

      expect(find.text('숙소에 없는 시설 · 제한 사항'), findsOneWidget);
      expect(find.text('세탁기 없음'), findsWidgets);
    });

    test('해외 게스트용 다국어(영·일·중) 문의 문구 자동 병기 생성 및 스폰서 우선노출·업종 필터', () {
      final range = DateTimeRange(start: DateTime(2026, 12, 10), end: DateTime(2026, 12, 13));
      final enMsg = buildBookingInquiryTemplate(
        {'title': '애월 돌집'},
        dateRange: range,
        adults: 2,
        lang: AppLang.en,
      );
      expect(enMsg, contains('안녕하세요 사장님!'));
      expect(enMsg, contains('3박 / 3 nights'));
      expect(enMsg, contains('government-verified stay'));

      final items = <MapEntry<String, Map<String, dynamic>>>[
        MapEntry('pub1', {
          'title': '공공 민박',
          'region_depth1': '제주특별자치도',
          'license_type': '농어촌민박업',
          'is_sponsored': false,
          'created_at': 5000,
          'i18n': {
            'en': {'title': 'Jeju Countryside Stay'},
          },
        }),
        MapEntry('sponsored1', {
          'title': '공식 한옥',
          'region_depth1': '제주특별자치도',
          'license_type': '한옥체험업',
          'is_sponsored': true,
          'created_at': 1000,
        }),
      ];
      // 스폰서 숙소는 최신순에서 일반 공공 숙소보다 상단에 배치된다
      expect(filterAndSortListings(items, region: '제주').map((e) => e.key).toList(), ['sponsored1', 'pub1']);
      // 업종 필터 및 영문 키워드 검색
      expect(filterAndSortListings(items, region: '전체', licenseType: '한옥체험업').map((e) => e.key).toList(), ['sponsored1']);
      expect(filterAndSortListings(items, region: '전체', query: 'countryside').map((e) => e.key).toList(), ['pub1']);
    });

    testWidgets('공공API 선별 숙소 상세페이지: 호스트 등록 배너 제거 확인 및 사용자 별점·후기 작성 동작', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appLangNotifier.value = AppLang.ko;

      final pubData = Map<String, dynamic>.from(kDemoListingsMap['stay_demo_pub_seoul']!);
      await tester.pumpWidget(MaterialApp(
        home: ListingDetailPage(
          listingId: 'stay_demo_pub_seoul',
          homeBuilder: (_) => const SizedBox.shrink(),
          initialData: pubData,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('행정안전부 공공데이터 영업확인 업소'), findsOneWidget);
      expect(find.textContaining('네이버 블로그 실방문 후기'), findsOneWidget);
      expect(find.text('무료 주인 등록 · 직거래 연결'), findsNothing);

      // 별점 4점 선택 후 닉네임·후기 작성 및 등록 검증
      final star4 = find.byKey(const Key('review_star_4'));
      await tester.scrollUntilVisible(star4, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(star4);
      await tester.pumpAndSettle();
      await tester.tap(star4);
      await tester.pump();

      await tester.enterText(find.byKey(const Key('review_nickname_input')), '홍대산책러');
      await tester.enterText(find.byKey(const Key('review_comment_input')), '연남동 경의선숲길 바로 옆이라 위치가 정말 좋았어요!');

      final submitBtn = find.byKey(const Key('review_submit_btn'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('홍대산책러'), findsWidgets);
      expect(find.textContaining('연남동 경의선숲길 바로 옆이라 위치가 정말 좋았어요!'), findsOneWidget);
      expect(find.text('4.0 / 5.0'), findsOneWidget);
    });

    testWidgets('반값여행 · 축제 · 정부/지자체 매거진 허브 렌더링 및 지역 원클릭 숙소 연동', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 경량 색인 항목(i18n 생략 시)에서도 영문/일문 지역명 조합 타이틀 정상 생성
      expect(
        localizedListingTitle({'title': '다로산스파펜션', 'region_depth1': '경상남도'}, AppLang.en),
        '다로산스파펜션 (Gyeongnam)',
      );

      String? pickedRegion;
      String? pickedCity;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PublicTravelHubView(
            lang: AppLang.ko,
            onSelectCityForStays: (rg, city) {
              pickedRegion = rg;
              pickedCity = city;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('2026 반값여행'), findsWidgets);
      expect(find.textContaining('K-공감'), findsWidgets);

      final namhaeChip = find.text('남해 합법숙소');
      await tester.scrollUntilVisible(namhaeChip, 250, scrollable: find.byType(Scrollable).first);
      await tester.tap(namhaeChip);
      await tester.pump();
      expect(pickedRegion, '부산/경상');
      expect(pickedCity, '남해');
    });

    test('전국 17개 시도 정규화 및 주변 먹거리·볼거리·축제·E-book 반경 연결(buildConnectedBundle)', () {
      expect(kProvinceJumpList.length, 18); // 전체 + 17개 시도
      expect(
        inferProvinceFromRaw({'region_depth1': '전남광주통합특별시', 'region_depth2': '동구 충장로'}),
        '광주',
      );
      expect(
        inferProvinceFromRaw({'region_depth1': '전남광주통합특별시', 'region_depth2': '여수시 돌산읍'}),
        '전남',
      );

      final anchor = kBuiltInSeedDiscoveryItems.firstWhere((e) => e.id == 'spot_fo_seed_1'); // 장수 한우명가
      expect(anchor.kakaoRouteUrl, contains('https://map.kakao.com/link/to/'));
      expect(anchor.googleTransitUrl, contains('travelmode=transit'));

      final jangsuEbook = kBuiltInSeedDiscoveryItems.firstWhere((e) => e.id == 'ebook_jeonbuk_jangsu');
      expect(jangsuEbook.pdfLinks.map((p) => p.url), contains('https://www.jangsu.go.kr/images/tour/tour_guide.pdf'));
      expect(jangsuEbook.pdfLinks.map((p) => p.url), contains('https://www.jangsu.go.kr/images/tour/content/sub05/tourist.pdf'));

      // 15일(끝자리 5) 전통 5일장 자동 매칭 확인 (장수전통시장 5일장 등)
      final day15Markets = marketsOpeningOn(DateTime(2026, 11, 15), kFallbackTraditional5DayMarkets, province: '전북');
      expect(day15Markets.map((m) => m.id), contains('mkt_jangsu'));

      final bundle = buildConnectedBundle(anchor, kBuiltInSeedDiscoveryItems);
      expect(bundle.ebooks.map((e) => e.id), contains('ebook_jeonbuk_jangsu'));
      expect(bundle.attractions.map((e) => e.id), contains('spot_at_seed_1'));
      expect(bundle.events.map((e) => e.id), contains('spot_ev_seed_1'));
    });

    testWidgets('Zillow 스타일 지도 + 실시간 로컬 피드 + 지자체 E-book·방문혜택 쿠폰 연동 검증', (tester) async {
      tester.view.physicalSize = const Size(1360, 920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appLangNotifier.value = AppLang.ko;

      await tester.pumpWidget(MaterialApp(
        home: HomePage(
          initialDemoMode: true,
          seedItemsOverride: kBuiltInSeedDiscoveryItems,
        ),
      ));
      await tester.pumpAndSettle();

      // 1. 선택 과부하 없는 첫 화면: 17개 시도 칩은 기본 접힘, 하루 한 편 '오늘의 로컬 스토리' 히어로 노출 확인
      expect(find.text('직스테이 로컬'), findsOneWidget);
      expect(find.byKey(const Key('daily_story_banner')), findsOneWidget);
      expect(find.byKey(const Key('prov_chip_전북')), findsNothing);
      expect(find.textContaining('실시간 로컬 피드'), findsOneWidget);

      // 2. 일일 스토리 배너 클릭 → 매거진형 스토리 상세 페이지(원문 + 《장수여행》 p.9 핵심 탐방박스 + 원본 PDF + 대중교통) 확인
      await tester.tap(find.byKey(const Key('open_daily_story_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('금강첫물, 뜬봉샘 발원지'), findsWidgets);
      expect(find.textContaining('조선 개국조 이성계가 봉황새가'), findsWidgets);
      expect(find.byKey(const Key('story_practical_box')), findsOneWidget);
      expect(find.textContaining('《장수여행》 가이드북 원본 열람'), findsOneWidget);
      expect(find.byKey(const Key('story_kakao_route_btn')), findsOneWidget);

      // 지도로 복귀
      await tester.tap(find.byKey(const Key('story_back_btn')));
      await tester.pumpAndSettle();

      // 3. 지역 선택 토글 클릭 후 전북 선택 시 전북(무주·진안·장수) 항목 표시 확인
      await tester.tap(find.byKey(const Key('region_picker_btn')));
      await tester.pumpAndSettle();
      final provChip = find.byKey(const Key('prov_chip_전북'));
      await tester.ensureVisible(provChip);
      await tester.tap(provChip);
      await tester.pumpAndSettle();

      final feedScrollable = find.descendant(
        of: find.byKey(const Key('live_feed_scroll')),
        matching: find.byType(Scrollable),
      ).first;
      final foodCard = find.byKey(const ValueKey('feed_card_spot_fo_seed_1'));
      await tester.scrollUntilVisible(foodCard, 200, scrollable: feedScrollable);
      await tester.pumpAndSettle();
      expect(find.textContaining('장수 한우명가 로컬식당'), findsWidgets);

      // 4. 방문혜택 쿠폰 식당 카드 클릭 → 팝업(BottomSheet) 없이 StoryDetailPage와 동일한 전체 상세 페이지 전환
      await tester.tap(foodCard);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SpotDetailSheet), findsOneWidget);
      expect(find.byKey(const Key('spot_practical_box')), findsOneWidget);
      expect(find.byKey(const Key('spot_place_search_box')), findsOneWidget);
      expect(find.byKey(const Key('spot_kakao_place_btn')), findsOneWidget);
      expect(find.byKey(const Key('spot_naver_place_btn')), findsOneWidget);
      expect(find.byKey(const Key('spot_naver_search_btn')), findsOneWidget);

      final sheetScrollable = find.descendant(
        of: find.byType(SpotDetailSheet),
        matching: find.byType(Scrollable),
      ).first;

      // 4-1. 방문 혜택 쿠폰 버튼 클릭 → 팝업 다이얼로그 없이 페이지 내 인라인 바우처 오픈 확인
      final couponBtn = find.byKey(const Key('sheet_coupon_btn'));
      await tester.scrollUntilVisible(couponBtn, 180, scrollable: sheetScrollable);
      await tester.ensureVisible(couponBtn);
      await tester.pumpAndSettle();
      await tester.tap(couponBtn);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('직스테이 로컬 방문 혜택 쿠폰'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();

      // 길찾기 버튼 및 지자체 공식 가이드북 PDF 연결 확인
      final dirBtn = find.byKey(const Key('sheet_directions_btn'));
      await tester.scrollUntilVisible(dirBtn, 160, scrollable: sheetScrollable);
      await tester.pumpAndSettle();
      expect(dirBtn, findsOneWidget);
      expect(find.byKey(const Key('sheet_kakao_route_btn')), findsOneWidget);
      expect(find.byKey(const Key('sheet_google_transit_btn')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.textContaining('장수군청 공식 관광안내도'),
        180,
        scrollable: sheetScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('장수군청 공식 관광안내도'), findsWidgets);
      expect(find.textContaining('관광안내지도 PDF 원본'), findsOneWidget);

      // 스크롤 후 주변 연결 코스(반경 매칭) 확인
      await tester.scrollUntilVisible(
        find.textContaining('함께 방문하기 좋은 주변 연결 코스'),
        180,
        scrollable: sheetScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('함께 방문하기 좋은 주변 연결 코스'), findsOneWidget);
      expect(find.textContaining('진안 마이산 탑사'), findsWidgets);

      // 5. 식당 방문자 별점 및 한줄 후기 작성 동작 확인
      final nickField = find.byKey(const Key('spot_review_nick'));
      await tester.scrollUntilVisible(nickField, 240, scrollable: sheetScrollable);
      await tester.ensureVisible(nickField);
      await tester.pumpAndSettle();
      await tester.enterText(nickField, '장수여행객');
      await tester.enterText(find.byKey(const Key('spot_review_comment')), '관광지도 보고 방문해서 음료 혜택까지 잘 받았어요!');
      await tester.tap(find.byKey(const Key('spot_review_submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('장수여행객: 관광지도 보고 방문해서 음료 혜택까지 잘 받았어요!'), findsOneWidget);
    });

    testWidgets('캘린더 보기 및 네이버 지도 보기 전환 동작 검증', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialDemoMode: true,
            seedItemsOverride: kBuiltInSeedDiscoveryItems,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 초기 화면에서는 지도가 로드되지 않음
      expect(find.byKey(const Key('interactive_korea_map_canvas')), findsNothing);
      expect(find.byKey(const Key('local_calendar_card')), findsNothing);

      // 1. 캘린더 보기 탭 전환 → 월간 축제·5일장 달력 및 일정 브리핑 확인
      await tester.tap(find.byKey(const Key('view_mode_calendar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('local_calendar_card')), findsOneWidget);
      expect(find.textContaining('무주 반딧불 & 덕유산 계절 트레킹 페스타'), findsWidgets);

      // 2. 네이버 지도 보기 탭 전환 → 한국어 핀 지도 + 네이버 지도 직결 바 + 핀 상세 진입 확인
      await tester.tap(find.byKey(const Key('view_mode_map')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('naver_map_top_bar')), findsOneWidget);
      expect(find.byKey(const Key('open_naver_map_region_btn')), findsOneWidget);
      expect(find.byKey(const Key('interactive_korea_map_canvas')), findsOneWidget);
      expect(find.byKey(const Key('map_pin_naver_btn')), findsOneWidget);
      expect(find.byKey(const Key('map_pin_detail_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('map_pin_detail_btn')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SpotDetailSheet), findsOneWidget);
    });

    testWidgets('다국어(EN/JA) 전환 시 스토리 배너·피드 카드·상세 페이지 번역 반영 검증', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() {
        tester.binding.setSurfaceSize(null);
        appLangNotifier.value = AppLang.ko;
        TranslationStore.clearForTest();
      });

      final storyId = kFallbackDailyMunicipalStories.first.id;
      final firstFeedId = kBuiltInSeedDiscoveryItems.first.id;
      TranslationStore.seedForTest(AppLang.en, {
        'stories': {
          storyId: {
            'title': 'Translated English Story Title',
            'season_badge': 'Autumn Forest Trail',
            'source_book': 'Jangsu Official Guide p.9',
            'subtitle': 'Jangsu-gun, Jeonbuk',
            'address': '10-18 Mulppuraengi-gil, Jangsu-gun',
            'pull_quote': 'Translated English Pull Quote',
            'paragraphs': ['Translated English story paragraph body.'],
          },
        },
        'items': {
          firstFeedId: {
            'title': 'Translated First Feed Spot',
            'region_label': 'Jeonbuk',
            'addr': 'Muju-gun, Jeonbuk',
            'overview': 'Seasonal trekking festival in Jeonbuk',
          },
        },
      });
      TranslationStore.seedForTest(AppLang.ja, {
        'stories': {
          storyId: {
            'title': '日本語ストーリータイトル',
            'season_badge': '秋の森トレイル',
            'source_book': '長水郡公式ガイド p.9',
            'subtitle': '全北・長水郡',
            'address': '全北特別自治道長水郡',
            'pull_quote': '日本語の抜粋フレーズ',
            'paragraphs': ['日本語の本文パラグラフ。'],
          },
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialDemoMode: true,
            seedItemsOverride: kBuiltInSeedDiscoveryItems,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 영어로 전환
      selectAppLang(AppLang.en);
      await tester.pumpAndSettle();
      expect(find.textContaining('Translated English Story Title'), findsWidgets);
      expect(find.textContaining('Translated First Feed Spot'), findsWidgets);
      expect(find.text('📖 Stories & Feed'), findsWidgets);

      // 일본어로 전환
      selectAppLang(AppLang.ja);
      await tester.pumpAndSettle();
      expect(find.textContaining('日本語ストーリータイトル'), findsWidgets);
      expect(find.text('📖 ストーリー・一覧'), findsWidgets);

      // 스토리 상세 페이지에서도 일본어 본문 확인
      await tester.tap(find.byKey(const Key('open_daily_story_btn')));
      await tester.pumpAndSettle();
      expect(find.textContaining('日本語の本文パラグラフ'), findsOneWidget);
    });

    test('임박(D-0~D-7) 신규 이벤트가 있으면 초기화면·지역 배너에 우선 노출', () {
      final imminent = DiscoveryItem(
        id: 'ev_imminent_test',
        category: DiscoveryCategory.event,
        title: '임박 테스트 불꽃축제',
        province: '부산',
        regionLabel: '부산 수영구',
        address: '부산광역시 수영구 광안해변로',
        lat: 35.153,
        lng: 129.118,
        imageUrl: 'https://example.com/fireworks.jpg',
        startDate: '20261118',
        endDate: '20261120',
      );
      final pickedAll = pickTodayMunicipalStory(
        stories: kFallbackDailyMunicipalStories,
        allItems: [...kBuiltInSeedDiscoveryItems, imminent],
        selectedProvince: '전체',
        now: DateTime(2026, 11, 15),
      );
      expect(pickedAll.id, 'ev_imminent_test');
      expect(pickedAll.seasonBadge, contains('D-3'));

      final pickedBusan = pickTodayMunicipalStory(
        stories: kFallbackDailyMunicipalStories,
        allItems: [...kBuiltInSeedDiscoveryItems, imminent],
        selectedProvince: '부산',
        now: DateTime(2026, 11, 15),
      );
      expect(pickedBusan.id, 'ev_imminent_test');
    });

    testWidgets('주말 1박2일·외국인 3·5일 여행코스 자동 생성 및 URL 인코딩/디코딩 검증', (tester) async {
      appLangNotifier.value = AppLang.ko;
      final plan = generateTripPlan(
        allItems: kBuiltInSeedDiscoveryItems,
        province: '전체',
        days: 2,
        foreignerOnly: false,
      );
      expect(plan.stops, isNotEmpty);

      final encoded = encodeTripPlanParam(plan);
      final decoded = decodeTripPlanParam(encoded, kBuiltInSeedDiscoveryItems);
      expect(decoded, isNotNull);
      expect(decoded!.days, 2);
      expect(decoded.stops.length, plan.stops.length);

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialDemoMode: true,
            seedItemsOverride: kBuiltInSeedDiscoveryItems,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trip_planner_btn')).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('주말 1박2일'), findsWidgets);
      expect(find.byKey(const Key('copy_trip_plan_url_btn')), findsOneWidget);
    });
  });

  group('네이버 지역 검색 보강 정보', () {
    test('공식 링크 종류별 라벨', () {
      expect(officialLinkLabel('https://www.instagram.com/abc', AppLang.ko), '공식 인스타그램');
      expect(officialLinkLabel('https://talk.naver.com/w43gsp', AppLang.ko), '네이버 톡톡 문의');
      expect(officialLinkLabel('https://blog.naver.com/saemmoru', AppLang.en), 'Owner blog');
      expect(officialLinkLabel('http://www.pensionsea.com/', AppLang.ja), '公式サイト');
    });

    testWidgets('업종·링크·출처 표시, 값이 없으면 숨김', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: NaverPlaceInfo(
            data: {'naver_category': '숙박>펜션', 'naver_link': 'https://www.instagram.com/abc'},
            lang: AppLang.ko,
          ),
        ),
      ));
      expect(find.text('숙박 › 펜션'), findsOneWidget);
      expect(find.byKey(const Key('naver_official_link_btn')), findsOneWidget);
      expect(find.text('정보 출처: 네이버'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: NaverPlaceInfo(data: {'naver_link': 'javascript:alert(1)'}, lang: AppLang.ko)),
      ));
      expect(find.byKey(const Key('naver_place_info')), findsNothing);
    });
  });

  group('허브 상세 지연 로드', () {
    setUp(HubDetailStore.clearForTest);
    tearDown(HubDetailStore.clearForTest);

    test('core 항목에 시·도 상세(본문·방문기·전체 개요)를 합치고 실시간 통계는 유지', () async {
      HubDetailStore.seed('daegu', {
        'spot_a': {
          'overview': '수성못 전체 개요입니다. 밤이면 야경이 아름답다.',
          'paragraphs': ['첫 문단', '둘째 문단'],
          'naver_reviews': [
            {'title': '수성못 산책 후기', 'summary': '좋아요', 'link': 'https://blog.naver.com/x/1'}
          ],
        },
      });
      final core = parseSpotJson({
        'id': 'spot_a',
        'kind': 'attraction',
        'title': '수성못',
        'province': '대구',
        'overview': '수성못 전체…',
        'lat': 35.8,
        'lng': 128.6,
        'has_details': true,
      }, fallbackCategory: DiscoveryCategory.attraction)!
          .copyWithStats(reviewCount: 3, scoreSum: 14);
      expect(core.paragraphs, isEmpty);

      final full = await hydrateDiscoveryItem(core);
      expect(full.paragraphs, ['첫 문단', '둘째 문단']);
      expect(full.naverReviews.length, 1);
      expect(full.subtitle, contains('야경'));
      expect(full.reviewCount, 3);
      expect(full.scoreSum, 14);
      expect(full.raw.containsKey('has_details'), isFalse);
    });

    test('상세 표시가 없는 항목은 그대로 반환', () async {
      final item = parseSpotJson({'id': 'spot_b', 'title': '짧은집', 'province': '세종', 'lat': 36.5, 'lng': 127.2},
          fallbackCategory: DiscoveryCategory.food)!;
      expect(identical(await hydrateDiscoveryItem(item), item), isTrue);
    });
  });

  group('직거래 링크 판정', () {
    test('운영자 링크만 직거래로 보고 네이버 지도 URL·빈 값은 제외', () {
      expect(hasDirectBookingUrl({'direct_booking_url': 'https://pension.example.com/book'}), isTrue);
      expect(hasDirectBookingUrl({'direct_booking_url': 'https://map.naver.com/p/search/abc'}), isFalse);
      expect(hasDirectBookingUrl({'direct_booking_url': 'javascript:alert(1)'}), isFalse);
      expect(hasDirectBookingUrl({}), isFalse);
      expect(bookingCtaLabel('https://map.naver.com/p/search/abc', data: {'direct_booking_url': 'https://map.naver.com/p/search/abc'}),
          '네이버 지도·예약처 보기');
    });
  });
}
