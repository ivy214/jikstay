// 전국 17개 시·도 지역 축제·행사 및 전통 5일장 월간 인터랙티브 캘린더 뷰.
// 선택한 날짜의 진행·개막 축제와 전통 장날을 한눈에 보여주고, 클릭 시 팝업 없이 전체 상세 페이지 또는 네이버 지도로 연결한다.
import 'package:material_ui/material_ui.dart';

import 'detail_page.dart' show StorageImage;
import 'discovery_models.dart';
import 'i18n.dart';
import 'legal.dart';

class LocalCalendarView extends StatefulWidget {
  final List<DiscoveryItem> allItems;
  final List<TraditionalMarketInfo> markets;
  final String selectedProvince;
  final String query;
  final AppLang lang;
  final ValueChanged<DiscoveryItem> onSelectItem;
  final ValueChanged<String> onOpenExternalUrl;

  const LocalCalendarView({
    super.key,
    required this.allItems,
    required this.markets,
    required this.selectedProvince,
    required this.query,
    required this.lang,
    required this.onSelectItem,
    required this.onOpenExternalUrl,
  });

  @override
  State<LocalCalendarView> createState() => _LocalCalendarViewState();
}

class _ParsedEventEntry {
  final DiscoveryItem item;
  final DateTime start;
  final DateTime end;

  const _ParsedEventEntry({
    required this.item,
    required this.start,
    required this.end,
  });

  bool isActiveOn(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  bool overlapsMonth(int year, int month) {
    final mStart = DateTime(year, month, 1);
    final mEnd = DateTime(year, month + 1, 0);
    return !end.isBefore(mStart) && !start.isAfter(mEnd);
  }
}

class _LocalCalendarViewState extends State<LocalCalendarView> {
  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(now.year, now.month, 1);
  }

  List<_ParsedEventEntry> _filteredEvents() {
    final q = widget.query.trim().toLowerCase();
    final out = <_ParsedEventEntry>[];
    for (final it in widget.allItems) {
      if (it.category != DiscoveryCategory.event) continue;
      if (widget.selectedProvince != '전체' && it.province != widget.selectedProvince) continue;
      if (q.isNotEmpty) {
        final hay = '${it.title} ${it.province} ${it.regionLabel} ${it.address} ${it.subtitle}'.toLowerCase();
        if (!hay.contains(q)) continue;
      }
      final sd = parseYmdDate(it.startDate) ?? parseYmdDate(it.endDate);
      final ed = parseYmdDate(it.endDate) ?? sd;
      if (sd == null || ed == null) continue;
      final normStart = DateTime(sd.year, sd.month, sd.day);
      final normEnd = ed.isBefore(normStart) ? normStart : DateTime(ed.year, ed.month, ed.day);
      out.add(_ParsedEventEntry(item: it, start: normStart, end: normEnd));
    }
    out.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      return cmp != 0 ? cmp : b.item.priorityScore.compareTo(a.item.priorityScore);
    });
    return out;
  }

  void _changeMonth(int deltaMonths) {
    setState(() {
      final next = DateTime(_focusedMonth.year, _focusedMonth.month + deltaMonths, 1);
      _focusedMonth = next;
      final now = DateTime.now();
      if (next.year == now.year && next.month == now.month) {
        _selectedDate = DateTime(now.year, now.month, now.day);
      } else {
        _selectedDate = DateTime(next.year, next.month, 1);
      }
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(now.year, now.month, 1);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  String _weekdayLabel(int weekday, AppLang lang) {
    if (lang != AppLang.ko) {
      const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return en[(weekday - 1).clamp(0, 6)];
    }
    const ko = ['월', '화', '수', '목', '금', '토', '일'];
    return ko[(weekday - 1).clamp(0, 6)];
  }

  String _fmtYmdShort(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildCalendarCard({
    required AppLang lang,
    required List<_ParsedEventEntry> events,
    required DateTime today,
  }) {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingEmpty = firstDay.weekday % 7; // 일요일=0 .. 토요일=6
    final totalCells = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;

    final quickMonths = List.generate(4, (i) => DateTime(today.year, today.month + i, 1));
    const weekHeadersKo = ['일', '월', '화', '수', '목', '금', '토'];
    const weekHeadersEn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final weekHeaders = lang == AppLang.ko ? weekHeadersKo : weekHeadersEn;

    final sourceMarkets = widget.markets.isNotEmpty ? widget.markets : kFallbackTraditional5DayMarkets;

    return Container(
      key: const Key('local_calendar_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x080F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 월 이동 헤더
          Row(
            children: [
              IconButton(
                key: const Key('cal_prev_month_btn'),
                visualDensity: VisualDensity.compact,
                tooltip: lang == AppLang.ko ? '이전 달' : 'Previous Month',
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded, size: 24),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      lang == AppLang.ko ? '$year년 $month월' : '$year-${month.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang == AppLang.ko
                          ? '${widget.selectedProvince == '전체' ? '전국 17개 시·도' : widget.selectedProvince} 축제 · 전통 5일장 달력'
                          : '${trProvince(widget.selectedProvince, lang)} Festivals & 5-Day Markets',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('cal_today_btn'),
                onPressed: _jumpToToday,
                child: Text(
                  lang == AppLang.ko ? '오늘' : 'Today',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
              IconButton(
                key: const Key('cal_next_month_btn'),
                visualDensity: VisualDensity.compact,
                tooltip: lang == AppLang.ko ? '다음 달' : 'Next Month',
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right_rounded, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 빠른 월 점프 칩 & 범례
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...quickMonths.map((qm) {
                final active = qm.year == year && qm.month == month;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() {
                    _focusedMonth = qm;
                    _selectedDate = (qm.year == today.year && qm.month == today.month)
                        ? today
                        : DateTime(qm.year, qm.month, 1);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: active ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      lang == AppLang.ko ? '${qm.month}월' : '${qm.year}.${qm.month}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: active ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 6),
              const Text(
                '🎉 축제·행사  🎊 당일개막  🧺 5일장',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 요일 헤더
          Row(
            children: List.generate(7, (idx) {
              final color = idx == 0
                  ? const Color(0xFFDC2626)
                  : (idx == 6 ? const Color(0xFF2563EB) : const Color(0xFF475569));
              return Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      weekHeaders[idx],
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                ),
              );
            }),
          ),
          const Divider(height: 8),

          // 날짜 그리드
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: 0.86,
            ),
            itemBuilder: (_, cellIdx) {
              final dayNum = cellIdx - leadingEmpty + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(year, month, dayNum);
              final isSelected = _sameDay(date, _selectedDate);
              final isToday = _sameDay(date, today);
              final colIdx = cellIdx % 7;

              final activeEvs = events.where((e) => e.isActiveOn(date)).toList();
              final startsToday = activeEvs.any((e) => _sameDay(e.start, date));
              final provMarkets = widget.selectedProvince == '전체'
                  ? sourceMarkets.where((m) => m.opensOnDay(dayNum)).toList()
                  : sourceMarkets
                      .where((m) => m.province == widget.selectedProvince && m.opensOnDay(dayNum))
                      .toList();

              final dayTextColor = isSelected
                  ? const Color(0xFF065F46)
                  : (colIdx == 0
                      ? const Color(0xFFDC2626)
                      : (colIdx == 6 ? const Color(0xFF2563EB) : const Color(0xFF0F172A)));

              return InkWell(
                key: Key('cal_day_${year}_${month}_$dayNum'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedDate = date),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFECFDF5)
                        : (activeEvs.isNotEmpty ? const Color(0xFFFAF5FF) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF059669)
                          : (isToday ? const Color(0xFF94A3B8) : const Color(0xFFE2E8F0)),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected || isToday ? FontWeight.w900 : FontWeight.w700,
                              color: dayTextColor,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 2),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFF059669),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      if (activeEvs.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: startsToday ? const Color(0xFF7C3AED) : const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            startsToday ? '🎊${activeEvs.length}' : '🎉${activeEvs.length}',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: startsToday ? Colors.white : const Color(0xFF6D28D9),
                            ),
                          ),
                        ),
                      if (provMarkets.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '🧺${provMarkets.length}',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSchedulePanel({
    required AppLang lang,
    required List<_ParsedEventEntry> allEvents,
    required DateTime today,
  }) {
    final dayEvents = allEvents.where((e) => e.isActiveOn(_selectedDate)).toList();
    final monthEvents = allEvents.where((e) => e.overlapsMonth(_focusedMonth.year, _focusedMonth.month)).toList();

    final sourceMarkets = widget.markets.isNotEmpty ? widget.markets : kFallbackTraditional5DayMarkets;
    final exactProvMarkets = widget.selectedProvince == '전체'
        ? sourceMarkets.where((m) => m.opensOnDay(_selectedDate.day)).toList()
        : sourceMarkets
            .where((m) => m.province == widget.selectedProvince && m.opensOnDay(_selectedDate.day))
            .toList();
    final fallbackMarkets = exactProvMarkets.isNotEmpty
        ? exactProvMarkets
        : sourceMarkets.where((m) => m.opensOnDay(_selectedDate.day)).take(3).toList();
    final usingFallbackMarket = widget.selectedProvince != '전체' && exactProvMarkets.isEmpty;

    final naverRegionFestivalUrl =
        'https://map.naver.com/p/search/${Uri.encodeComponent('${widget.selectedProvince == '전체' ? '전국' : widget.selectedProvince} 축제 가볼만한곳')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 선택 날짜 브리핑 헤더 카드
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lang == AppLang.ko
                          ? '📅 ${_selectedDate.month}월 ${_selectedDate.day}일 (${_weekdayLabel(_selectedDate.weekday, lang)}) 로컬 일정'
                          : '📅 Schedule for ${_fmtYmdShort(_selectedDate)} (${_weekdayLabel(_selectedDate.weekday, lang)})',
                      style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDCFCE7),
                      foregroundColor: const Color(0xFF166534),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => widget.onOpenExternalUrl(naverRegionFestivalUrl),
                    icon: const Icon(Icons.map_rounded, size: 15),
                    label: Text(
                      lang == AppLang.ko ? '🟢 네이버지도' : '🟢 Naver Map',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                lang == AppLang.ko
                    ? '진행·개막 축제 ${dayEvents.length}건 · 전통 5일장 ${exactProvMarkets.isNotEmpty ? exactProvMarkets.length : fallbackMarkets.length}곳'
                    : '${dayEvents.length} active festivals · ${fallbackMarkets.length} traditional 5-day markets',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
              ),
              const SizedBox(height: 14),

              if (dayEvents.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    lang == AppLang.ko
                        ? '선택하신 날짜 당일에 진행 중인 등록 축제는 없습니다.\n달력에서 🎉 표시된 날짜를 누르시거나 아래 ‘이달의 축제 타임라인’에서 개막 일정을 바로 확인해 보세요.'
                        : 'No registered festival on this exact date. Tap a highlighted 🎉 day on the calendar or browse this month’s lineup below.',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.55),
                  ),
                )
              else
                ...dayEvents.map((ev) => _CalendarEventTile(
                      entry: ev,
                      selectedDate: _selectedDate,
                      lang: lang,
                      onTapDetail: () => widget.onSelectItem(ev.item),
                      onOpenNaver: () => widget.onOpenExternalUrl(ev.item.naverRouteUrl),
                    )),

              // 전통 5일장 장날 섹션
              if (fallbackMarkets.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                ),
                Text(
                  lang == AppLang.ko
                      ? (usingFallbackMarket
                          ? '🧺 오늘(${_selectedDate.day % 10}일 끝자리) 열리는 전국 대표 전통 5일장'
                          : '🧺 선택 날짜(${_selectedDate.day}일) 열리는 전통 5일장 장날')
                      : '🧺 Traditional 5-Day Markets Open on Day ${_selectedDate.day}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                ),
                const SizedBox(height: 8),
                ...fallbackMarkets.map(
                  (mkt) {
                    final mktNaverUrl =
                        'https://map.naver.com/p/search/${Uri.encodeComponent('${mkt.province} ${mkt.city} ${mkt.title}')}';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[${trProvince(mkt.province, lang)} ${mkt.tCity(lang)}] ${mkt.tTitle(lang)} (${mkt.days.join("·")}${pickLangText(lang, ko: '일장', en: ' Market', ja: '日市', zh: '日市')})',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF78350F),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${pickLangText(lang, ko: '별미·특산', en: 'Specialty', ja: '名物', zh: '特產')}: ${mkt.tSpecialty(lang)}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () => widget.onOpenExternalUrl(mktNaverUrl),
                            child: Text(
                              lang == AppLang.ko ? '🟢 네이버지도 ↗' : '🟢 Map ↗',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),

        // 2. 이달의 전체 축제 타임라인
        if (monthEvents.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lang == AppLang.ko
                      ? '📌 ${_focusedMonth.month}월 주요 개막·진행 축제 전체 타임라인 (${monthEvents.length}건)'
                      : '📌 All Festivals in ${_focusedMonth.year}.${_focusedMonth.month} (${monthEvents.length})',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 10),
                ...monthEvents.take(12).map(
                      (ev) => _CalendarEventTile(
                        entry: ev,
                        selectedDate: today,
                        lang: lang,
                        onTapDetail: () => widget.onSelectItem(ev.item),
                        onOpenNaver: () => widget.onOpenExternalUrl(ev.item.naverRouteUrl),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final events = _filteredEvents();
    final isWide = MediaQuery.sizeOf(context).width >= 880;

    return SingleChildScrollView(
      key: const Key('calendar_view_scroll'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 52,
                      child: _buildCalendarCard(lang: lang, events: events, today: today),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 48,
                      child: _buildSchedulePanel(lang: lang, allEvents: events, today: today),
                    ),
                  ],
                )
              else ...[
                _buildCalendarCard(lang: lang, events: events, today: today),
                const SizedBox(height: 16),
                _buildSchedulePanel(lang: lang, allEvents: events, today: today),
              ],
              const SizedBox(height: 24),
              const LegalFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  final _ParsedEventEntry entry;
  final DateTime selectedDate;
  final AppLang lang;
  final VoidCallback onTapDetail;
  final VoidCallback onOpenNaver;

  const _CalendarEventTile({
    required this.entry,
    required this.selectedDate,
    required this.lang,
    required this.onTapDetail,
    required this.onOpenNaver,
  });

  String _fmt(DateTime d) => '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final it = entry.item;
    final isOpeningDay = entry.start.year == selectedDate.year &&
        entry.start.month == selectedDate.month &&
        entry.start.day == selectedDate.day;
    final isClosingDay = entry.end.year == selectedDate.year &&
        entry.end.month == selectedDate.month &&
        entry.end.day == selectedDate.day;
    final isUpcoming = selectedDate.isBefore(entry.start);

    final statusLabel = isOpeningDay
        ? (lang == AppLang.ko ? '🎊 오늘 개막' : '🎊 Opens Today')
        : (isClosingDay
            ? (lang == AppLang.ko ? '⏰ 오늘 마감' : '⏰ Last Day')
            : (isUpcoming
                ? (lang == AppLang.ko ? '📅 개막 예정' : '📅 Upcoming')
                : (lang == AppLang.ko ? '🎉 진행중' : '🎉 Live')));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTapDetail,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: it.imageUrl.isNotEmpty
                      ? StorageImage(url: it.imageUrl, cacheWidth: 220)
                      : Container(
                          color: const Color(0xFFEDE9FE),
                          alignment: Alignment.center,
                          child: const Icon(Icons.celebration_rounded, color: Color(0xFF7C3AED)),
                        ),
                ),
              ),
              const SizedBox(width: 11),
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
                            color: const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${it.province} · $statusLabel',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF6D28D9),
                            ),
                          ),
                        ),
                        Text(
                          '${_fmt(entry.start)} ~ ${_fmt(entry.end)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      it.tTitle(lang),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lang == AppLang.ko ? '매거진 상세 보기 →' : 'Read Details →',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: onOpenNaver,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              lang == AppLang.ko ? '🟢 네이버지도 ↗' : '🟢 Naver Map ↗',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF15803D),
                              ),
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
      ),
    );
  }
}
