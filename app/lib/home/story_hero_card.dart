part of '../main.dart';

class _DailyStoryHeroCard extends StatelessWidget {
  final DailyStoryItem story;
  final AppLang lang;
  final VoidCallback onTap;

  const _DailyStoryHeroCard({
    super.key,
    required this.story,
    required this.lang,
    required this.onTap,
  });

  Widget _buildImagePanel({required double height, required BorderRadius borderRadius, required String dateTag}) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            StorageImage(
              key: ValueKey('hero_img_${story.id}_${story.heroImage}'),
              url: story.heroImage,
              cacheWidth: 960,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.26),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF065F46).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      lang == AppLang.ko ? '📖 $dateTag' : trUi('today_local_story', lang),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      story.tSeasonBadge(lang),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: Text(
                '${story.tRegionLabel(lang)} · ${story.tSourceBook(lang)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextPanel({required bool isWide, required String dateTag}) {
    final pq = story.tPullQuote(lang);
    final ps = story.tParagraphs(lang);
    final sub = story.tSubtitle(lang);
    final summaryText = pq.isNotEmpty ? pq : (ps.isNotEmpty ? ps.first : sub);

    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, isWide ? 22 : 14, isWide ? 24 : 16, isWide ? 22 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (story.heroImage.isEmpty || isWide) ...[
            Text(
              isWide
                  ? '${story.tRegionLabel(lang)} · ${story.tSourceBook(lang)}'
                  : '${lang == AppLang.ko ? '📖 $dateTag' : trUi('today_local_story', lang)} · ${story.tSeasonBadge(lang)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            story.tTitle(lang),
            style: TextStyle(
              fontSize: isWide ? 23 : 19,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
              height: 1.3,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summaryText,
            maxLines: isWide ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isWide ? 14.5 : 13.5,
              color: const Color(0xFF334155),
              height: 1.62,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  lang == AppLang.ko ? '📍 ${story.subtitle}' : '📍 ${story.tAddress(lang)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF065F46),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      trUi('read_story_btn', lang),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateTag = '${now.month}월 ${now.day}일 오늘의 로컬 스토리';
    final isWide = MediaQuery.sizeOf(context).width >= 760 && story.heroImage.isNotEmpty;

    return Container(
      key: const Key('daily_story_banner'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.4),
        boxShadow: const [
          BoxShadow(color: Color(0x0D0F172A), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: InkWell(
        key: const Key('open_daily_story_btn'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: isWide
            ? Row(
                children: [
                  Expanded(
                    flex: 53,
                    child: _buildImagePanel(
                      height: 270,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(18.5)),
                      dateTag: dateTag,
                    ),
                  ),
                  Expanded(
                    flex: 47,
                    child: _buildTextPanel(isWide: true, dateTag: dateTag),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (story.heroImage.isNotEmpty)
                    _buildImagePanel(
                      height: 190,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18.5)),
                      dateTag: dateTag,
                    ),
                  _buildTextPanel(isWide: false, dateTag: dateTag),
                ],
              ),
      ),
    );
  }
}
