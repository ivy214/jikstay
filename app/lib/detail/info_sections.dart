part of '../detail_page.dart';

class _PricingTableCard extends StatelessWidget {
  final Map<String, dynamic> pricing;

  const _PricingTableCard({required this.pricing});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final rows = <(String, num)>[
      if (pricing['nightly_min'] is num)
        (pickLangText(lang, ko: '1박 (최저 기준)', en: '1 night (from)', ja: '1泊（最低基準）', zh: '每晚（最低参考）'), pricing['nightly_min'] as num),
      if (pricing['weekly_price'] is num)
        (pickLangText(lang, ko: '일주일 (6~7박 연박)', en: '1 week (6–7 nights)', ja: '1週間（6〜7泊）', zh: '一周（6~7晚连住）'), pricing['weekly_price'] as num),
      if (pricing['monthly_price'] is num)
        (pickLangText(lang, ko: '한달살기 (28박 이상)', en: 'Monthly (28+ nights)', ja: '1ヶ月（28泊以上）', zh: '月租（28晚以上）'), pricing['monthly_price'] as num),
    ];
    final note = (pricing['price_note'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Text(
              pickLangText(
                lang,
                ko: '호스트 예약 창구에서 일정별 정확한 직거래 요금을 확인하세요.',
                en: 'Check exact direct rates for your dates on the host booking page.',
                ja: 'ホストの予約窓口で日程別の正確な直接料金をご確認ください。',
                zh: '请在房东预订渠道查询具体日期的直订房价。',
              ),
              style: const TextStyle(fontSize: 14),
            )
          else
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r.$1, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                      Text(formatWon(r.$2), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                )),
          if (note.isNotEmpty) ...[
            const Divider(height: 18),
            Text('· $note', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 8),
          Text(
            pickLangText(
              lang,
              ko: '· 일반 숙박 플랫폼의 게스트 서비스 수수료(약 14~16%) 없이 호스트에게 직접 예약합니다.',
              en: '· Book directly with the host without typical OTA guest service fees (~14–16%).',
              ja: '· 一般的な宿泊サイトのゲスト手数料（約14〜16%）なしでホストへ直接予約します。',
              zh: '· 无需支付常规订房平台约14~16%的旅客服务费，直接联系房东预订。',
            ),
            style: const TextStyle(fontSize: 12.5, color: kBrand, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _HouseRulesSection extends StatelessWidget {
  final Map<String, dynamic> houseRules;
  final bool isForeignOnly;

  const _HouseRulesSection({required this.houseRules, required this.isForeignOnly});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final checkIn = (houseRules['check_in_time'] ?? '').toString().trim();
    final checkOut = (houseRules['check_out_time'] ?? '').toString().trim();
    final selfCheckIn = (houseRules['self_check_in'] ?? '').toString().trim();
    final quietHours = (houseRules['quiet_hours'] ?? '').toString().trim();
    final smoking = (houseRules['smoking_policy'] ?? '').toString().trim();
    final pets = (houseRules['pet_policy'] ?? '').toString().trim();
    final extras = List<String>.from(houseRules['extra_rules'] ?? const []);

    final items = <(IconData, String, String)>[
      if (checkIn.isNotEmpty) (Icons.login_rounded, pickLangText(lang, ko: '체크인', en: 'Check-in', ja: 'チェックイン', zh: '入住'), checkIn),
      if (checkOut.isNotEmpty) (Icons.logout_rounded, pickLangText(lang, ko: '체크아웃', en: 'Check-out', ja: 'チェックアウト', zh: '退房'), checkOut),
      if (selfCheckIn.isNotEmpty) (Icons.dialpad_rounded, pickLangText(lang, ko: '체크인 방식', en: 'Check-in Method', ja: 'チェックイン方法', zh: '入住方式'), selfCheckIn),
      if (quietHours.isNotEmpty) (Icons.nightlight_outlined, pickLangText(lang, ko: '매너타임', en: 'Quiet Hours', ja: 'クワイエットアワー', zh: '安静时段'), quietHours),
      if (smoking.isNotEmpty) (Icons.smoke_free_rounded, pickLangText(lang, ko: '금연 안내', en: 'Smoking Policy', ja: '喫煙ポリシー', zh: '禁烟规定'), smoking),
      if (pets.isNotEmpty) (Icons.pets_outlined, pickLangText(lang, ko: '반려동물', en: 'Pets', ja: 'ペット', zh: '宠物政策'), pets),
    ];

    if (items.isEmpty && extras.isEmpty && !isForeignOnly) {
      return Text(
        pickLangText(
          lang,
          ko: '상세 체크인·체크아웃 시간 및 환불 규정은 호스트 직거래 예약 창구에서 확인해 주세요.',
          en: 'Please confirm exact check-in/out times and cancellation rules on the host booking page.',
          ja: 'チェックイン・アウト時間やキャンセル規定の詳細はホストの予約窓口でご確認ください。',
          zh: '具体入住/退房时间及退改规则请在房东直订页面确认。',
        ),
        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: items
                .map((it) => Container(
                      width: 310,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE9ECEF)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(it.$1, size: 20, color: const Color(0xFF222222)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(it.$3, style: const TextStyle(fontSize: 13.5, color: Color(0xFF343A40))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...extras.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF6C757D)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13.5, height: 1.45))),
                  ],
                ),
              )),
        ],
      ],
    );
  }
}

class _LocationSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic> locationInfo;
  final String listingId;

  const _LocationSection({required this.data, required this.locationInfo, this.listingId = ''});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final addr = (locationInfo['display_address'] ?? '').toString().trim();
    final fallbackAddr = _tStayRegion(listingId, data, lang);
    final displayAddr = lang == AppLang.ko
        ? (addr.isNotEmpty ? addr : fallbackAddr)
        : (fallbackAddr.isNotEmpty ? fallbackAddr : addr);
    final nearby = (locationInfo['nearby_spots'] ?? '').toString().trim();
    final parking = (locationInfo['parking_note'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: kBrand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(displayAddr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (nearby.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('· 주변 환경: $nearby', style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ],
          if (parking.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('· 주차 안내: $parking', style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final q = Uri.encodeComponent(displayAddr.isNotEmpty ? displayAddr : '${data['title'] ?? ''}');
                  final uri = Uri.parse('https://map.naver.com/p/search/$q');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.map_outlined, size: 17, color: Color(0xFF03C75A)),
                label: Text(pickLangText(
                  lang,
                  ko: '네이버 지도에서 주변 위치 보기',
                  en: 'View Location on Naver Map',
                  ja: 'Naverマップで周辺を見る',
                  zh: '在 Naver 地图查看位置',
                )),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final lat = (data['lat'] as num?)?.toDouble() ?? (locationInfo['lat'] as num?)?.toDouble();
                  final lng = (data['lng'] as num?)?.toDouble() ?? (locationInfo['lng'] as num?)?.toDouble();
                  final titleEnc = Uri.encodeComponent((data['title'] ?? displayAddr).toString());
                  final url = (lat != null && lng != null)
                      ? 'https://map.kakao.com/link/to/$titleEnc,${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
                      : 'https://map.kakao.com/?q=${Uri.encodeComponent(displayAddr)}';
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.directions_bus_filled_rounded, size: 17, color: Color(0xFFD97706)),
                label: const Text('카카오 대중교통 · 내비 길찾기'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final lat = (data['lat'] as num?)?.toDouble() ?? (locationInfo['lat'] as num?)?.toDouble();
                  final lng = (data['lng'] as num?)?.toDouble() ?? (locationInfo['lng'] as num?)?.toDouble();
                  final dest = (lat != null && lng != null)
                      ? '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
                      : Uri.encodeComponent(displayAddr);
                  final url = 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=transit';
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.train_rounded, size: 17, color: Color(0xFF2563EB)),
                label: const Text('Google 대중교통 경로'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 편의시설 전체 보기 모달 (카테고리별 그룹 + 하단 취소선 미제공 시설)
void _showAllAmenitiesDialog(
  BuildContext context,
  List<AmenityCategoryGroup> groups,
  List<String> unavailable,
  int totalCount,
) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('숙소 편의시설 ($totalCount개)',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ...groups.map((g) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.category, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            ...g.items.map((item) => Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Row(
                                        children: [
                                          Icon(amenityIconFor(item), size: 22, color: const Color(0xFF222222)),
                                          const SizedBox(width: 14),
                                          Expanded(child: Text(item, style: const TextStyle(fontSize: 14.5))),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1, color: Color(0xFFF1F3F5)),
                                  ],
                                )),
                          ],
                        ),
                      )),
                  if (unavailable.isNotEmpty) ...[
                    const Text('숙소에 없는 시설 · 제한 사항',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ...unavailable.map((item) => Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Icon(Icons.not_interested_rounded, size: 20, color: Colors.grey.shade500),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        color: Colors.grey.shade600,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F3F5)),
                          ],
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
