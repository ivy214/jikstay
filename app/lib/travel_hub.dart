// 한국관광공사(TourAPI KorService2) + 정부·지자체 공식 웹진 + 2026 반값여행·외국인 혜택 통합 허브 화면.
// - 앱 번들 크기를 늘리지 않기 위해 정적 빌드된 허브 핵심 데이터(/data/hub/core.json)를 탭 진입 시 지연 로드한다.
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'detail_page.dart' show StorageImage, kBrand;
import 'hub_details.dart';
import 'i18n.dart';

const List<Map<String, dynamic>> _kFallbackHalfPriceRegions = [
  {
    'region_group': '강원',
    'cities': ['평창', '영월', '횡성', '화천'],
    'benefit_ko': '여행경비 50% 지역화폐 환급 (1인 최대 10만원 · 2인 이상 최대 20만원)',
    'benefit_en': '50% Travel Cashback + K-Tourism Digital Pass up to 50% instant discounts',
  },
  {
    'region_group': '전라/충청',
    'cities': ['강진', '해남', '완도', '고흥', '영광', '영암', '장흥', '고창', '제천', '태안', '서천'],
    'benefit_ko': '여행경비 50% 환급 (청년 일부 최대 70%) · 지자체 인정 업소 영수증 필수',
    'benefit_en': '50% Stay & Dining Cashback + Digital Resident Pass partner perks',
  },
  {
    'region_group': '부산/경상',
    'cities': ['남해', '하동', '밀양', '합천', '거창', '고성', '산청', '함양', '안동', '영천'],
    'benefit_ko': '여행 전 사전신청 필수 · 숙박·식비·체험 영수증 정산 후 모바일 지역화폐 지급',
    'benefit_en': 'Pre-registration Regional Subsidy + Traditional Hanok & Local Stay Perks',
  },
];

const List<Map<String, dynamic>> _kFallbackBenefits = [
  {
    'badge': 'FOREIGNER & LOCAL · 최대 50% 즉시할인',
    'official_url': 'https://korean.visitkorea.or.kr/digtCard/digt_card_intro.do',
    'ko': {
      'title': '디지털 관광주민증 (한국관광공사 공식)',
      'desc': '인구감소지역 35개+ 시·군 방문 시 숙박·관람·케이블카·체험 최대 10~50% 현장 즉시 할인! 내·외국인 모두 모바일 무료 발급.',
    },
    'en': {
      'title': 'K-Tourism Digital Resident Card (Official KTO Pass)',
      'desc': 'Free mobile pass for international & local visitors! Enjoy 10–50% instant discounts on stays, cable cars & museums in 35+ Korean towns.',
    },
    'ja': {
      'title': 'デジタル観光住民証（韓国観光公社公式パス）',
      'desc': '外国人旅行者も無料発行可能！韓国地方35以上の市・郡で宿泊・ケーブルカー・体験が最大50%即時割引。',
    },
    'zh': {
      'title': '數位觀光居民證（韓國觀光公社官方通行證）',
      'desc': '外國旅客亦可免費申辦！走訪韓國35個以上特色市郡，享住宿、纜車、景點最高50%現場折扣。',
    },
  },
  {
    'badge': '2026 정부·지자체 지원 · 50% 환급',
    'official_url': 'https://korean.visitkorea.or.kr',
    'ko': {
      'title': '2026 대한민국 반값여행 (25개 지자체 50% 환급)',
      'desc': '여행 전 사전신청 후 지자체가 인정한 숙소·식당 영수증을 제출하면 지출액의 50%(2인 최대 20만원)를 지역화폐로 환급받습니다. (미신고 불법숙소 영수증 제외)',
    },
    'en': {
      'title': '2026 Half-Price Regional Travel & Foreigner FIT Perks',
      'desc': '25 municipalities offer 50% travel cashback for pre-registered residents, plus regional stay vouchers & Korea Grand Sale perks for international guests.',
    },
    'ja': {
      'title': '2026 半額旅行支援＆外国人FIT自治体ステイ特典',
      'desc': '25自治体で事前申請による旅費50%還元を実施。外国人個人旅行客向けにも自治体宿泊クーポン等を提供（※宿泊の領収書必須）。',
    },
    'zh': {
      'title': '2026 韓國半價旅遊補助＆外國自由行地方住宿優惠',
      'desc': '25個地方政府推出旅費50%回饋，並針對外國自由行旅客提供地方住宿優惠券（※須入住合法認證民宿以取得收據）。',
    },
  },
];

const List<Map<String, String>> _kFallbackMagazines = [
  {
    'publisher': '문화체육관광부',
    'title': '대한민국 정책주간지 《K-공감》 e-Book·웹진',
    'region_group': '전체',
    'desc': '정부가 매주 발행하는 공식 시사·생활정책·로컬 여행 교양잡지 무료 열람',
    'url': 'https://gonggam.korea.kr',
    'lang_badge': 'KO',
  },
  {
    'publisher': '한국관광공사',
    'title': '대한민국 구석구석 《여행기사 & 월간 테마매거진》',
    'region_group': '전체',
    'desc': '전국 숨은 로컬 명소, 계절별 축제, 반값여행·디지털 관광주민증 공식 특집호',
    'url': 'https://korean.visitkorea.or.kr/list/travelinfo.do?service=ms',
    'lang_badge': 'KO',
  },
  {
    'publisher': 'Korea Tourism Organization',
    'title': 'VisitKorea Global Travel Magazine & News',
    'region_group': '전체',
    'desc': 'Official multilingual travel magazines, K-food & Hanok stay stories for global visitors',
    'url': 'https://english.visitkorea.or.kr',
    'lang_badge': 'EN · JA · ZH',
  },
];

class PublicTravelHubView extends StatefulWidget {
  final AppLang lang;
  final void Function(String regionGroup, String cityKeyword) onSelectCityForStays;

  const PublicTravelHubView({
    super.key,
    required this.lang,
    required this.onSelectCityForStays,
  });

  @override
  State<PublicTravelHubView> createState() => _PublicTravelHubViewState();
}

class _PublicTravelHubViewState extends State<PublicTravelHubView> {
  static Map<String, dynamic>? _cachedHub;
  Map<String, dynamic>? _hub;
  bool _loading = true;
  String _regionFilter = '전체';

  @override
  void initState() {
    super.initState();
    if (_cachedHub != null) {
      _hub = _cachedHub;
      _loading = false;
    } else {
      _loadHub();
    }
  }

  Future<void> _loadHub() async {
    final res = await fetchHubCore();
    if (!mounted) return;
    setState(() {
      _cachedHub = res;
      _hub = res;
      _loading = false;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _fmtYmd(String raw) {
    if (raw.length == 8) {
      return '${raw.substring(0, 4)}.${raw.substring(4, 6)}.${raw.substring(6, 8)}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final benefits = (_hub?['global_benefits'] as List?)?.whereType<Map>().toList() ?? _kFallbackBenefits;
    final halfRegions = (_hub?['half_price_regions'] as List?)?.whereType<Map>().toList() ?? _kFallbackHalfPriceRegions;
    final allFestivals = (_hub?['festivals'] as List?)?.whereType<Map>().toList() ?? const [];
    final allCourses = (_hub?['courses'] as List?)?.whereType<Map>().toList() ?? const [];
    final allMagazines = (_hub?['public_magazines'] as List?)?.whereType<Map>().toList() ?? _kFallbackMagazines;
    final municipalEbooks = (_hub?['municipal_ebooks'] as List?)?.whereType<Map>().toList() ?? const [];
    final subsidyGuides = (_hub?['subsidy_guides'] as List?)?.whereType<Map>().toList() ?? const [];

    final festivals = _regionFilter == '전체'
        ? allFestivals
        : allFestivals.where((f) => f['region_group'] == _regionFilter).toList();
    final courses = _regionFilter == '전체'
        ? allCourses
        : allCourses.where((c) => c['region_group'] == _regionFilter || c['region_group'] == '전체').toList();
    final magazines = _regionFilter == '전체'
        ? allMagazines
        : allMagazines.where((m) => m['region_group'] == _regionFilter || m['region_group'] == '전체').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 헤더 배너
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        lang == AppLang.ko
                            ? '한국관광공사 TourAPI · 문체부 · 지자체 공공데이터 (주 1회 갱신)'
                            : 'Official Korea Tourism (KTO) · Gov Subsidies · Local Webzines',
                        style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      lang == AppLang.ko
                          ? '2026 반값여행 지원금 · 전국 축제 · 정부/지자체 매거진'
                          : lang == AppLang.ja
                              ? '2026 韓国旅行50%割引パス・地域祭り・自治体公式マガジン'
                              : lang == AppLang.zh
                                  ? '2026 韓國旅遊半價補助・地方慶典・政府官方旅遊雜誌'
                                  : '2026 Korea 50% Travel Pass · Festivals · Official Magazines',
                      style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lang == AppLang.ko
                          ? '원하는 혜택 지역이나 축제 도시를 누르면 영수증 정산이 가능한 해당 지역의 공공데이터 등록 숙소로 바로 연결됩니다.'
                          : 'Tap any subsidy town or festival below to filter verified legal stays eligible for official receipts & tourist discounts.',
                      style: const TextStyle(color: Color(0xFFDBEAFE), fontSize: 13.5, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 권역 필터 바
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['전체', '제주', '강원', '부산/경상', '전라/충청', '서울/경기'].map((rg) {
                  final sel = _regionFilter == rg;
                  return ChoiceChip(
                    label: Text(trRegion(rg, lang)),
                    selected: sel,
                    selectedColor: const Color(0xFF222222),
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : const Color(0xFF222222),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    onSelected: (_) => setState(() => _regionFilter = rg),
                  );
                }).toList(),
              ),
              const SizedBox(height: 26),

              // 2. 내·외국인 핵심 여행 지원제도 TOP 3 카드
              Text(
                lang == AppLang.ko ? '💡 놓치면 아까운 정부·관광공사 공식 여행 혜택' : '💡 Official Tourist Discounts & Travel Passes',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF222222)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: benefits.map((b) {
                  final localized = (b[lang.code] as Map?) ?? (b['ko'] as Map?) ?? const {};
                  final url = (b['official_url'] ?? '').toString();
                  return ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (b['badge'] ?? '').toString(),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kBrand),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            (localized['title'] ?? '').toString(),
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            (localized['desc'] ?? '').toString(),
                            style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.5),
                          ),
                          if (url.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                              onPressed: () => _openUrl(url),
                              icon: const Icon(Icons.open_in_new_rounded, size: 15),
                              label: Text(lang == AppLang.ko ? '공식 안내 페이지 열기' : 'Official Guide'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // 3. 2026 반값여행 25개 대상 시·군 원클릭 숙소 매칭 & 사전신청 가이드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang == AppLang.ko
                          ? '🗺️ 2026 반값여행(50% 환급) 25개 대상 지역 — 클릭 시 해당 지역 숙소 바로 검색'
                          : '🗺️ 25 Half-Price / Digital-Pass Towns — Tap a Town to Find Stays',
                      style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lang == AppLang.ko
                          ? '절차: ① 여행 전 대한민국 구석구석·지자체 누리집 사전신청 → ② 승인 후 여행 → ③ 인정 숙소·식당 영수증 제출 → ④ 50%(최대 20만원) 모바일 지역화폐 환급'
                          : 'How it works: Pre-register online (or activate K-Tourism Digital Resident Card for instant foreigner discounts) → Stay at a qualifying property → Claim up to 50% perks!',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF78350F), height: 1.45),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pickLangText(lang,
                          ko: '※ 2026년 공고 기준 요약입니다. 대상 지역·환급률·한도·인정 업소는 지자체마다 다르고 바뀔 수 있으니 신청 전 공식 누리집에서 꼭 확인하세요.',
                          en: '* Summary of 2026 notices. Eligible towns, rates, caps and qualifying businesses vary by city and may change — check the official site before applying.',
                          ja: '※2026年の公告に基づく要約です。対象地域・還付率・上限は自治体ごとに異なり変更される場合があります。申請前に公式サイトで必ずご確認ください。',
                          zh: '※ 依2026年公告整理。適用地區、退還比例與上限各地不同且可能變動，申請前請至官方網站確認。'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    ...halfRegions.map((grp) {
                      final rg = (grp['region_group'] ?? '').toString();
                      final cities = (grp['cities'] as List? ?? const []).map((e) => e.toString()).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${trRegion(rg, lang)} (${lang == AppLang.ko ? grp['benefit_ko'] : grp['benefit_en']})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: cities
                                  .map((city) => ActionChip(
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: Color(0xFFF59E0B)),
                                        avatar: const Icon(Icons.home_work_outlined, size: 15, color: Color(0xFFD97706)),
                                        label: Text(
                                          lang == AppLang.ko ? '$city 숙소' : '$city Stays',
                                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                        ),
                                        onPressed: () => widget.onSelectCityForStays(rg, city),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (subsidyGuides.isNotEmpty) ...[
                      const Divider(color: Color(0xFFFDE68A), height: 22),
                      Text(
                        lang == AppLang.ko ? '📌 반값여행 · 지자체 숙박지원 실전 신청 가이드 모음 (네이버 공개 글)' : '📌 Detailed Application Guides (Korean Blog Posts)',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                      ),
                      const SizedBox(height: 8),
                      ...subsidyGuides.take(4).map((g) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: () => _openUrl((g['link'] ?? '').toString()),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (g['tag'] ?? '가이드').toString(),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      (g['title'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1D4ED8),
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF6B7280)),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 4. 한국관광공사 실시간 지역 축제·행사 (searchFestival2)
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (festivals.isNotEmpty) ...[
                Text(
                  lang == AppLang.ko ? '🎉 지금 열리는 · 다가오는 지역 축제 & 행사 (한국관광공사)' : '🎉 Current & Upcoming Regional Festivals (Official KTO)',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 270,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: festivals.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, idx) {
                      final f = festivals[idx];
                      final rg = (f['region_group'] ?? '전체').toString();
                      final city = (f['search_city'] ?? '').toString();
                      return SizedBox(
                        width: 245,
                        child: Card(
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 132,
                                width: double.infinity,
                                child: StorageImage(
                                  url: (f['image_url'] ?? '').toString(),
                                  cacheWidth: 420,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(11),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${f['region_label']} · ${_fmtYmd((f['start_date'] ?? '').toString())}~${_fmtYmd((f['end_date'] ?? '').toString())}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (f['title'] ?? '').toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                      ),
                                      const Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          InkWell(
                                            onTap: () => _openUrl((f['map_url'] ?? '').toString()),
                                            child: Text(
                                              lang == AppLang.ko ? '위치 보기' : 'Map',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => widget.onSelectCityForStays(rg, city),
                                            child: Text(
                                              lang == AppLang.ko ? '주변 숙소 찾기 →' : 'Nearby Stays →',
                                              style: const TextStyle(fontSize: 12, color: kBrand, fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
              ],

              // 5. 한국관광공사 공식 추천 여행코스 매거진 (contentTypeId=25)
              if (courses.isNotEmpty) ...[
                Text(
                  lang == AppLang.ko ? '🧭 한국관광공사 추천 로컬 여행코스 매거진' : '🧭 Official KTO Recommended Travel Courses',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 12),
                ...courses.take(6).map((c) {
                  final stops = (c['stops'] as List? ?? const []).map((e) => e.toString()).toList();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 112,
                            height: 92,
                            child: StorageImage(
                              url: (c['image_url'] ?? '').toString(),
                              cacheWidth: 320,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (c['region_label'] ?? c['region_group'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: () => _openUrl((c['article_url'] ?? '').toString()),
                                    child: Text(
                                      lang == AppLang.ko ? '코스 상세 열람 ↗' : 'Read Course ↗',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                (c['title'] ?? '').toString(),
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (c['overview'] ?? '').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF4B5563), height: 1.45),
                              ),
                              if (stops.isNotEmpty) ...[
                                const SizedBox(height: 7),
                                Text(
                                  '코스 동선: ${stops.join(' → ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 28),
              ],

              // 6. 전국 17개 시·도 및 시·군 지자체 관광안내도 PDF / E-book 아카이브
              if (municipalEbooks.isNotEmpty) ...[
                Text(
                  lang == AppLang.ko
                      ? '🗺️ 전국 17개 시·도 지자체 공식 관광안내도 · E-book 즉시 열람'
                      : '🗺️ All 17 Provinces Official Tourist Maps & PDF Guidebooks',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 6),
                Text(
                  lang == AppLang.ko
                      ? '회원가입 없이 각 시·도 및 군청 문화관광 누리집의 고화질 관광지도 PDF와 E-book 뷰어를 바로 엽니다.'
                      : 'No sign-up needed — open official high-resolution PDF maps and e-guidebooks directly.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: municipalEbooks.map((eb) {
                    final pdfLinks = (eb['pdf_links'] as List? ?? const []).whereType<Map>().toList();
                    return ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 250, maxWidth: 355),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openUrl((eb['url'] ?? '').toString()),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${eb['province'] ?? ''} · ${eb['city'] ?? ''}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (eb['title'] ?? '').toString(),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (eb['materials'] ?? '').toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                              ),
                              if (pdfLinks.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: pdfLinks.map((pl) {
                                    final lbl = lang == AppLang.ko
                                        ? (pl['label'] ?? 'PDF 열람').toString()
                                        : ((pl['label_en'] ?? pl['label'] ?? 'Open PDF').toString());
                                    return ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(color: Color(0xFF93C5FD)),
                                      label: Text(
                                        lbl,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                                      ),
                                      onPressed: () => _openUrl((pl['url'] ?? '').toString()),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
              ],

              // 7. 정부·지자체 공식 발행 잡지·웹진·e-Book 열람관
              Text(
                lang == AppLang.ko ? '📖 정부 · 지자체 발행 공식 잡지 & 관광 e-북 무료 열람관' : '📖 Free Government & Municipal Official Travel Magazines (e-Books)',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF222222)),
              ),
              const SizedBox(height: 6),
              Text(
                lang == AppLang.ko
                    ? '문화체육관광부 주간지 《K-공감》과 각 광역지자체가 공공누리로 무료 개방한 공식 웹진·가이드북을 광고 없이 열람하세요.'
                    : 'Browse official government magazines and multilingual regional e-guidebooks published by MCST, KTO, and local tourism boards.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: magazines.map((m) {
                  return ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openUrl((m['url'] ?? '').toString()),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFD1D5DB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (m['publisher'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F766E)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    (m['lang_badge'] ?? 'KO').toString(),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              (m['title'] ?? '').toString(),
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              (m['desc'] ?? '').toString(),
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF4B5563), height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  lang == AppLang.ko ? '무료 웹진·e-Book 열람하기' : 'Open Official Webzine',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF2563EB)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
