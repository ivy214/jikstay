part of '../main.dart';

class _LiveFeedItemCard extends StatelessWidget {
  final DiscoveryItem item;
  final AppLang lang;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<String> onOpenEbookDirect;

  const _LiveFeedItemCard({
    super.key,
    required this.item,
    required this.lang,
    required this.isSelected,
    required this.onTap,
    required this.onOpenEbookDirect,
  });

  @override
  Widget build(BuildContext context) {
    final freshBadge = item.dynamicFreshnessBadge(lang);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0F172A)
                : (item.isSponsored ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 88,
                height: 88,
                child: item.imageUrl.isNotEmpty
                    ? StorageImage(url: item.imageUrl, cacheWidth: 280)
                    : Container(
                        color: item.category.color.withValues(alpha: 0.1),
                        alignment: Alignment.center,
                        child: Icon(item.category.icon, color: item.category.color, size: 30),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.category.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.categoryEmoji} ${trProvince(item.province, lang)} · ${item.categoryBadgeText(lang)}',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: item.category.color),
                        ),
                      ),
                      if (freshBadge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            freshBadge,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C)),
                          ),
                        ),
                      if (item.isSponsored)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pickLangText(
                              lang,
                              ko: '🎁 방문혜택 쿠폰',
                              en: '🎁 Visit Perk',
                              ja: '🎁 来店特典',
                              zh: '🎁 造訪優惠',
                            ),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                          ),
                        ),
                      if (item.reviewCount > 0)
                        Text(
                          '★ ${item.averageRating.toStringAsFixed(1)} (${item.reviewCount})',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.tTitle(lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.couponTitle.isNotEmpty
                        ? item.tCouponTitle(lang)
                        : (item.tSubtitle(lang).isNotEmpty ? item.tSubtitle(lang) : item.tAddress(lang)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.couponTitle.isNotEmpty ? const Color(0xFF92400E) : const Color(0xFF475569),
                      fontWeight: item.couponTitle.isNotEmpty ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          trUi('connected_nearby_hint', lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                        ),
                      ),
                      if (item.category == DiscoveryCategory.ebook && item.externalUrl.isNotEmpty)
                        InkWell(
                          onTap: () => onOpenEbookDirect(item.externalUrl),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              pickLangText(
                                lang,
                                ko: '즉시 열람 ↗',
                                en: 'Open PDF ↗',
                                ja: '今すぐ開く ↗',
                                zh: '立即開啟 ↗',
                              ),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 개별 숙소 카드 위젯 (상세페이지·데모 호환 유지)
class ListingCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final StayPeriod period;
  final bool demoMode;

  const ListingCard({
    super.key,
    required this.docId,
    required this.data,
    this.period = StayPeriod.all,
    this.demoMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final images = (data['images'] as List?) ?? [];
    final firstImg = images.isNotEmpty ? Map<String, dynamic>.from(images.first as Map) : const <String, dynamic>{};
    final thumbUrl = (firstImg['url'] ?? '').toString();
    final thumbPath = (firstImg['path'] ?? '').toString();
    final points = List<String>.from(data['summary_points'] ?? []);
    final topAm = extractTopAmenities(data, limit: 3);
    final isForeignOnly = data['license_type'] == kForeignOnly;
    final hasDirect = hasDirectBookingUrl(data);
    final isSponsored = data['is_sponsored'] == true;
    final promoTitle = (data['promo_title'] ?? '').toString().trim();
    final rawBookingUrl = (data['direct_booking_url'] ?? data['naver_map_url'] ?? '').toString();
    final channelName = bookingChannelName(rawBookingUrl);
    final ctaText = !hasDirect
        ? (lang == AppLang.ko ? '네이버 정보·지도' : 'Map & Reviews')
        : (channelName == '네이버 예약' ? '네이버 예약 직거래' : '수수료 0원 직거래');

    final capMax = data['capacity_max'];
    final blogTotal = (data['naver_blog_total'] as num?)?.toInt() ?? 0;
    final specs = data['room_specs'] is Map ? Map<String, dynamic>.from(data['room_specs'] as Map) : const {};
    final rating = extractListingRating(data);
    final specBadge = [
      if (capMax != null) '최대 $capMax명',
      if (specs['bedrooms'] != null) '침실 ${specs['bedrooms']}',
      if (capMax == null && blogTotal > 0) '블로그 $blogTotal건',
    ].join(' · ');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isSponsored ? const Color(0xFFFFCCD5) : const Color(0xFFEBEBEB), width: isSponsored ? 1.4 : 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ListingDetailPage(
            listingId: docId,
            homeBuilder: (_) => HomePage(initialDemoMode: demoMode),
          ),
        )),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            SizedBox(
              height: 192,
              width: double.infinity,
              child: StorageImage(
                path: thumbPath,
                url: thumbUrl,
                cacheWidth: 560,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.assured_workload_rounded,
                      size: 14,
                      color: Color(0xFF198754),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${data['license_type']} 영업확인',
                      style: const TextStyle(color: Color(0xFF222222), fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            if (promoTitle.isNotEmpty || isSponsored)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    promoTitle.isNotEmpty ? '🎁 이벤트' : '⚡ 공식 직거래',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (isForeignOnly)
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                  child: const Text('외국인 전용 숙소', style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
          ]),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${data['region_depth1']} ${data['region_depth2']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (rating.count > 0) ...[
                      const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 2),
                      Text(
                        '${rating.average.toStringAsFixed(1)} (${rating.count})',
                        style: const TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ] else if (specBadge.isNotEmpty)
                      Text(specBadge, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  localizedListingTitle(data, lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: Color(0xFF222222)),
                ),
                const SizedBox(height: 5),
                if (points.isNotEmpty)
                  Text(
                    '· ${points.first}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                if (topAm.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    topAm.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF6C757D)),
                  ),
                ],
                const Spacer(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shortPrice(
                            data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : null,
                            period: period,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF222222)),
                        ),
                        const Text('중개수수료 0원', style: TextStyle(fontSize: 11, color: kBrand, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrand,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => goDirectBooking(context, docId, data),
                    child: Text(ctaText, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
