// 지자체 공식 가이드북(PDF)·문화관광 누리집 원문 기반 매거진형 스토리 상세 페이지.
// 가독성(줄간격 1.88, 본문 폭 760px 제한), 핵심 탐방정보 박스(《장수여행》 p.9 모델),
// 원본 PDF 직링크, 3사 대중교통 길찾기, 과하지 않은 주변 동선 추천을 하나로 통합한다.
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'detail_page.dart' show ListingDetailPage, StorageImage;
import 'discovery_models.dart';
import 'hub_details.dart';
import 'i18n.dart';
import 'spot_detail_sheet.dart';
import 'translation_store.dart';
import 'ux_widgets.dart';
import 'web_utils.dart';

class StoryDetailPage extends StatefulWidget {
  final DailyStoryItem story;
  final List<DailyStoryItem> allStories;
  final List<DiscoveryItem> allItems;
  final AppLang lang;
  final bool offlineMode;
  final WidgetBuilder homeBuilder;

  const StoryDetailPage({
    super.key,
    required this.story,
    required this.allStories,
    required this.allItems,
    required this.lang,
    required this.homeBuilder,
    this.offlineMode = false,
  });

  @override
  State<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends State<StoryDetailPage> {
  late DailyStoryItem _story;
  int _heroIndex = 0;
  DiscoveryCategory _connectedFilter = DiscoveryCategory.all;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _onEnterStory(_story);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onEnterStory(DailyStoryItem st) {
    syncPortalParams(region: st.province, storyId: st.id);
    trackPortalEvent('view_story_page', {
      'story_id': st.id,
      'province': st.province,
      'title': st.title,
    });
    _hydrateSpotStory(st);
  }

  /// 명소·축제에서 만든 스토리는 첫 화면 데이터에 본문이 없으므로 시·도별 상세 파일로 다시 만든다.
  Future<void> _hydrateSpotStory(DailyStoryItem st) async {
    TranslationStore.ensureDetails(appLangNotifier.value, kProvinceDetailCodes[st.province] ?? 'etc');
    DiscoveryItem? spot;
    for (final it in widget.allItems) {
      if (it.id == st.id) {
        spot = it;
        break;
      }
    }
    if (spot == null || spot.raw['has_details'] != true) return;
    final full = await hydrateDiscoveryItem(spot);
    if (!mounted || identical(full, spot) || _story.id != st.id) return;
    setState(() => _story = rebuildStoryFromSpot(st, full, widget.allItems));
  }

  Future<void> _openUrl(String rawUrl, {String eventTag = 'story_external_open', bool countVisit = false}) async {
    trackPortalEvent(eventTag, {
      'story_id': _story.id,
      'province': _story.province,
      'url': rawUrl,
    });
    if (countVisit) {
      await recordOutboundVisitClick(_story.toDiscoveryItem(), offlineMode: widget.offlineMode);
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'tel')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openConnectedSpot(BuildContext context, AppLang lang, DiscoveryItem it) {
    if (it.category == DiscoveryCategory.stay) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ListingDetailPage(
          listingId: it.id,
          homeBuilder: widget.homeBuilder,
        ),
      ));
      return;
    }
    for (final st in widget.allStories) {
      if (st.id == it.id) {
        setState(() {
          _story = st;
          _heroIndex = 0;
          _connectedFilter = DiscoveryCategory.all;
        });
        _onEnterStory(st);
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SpotDetailSheet(
        item: it,
        allItems: widget.allItems,
        lang: lang,
        offlineMode: widget.offlineMode,
        homeBuilder: widget.homeBuilder,
        onSelectConnectedItem: (_) {},
        onOpenFullStayPage: (stayId) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ListingDetailPage(
              listingId: stayId,
              homeBuilder: widget.homeBuilder,
            ),
          ));
        },
        onOpenStoryPage: (storyId) {
          for (final s in widget.allStories) {
            if (s.id == storyId) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StoryDetailPage(
                  story: s,
                  allStories: widget.allStories,
                  allItems: widget.allItems,
                  lang: lang,
                  offlineMode: widget.offlineMode,
                  homeBuilder: widget.homeBuilder,
                ),
              ));
              return;
            }
          }
        },
      ),
    ));
  }

  Future<void> _copyShareLink() async {
    final shareUrl = '${currentSiteOrigin()}/?story=${Uri.encodeComponent(_story.id)}';
    trackPortalEvent('share_story_link', {'story_id': _story.id});
    final lang = appLangNotifier.value;
    await sharePlace(context, title: _story.tTitle(lang), url: shareUrl, lang: lang);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLangNotifier,
      builder: (context, activeLang, _) {
        return ValueListenableBuilder<int>(
          valueListenable: translationRevisionNotifier,
          builder: (context, _, _) => _buildContent(context, activeLang),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, AppLang lang) {
    final anchorItem = _story.toDiscoveryItem();
    final bundle = buildConnectedBundle(anchorItem, widget.allItems, limitPerType: 8);
    final images = _story.images;
    final activeHero = (images.isNotEmpty && _heroIndex < images.length) ? images[_heroIndex] : '';
    final otherStories = widget.allStories.where((s) => s.id != _story.id).take(8).toList();
    final screenW = MediaQuery.sizeOf(context).width;
    final isWide = screenW >= 720;
    final tTitle = _story.tTitle(lang);
    final tSubtitle = _story.tSubtitle(lang);
    final tAddress = _story.tAddress(lang);
    final tPullQuote = _story.tPullQuote(lang);
    final tParagraphs = _story.tParagraphs(lang);
    final tPracticalHeader = _story.tPracticalHeader(lang);
    final tPracticalInfo = _story.tPracticalInfo(lang);
    final tSeasonBadge = _story.tSeasonBadge(lang);
    final tSourceBook = _story.tSourceBook(lang);
    final tRegion = _story.tRegionLabel(lang);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        leading: IconButton(
          key: const Key('story_back_btn'),
          tooltip: trUi('back_btn', lang),
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: widget.homeBuilder));
            }
          },
        ),
        title: Text(
          tSourceBook,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LangSelectorButton(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              key: const Key('story_share_btn'),
              onPressed: _copyShareLink,
              icon: const Icon(Icons.ios_share_rounded, size: 17),
              label: Text(trUi('share_btn', lang)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : DetailActionBar(
              itemId: _story.id,
              lang: lang,
              onDirections: () => _openUrl(anchorItem.naverRouteUrl, eventTag: 'story_transit_naver'),
              onShare: _copyShareLink,
              phone: _story.phone,
              onCall: () => _openUrl('tel:${_story.phone.replaceAll(' ', '')}', eventTag: 'story_call'),
            ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 16, vertical: isWide ? 28 : 18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              padding: EdgeInsets.all(isWide ? 34 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A0F172A), blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 계절·테마 태그 & 출처 표기
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Text(
                          tSeasonBadge,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                        ),
                      ),
                      Text(
                        '$tRegion · $tSourceBook',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. 매거진 화보형 포토 그리드 (대표 사진 + 썸네일 갤러리)
                  if (activeHero.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: isWide ? 350 : 225,
                        width: double.infinity,
                        child: StorageImage(url: activeHero, cacheWidth: 1080),
                      ),
                    ),
                    if (images.length > 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: isWide ? 84 : 74,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final selected = idx == _heroIndex;
                            return InkWell(
                              onTap: () => setState(() => _heroIndex = idx),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: isWide ? 116 : 96,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                                    width: selected ? 2.5 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: StorageImage(url: images[idx], cacheWidth: 320),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],

                  // 3. 매거진 타이틀 & 지자체 책자 스타일 부제(주소)
                  Text(
                    tTitle,
                    style: TextStyle(
                      fontSize: isWide ? 28 : 22.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF14532D),
                      height: 1.28,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFBBF7D0), width: 1.5)),
                    ),
                    child: Text(
                      tSubtitle.isNotEmpty ? tSubtitle : tAddress,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 3-1. 방문 결정용 핵심 정보 칩 + 출처·기준일
                  QuickFactsChips(rows: tPracticalInfo),
                  const SizedBox(height: 8),
                  SourceLine(item: anchorItem, lang: lang),
                  const SizedBox(height: 20),

                  // 4. 핵심 설화·감성 한 줄 콜아웃 (Pull-Quote)
                  if (tPullQuote.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(left: BorderSide(color: Color(0xFF10B981), width: 4)),
                      ),
                      child: Text(
                        '“$tPullQuote”',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                          height: 1.65,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // 5. 지자체 공식 원문 스토리 본문 (챕터별 TourAPI 정합 대표 이미지 + 웹 매거진 카드)
                  ...(() {
                    var chapterCounter = 0;
                    return tParagraphs.map((p) {
                      final trimmed = p.trim();
                      final nlIdx = trimmed.indexOf('\n');
                      final isChapter = nlIdx > 0 &&
                          (trimmed.startsWith('【') ||
                              trimmed.startsWith('▌') ||
                              trimmed.startsWith('📌 ') ||
                              trimmed.startsWith('## '));
                      if (isChapter) {
                        final heading = trimmed
                            .substring(0, nlIdx)
                            .replaceFirst(RegExp(r'^##\s*'), '')
                            .trim();
                        final body = trimmed.substring(nlIdx + 1).trim();
                        final media = chapterCounter < _story.chapterMedia.length
                            ? _story.chapterMedia[chapterCounter]
                            : null;
                        chapterCounter += 1;
                        final chapterImg = media?.imageUrl ?? '';
                        final chapterCaption = media?.label ?? '';

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 18),
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.only(left: 10),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    left: BorderSide(color: Color(0xFF059669), width: 3.5),
                                  ),
                                ),
                                child: Text(
                                  heading,
                                  style: const TextStyle(
                                    fontSize: 17.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              if (chapterImg.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: isWide ? 230 : 175,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        StorageImage(url: chapterImg, cacheWidth: 880),
                                        if (chapterCaption.isNotEmpty)
                                          Positioned(
                                            left: 10,
                                            bottom: 10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.65),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                '📍 $chapterCaption',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  body,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    color: Color(0xFF334155),
                                    height: 1.82,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          p,
                          style: const TextStyle(
                            fontSize: 16.5,
                            color: Color(0xFF1E293B),
                            height: 1.88,
                            letterSpacing: -0.1,
                          ),
                        ),
                      );
                    });
                  })(),
                  const SizedBox(height: 8),

                  // 6. 방문 전 꼭 필요한 '핵심 탐방·편의 정보 박스' (《장수여행》 p.9 하단 초록 박스 모델)
                  if (tPracticalHeader.isNotEmpty || tPracticalInfo.isNotEmpty) ...[
                    Container(
                      key: const Key('story_practical_box'),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FEE7).withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC), width: 1.3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tPracticalHeader.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: const BoxDecoration(
                                color: Color(0xFF16A34A),
                                borderRadius: BorderRadius.vertical(top: Radius.circular(12.5)),
                              ),
                              child: Text(
                                '🌿 $tPracticalHeader',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: tPracticalInfo
                                  .map(
                                    (row) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: RichText(
                                        text: TextSpan(
                                          style: const TextStyle(fontSize: 14, height: 1.55, color: Color(0xFF1E293B)),
                                          children: [
                                            TextSpan(
                                              text: '• ${row.label} : ',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF15803D),
                                              ),
                                            ),
                                            TextSpan(text: row.value),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // 7. 정돈된 행동 영역: ① 원본 가이드북 PDF 열람 + ② 1줄 대중교통·내비 길찾기
                  if (_story.pdfLinks.isNotEmpty) ...[
                    Text(
                      pickLangText(
                        lang,
                        ko: '공식 가이드북 & 관광지도 원본',
                        en: 'Official Municipal Guidebook & Map PDF',
                        ja: '自治体公式ガイドブック＆観光地図PDF',
                        zh: '地方政府官方旅遊指南＆觀光地圖PDF',
                      ),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _story.pdfLinks
                          .asMap()
                          .entries
                          .map(
                            (entry) => FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              ),
                              onPressed: () => _openUrl(entry.value.url, eventTag: 'open_municipal_pdf'),
                              icon: const Icon(Icons.menu_book_rounded, size: 17),
                              label: Text(_story.tPdfLabel(lang, entry.key, entry.value.localizedLabel(lang))),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                  ],

                  Text(
                    pickLangText(
                      lang,
                      ko: '바로 떠나기 · 대중교통 및 내비게이션 경로',
                      en: 'Directions & Public Transit',
                      ja: 'アクセス・公共交通ルート案内',
                      zh: '立即出發・大眾運輸與導航路線',
                    ),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('story_naver_route_btn'),
                        onPressed: () => _openUrl(anchorItem.naverRouteUrl, eventTag: 'click_transit_naver', countVisit: true),
                        icon: const Icon(Icons.map_outlined, size: 17, color: Color(0xFF03C75A)),
                        label: Text(pickLangText(lang, ko: '🟢 네이버지도 길찾기', en: '🟢 Naver Map', ja: '🟢 NAVER地図', zh: '🟢 NAVER地圖')),
                      ),
                      OutlinedButton.icon(
                        key: const Key('story_kakao_route_btn'),
                        onPressed: () => _openUrl(anchorItem.kakaoRouteUrl, eventTag: 'click_transit_kakao', countVisit: true),
                        icon: const Icon(Icons.directions_bus_filled_rounded, size: 17, color: Color(0xFFD97706)),
                        label: Text(pickLangText(lang, ko: '🟡 카카오 대중교통·내비', en: '🟡 Kakao Transit', ja: '🟡 Kakao乗換案内', zh: '🟡 Kakao大眾運輸')),
                      ),
                      OutlinedButton.icon(
                        key: const Key('story_google_route_btn'),
                        onPressed: () => _openUrl(anchorItem.googleTransitUrl, eventTag: 'click_transit_google', countVisit: true),
                        icon: const Icon(Icons.train_rounded, size: 17, color: Color(0xFF2563EB)),
                        label: Text(pickLangText(lang, ko: '🔵 Google 대중교통', en: '🔵 Google Transit', ja: '🔵 Google乗換案内', zh: '🔵 Google大眾運輸')),
                      ),
                      if (_story.phone.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUrl('tel:${_story.phone.replaceAll(' ', '')}', eventTag: 'click_phone'),
                          icon: const Icon(Icons.call_outlined, size: 17),
                          label: Text(_story.phone),
                        ),
                    ],
                  ),

                  // 8. 자연스러운 다음 발걸음 (카테고리 칩으로 볼거리·먹거리·축제·숙소까지 깊게 이어 탐색)
                  if (bundle.foods.isNotEmpty ||
                      bundle.attractions.isNotEmpty ||
                      bundle.events.isNotEmpty ||
                      bundle.stays.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Divider(height: 1),
                    ),
                    Text(
                      pickLangText(
                        lang,
                        ko: '✨ 이 이야기의 무대로 떠난다면, 함께 들르기 좋은 동선',
                        en: '✨ Suggested Nearby Stops for Your Trip',
                        ja: '✨ このストーリーの舞台と一緒に巡りたい周辺スポット',
                        zh: '✨ 前往此故事舞台時，推薦順遊的周邊好去處',
                      ),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pickLangText(
                        lang,
                        ko: '볼거리·먹거리·축제·공공데이터 등록 숙소까지 연관 장소를 눌러 계속 이어서 탐색하세요.',
                        en: 'Tap any connected sight, eatery, festival, or licensed stay to keep exploring.',
                        ja: '見どころ・グルメ・祭り・宿泊まで関連スポットをタップして続けて探索できます。',
                        zh: '點擊相連景點、美食、慶典或合法認證住宿，持續深入探索行程。',
                      ),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in <(DiscoveryCategory, String, int)>[
                          (
                            DiscoveryCategory.all,
                            pickLangText(lang, ko: '전체', en: 'All', ja: 'すべて', zh: '全部'),
                            bundle.foods.length + bundle.attractions.length + bundle.events.length + bundle.stays.length,
                          ),
                          if (bundle.attractions.isNotEmpty)
                            (
                              DiscoveryCategory.attraction,
                              pickLangText(lang, ko: '🏞️ 볼거리', en: '🏞️ Sights', ja: '🏞️ 名所', zh: '🏞️ 景點'),
                              bundle.attractions.length,
                            ),
                          if (bundle.foods.isNotEmpty)
                            (
                              DiscoveryCategory.food,
                              pickLangText(lang, ko: '🍲 먹거리', en: '🍲 Food', ja: '🍲 グルメ', zh: '🍲 美食'),
                              bundle.foods.length,
                            ),
                          if (bundle.events.isNotEmpty)
                            (
                              DiscoveryCategory.event,
                              pickLangText(lang, ko: '🎉 축제', en: '🎉 Events', ja: '🎉 祭り', zh: '🎉 慶典'),
                              bundle.events.length,
                            ),
                          if (bundle.stays.isNotEmpty)
                            (
                              DiscoveryCategory.stay,
                              pickLangText(lang, ko: '🏡 숙소', en: '🏡 Stays', ja: '🏡 宿泊', zh: '🏡 住宿'),
                              bundle.stays.length,
                            ),
                        ])
                          ChoiceChip(
                            label: Text('${entry.$2} (${entry.$3})'),
                            selected: _connectedFilter == entry.$1,
                            onSelected: (_) => setState(() => _connectedFilter = entry.$1),
                            selectedColor: const Color(0xFF065F46),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: _connectedFilter == entry.$1 ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...(() {
                      final combined = switch (_connectedFilter) {
                        DiscoveryCategory.attraction => bundle.attractions,
                        DiscoveryCategory.food => bundle.foods,
                        DiscoveryCategory.event => bundle.events,
                        DiscoveryCategory.stay => bundle.stays,
                        _ => [...bundle.attractions, ...bundle.foods, ...bundle.events, ...bundle.stays],
                      };
                      return combined.take(12);
                    })().map(
                          (it) => _StoryNearbyStopTile(
                            item: it,
                            anchor: anchorItem,
                            lang: lang,
                            onTap: () => _openConnectedSpot(context, lang, it),
                          ),
                        ),
                  ],

                  // 9. 다른 계절·지역 스토리 이어 읽기
                  if (otherStories.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(height: 1),
                    ),
                    Text(
                      pickLangText(
                        lang,
                        ko: '📚 다른 지역의 공식 가이드북 스토리',
                        en: '📚 More Local Stories Across Korea',
                        ja: '📚 韓国各地の公式ガイドブック・ストーリー',
                        zh: '📚 韓國各地官方旅遊指南故事',
                      ),
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 12),
                    ...otherStories.map(
                      (st) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              _story = st;
                              _heroIndex = 0;
                              _connectedFilter = DiscoveryCategory.all;
                            });
                            _onEnterStory(st);
                            if (_scrollCtrl.hasClients) {
                              _scrollCtrl.animateTo(
                                0,
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                if (st.heroImage.isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 84,
                                      height: 72,
                                      child: StorageImage(url: st.heroImage, cacheWidth: 220),
                                    ),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${st.tSeasonBadge(lang)} · ${st.tRegionLabel(lang)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        st.tTitle(lang),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryNearbyStopTile extends StatelessWidget {
  final DiscoveryItem item;
  final DiscoveryItem anchor;
  final AppLang lang;
  final VoidCallback onTap;

  const _StoryNearbyStopTile({
    required this.item,
    required this.anchor,
    required this.lang,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final distKm = haversineKm(anchor.lat, anchor.lng, item.lat, item.lng);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 84,
                  height: 64,
                  child: item.imageUrl.isNotEmpty
                      ? StorageImage(url: item.imageUrl, cacheWidth: 240)
                      : Container(
                          color: item.category.color.withValues(alpha: 0.1),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(item.category.icon, color: item.category.color, size: 22),
                              const SizedBox(height: 2),
                              Text(
                                item.categoryBadgeText(lang),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: item.category.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.tTitle(lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.categoryEmoji} ${item.categoryBadgeText(lang)} · ${item.distanceLabel(distKm, lang)}${item.couponTitle.isNotEmpty ? " · 🎁 ${item.tCouponTitle(lang)}" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    if (item.tSubtitle(lang).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.tSubtitle(lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
