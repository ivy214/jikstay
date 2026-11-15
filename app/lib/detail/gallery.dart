part of '../detail_page.dart';

/// 에어비앤비 스타일 데스크톱 5분할 벤토 그리드 + 모바일 스와이프 갤러리 + 공간별 포토 투어 모달
class _BentoGallery extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final String title;

  const _BentoGallery({required this.images, required this.title});

  @override
  State<_BentoGallery> createState() => _BentoGalleryState();
}

class _BentoGalleryState extends State<_BentoGallery> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openTour(BuildContext context, {String? initialTag}) {
    final tags = <String>{'전체'};
    for (final im in widget.images) {
      final t = (im['space_tag'] ?? '').toString().trim();
      if (t.isNotEmpty) tags.add(t);
    }
    String selectedTag = initialTag ?? '전체';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = selectedTag == '전체'
              ? widget.images
              : widget.images.where((im) => (im['space_tag'] ?? '').toString() == selectedTag).toList();
          return Dialog.fullscreen(
            backgroundColor: Colors.white,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pickLangText(
                              appLangNotifier.value,
                              ko: '사진 투어 · ${widget.title}',
                              en: 'Photo Tour · ${widget.title}',
                              ja: '写真ツアー · ${widget.title}',
                              zh: '照片导览 · ${widget.title}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tags.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: tags
                            .map((t) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(t),
                                    selected: selectedTag == t,
                                    onSelected: (_) => setModalState(() => selectedTag = t),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 24),
                      itemBuilder: (_, i) {
                        final im = filtered[i];
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 540),
                                    child: StorageImage(
                                      path: im['path']?.toString(),
                                      url: im['url']?.toString(),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorIconSize: 40,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if ((im['space_tag'] ?? '').toString().isNotEmpty) '[${im['space_tag']}]',
                                    if ((im['caption'] ?? '').toString().isNotEmpty) im['caption'].toString(),
                                  ].join(' '),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
            ),
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> im) {
    return InkWell(
      onTap: () => _openTour(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StorageImage(
            path: im['path']?.toString(),
            url: im['url']?.toString(),
            fit: BoxFit.cover,
            width: double.infinity,
            errorIconSize: 36,
          ),
          if ((im['space_tag'] ?? '').toString().isNotEmpty)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  im['space_tag'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;
    final imgs = widget.images;

    if (isWide && imgs.length >= 3) {
      final sub = imgs.skip(1).take(4).toList();
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 400,
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(flex: 5, child: _tile(context, imgs.first)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: sub.length >= 4
                        ? Column(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(child: _tile(context, sub[0])),
                                    const SizedBox(width: 8),
                                    Expanded(child: _tile(context, sub[1])),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(child: _tile(context, sub[2])),
                                    const SizedBox(width: 8),
                                    Expanded(child: _tile(context, sub[3])),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              for (int i = 0; i < sub.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                Expanded(child: _tile(context, sub[i])),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF222222),
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF222222)),
                    ),
                  ),
                  onPressed: () => _openTour(context),
                  icon: const Icon(Icons.grid_view_rounded, size: 17),
                  label: Text(
                    pickLangText(
                      appLangNotifier.value,
                      ko: '사진 모두 보기 (${imgs.length}장)',
                      en: 'Show all photos (${imgs.length})',
                      ja: '写真をすべて見る (${imgs.length}枚)',
                      zh: '查看全部照片 (${imgs.length}张)',
                    ),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final current = imgs[_page];
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 300,
        child: Stack(
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: imgs.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openTour(context),
                child: StorageImage(
                  path: imgs[i]['path']?.toString(),
                  url: imgs[i]['url']?.toString(),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorIconSize: 40,
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                child: Text(
                  '${current['space_tag'] ?? ''} ${current['caption'] ?? ''} (${_page + 1}/${imgs.length})'.trim(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.tonalIcon(
                onPressed: () => _openTour(context),
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: Text(
                  pickLangText(appLangNotifier.value, ko: '사진 투어', en: 'Photo Tour', ja: '写真ツアー', zh: '照片导览'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 외부 공식 이미지 URL(Image.network) 전용 경량 이미지 위젯 (Storage 업로드 폐지에 맞춰 슬림화)
class StorageImage extends StatelessWidget {
  final String? path;
  final String? url;
  final BoxFit fit;
  final double? width;
  final int? cacheWidth;
  final double errorIconSize;

  const StorageImage({
    super.key,
    this.path,
    this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.cacheWidth,
    this.errorIconSize = 24,
  });

  Widget _broken() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1F4F8), Color(0xFFE6ECF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.villa_outlined, size: errorIconSize + 8, color: const Color(0xFF6C7A89)),
              const SizedBox(height: 4),
              const Text('공공데이터 등록 스테이', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5A6877))),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return _broken();
    return Image.network(
      u,
      key: ValueKey(u),
      fit: fit,
      width: width,
      cacheWidth: cacheWidth,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, _, _) => _broken(),
    );
  }
}

/// 외부 사진 링크가 아직 없는 공공API 선별 숙소용 고신뢰 비주얼 배너
class _PublicStayVisualHero extends StatelessWidget {
  final Map<String, dynamic> data;
  final Future<void> Function(String url) onOpenExternal;

  const _PublicStayVisualHero({required this.data, required this.onOpenExternal});

  @override
  Widget build(BuildContext context) {
    final mapUrl = (data['naver_map_url'] ?? '').toString();
    final searchUrl = (data['naver_search_url'] ?? '').toString();
    final blogTotal = (data['naver_blog_total'] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2937), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF34D399)),
                  ),
                  child: Text(
                    '✓ ${stayVerificationLabel(data, appLangNotifier.value)} · ${data['license_type'] ?? ''}',
                    style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${data['region_depth1'] ?? ''} ${data['region_depth2'] ?? ''} 공공데이터 등록 숙소',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  blogTotal > 0
                      ? '무단 이미지 복제 없이 공식 데이터와 네이버 방문 후기 $blogTotal건을 안전하게 연결합니다.'
                      : '공공 인허가 데이터를 기반으로 등록된 숙소입니다. 네이버 지도·플레이스에서 현장 사진과 예약처를 바로 확인하세요.',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (mapUrl.startsWith('http'))
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF03C75A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onPressed: () => onOpenExternal(mapUrl),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('네이버 지도·플레이스 사진 보기', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              if (searchUrl.startsWith('http'))
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onPressed: () => onOpenExternal(searchUrl),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('네이버 통합검색'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
