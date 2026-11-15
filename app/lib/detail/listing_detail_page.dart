part of '../detail_page.dart';

class ListingDetailPage extends StatefulWidget {
  final String listingId;
  final WidgetBuilder homeBuilder;
  final Map<String, dynamic>? initialData;

  const ListingDetailPage({
    super.key,
    required this.listingId,
    required this.homeBuilder,
    this.initialData,
  });

  @override
  State<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends State<ListingDetailPage> {
  Future<Map<String, dynamic>?>? _future;

  // 일정·인원·이벤트 신청 상태 (상세페이지 & 모바일 하단바 공유)
  DateTimeRange? _dateRange;
  int _adults = 2;
  int _children = 0;
  bool _includePromo = true;
  int _localAddedCount = 0;
  int _localAddedScore = 0;

  @override
  void initState() {
    super.initState();
    syncListingUrl(widget.listingId);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));
    _dateRange = DateTimeRange(start: start, end: start.add(const Duration(days: 2)));
    _future = _loadListing();
  }

  Future<Map<String, dynamic>?> _loadListing() async {
    if (widget.initialData != null) return widget.initialData;
    final demo = findDemoListing(widget.listingId);
    if (demo != null) return demo;
    final snap = await FirebaseFirestore.instance.collection('listings').doc(widget.listingId).get();
    return snap.data();
  }

  void _back(BuildContext context) {
    syncListingUrl(null);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: widget.homeBuilder));
    }
  }

  Future<void> _copyShareLink(BuildContext context, String title) async {
    final shareUrl = '${currentSiteOrigin()}/?id=${Uri.encodeComponent(widget.listingId)}';
    await sharePlace(context, title: title, url: shareUrl, lang: appLangNotifier.value);
  }


  Future<void> _pickDates(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lang = appLangNotifier.value;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      helpText: pickLangText(
        lang,
        ko: '체크인 · 체크아웃 날짜 선택',
        en: 'Select Check-in & Check-out Dates',
        ja: 'チェックイン・チェックアウト日を選択',
        zh: '选择入住与退房日期',
      ),
      saveText: pickLangText(lang, ko: '일정 적용', en: 'Apply', ja: '適用', zh: '应用'),
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 940;
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLangNotifier,
      builder: (context, lang, _) {
        if (lang != AppLang.ko && !TranslationStore.isLoaded(lang)) {
          TranslationStore.ensureLoaded(lang);
        }
        return ValueListenableBuilder<int>(
          valueListenable: translationRevisionNotifier,
          builder: (context, _, _) => FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              final data = snap.data;
              final hasData = snap.connectionState == ConnectionState.done && !snap.hasError && data != null;
              return Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 0,
                  shape: const Border(bottom: BorderSide(color: Color(0xFFEBEBEB))),
                  leading: IconButton(tooltip: trUi('back_btn', lang), icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _back(context)),
                  title: Text(
                    hasData
                        ? _tStayTitle(widget.listingId, data, lang)
                        : pickLangText(lang, ko: '숙소 상세', en: 'Stay Details', ja: '宿泊詳細', zh: '住宿详情'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  actions: [
                    const LangSelectorButton(),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<List<String>>(
                      valueListenable: SavedPlaces.ids,
                      builder: (context, saved, _) {
                        final on = saved.contains(widget.listingId);
                        return IconButton(
                          key: const Key('stay_save_btn'),
                          tooltip: on
                              ? pickLangText(lang, ko: '찜 해제', en: 'Unsave', ja: '保存解除', zh: '取消收藏')
                              : pickLangText(lang, ko: '찜하기', en: 'Save', ja: '保存', zh: '收藏'),
                          icon: Icon(on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: on ? const Color(0xFFE11D48) : const Color(0xFF334155)),
                          onPressed: () => SavedPlaces.toggle(widget.listingId),
                        );
                      },
                    ),
                    TextButton.icon(
                      onPressed: () => _copyShareLink(context, (data?['title'] ?? '').toString()),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: Text(pickLangText(lang, ko: '공유하기', en: 'Share', ja: '共有', zh: '分享')),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: Builder(builder: (context) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError || data == null) {
                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(pickLangText(
                          lang,
                          ko: '공개 중인 숙소를 찾을 수 없습니다.',
                          en: 'Listing not found.',
                          ja: '公開中の宿泊施設が見つかりません。',
                          zh: '未找到公开中的住宿。',
                        )),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _back(context),
                          child: Text(pickLangText(lang, ko: '전체 숙소 보기', en: 'Browse All Stays', ja: '宿泊一覧へ', zh: '查看全部住宿')),
                        ),
                      ]),
                    );
                  }
                  return ListView(
                    children: [
                      if (widget.listingId.startsWith('stay_demo_'))
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFFFF8E6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Center(
                            child: Text(
                              pickLangText(
                                lang,
                                ko: '미리보기 데모 화면입니다 · 실제 운영 시 영업신고 대조를 마친 숙소 및 공공 API 선별 정보가 표시됩니다.',
                                en: 'Preview demo listing · Live listings display verified municipal registrations and public API data.',
                                ja: 'デモプレビュー画面です · 本番時は営業届出照合済みの宿泊施設と公的API情報が表示されます。',
                                zh: '此为演示预览页面 · 正式页面展示经官方营业核验与公共API筛选的住宿信息。',
                              ),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF856404)),
                            ),
                          ),
                        ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: ListingDetailBody(
                        listingId: widget.listingId,
                        data: {
                          ...data,
                          if (_localAddedCount > 0) ...{
                            'review_count': ((data['review_count'] as num?)?.toInt() ?? 0) + _localAddedCount,
                            'score_sum': ((data['score_sum'] as num?)?.toInt() ?? 0) + _localAddedScore,
                          },
                        },
                        isOfflineDemo: widget.initialData != null || widget.listingId.startsWith('stay_demo_'),
                        onReviewAdded: (addedScore) => setState(() {
                          _localAddedCount += 1;
                          _localAddedScore += addedScore;
                        }),
                        dateRange: _dateRange,
                        adults: _adults,
                        children: _children,
                        includePromo: _includePromo,
                        onPickDates: () => _pickDates(context),
                        onGuestsChanged: (a, c) => setState(() {
                          _adults = a;
                          _children = c;
                        }),
                        onIncludePromoChanged: (v) => setState(() => _includePromo = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const LegalFooter(),
                ],
              );
            }),
            bottomNavigationBar: (!hasData || isDesktop)
                ? null
                : _MobileStickyBookingBar(
                    listingId: widget.listingId,
                    data: data,
                    dateRange: _dateRange,
                    adults: _adults,
                    children: _children,
                    includePromo: _includePromo,
                    onPickDates: () => _pickDates(context),
                  ),
              );
            },
          ),
        );
      },
    );
  }
}

class ListingDetailBody extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final bool isOfflineDemo;
  final ValueChanged<int>? onReviewAdded;
  final DateTimeRange? dateRange;
  final int adults;
  final int children;
  final bool includePromo;
  final VoidCallback onPickDates;
  final void Function(int adults, int children) onGuestsChanged;
  final ValueChanged<bool> onIncludePromoChanged;

  const ListingDetailBody({
    super.key,
    required this.listingId,
    required this.data,
    this.isOfflineDemo = false,
    this.onReviewAdded,
    required this.dateRange,
    required this.adults,
    required this.children,
    required this.includePromo,
    required this.onPickDates,
    required this.onGuestsChanged,
    required this.onIncludePromoChanged,
  });

  Future<void> _openExternal(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _buildSpecsLine(AppLang lang) {
    final specs = data['room_specs'] is Map ? Map<String, dynamic>.from(data['room_specs'] as Map) : const {};
    final capStd = data['capacity_standard'];
    final capMax = data['capacity_max'];
    final parts = <String>[
      if (capMax != null)
        pickLangText(lang, ko: '최대 $capMax명', en: 'Max $capMax guests', ja: '最大$capMax名', zh: '最多$capMax人')
      else if (capStd != null)
        pickLangText(lang, ko: '기준 $capStd명', en: 'Standard $capStd guests', ja: '基準$capStd名', zh: '标准$capStd人'),
      if (capStd != null && capMax != null && capStd != capMax)
        pickLangText(lang, ko: '(기준 $capStd명)', en: '(Std $capStd)', ja: '（基準$capStd名）', zh: '（标准$capStd人）'),
      if (specs['bedrooms'] != null)
        pickLangText(lang, ko: '침실 ${specs['bedrooms']}개', en: '${specs['bedrooms']} bedroom(s)', ja: '寝室${specs['bedrooms']}', zh: '${specs['bedrooms']}间卧室'),
      if (specs['beds'] != null)
        pickLangText(lang, ko: '침대 ${specs['beds']}개', en: '${specs['beds']} bed(s)', ja: 'ベッド${specs['beds']}', zh: '${specs['beds']}张床'),
      if (specs['bathrooms'] != null)
        pickLangText(lang, ko: '욕실 ${specs['bathrooms']}개', en: '${specs['bathrooms']} bath(s)', ja: 'バスルーム${specs['bathrooms']}', zh: '${specs['bathrooms']}间卫浴'),
    ];
    return parts.join(' · ');
  }

  List<Map<String, String>> _resolveHighlights() {
    final raw = data['highlights'];
    final out = <Map<String, String>>[];
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        if (item is Map) {
          final t = (item['title'] ?? '').toString().trim();
          final sub = (item['subtitle'] ?? '').toString().trim();
          final iconKey = (item['icon_key'] ?? t).toString();
          if (t.isNotEmpty) {
            out.add({'icon_key': iconKey, 'title': t, 'subtitle': sub});
          }
        }
      }
    }
    if (out.isEmpty) {
      final pts = List<String>.from(data['summary_points'] ?? const []);
      for (final p in pts.take(3)) {
        out.add({'icon_key': p, 'title': p, 'subtitle': '호스트 소개 자료에서 확인된 숙소 주요 매력입니다.'});
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 940;
    final images = List<Map<String, dynamic>>.from(
      ((data['images'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final naverReviews = List<Map<String, dynamic>>.from(
      ((data['naver_reviews'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final promoTitle = (data['promo_title'] ?? '').toString().trim();
    final promoDetail = (data['promo_detail'] ?? '').toString().trim();
    final editorialStory = localizedListingStory(data, lang);
    final points = List<String>.from(data['summary_points'] ?? const []);
    final highlights = _resolveHighlights();
    final amenityGroups = resolveAmenityGroups(data);
    final topAmenities = extractTopAmenities(data, limit: 10);
    final totalAmenities = totalAmenityCount(data);
    final unavailable = extractUnavailableAmenities(data);
    final pricing = data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : <String, dynamic>{};
    final specs = data['room_specs'] is Map ? Map<String, dynamic>.from(data['room_specs'] as Map) : <String, dynamic>{};
    final houseRules =
        data['house_rules'] is Map ? Map<String, dynamic>.from(data['house_rules'] as Map) : <String, dynamic>{};
    final locationInfo =
        data['location_info'] is Map ? Map<String, dynamic>.from(data['location_info'] as Map) : <String, dynamic>{};
    final isForeignOnly = data['license_type'] == kForeignOnly;
    final blogUrl = (data['source_blog_url'] ?? '').toString().trim();
    final specsLine = _buildSpecsLine(lang);
    final regionLabel = _tStayRegion(listingId, data, lang);
    final accommType = _tAccommodationType((data['accommodation_type'] ?? '').toString(), lang);

    final bookingCard = _DirectBookingConversionCard(
      listingId: listingId,
      data: data,
      dateRange: dateRange,
      adults: adults,
      children: children,
      includePromo: includePromo,
      onPickDates: onPickDates,
      onGuestsChanged: onGuestsChanged,
      onIncludePromoChanged: onIncludePromoChanged,
    );

    final mainDetailsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 서브타이틀 & 객실 물리 스펙
        Text(
          [
            regionLabel,
            if (accommType.isNotEmpty) accommType,
          ].where((s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF222222)),
        ),
        if (specsLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(specsLine, style: const TextStyle(fontSize: 14.5, color: Color(0xFF555555))),
        ],
        if ((specs['bed_summary'] ?? '').toString().isNotEmpty || (specs['floor_info'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [specs['bed_summary'], specs['floor_info']]
                .where((e) => e != null && e.toString().trim().isNotEmpty)
                .join(' · '),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
        if (data['naver_category'] != null || data['naver_link'] != null) ...[
          const SizedBox(height: 12),
          NaverPlaceInfo(data: data, lang: lang, itemId: listingId),
        ],
        const SizedBox(height: 18),

        // 2. 에어비앤비 '게스트 선호' 스타일 합법 인증 & 수수료 0원 배지 바
        _VerifiedTrustBar(data: data, isForeignOnly: isForeignOnly),
        const SizedBox(height: 24),

        // 3. 호스트 직거래 전용 프로모션 배너 (있는 경우)
        if (promoTitle.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFF0F3), Color(0xFFFFF8F6)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFCCD5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.card_giftcard_rounded, color: kBrand, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickLangText(
                          lang,
                          ko: '호스트 직거래 신청 이벤트 · $promoTitle',
                          en: 'Host Direct Booking Promo · $promoTitle',
                          ja: 'ホスト直接予約特典 · $promoTitle',
                          zh: '房东直订专享优惠 · $promoTitle',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF222222)),
                      ),
                      if (promoDetail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(promoDetail, style: const TextStyle(fontSize: 13.5, color: Color(0xFF495057), height: 1.4)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 4. 3대 핵심 하이라이트 블록
        if (highlights.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFEBEBEB)),
          const SizedBox(height: 22),
          ...highlights.map((h) {
                final th = _tHighlight(h, data, listingId, lang);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(highlightIconFor(h['icon_key'] ?? ''), size: 26, color: const Color(0xFF222222)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(th.title,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: Color(0xFF222222))),
                            if (th.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(th.subtitle, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
        ],

        // 5. 공간 이야기 & 매력 요약
        if (editorialStory.isNotEmpty || points.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFEBEBEB)),
          const SizedBox(height: 24),
          Text(
            pickLangText(lang, ko: '숙소 소개', en: 'About this stay', ja: '宿泊施設のご案内', zh: '住宿介绍'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (editorialStory.isNotEmpty)
            Text(
              editorialStory,
              style: const TextStyle(fontSize: 15, height: 1.75, color: Color(0xFF2B2E33)),
            ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: points
                    .map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('✓ ', style: TextStyle(color: kBrand, fontWeight: FontWeight.bold)),
                              Expanded(child: Text(p, style: const TextStyle(fontSize: 14, height: 1.45))),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (blogUrl.startsWith('http')) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openExternal(blogUrl),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: Text(pickLangText(
                lang,
                ko: '호스트 원문 소개글 보기',
                en: 'Read Original Host Post',
                ja: 'ホストの元記事を見る',
                zh: '查看房东原文介绍',
              )),
            ),
          ],
          const SizedBox(height: 24),
        ],

        // 5-A. 사용자 직접 참여 별점(1~5점) · 이용 후기 섹션
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        UserReviewsSection(
          listingId: listingId,
          data: data,
          lang: lang,
          isOfflineDemo: isOfflineDemo,
          onReviewSubmitted: onReviewAdded,
        ),
        const SizedBox(height: 24),

        // 5-B. 네이버 블로그 검색 보완 후기 섹션 (무단 복제 없이 공식 검색 요약·원문 링크만 연결)
        if (naverReviews.isNotEmpty || (data['naver_search_url'] ?? '').toString().startsWith('http')) ...[
          const Divider(height: 1, color: Color(0xFFEBEBEB)),
          const SizedBox(height: 24),
          _NaverReviewsSection(
            data: data,
            reviews: naverReviews,
            lang: lang,
            onOpenExternal: _openExternal,
          ),
          const SizedBox(height: 24),
        ],

        // 모바일일 때는 예약·신청 위젯을 편의시설 바로 위에 한 번 배치해 전환 접근성을 높인다.
        if (!isDesktop) ...[
          bookingCard,
          const SizedBox(height: 28),
        ],

        // 6. 숙소 편의시설 (Amenity 핵심 섹션)
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '숙소 편의시설', en: 'Amenities', ja: '設備・アメニティ', zh: '住宿设施与服务'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          pickLangText(
            lang,
            ko: '호스트가 제공하는 필수 편의시설과 미제공 시설을 사전에 투명하게 확인하세요.',
            en: 'Check included and unavailable amenities provided by the host in advance.',
            ja: 'ホストが提供する設備・非対応設備を事前にご確認いただけます。',
            zh: '提前透明了解房东提供及未提供的设施与服务。',
          ),
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        if (topAmenities.isEmpty)
          Text(pickLangText(
            lang,
            ko: '등록된 편의시설 상세 정보가 없습니다. 호스트 예약 창구에서 확인해 주세요.',
            en: 'Detailed amenity info is not listed. Please check on the host booking page.',
            ja: '設備詳細情報が登録されていません。ホストの予約窓口でご確認ください。',
            zh: '暂无详细设施信息，请在房东预订页面确认。',
          ))
        else
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: topAmenities
                .map((item) => SizedBox(
                      width: isDesktop ? 290 : (math.max(240, (width - 56) / 2)),
                      child: Row(
                        children: [
                          Icon(amenityIconFor(item), size: 22, color: const Color(0xFF222222)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(item, style: const TextStyle(fontSize: 14.5, color: Color(0xFF222222))),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: unavailable
                .take(2)
                .map((u) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.not_interested_rounded, size: 18, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Text(
                          u,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ))
                .toList(),
          ),
        ],
        if (totalAmenities > 0 || unavailable.isNotEmpty) ...[
          const SizedBox(height: 18),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF222222),
              side: const BorderSide(color: Color(0xFF222222), width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _showAllAmenitiesDialog(context, amenityGroups, unavailable, totalAmenities),
            child: Text(
              pickLangText(
                lang,
                ko: '편의시설 $totalAmenities개 모두 보기',
                en: 'Show all $totalAmenities amenities',
                ja: '設備・アメニティ $totalAmenities件をすべて見る',
                zh: '查看全部 $totalAmenities 项设施',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
          ),
        ],
        const SizedBox(height: 28),

        // 7. 직거래 요금 안내 테이블
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '직거래 기준 요금 안내', en: 'Direct Booking Base Rates', ja: '直接予約 基準料金のご案内', zh: '直订参考房价'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _PricingTableCard(pricing: pricing),
        const SizedBox(height: 28),

        // 8. 숙소 이용규칙 및 체크인 안내
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '알아두어야 할 사항 (숙소 이용규칙)', en: 'Things to Know (House Rules)', ja: 'ご案内事項（ハウスルール）', zh: '入住须知（房屋守则）'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _HouseRulesSection(houseRules: houseRules, isForeignOnly: isForeignOnly),
        const SizedBox(height: 28),

        // 9. 위치 및 주변 안내
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '위치 및 주변 정보', en: 'Location & Nearby', ja: '所在地・周辺案内', zh: '位置与周边信息'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _LocationSection(data: data, locationInfo: locationInfo, listingId: listingId),

        // 9-2. 한국관광공사(locationBasedList2) 반경 5km 공식 주변 명소·맛집
        if ((data['nearby_places'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 24),
          _TourNearbyPlacesSection(
            places: (data['nearby_places'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
            lang: lang,
            onOpenExternal: _openExternal,
          ),
        ],
      ],
    );

    final rating = extractListingRating(data);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 숙소 타이틀 헤더
          if (promoTitle.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFCCD5)),
              ),
              child: Text('🎁 $promoTitle',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBrand)),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _tStayTitle(listingId, data, lang),
                style: TextStyle(fontSize: isDesktop ? 26 : 21, fontWeight: FontWeight.w800, color: const Color(0xFF222222)),
              ),
              if (rating.count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 17, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 3),
                      Text(
                        '${rating.average.toStringAsFixed(1)} (${rating.count})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 에어비앤비 스타일 5분할 벤토 포토 그리드(외부 이미지 URL 링크) 또는 공공숙소 비주얼 히어로
          if (images.isNotEmpty) ...[
            _BentoGallery(images: images, title: _tStayTitle(listingId, data, lang)),
            const SizedBox(height: 28),
          ] else ...[
            _PublicStayVisualHero(data: data, onOpenExternal: _openExternal),
            const SizedBox(height: 28),
          ],

          // 데스크톱 2단 레이아웃 vs 모바일 단일 컬럼
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: mainDetailsColumn),
                const SizedBox(width: 48),
                SizedBox(width: 372, child: bookingCard),
              ],
            )
          else
            mainDetailsColumn,
        ],
      ),
    );
  }
}
