part of '../discovery_models.dart';

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
