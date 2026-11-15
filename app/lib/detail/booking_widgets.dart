part of '../detail_page.dart';

class _VerifiedTrustBar extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isForeignOnly;

  const _VerifiedTrustBar({required this.data, required this.isForeignOnly});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final rawUrl = (data['direct_booking_url'] ?? data['naver_map_url'] ?? '').toString();
    final channel = bookingChannelName(rawUrl, lang: lang);
    final licenseLabel = _tLicenseType((data['license_type'] ?? '').toString(), lang);
    final licenseNum = (data['license_number'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDDDDD)),
          ),
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.assured_workload_rounded,
                    color: Color(0xFF198754),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stayVerificationLabel(data, lang),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        licenseNum.isNotEmpty ? '$licenseLabel · $licenseNum' : licenseLabel,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.savings_outlined, color: kBrand, size: 24),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickLangText(
                          lang,
                          ko: '게스트 중개수수료 0원',
                          en: '0% Guest Service Fee',
                          ja: 'ゲスト仲介手数料 0ウォン',
                          zh: '旅客平台服务费 0韩元',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        pickLangText(
                          lang,
                          ko: '연결 창구: $channel',
                          en: 'Channel: $channel',
                          ja: '予約窓口: $channel',
                          zh: '预订渠道: $channel',
                        ),
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isForeignOnly) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFF664D03)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pickLangText(
                      lang,
                      ko: '외국인 전용 숙소 (외국인관광도시민박업 · 내국인 투숙 불가)',
                      en: 'Foreign Visitors Only (Licensed Urban Homestay · Domestic Korean guests not eligible)',
                      ja: '外国人専用宿泊施設（外国人観光都市民泊業・韓国国内居住者は宿泊不可）',
                      zh: '仅限外籍旅客入住（外国人观光城市民宿 · 韩国本国居民不可入住）',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 우측 고정형 직거래 예약·문의 신청 전환 카드 (Airbnb Sticky Reservation Widget 참조)
class _DirectBookingConversionCard extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final DateTimeRange? dateRange;
  final int adults;
  final int children;
  final bool includePromo;
  final VoidCallback onPickDates;
  final void Function(int adults, int children) onGuestsChanged;
  final ValueChanged<bool> onIncludePromoChanged;

  const _DirectBookingConversionCard({
    required this.listingId,
    required this.data,
    required this.dateRange,
    required this.adults,
    required this.children,
    required this.includePromo,
    required this.onPickDates,
    required this.onGuestsChanged,
    required this.onIncludePromoChanged,
  });

  void _showGuestPicker(BuildContext context, int maxGuests) {
    final lang = appLangNotifier.value;
    int tempAdults = adults;
    int tempChildren = children;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final total = tempAdults + tempChildren;
          return AlertDialog(
            title: Text(
              pickLangText(
                lang,
                ko: '인원 선택 (최대 $maxGuests명)',
                en: 'Select Guests (Max $maxGuests)',
                ja: '人数選択（最大$maxGuests名）',
                zh: '选择人数（最多$maxGuests人）',
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GuestStepperRow(
                  label: pickLangText(lang, ko: '성인', en: 'Adults', ja: '大人', zh: '成人'),
                  subtitle: pickLangText(lang, ko: '만 13세 이상', en: 'Ages 13 or above', ja: '13歳以上', zh: '13岁及以上'),
                  value: tempAdults,
                  canDec: tempAdults > 1,
                  canInc: total < maxGuests,
                  onChanged: (v) => setModalState(() => tempAdults = v),
                ),
                const Divider(),
                _GuestStepperRow(
                  label: pickLangText(lang, ko: '어린이', en: 'Children', ja: '子供', zh: '儿童'),
                  subtitle: pickLangText(lang, ko: '만 2~12세', en: 'Ages 2–12', ja: '2〜12歳', zh: '2–12岁'),
                  value: tempChildren,
                  canDec: tempChildren > 0,
                  canInc: total < maxGuests,
                  onChanged: (v) => setModalState(() => tempChildren = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(pickLangText(lang, ko: '취소', en: 'Cancel', ja: 'キャンセル', zh: '取消')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kBrand),
                onPressed: () {
                  onGuestsChanged(tempAdults, tempChildren);
                  Navigator.pop(ctx);
                },
                child: Text(pickLangText(lang, ko: '적용', en: 'Apply', ja: '適用', zh: '应用')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final pricing = data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : null;
    final est = calculateStayEstimate(pricing, dateRange: dateRange);
    final rawUrl = (data['direct_booking_url'] ?? '').toString();
    final channel = bookingChannelName(rawUrl, lang: lang);
    final promoTitle = (data['promo_title'] ?? '').toString().trim();
    final maxGuests = (data['capacity_max'] as num?)?.toInt() ?? 10;
    final totalGuests = adults + children;
    final guestSummary = lang == AppLang.ko
        ? '게스트 $totalGuests명 (성인 $adults${children > 0 ? ', 어린이 $children' : ''})'
        : pickLangText(
            lang,
            ko: '',
            en: '$totalGuests guest${totalGuests > 1 ? 's' : ''} ($adults adult${adults > 1 ? 's' : ''}${children > 0 ? ', $children child' : ''})',
            ja: 'ゲスト$totalGuests名（大人$adults${children > 0 ? '・子供$children' : ''}）',
            zh: '$totalGuests位房客（成人$adults${children > 0 ? '，儿童$children' : ''}）',
          );
    final selectDateLabel = pickLangText(lang, ko: '날짜 선택', en: 'Select date', ja: '日付を選択', zh: '选择日期');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDDDDD)),
        boxShadow: const [
          BoxShadow(color: Color(0x18000000), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // (수수료 절감액 배지는 실제 직거래 가격을 알 수 없어 표시하지 않는다)

          // 대표 예상 요금
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                est.estimatedAmount != null ? formatWon(est.estimatedAmount!) : shortPrice(pricing, lang: lang),
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  est.estimatedAmount != null ? '· ${est.unitLabel}' : '',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 에어비앤비 스타일 2단 일정·인원 선택 박스
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB0B0B0)),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  onTap: onPickDates,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickLangText(lang, ko: '체크인', en: 'CHECK-IN', ja: 'チェックイン', zh: '入住'),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateRange != null ? _fmtDate(dateRange!.start) : selectDateLabel,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, height: 44, color: const Color(0xFFB0B0B0)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickLangText(lang, ko: '체크아웃', en: 'CHECK-OUT', ja: 'チェックアウト', zh: '退房'),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateRange != null ? _fmtDate(dateRange!.end) : selectDateLabel,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFB0B0B0)),
                InkWell(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  onTap: () => _showGuestPicker(context, maxGuests),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pickLangText(lang, ko: '인원', en: 'GUESTS', ja: '人数', zh: '人数'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(guestSummary, style: const TextStyle(fontSize: 13.5)),
                          ],
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 직거래 혜택 자동 포함 체크박스
          if (promoTitle.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onIncludePromoChanged(!includePromo),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: includePromo,
                        activeColor: kBrand,
                        onChanged: (v) => onIncludePromoChanged(v ?? true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickLangText(
                          lang,
                          ko: '문의 시 [$promoTitle] 함께 신청',
                          en: 'Include [$promoTitle] in inquiry',
                          ja: 'お問い合わせ時に[$promoTitle]も申請',
                          zh: '咨询时一并申请[$promoTitle]',
                        ),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 풀와이드 마젠타/코랄 메인 신청 CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kBrand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => goDirectBooking(
                context,
                listingId,
                data,
                dateRange: dateRange,
                adults: adults,
                children: children,
                includePromo: includePromo,
              ),
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: Text(
                bookingCtaLabel(rawUrl, data: data, lang: lang),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              pickLangText(
                lang,
                ko: '예약 확정 전에는 요금이 청구되지 않습니다.',
                en: 'You won\'t be charged before confirmation.',
                ja: '予約確定前に料金が請求されることはありません。',
                zh: '在预订确认前不会向您收取费用。',
              ),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF555555)),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              pickLangText(
                lang,
                ko: '선택한 일정·인원이 자동 복사되어 $channel 창구로 연결됩니다.',
                en: 'Selected dates & guests are copied and linked to $channel.',
                ja: '選択した日程・人数が自動コピーされ、$channel窓口へ接続されます。',
                zh: '所选日期与人数将自动复制并跳转至$channel。',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                pickLangText(lang, ko: '직스테이 중개수수료', en: 'Jikstay Service Fee', ja: 'ジクステイ仲介手数料', zh: 'Jikstay 平台服务费'),
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF495057)),
              ),
              Text(
                pickLangText(lang, ko: '0원 (무료 직결)', en: '₩0 (Direct Free)', ja: '0ウォン（無料直結）', zh: '0韩元（免费直连）'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF198754)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuestStepperRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final int value;
  final bool canDec;
  final bool canInc;
  final ValueChanged<int> onChanged;

  const _GuestStepperRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.canDec,
    required this.canInc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          Row(
            children: [
              IconButton.outlined(
                visualDensity: VisualDensity.compact,
                onPressed: canDec ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove, size: 16),
              ),
              SizedBox(
                width: 34,
                child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton.outlined(
                visualDensity: VisualDensity.compact,
                onPressed: canInc ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileStickyBookingBar extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final DateTimeRange? dateRange;
  final int adults;
  final int children;
  final bool includePromo;
  final VoidCallback onPickDates;

  const _MobileStickyBookingBar({
    required this.listingId,
    required this.data,
    required this.dateRange,
    required this.adults,
    required this.children,
    required this.includePromo,
    required this.onPickDates,
  });

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final pricing = data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : null;
    final est = calculateStayEstimate(pricing, dateRange: dateRange);
    final rawUrl = (data['direct_booking_url'] ?? '').toString();
    final channel = bookingChannelName(rawUrl, lang: lang);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3E5E8))),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPickDates,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      est.estimatedAmount != null ? formatWon(est.estimatedAmount!) : shortPrice(pricing, lang: lang),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF222222)),
                    ),
                    Text(
                      dateRange != null
                          ? pickLangText(
                              lang,
                              ko: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 수수료 0원',
                              en: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 0% Fee',
                              ja: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 手数料0ウォン',
                              zh: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 0服务费',
                            )
                          : pickLangText(
                              lang,
                              ko: '중개수수료 0원 · $channel',
                              en: '0% Fee · $channel',
                              ja: '仲介手数料0ウォン · $channel',
                              zh: '0平台费 · $channel',
                            ),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kBrand,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => goDirectBooking(
                  context,
                  listingId,
                  data,
                  dateRange: dateRange,
                  adults: adults,
                  children: children,
                  includePromo: includePromo,
                ),
                child: Text(
                  bookingCtaLabel(rawUrl, data: data, lang: appLangNotifier.value),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
