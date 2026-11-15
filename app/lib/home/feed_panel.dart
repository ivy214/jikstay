part of '../main.dart';

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
                key: ValueKey('hero_${todayStory.id}_${todayStory.heroImage}'),
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
