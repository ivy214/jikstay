part of '../detail_page.dart';

/// 네이버 블로그 검색 오픈 API 메타데이터 기반 후기·소개 아웃링크 섹션
class _NaverReviewsSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> reviews;
  final AppLang lang;
  final Future<void> Function(String url) onOpenExternal;

  const _NaverReviewsSection({
    required this.data,
    required this.reviews,
    required this.lang,
    required this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    final blogTotal = (data['naver_blog_total'] as num?)?.toInt() ?? reviews.length;
    final searchUrl = (data['naver_search_url'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF03C75A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('N 블로그', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                trUi('naver_reviews_title', lang),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            if (blogTotal > 0)
              Text('검색 $blogTotal건', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          trUi('naver_reviews_sub', lang),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        ...reviews.map((r) {
          final link = (r['link'] ?? '').toString();
          final blogger = (r['blogger_name'] ?? '').toString();
          final date = (r['postdate'] ?? '').toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: link.startsWith('http') ? () => onOpenExternal(link) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (r['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF6B7280)),
                      ],
                    ),
                    if ((r['summary'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        (r['summary'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFF4B5563), height: 1.45),
                      ),
                    ],
                    if (blogger.isNotEmpty || date.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [if (blogger.isNotEmpty) '블로그: $blogger', if (date.isNotEmpty) date].join(' · '),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        if (searchUrl.startsWith('http'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton.icon(
              onPressed: () => onOpenExternal(searchUrl),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('네이버에서 방문 후기·요금 정보 더 보기'),
            ),
          ),
      ],
    );
  }
}

/// 한국관광공사(KorService2/locationBasedList2) 반경 5km 주변 명소·맛집 추천 섹션
class _TourNearbyPlacesSection extends StatelessWidget {
  final List<Map<String, dynamic>> places;
  final AppLang lang;
  final Future<void> Function(String url) onOpenExternal;

  const _TourNearbyPlacesSection({
    required this.places,
    required this.lang,
    required this.onOpenExternal,
  });

  String _fmtDist(dynamic raw) {
    final m = (raw as num?)?.toInt() ?? 0;
    if (m <= 0) return '';
    if (m < 1000) return '${m}m';
    return '${(m / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trUi('nearby_spots_title', lang),
          style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: places.take(4).map((p) {
            final dist = _fmtDist(p['distance_m']);
            final mapUrl = (p['map_url'] ?? '').toString();
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: mapUrl.startsWith('http') ? () => onOpenExternal(mapUrl) : null,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 62,
                          height: 62,
                          child: StorageImage(
                            url: (p['image_url'] ?? '').toString(),
                            cacheWidth: 220,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                (p['category'] ?? '명소').toString(),
                                if (dist.isNotEmpty) dist,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              (p['title'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (p['addr'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// 사용자 참여형 별점(score 1~5) 및 후기(review) 작성·열람 섹션
class UserReviewsSection extends StatefulWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final AppLang lang;
  final bool isOfflineDemo;
  final ValueChanged<int>? onReviewSubmitted;

  const UserReviewsSection({
    super.key,
    required this.listingId,
    required this.data,
    required this.lang,
    this.isOfflineDemo = false,
    this.onReviewSubmitted,
  });

  @override
  State<UserReviewsSection> createState() => _UserReviewsSectionState();
}

class _UserReviewsSectionState extends State<UserReviewsSection> {
  static const List<String> _visitTags = ['커플·2인', '가족여행', '혼행·워케이션', '단기숙박', '한달살기'];

  final TextEditingController _nickCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();

  int _selectedScore = 5;
  String _selectedTag = '커플·2인';
  bool _submitting = false;
  bool _loadingRemote = false;
  final List<Map<String, dynamic>> _localPrepended = [];
  List<Map<String, dynamic>> _remoteReviews = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.isOfflineDemo && !widget.listingId.startsWith('stay_demo_')) {
      _fetchRemoteReviews();
    }
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteReviews() async {
    setState(() => _loadingRemote = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('reviews')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();
      if (!mounted) return;
      setState(() {
        _remoteReviews = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    } catch (_) {
      // 오프라인이나 초기 무후기 상태는 빈 목록으로 처리
    } finally {
      if (mounted) setState(() => _loadingRemote = false);
    }
  }

  String _scoreDescription(int s, AppLang lang) {
    if (lang != AppLang.ko) return '$s / 5';
    return switch (s) {
      5 => '5점 · 최고예요! 다시 찾고 싶어요',
      4 => '4점 · 만족스러운 숙소였어요',
      3 => '3점 · 무난하고 괜찮았어요',
      2 => '2점 · 조금 아쉬운 점이 있었어요',
      _ => '1점 · 개선이 필요해요',
    };
  }

  String _formatReviewDate(Map<String, dynamic> r) {
    final preset = (r['date_label'] ?? '').toString().trim();
    if (preset.isNotEmpty) return preset;
    final ts = r['created_at'];
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    if (ts is DateTime) dt = ts;
    if (dt == null) return '방금 전';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submitReview() async {
    final nick = _nickCtrl.text.trim();
    final body = _commentCtrl.text.trim();
    final err = validateUserReviewInput(nickname: nick, score: _selectedScore, comment: body);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_validation_err', widget.lang))),
      );
      return;
    }

    final scoreToSave = _selectedScore;
    final tagToSave = _selectedTag;
    final langCode = widget.lang.code;

    setState(() => _submitting = true);
    try {
      if (!widget.isOfflineDemo && !widget.listingId.startsWith('stay_demo_')) {
        final result = await submitReviewBatch(
          collection: 'listings',
          targetId: widget.listingId,
          targetIdField: 'listing_id',
          score: scoreToSave,
          payload: <String, dynamic>{
            'nickname': nick,
            'comment': body,
            if (tagToSave.isNotEmpty) 'visit_tag': tagToSave,
            'lang': langCode,
          },
        );
        if (result == ReviewSubmitResult.alreadyReviewed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(trUi('review_already_posted', widget.lang))),
            );
          }
          return;
        }
      }

      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _localPrepended.insert(0, {
          'nickname': nick,
          'score': scoreToSave,
          'visit_tag': tagToSave,
          'comment': body,
          'lang': langCode,
          'created_at': now,
        });
        _commentCtrl.clear();
        _selectedScore = 5;
      });
      widget.onReviewSubmitted?.call(scoreToSave);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_submitted', widget.lang))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('후기 등록 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rating = extractListingRating(widget.data);
    final demoItems = (widget.data['demo_reviews'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    final allReviews = <Map<String, dynamic>>[
      ..._localPrepended,
      ..._remoteReviews,
      if (_remoteReviews.isEmpty) ...demoItems,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 헤더 & 평균 별점 요약 카드
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFF59E0B), size: 24),
                const SizedBox(width: 8),
                Text(
                  trUi('user_reviews_title', widget.lang),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
                ),
              ],
            ),
            if (rating.count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 19),
                    const SizedBox(width: 4),
                    Text(
                      '${rating.average.toStringAsFixed(1)} / 5.0',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${rating.count}건)',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          trUi('user_reviews_sub', widget.lang),
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),

        // 2. 대화형 별점(1~5) 및 후기 입력 카드
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trUi('write_review_title', widget.lang),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (int s = 1; s <= 5; s++)
                    InkWell(
                      key: Key('review_star_$s'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: _submitting ? null : () => setState(() => _selectedScore = s),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          s <= _selectedScore ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 32,
                          color: s <= _selectedScore ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _scoreDescription(_selectedScore, widget.lang),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.lang == AppLang.ko) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _visitTags.map((tag) {
                    final active = _selectedTag == tag;
                    return ChoiceChip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      selected: active,
                      visualDensity: VisualDensity.compact,
                      selectedColor: const Color(0xFFFFF0F3),
                      side: BorderSide(color: active ? kBrand : const Color(0xFFDDDDDD)),
                      labelStyle: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                        color: active ? kBrand : const Color(0xFF495057),
                      ),
                      showCheckmark: false,
                      onSelected: _submitting ? null : (_) => setState(() => _selectedTag = tag),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const Key('review_nickname_input'),
                      controller: _nickCtrl,
                      enabled: !_submitting,
                      maxLength: 24,
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        labelText: trUi('nickname_label', widget.lang),
                        hintText: trUi('nickname_hint', widget.lang),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('review_comment_input'),
                controller: _commentCtrl,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 600,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: trUi('comment_hint', widget.lang),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('review_submit_btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrand,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _submitting ? null : _submitReview,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(
                    trUi('submit_review_btn', widget.lang),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. 등록된 후기 목록
        if (_loadingRemote && allReviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (allReviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEBEBEB)),
            ),
            child: Text(
              trUi('review_empty', widget.lang),
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
            ),
          )
        else
          ...allReviews.map((r) {
            final sc = ((r['score'] as num?)?.toInt() ?? 5).clamp(1, 5);
            final nick = (r['nickname'] ?? '여행자').toString();
            final tag = (r['visit_tag'] ?? '').toString().trim();
            final comment = (r['comment'] ?? '').toString();
            final initial = nick.isNotEmpty ? nick.characters.first.toUpperCase() : 'G';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFFFF0F3),
                        child: Text(
                          initial,
                          style: const TextStyle(color: kBrand, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(nick, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (tag.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(tag, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                              ),
                          ],
                        ),
                      ),
                      Text(_formatReviewDate(r), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (int i = 1; i <= 5; i++)
                        Icon(
                          i <= sc ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 16,
                          color: i <= sc ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                        ),
                      const SizedBox(width: 6),
                      Text('$sc.0', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(comment, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155))),
                ],
              ),
            );
          }),
      ],
    );
  }
}
