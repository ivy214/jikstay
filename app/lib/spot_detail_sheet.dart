// 축제·볼거리·먹거리·지자체 E-book·숙소 상세 연결 시트 (방문 쿠폰 CPC 유도 + 주변 동선 자동 연결 + 별점·후기).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'detail_page.dart' show StorageImage, validateUserReviewInput;
import 'discovery_models.dart';
import 'i18n.dart';
import 'web_utils.dart';

Future<void> recordOutboundVisitClick(DiscoveryItem item, {bool offlineMode = false}) async {
  if (offlineMode || item.category == DiscoveryCategory.ebook) return;
  final colName = item.category == DiscoveryCategory.stay ? 'listings' : 'spots';
  try {
    await FirebaseFirestore.instance
        .collection(colName)
        .doc(item.id)
        .update({'outbound_clicks': FieldValue.increment(1)})
        .timeout(const Duration(seconds: 2));
  } catch (_) {}
}

class SpotDetailSheet extends StatefulWidget {
  final DiscoveryItem item;
  final List<DiscoveryItem> allItems;
  final AppLang lang;
  final bool offlineMode;
  final ValueChanged<DiscoveryItem> onSelectConnectedItem;
  final ValueChanged<String>? onOpenFullStayPage;
  final ValueChanged<String>? onOpenStoryPage;
  final void Function(String itemId, int reviewCount, int scoreSum)? onStatsUpdated;

  const SpotDetailSheet({
    super.key,
    required this.item,
    required this.allItems,
    required this.lang,
    required this.onSelectConnectedItem,
    this.offlineMode = false,
    this.onOpenFullStayPage,
    this.onOpenStoryPage,
    this.onStatsUpdated,
  });

  @override
  State<SpotDetailSheet> createState() => _SpotDetailSheetState();
}

class _SpotDetailSheetState extends State<SpotDetailSheet> {
  late DiscoveryItem _current;
  int _selectedScore = 5;
  final TextEditingController _nickCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submittingReview = false;
  List<Map<String, dynamic>> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _current = widget.item;
    trackPortalEvent('view_spot_sheet', {
      'item_id': _current.id,
      'category': _current.category.name,
      'province': _current.province,
    });
    _loadReviews();
  }

  @override
  void didUpdateWidget(covariant SpotDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _current = widget.item;
      _reviews = const [];
      trackPortalEvent('view_spot_sheet', {
        'item_id': _current.id,
        'category': _current.category.name,
        'province': _current.province,
      });
      _loadReviews();
    }
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    if (widget.offlineMode || _current.category == DiscoveryCategory.ebook) return;
    final colName = _current.category == DiscoveryCategory.stay ? 'listings' : 'spots';
    try {
      final snap = await FirebaseFirestore.instance
          .collection(colName)
          .doc(_current.id)
          .collection('reviews')
          .orderBy('created_at', descending: true)
          .limit(15)
          .get();
      if (!mounted) return;
      setState(() {
        _reviews = snap.docs.map((d) => d.data()).toList();
      });
    } catch (_) {}
  }

  Future<void> _openExternal(String rawUrl, {bool trackClick = true, String eventTag = 'external_open'}) async {
    trackPortalEvent(eventTag, {
      'item_id': _current.id,
      'province': _current.province,
      'url': rawUrl,
    });
    if (trackClick) {
      await recordOutboundVisitClick(_current, offlineMode: widget.offlineMode);
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'tel')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showVisitCouponDialog() {
    trackPortalEvent('claim_visit_coupon', {
      'item_id': _current.id,
      'province': _current.province,
      'title': _current.title,
    });
    recordOutboundVisitClick(_current, offlineMode: widget.offlineMode);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Text('🎁 ', style: TextStyle(fontSize: 22)),
            Expanded(
              child: Text(
                widget.lang == AppLang.ko ? '직스테이 로컬 방문 혜택 쿠폰' : 'JikStay Local Visit Coupon',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _current.title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _current.couponTitle.isNotEmpty
                        ? _current.couponTitle
                        : '현장 방문 시 직스테이 로컬 화면을 제시해 주세요.',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF78350F)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.lang == AppLang.ko
                  ? '• 별도 회원가입이나 수수료 결제 없이 현장 주문·체크인 시 이 화면을 보여주시면 됩니다.\n• 아래 길찾기 버튼으로 위치를 바로 확인하세요.'
                  : '• No sign-up or booking fee required. Simply show this screen upon arrival.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(widget.lang == AppLang.ko ? '닫기' : 'Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openExternal(_current.mapUrl, trackClick: false);
            },
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: Text(trUi('directions_btn', widget.lang)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReview() async {
    final err = validateUserReviewInput(
      nickname: _nickCtrl.text,
      comment: _commentCtrl.text,
      score: _selectedScore,
    );
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_validation_err', widget.lang))),
      );
      return;
    }

    final nick = _nickCtrl.text.trim();
    final comment = _commentCtrl.text.trim();
    setState(() => _submittingReview = true);

    try {
      if (!widget.offlineMode) {
        final isStay = _current.category == DiscoveryCategory.stay;
        final colName = isStay ? 'listings' : 'spots';
        final idField = isStay ? 'listing_id' : 'spot_id';
        final docRef = FirebaseFirestore.instance.collection(colName).doc(_current.id);
        final revRef = docRef.collection('reviews').doc();

        final batch = FirebaseFirestore.instance.batch();
        batch.set(revRef, {
          idField: _current.id,
          'nickname': nick,
          'score': _selectedScore,
          'comment': comment,
          'lang': widget.lang.code,
          'created_at': FieldValue.serverTimestamp(),
        });
        batch.update(docRef, {
          'review_count': FieldValue.increment(1),
          'score_sum': FieldValue.increment(_selectedScore),
          'last_review_id': revRef.id,
        });
        await batch.commit();
      }

      if (!mounted) return;
      final nextCount = _current.reviewCount + 1;
      final nextSum = _current.scoreSum + _selectedScore;
      setState(() {
        _current = _current.copyWithStats(reviewCount: nextCount, scoreSum: nextSum);
        _reviews = [
          {
            'nickname': nick,
            'score': _selectedScore,
            'comment': comment,
            'lang': widget.lang.code,
          },
          ..._reviews,
        ];
        _nickCtrl.clear();
        _commentCtrl.clear();
        _submittingReview = false;
      });
      trackPortalEvent('submit_review', {
        'item_id': _current.id,
        'province': _current.province,
        'score': _selectedScore,
      });
      widget.onStatsUpdated?.call(_current.id, nextCount, nextSum);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_submitted', widget.lang))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submittingReview = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 오프라인/미동기화 항목이거나 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  String _fmtDateRange(String s, String e) {
    String fmt(String d) => d.length == 8 ? '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6, 8)}' : d;
    if (s.isEmpty && e.isEmpty) return '';
    if (e.isEmpty) return fmt(s);
    return '${fmt(s)} ~ ${fmt(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final bundle = buildConnectedBundle(_current, widget.allItems);
    final dateRange = _fmtDateRange(_current.startDate, _current.endDate);

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // 상단 드래그 핸들 + 닫기
              Row(
                children: [
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),

              // 대표 이미지
              if (_current.imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: StorageImage(url: _current.imageUrl, cacheWidth: 720),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // 배지 행
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _current.category.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_current.categoryEmoji} ${_current.province} · ${_current.categoryBadgeText(lang)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _current.category.color),
                    ),
                  ),
                  if (_current.isSponsored)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '🎁 지역 상생 추천 · 방문혜택',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                      ),
                    ),
                  if (_current.reviewCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '★ ${_current.averageRating.toStringAsFixed(1)} (${_current.reviewCount})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // 제목 및 주소/일정
              Text(
                _current.title,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              if (dateRange.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '📅 행사 기간: $dateRange',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED)),
                  ),
                ),
              if (_current.address.isNotEmpty)
                Text(
                  '📍 ${_current.address}',
                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569), height: 1.45),
                ),
              if (_current.subtitle.isNotEmpty && _current.subtitle != _current.address) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _current.subtitle,
                    style: const TextStyle(fontSize: 14.5, color: Color(0xFF1E293B), height: 1.78),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // 방문 유도 CTA 박스 (1단: 핵심 상세·혜택 / 2단: 정돈된 길찾기 바)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_current.couponTitle.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Text(
                          '🎁 ${_current.couponTitle}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                    if ((_current.raw['is_story'] == true && widget.onOpenStoryPage != null) ||
                        _current.pdfLinks.isNotEmpty ||
                        (_current.category == DiscoveryCategory.ebook && _current.externalUrl.isNotEmpty) ||
                        _current.isSponsored ||
                        _current.couponTitle.isNotEmpty ||
                        (_current.category == DiscoveryCategory.stay && widget.onOpenFullStayPage != null)) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_current.raw['is_story'] == true && widget.onOpenStoryPage != null)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onOpenStoryPage!(_current.id);
                              },
                              icon: const Icon(Icons.auto_stories_rounded, size: 18),
                              label: Text(lang == AppLang.ko ? '스토리 전체 페이지 읽기' : 'Read Full Story'),
                            ),
                          if (_current.pdfLinks.isNotEmpty)
                            ..._current.pdfLinks.map((pl) => FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                                  onPressed: () => _openExternal(
                                    pl.url,
                                    trackClick: false,
                                    eventTag: 'open_municipal_pdf',
                                  ),
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
                                  label: Text(pl.localizedLabel(lang)),
                                ))
                          else if (_current.category == DiscoveryCategory.ebook && _current.externalUrl.isNotEmpty)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                              onPressed: () => _openExternal(
                                _current.externalUrl,
                                trackClick: false,
                                eventTag: 'open_municipal_pdf',
                              ),
                              icon: const Icon(Icons.menu_book_rounded, size: 18),
                              label: Text(trUi('open_ebook_btn', lang)),
                            ),
                          if (_current.isSponsored || _current.couponTitle.isNotEmpty)
                            FilledButton.icon(
                              key: const Key('sheet_coupon_btn'),
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                              onPressed: _showVisitCouponDialog,
                              icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                              label: Text(trUi('coupon_action_btn', lang)),
                            ),
                          if (_current.category == DiscoveryCategory.stay && widget.onOpenFullStayPage != null)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onOpenFullStayPage!(_current.id);
                              },
                              icon: const Icon(Icons.cottage_rounded, size: 18),
                              label: Text(lang == AppLang.ko ? '숙소 상세 · 직거래 창구 열기' : 'Open Full Stay Page'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      lang == AppLang.ko ? '길찾기 · 대중교통 경로' : 'Directions & Public Transit',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('sheet_directions_btn'),
                          onPressed: () => _openExternal(_current.naverRouteUrl, eventTag: 'click_transit_naver'),
                          icon: const Icon(Icons.map_outlined, size: 17, color: Color(0xFF03C75A)),
                          label: Text(lang == AppLang.ko ? '🟢 네이버지도 · 길찾기' : '🟢 Naver Map'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('sheet_kakao_route_btn'),
                          onPressed: () => _openExternal(_current.kakaoRouteUrl, eventTag: 'click_transit_kakao'),
                          icon: const Icon(Icons.directions_bus_filled_rounded, size: 17, color: Color(0xFFD97706)),
                          label: Text(lang == AppLang.ko ? '🟡 카카오 대중교통 · 내비' : '🟡 Kakao Transit'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('sheet_google_transit_btn'),
                          onPressed: () => _openExternal(_current.googleTransitUrl, eventTag: 'click_transit_google'),
                          icon: const Icon(Icons.train_rounded, size: 17, color: Color(0xFF2563EB)),
                          label: Text(lang == AppLang.ko ? '🔵 Google 대중교통' : '🔵 Google Transit'),
                        ),
                        if (_current.phone.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _openExternal('tel:${_current.phone.replaceAll(' ', '')}', eventTag: 'click_phone'),
                            icon: const Icon(Icons.call_outlined, size: 18),
                            label: Text(_current.phone),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 해당 지자체 공식 관광지도 / E-book 원클릭 배너 (비 E-book 항목일 때 자동 연결)
              if (_current.category != DiscoveryCategory.ebook && bundle.ebooks.isNotEmpty) ...[
                Text(
                  lang == AppLang.ko
                      ? '📖 ${_current.province} 지자체 발행 공식 관광지도 · 가이드북 (원본 PDF 즉시 열람)'
                      : '📖 Official ${_current.province} Municipal Tourist Maps & Direct PDFs',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                ...bundle.ebooks.map((eb) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.menu_book_rounded, color: Color(0xFF2563EB), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      eb.title,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
                                    ),
                                    if (eb.address.isNotEmpty)
                                      Text(
                                        eb.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF3B82F6)),
                                      ),
                                  ],
                                ),
                              ),
                              if (eb.pdfLinks.isEmpty) ...[
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: () => _openExternal(
                                    eb.externalUrl,
                                    trackClick: false,
                                    eventTag: 'open_municipal_pdf',
                                  ),
                                  child: Text(lang == AppLang.ko ? '바로 열람' : 'Open PDF'),
                                ),
                              ],
                            ],
                          ),
                          if (eb.pdfLinks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: eb.pdfLinks
                                  .map((pl) => FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: () => _openExternal(
                                          pl.url,
                                          trackClick: false,
                                          eventTag: 'open_municipal_pdf',
                                        ),
                                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                        label: Text(
                                          pl.localizedLabel(lang),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    )),
                const SizedBox(height: 14),
              ],

              // 자연스럽게 이어지는 주변 연결 코스 (축제 + 먹거리 + 볼거리 + 안심숙소)
              if (bundle.totalNearbyCount > 0) ...[
                Text(
                  '🔗 ${trUi('connected_course_title', lang)}',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  lang == AppLang.ko
                      ? '카드를 누르면 해당 장소의 상세 안내와 지도로 자연스럽게 이동합니다.'
                      : 'Tap any nearby place to jump directly on the map.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                _ConnectedHorizontalRow(
                  title: lang == AppLang.ko ? '🍲 근처 로컬 먹거리 · 맛집' : '🍲 Nearby Local Food',
                  items: bundle.foods,
                  anchor: _current,
                  onTap: (it) {
                    setState(() => _current = it);
                    widget.onSelectConnectedItem(it);
                  },
                ),
                _ConnectedHorizontalRow(
                  title: lang == AppLang.ko ? '🏞️ 함께 들를 볼거리 · 명소' : '🏞️ Nearby Attractions',
                  items: bundle.attractions,
                  anchor: _current,
                  onTap: (it) {
                    setState(() => _current = it);
                    widget.onSelectConnectedItem(it);
                  },
                ),
                _ConnectedHorizontalRow(
                  title: lang == AppLang.ko ? '🎉 주변 진행·예정 축제' : '🎉 Nearby Festivals & Events',
                  items: bundle.events,
                  anchor: _current,
                  onTap: (it) {
                    setState(() => _current = it);
                    widget.onSelectConnectedItem(it);
                  },
                ),
                _ConnectedHorizontalRow(
                  title: lang == AppLang.ko ? '🏡 근처 합법 인증 안심숙소' : '🏡 Nearby Gov-Verified Stays',
                  items: bundle.stays,
                  anchor: _current,
                  onTap: (it) {
                    setState(() => _current = it);
                    widget.onSelectConnectedItem(it);
                  },
                ),
                const SizedBox(height: 12),
              ],

              // 방문자 별점 & 한줄 후기 (E-book 제외 모든 장소 지원)
              if (_current.category != DiscoveryCategory.ebook) ...[
                const Divider(height: 28),
                Text(
                  '⭐ ${trUi('user_reviews_title', lang)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (int s = 1; s <= 5; s++)
                            IconButton(
                              key: Key('spot_star_$s'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              onPressed: () => setState(() => _selectedScore = s),
                              icon: Icon(
                                s <= _selectedScore ? Icons.star_rounded : Icons.star_border_rounded,
                                color: const Color(0xFFF59E0B),
                                size: 26,
                              ),
                            ),
                          const SizedBox(width: 6),
                          Text('$_selectedScore.0 / 5.0',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: TextField(
                              key: const Key('spot_review_nick'),
                              controller: _nickCtrl,
                              decoration: InputDecoration(
                                hintText: trUi('nickname_label', lang),
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const Key('spot_review_comment'),
                              controller: _commentCtrl,
                              decoration: InputDecoration(
                                hintText: lang == AppLang.ko ? '방문 후기 한줄 (4자 이상)' : 'Short visit tip (4+ chars)',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key('spot_review_submit'),
                            onPressed: _submittingReview ? null : _submitReview,
                            child: Text(lang == AppLang.ko ? '등록' : 'Post'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_reviews.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final rev in _reviews)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '★ ${(rev['score'] ?? 5)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${rev['nickname'] ?? '방문자'}: ${rev['comment'] ?? ''}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConnectedHorizontalRow extends StatelessWidget {
  final String title;
  final List<DiscoveryItem> items;
  final DiscoveryItem anchor;
  final ValueChanged<DiscoveryItem> onTap;

  const _ConnectedHorizontalRow({
    required this.title,
    required this.items,
    required this.anchor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
          const SizedBox(height: 8),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final it = items[i];
                final dist = haversineKm(anchor.lat, anchor.lng, it.lat, it.lng);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(it),
                  child: Container(
                    width: 235,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: it.isSponsored ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 66,
                            height: 76,
                            child: it.imageUrl.isNotEmpty
                                ? StorageImage(url: it.imageUrl, cacheWidth: 220)
                                : Container(
                                    color: it.category.color.withValues(alpha: 0.1),
                                    alignment: Alignment.center,
                                    child: Icon(it.category.icon, color: it.category.color, size: 24),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (it.isSponsored)
                                const Text(
                                  '🎁 방문혜택',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                ),
                              Text(
                                it.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${dist < 1.0 ? "${(dist * 1000).round()}m" : "${dist.toStringAsFixed(1)}km"} · ${it.regionLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
