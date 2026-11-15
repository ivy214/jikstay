part of '../discovery_models.dart';

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

  final chapterMedia = <ChapterMediaItem>[];
  if (m['chapter_media'] is List) {
    for (final raw in m['chapter_media'] as List) {
      if (raw is Map) {
        chapterMedia.add(ChapterMediaItem(
          imageUrl: (raw['image_url'] ?? '').toString().trim(),
          label: (raw['label'] ?? '').toString().trim(),
        ));
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
    chapterMedia: chapterMedia,
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
  DailyStoryItem(
    id: 'story_seoul_visitseoul_guide',
    province: '서울',
    city: '종로·중구·성수',
    seasonBadge: '🏙️ 웹 버전 공식 투어가이드',
    sourceBook: '서울관광재단 비짓서울 《2026 서울관광안내서》 웹 에디션',
    months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    title: '서울 공식 투어가이드 — 고궁 산책부터 한강·성수 로컬 코스까지',
    subtitle: '서울특별시 중구·종로구 일대 (12MB PDF 핵심 요약 웹 버전)',
    address: '서울특별시 종로구 사직로 161 (경복궁·북촌·남산·한강 권역)',
    lat: 37.5796,
    lng: 126.9770,
    phone: '02-120',
    pullQuote: '12MB 대용량 PDF를 내려받지 않아도, 서울 5대 권역 핵심 명소와 교통·맛집 동선을 웹 매거진으로 바로 읽어보세요',
    paragraphs: [
      '서울관광재단(Visit Seoul)이 발간한 《2026 서울관광안내서》는 도심 고궁(경복궁·창덕궁·덕수궁)과 북촌 한옥마을의 천년 역사부터, 남산 서울타워·청계천 야경, 성수동·연남동 로컬 감성 골목, 한강공원 피크닉까지 서울의 매력을 권역별로 정리한 공식 종합 가이드북입니다.',
      '직스테이 로컬은 12MB PDF 전체를 내려받기 전에도 모바일·PC에서 1초 만에 핵심 코스를 훑어보고, 바로 대중교통 길찾기와 주변 로컬 맛집·합법 인증 도시민박(한옥·외국인관광도시민박)까지 이어볼 수 있도록 가벼운 웹 매거진 버전으로 재구성했습니다.',
    ],
    images: [
      'https://tong.visitkorea.or.kr/cms/resource/43/4056543_image2_1.jpg',
      'https://tong.visitkorea.or.kr/cms/resource/50/3509850_image2_1.jpg',
      'https://tong.visitkorea.or.kr/cms/resource/83/3077783_image2_1.JPG',
    ],
    practicalHeader: '《2026 서울관광안내서》 핵심 권역 · 대중교통 패스 · 다국어 안내',
    practicalInfo: [
      PracticalInfoRow(label: '핵심 5대 권역', value: '도심 고궁·북촌 / 홍대·연남 / 강남·잠실 / 성수·건대 / 여의도·한강'),
      PracticalInfoRow(label: '추천 교통패스', value: '기후동행카드(관광권) · 티머니 · 공항철도 AREX'),
      PracticalInfoRow(label: '종합 안내전화', value: '다산콜센터 02-120 / 관광통역안내 1330 (한·영·일·중)'),
      PracticalInfoRow(label: '원본 책자', value: '비짓서울 공식 2026 가이드북 PDF (12MB) 무료 제공'),
    ],
    pdfLinks: [
      MunicipalPdfLink(
        label: '📥 비짓서울 공식 가이드북 원본 PDF (12MB)',
        labelEn: '📥 VisitSeoul Official 2026 Guidebook PDF (12MB)',
        url: 'https://korean.visitseoul.net/comm/getFile?srvcId=GUIDEBOOK&parentSn=1154&fileTy=ATTACH&fileNo=8',
      ),
      MunicipalPdfLink(
        label: '🌐 비짓서울 가이드북 & 지도 모음',
        labelEn: '🌐 VisitSeoul Maps & Guides Portal',
        url: 'https://korean.visitseoul.net/map-guide-book',
      ),
    ],
    enSummary: 'Web edition of Visit Seoul’s Official 2026 Guidebook—explore royal palaces, Bukchon Hanok Village, Seongsu, and Hangang River routes instantly without downloading the 12MB PDF.',
  ),
];

/// 명소·축제로 만든 스토리를 (상세 필드가 채워진) 새 명소 데이터로 다시 만든다. 배지 문구는 유지.
DailyStoryItem rebuildStoryFromSpot(DailyStoryItem story, DiscoveryItem spot, List<DiscoveryItem> allItems) =>
    _storyFromSpot(spot, story.province, allItems, badgeOverride: story.seasonBadge);

/// 계절(월)·선택 지역·오늘 날짜에 맞춰 '하루 단 한 편' 주인공 로컬 스토리를 선정한다.
DailyStoryItem _storyFromSpot(
  DiscoveryItem topSpot,
  String province,
  List<DiscoveryItem> allItems, {
  String? badgeOverride,
}) {
  final provEbooks = allItems
      .where((e) => e.category == DiscoveryCategory.ebook && e.province == province)
      .toList();
  final eb = provEbooks.isNotEmpty ? provEbooks.first : null;
  final cleanCity = topSpot.regionLabel.startsWith(province)
      ? topSpot.regionLabel.substring(province.length).trim()
      : topSpot.regionLabel;
  return DailyStoryItem(
    id: topSpot.id,
    province: province,
    city: cleanCity,
    seasonBadge: badgeOverride ??
        (topSpot.category == DiscoveryCategory.event
            ? '🎉 지금 주목할 지역 축제 스토리'
            : '🏞️ 계절 테마 로컬 명소 이야기'),
    sourceBook: eb != null ? eb.title : '$province 공식 문화관광 자료',
    months: const [],
    title: topSpot.title,
    subtitle: topSpot.address,
    address: topSpot.address,
    lat: topSpot.lat,
    lng: topSpot.lng,
    phone: topSpot.phone,
    pullQuote: topSpot.pullQuote.isNotEmpty
        ? topSpot.pullQuote
        : (topSpot.subtitle.isNotEmpty ? topSpot.subtitle : '$province에서 만나는 특별한 계절 여행지'),
    paragraphs: [
      if (topSpot.paragraphs.isNotEmpty)
        ...topSpot.paragraphs
      else if (topSpot.subtitle.isNotEmpty)
        topSpot.subtitle,
      if (eb != null)
        '${eb.title}(${eb.address})을 함께 열람하시면 주변 추천 산책코스와 로컬 먹거리 지도를 한눈에 확인하실 수 있습니다.',
    ],
    images: topSpot.effectiveGallery,
    practicalHeader: topSpot.practicalHeader.isNotEmpty
        ? topSpot.practicalHeader
        : '$province 추천 방문지 · 대중교통 및 자차 길찾기 바로 연결',
    practicalInfo: topSpot.practicalInfo.isNotEmpty
        ? topSpot.practicalInfo
        : [
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

List<DailyStoryItem> _pickImminentEventStories(
  List<DiscoveryItem> allItems,
  DateTime todayDay, {
  String province = '전체',
  int maxCount = 4,
}) {
  final scored = <(int, DiscoveryItem)>[];
  for (final ev in allItems) {
    if (ev.category != DiscoveryCategory.event || ev.imageUrl.isEmpty) continue;
    if (province != '전체' && ev.province != province) continue;
    final start = parseYmdDate(ev.startDate);
    if (start == null) continue;
    final daysToStart = start.difference(todayDay).inDays;
    if (daysToStart >= 0 && daysToStart <= 7) {
      scored.add((daysToStart, ev));
    }
  }
  scored.sort((a, b) => a.$1.compareTo(b.$1));
  return scored.take(maxCount).map((pair) {
    final days = pair.$1;
    final ev = pair.$2;
    final badge = days == 0 ? '🔥 오늘 개막 · 임박 축제' : '⏳ 개막 D-$days · 임박 축제';
    return _storyFromSpot(ev, ev.province, allItems, badgeOverride: badge);
  }).toList();
}

DailyStoryItem pickTodayMunicipalStory({
  required List<DailyStoryItem> stories,
  required List<DiscoveryItem> allItems,
  String selectedProvince = '전체',
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final todayDay = DateTime(today.year, today.month, today.day);
  final dayOffset = todayDay.difference(DateTime(2026, 11, 15)).inDays.abs();
  final source = stories.isNotEmpty ? stories : kFallbackDailyMunicipalStories;

  // 1. 특정 시·도를 선택한 경우: 임박(D-0~D-7) 축제 또는 해당 시·도 공식 가이드북 웹 버전 우선
  if (selectedProvince != '전체') {
    final imminentProv = _pickImminentEventStories(allItems, todayDay, province: selectedProvince, maxCount: 2);
    final mergedProv = [
      ...source.where((s) => s.province == selectedProvince),
      ...kFallbackDailyMunicipalStories.where(
        (fb) => fb.province == selectedProvince && !source.any((s) => s.id == fb.id),
      ),
    ];
    final seasonalProv = mergedProv.where((s) => s.months.isEmpty || s.months.contains(today.month)).toList();
    final baseProv = seasonalProv.isNotEmpty ? seasonalProv : mergedProv;
    final pool = [...imminentProv, ...baseProv];
    if (pool.isNotEmpty) {
      return pool[dayOffset % pool.length];
    }
    final provSpots = allItems
        .where((e) =>
            (e.category == DiscoveryCategory.event || e.category == DiscoveryCategory.attraction) &&
            e.province == selectedProvince)
        .toList();
    if (provSpots.isNotEmpty) {
      return _storyFromSpot(provSpots.first, selectedProvince, allItems);
    }
  }

  // 2. 전체 보기: 임박(D-0~D-7) 신규 축제를 최우선으로 배치하고 계절별 지자체 스토리와 함께 순환
  final imminentAll = _pickImminentEventStories(allItems, todayDay, maxCount: 4);
  final seasonal = source.where((s) => s.months.isEmpty || s.months.contains(today.month)).toList();
  final basePool = seasonal.isNotEmpty ? seasonal : source;
  final pool = [...imminentAll, ...basePool];
  return pool[dayOffset % pool.length];
}
