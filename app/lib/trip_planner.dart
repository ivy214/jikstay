// 주말 1박2일(한국인) & 3·5일(외국인) 여행 코스 자동 생성기 + URL 공유(딥링크) 모듈.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'discovery_models.dart';
import 'i18n.dart';
import 'web_utils.dart';

enum TripTheme { all, festival, food, hanok }

class TripStop {
  final int day;
  final String slotKey; // 'morning' | 'lunch' | 'afternoon' | 'stay'
  final DiscoveryItem item;

  const TripStop({
    required this.day,
    required this.slotKey,
    required this.item,
  });
}

class TripPlan {
  final String province;
  final int days;
  final TripTheme theme;
  final bool foreignerOnly;
  final List<TripStop> stops;

  const TripPlan({
    required this.province,
    required this.days,
    required this.theme,
    required this.foreignerOnly,
    required this.stops,
  });
}

bool _isForeignerEligibleStay(DiscoveryItem s) {
  if (s.category != DiscoveryCategory.stay) return false;
  final lic = s.licenseType;
  final title = s.title;
  if (title.contains('내국인 전용')) return false;
  // 외국인관광도시민박업, 한옥체험업, 관광숙박업(호텔/호스텔) 우선, 미분류 공공숙소도 허용
  if (lic.contains('외국인') || lic.contains('한옥') || lic.contains('호텔') || lic.contains('호스텔')) {
    return true;
  }
  return true;
}

int _stayForeignerScore(DiscoveryItem s) {
  final lic = s.licenseType;
  if (lic.contains('외국인')) return 3;
  if (lic.contains('한옥') || lic.contains('호텔') || lic.contains('호스텔')) return 2;
  return 1;
}

int _daysUntilStart(DiscoveryItem it) {
  final s = it.startDate.replaceAll(RegExp(r'[^0-9]'), '');
  if (s.length < 8) return 999;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return 999;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(y, m, d);
  final diff = target.difference(today).inDays;
  return diff < 0 ? 0 : diff;
}

/// 선택한 지역·일수·테마에 맞춰 반경 45km 내 명소·맛집·축제·합법 숙소를 자동 조합한다.
TripPlan generateTripPlan({
  required List<DiscoveryItem> allItems,
  String province = '전체',
  int days = 2,
  TripTheme theme = TripTheme.all,
  bool foreignerOnly = false,
  int seedOffset = 0,
}) {
  final prov = province.trim().isEmpty ? '전체' : province.trim();
  final scoped = prov == '전체'
      ? allItems
      : allItems.where((it) => it.province == prov).toList();
  final pool = scoped.isNotEmpty ? scoped : allItems;

  // 1. 앵커 선정: 임박/진행중 축제 > 스토리/볼거리 > 일반 아이템
  final anchors = <DiscoveryItem>[];
  for (final it in pool) {
    if (it.category == DiscoveryCategory.event) {
      anchors.add(it);
    }
  }
  anchors.sort((a, b) {
    final da = _daysUntilStart(a);
    final db = _daysUntilStart(b);
    if (da != db) return da.compareTo(db);
    return b.priorityScore.compareTo(a.priorityScore);
  });

  if (anchors.isEmpty || theme == TripTheme.food || theme == TripTheme.hanok) {
    final fallbackAnchors = pool
        .where((it) => it.category == DiscoveryCategory.attraction || it.category == DiscoveryCategory.ebook)
        .toList()
      ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    anchors.addAll(fallbackAnchors);
  }
  if (anchors.isEmpty && pool.isNotEmpty) {
    anchors.add(pool.first);
  }

  final anchor = anchors.isEmpty ? null : anchors[seedOffset % anchors.length];
  final bundle = anchor != null
      ? buildConnectedBundle(anchor, allItems, maxRadiusKm: 55.0, limitPerType: 20)
      : const ConnectedBundle();

  final attractions = <DiscoveryItem>[
    if (anchor != null && (anchor.category == DiscoveryCategory.attraction || anchor.category == DiscoveryCategory.ebook))
      anchor,
    ...bundle.attractions,
    ...pool.where((it) => it.category == DiscoveryCategory.attraction || it.category == DiscoveryCategory.ebook),
  ];
  final events = <DiscoveryItem>[
    if (anchor != null && anchor.category == DiscoveryCategory.event) anchor,
    ...bundle.events,
    ...pool.where((it) => it.category == DiscoveryCategory.event),
  ];
  final foods = <DiscoveryItem>[
    ...bundle.foods,
    ...pool.where((it) => it.category == DiscoveryCategory.food),
  ];
  final stays = <DiscoveryItem>[
    ...bundle.stays,
    ...pool.where((it) => it.category == DiscoveryCategory.stay),
  ].where((s) => !foreignerOnly || _isForeignerEligibleStay(s)).toList();

  if (foreignerOnly) {
    stays.sort((a, b) => _stayForeignerScore(b).compareTo(_stayForeignerScore(a)));
  }

  final usedIds = <String>{};
  DiscoveryItem? pickNext(List<DiscoveryItem> list, {bool preferHanok = false}) {
    if (preferHanok) {
      for (final it in list) {
        if (!usedIds.contains(it.id) && (it.title.contains('한옥') || it.licenseType.contains('한옥'))) {
          usedIds.add(it.id);
          return it;
        }
      }
    }
    for (final it in list) {
      if (!usedIds.contains(it.id)) {
        usedIds.add(it.id);
        return it;
      }
    }
    return null;
  }

  final stops = <TripStop>[];
  final clampedDays = days.clamp(1, 5);
  for (int d = 1; d <= clampedDays; d++) {
    final morning = theme == TripTheme.festival && d == 1
        ? (pickNext(events) ?? pickNext(attractions))
        : (pickNext(attractions) ?? pickNext(events));
    if (morning != null) stops.add(TripStop(day: d, slotKey: 'morning', item: morning));

    final lunch = pickNext(foods);
    if (lunch != null) stops.add(TripStop(day: d, slotKey: 'lunch', item: lunch));

    final afternoon = theme == TripTheme.food
        ? (pickNext(foods) ?? pickNext(events) ?? pickNext(attractions))
        : (pickNext(events) ?? pickNext(attractions));
    if (afternoon != null) stops.add(TripStop(day: d, slotKey: 'afternoon', item: afternoon));

    if (d < clampedDays) {
      final stay = pickNext(stays, preferHanok: theme == TripTheme.hanok);
      if (stay != null) stops.add(TripStop(day: d, slotKey: 'stay', item: stay));
    }
  }

  return TripPlan(
    province: prov,
    days: clampedDays,
    theme: theme,
    foreignerOnly: foreignerOnly,
    stops: stops,
  );
}

String encodeTripPlanParam(TripPlan plan) {
  final fFlag = plan.foreignerOnly ? '1' : '0';
  final encodedStops = plan.stops.map((s) => '${s.day}.${s.slotKey[0]}.${s.item.id}').join(',');
  return 'd${plan.days}:${plan.province}:${plan.theme.name}:$fFlag:$encodedStops';
}

TripPlan? decodeTripPlanParam(String raw, List<DiscoveryItem> allItems) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(':');
  if (parts.length < 5) return null;
  final days = int.tryParse(parts[0].replaceFirst('d', '')) ?? 2;
  final province = parts[1].isEmpty ? '전체' : parts[1];
  final theme = TripTheme.values.firstWhere(
    (t) => t.name == parts[2],
    orElse: () => TripTheme.all,
  );
  final foreignerOnly = parts[3] == '1';
  final byId = {for (final it in allItems) it.id: it};
  final stops = <TripStop>[];
  for (final token in parts.sublist(4).join(':').split(',')) {
    final segs = token.split('.');
    if (segs.length < 3) continue;
    final day = int.tryParse(segs[0]) ?? 1;
    final shortSlot = segs[1];
    final slotKey = switch (shortSlot) {
      'm' => 'morning',
      'l' => 'lunch',
      'a' => 'afternoon',
      's' => 'stay',
      _ => 'morning',
    };
    final id = segs.sublist(2).join('.');
    final found = byId[id];
    if (found != null) {
      stops.add(TripStop(day: day, slotKey: slotKey, item: found));
    }
  }
  if (stops.isEmpty) return null;
  return TripPlan(
    province: province,
    days: days.clamp(1, 5),
    theme: theme,
    foreignerOnly: foreignerOnly,
    stops: stops,
  );
}

class TripPlannerDialog extends StatefulWidget {
  final List<DiscoveryItem> allItems;
  final String initialProvince;
  final TripPlan? initialPlan;
  final ValueChanged<DiscoveryItem> onOpenItem;

  const TripPlannerDialog({
    super.key,
    required this.allItems,
    required this.initialProvince,
    this.initialPlan,
    required this.onOpenItem,
  });

  @override
  State<TripPlannerDialog> createState() => _TripPlannerDialogState();
}

class _TripPlannerDialogState extends State<TripPlannerDialog> {
  late String _province;
  late int _days;
  late TripTheme _theme;
  late bool _foreignerOnly;
  late TripPlan _plan;
  int _seedOffset = 0;

  @override
  void initState() {
    super.initState();
    final init = widget.initialPlan;
    if (init != null) {
      _province = init.province;
      _days = init.days;
      _theme = init.theme;
      _foreignerOnly = init.foreignerOnly;
      _plan = init;
    } else {
      final lang = appLangNotifier.value;
      _province = widget.initialProvince;
      _days = lang == AppLang.ko ? 2 : 3;
      _theme = TripTheme.all;
      _foreignerOnly = lang != AppLang.ko;
      _rebuildPlan();
    }
  }

  void _rebuildPlan() {
    _plan = generateTripPlan(
      allItems: widget.allItems,
      province: _province,
      days: _days,
      theme: _theme,
      foreignerOnly: _foreignerOnly,
      seedOffset: _seedOffset,
    );
  }

  String _slotLabel(String slotKey, AppLang lang) => switch (slotKey) {
        'morning' => pickLangText(lang, ko: '오전 코스', en: 'Morning', ja: '午前', zh: '上午'),
        'lunch' => pickLangText(lang, ko: '로컬 미식', en: 'Local Food', ja: 'ご当地グルメ', zh: '当地美食'),
        'afternoon' => pickLangText(lang, ko: '오후 · 축제', en: 'Afternoon / Event', ja: '午後・祭り', zh: '下午・庆典'),
        'stay' => pickLangText(lang, ko: '수수료 0원 숙박', en: '0% Fee Stay', ja: '手数料0円宿', zh: '0手续费住宿'),
        _ => slotKey,
      };

  String _themeLabel(TripTheme t, AppLang lang) => switch (t) {
        TripTheme.all => pickLangText(lang, ko: '균형 추천', en: 'Balanced', ja: 'バランス', zh: '综合推荐'),
        TripTheme.festival => pickLangText(lang, ko: '축제·행사', en: 'Festivals', ja: '祭り・イベント', zh: '庆典活动'),
        TripTheme.food => pickLangText(lang, ko: '로컬 미식', en: 'Foodie', ja: 'グルメ', zh: '美食之旅'),
        TripTheme.hanok => pickLangText(lang, ko: '한옥·힐링', en: 'Hanok & Calm', ja: '韓屋・癒し', zh: '韩屋慢游'),
      };

  Future<void> _copyShareUrl(AppLang lang) async {
    final param = Uri.encodeComponent(encodeTripPlanParam(_plan));
    final langParam = lang == AppLang.ko ? '' : '&lang=${lang.code}';
    final url = '${currentSiteOrigin()}/?plan=$param$langParam';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pickLangText(
            lang,
            ko: '내 여행 코스 링크가 복사되었습니다! 단톡방·SNS에 공유해 보세요.',
            en: 'Trip itinerary link copied! Share it with friends.',
            ja: '旅行プランのリンクをコピーしました！',
            zh: '行程链接已复制，快分享给同行伙伴吧！',
          )),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final provinces = <String>['전체', ...kProvinceJumpList.where((p) => p.key != '전체').map((p) => p.key)];
    final grouped = <int, List<TripStop>>{};
    for (final s in _plan.stops) {
      grouped.putIfAbsent(s.day, () => []).add(s);
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.route_rounded, color: Color(0xFF0F766E), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pickLangText(
                            lang,
                            ko: '주말 1박2일 · 외국인 3·5일 코스 자동 생성기',
                            en: 'Korea 2 / 3 / 5-Day Trip & Legal Stay Planner',
                            ja: '韓国 2日・3日・5日 旅行＆公認宿プランナー',
                            zh: '韩国 2日/3日/5日 行程与合法住宿规划',
                          ),
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          pickLangText(
                            lang,
                            ko: '임박 축제·로컬 맛집·수수료 0원 합법 숙소를 반경 55km 내로 자동 연결합니다.',
                            en: 'Auto-combines festivals, local food & 0% fee verified stays within 55km.',
                            ja: '開催間近の祭り・地元グルメ・手数料0円公認宿を半径55km以内で自動組合せ。',
                            zh: '自动串联方圆55公里内的庆典、地道美食与0手续费合法住宿。',
                          ),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            // Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final d in [2, 3, 5])
                        ChoiceChip(
                          key: Key('plan_days_$d'),
                          label: Text(switch (d) {
                            2 => pickLangText(lang, ko: '주말 1박2일', en: '2 Days (Weekend)', ja: '1泊2日', zh: '周末2日游'),
                            3 => pickLangText(lang, ko: '3일 추천', en: '3 Days', ja: '3日間', zh: '3日游'),
                            _ => pickLangText(lang, ko: '5일 완주', en: '5 Days', ja: '5日間', zh: '5日深度游'),
                          }),
                          selected: _days == d,
                          onSelected: (_) => setState(() {
                            _days = d;
                            if (d >= 3 && lang != AppLang.ko) _foreignerOnly = true;
                            _rebuildPlan();
                          }),
                        ),
                      FilterChip(
                        label: Text(pickLangText(
                          lang,
                          ko: '외국인 투숙 가능 숙소',
                          en: 'Foreigner-Friendly Stays',
                          ja: '外国人宿泊可',
                          zh: '外籍可住',
                        )),
                        selected: _foreignerOnly,
                        onSelected: (v) => setState(() {
                          _foreignerOnly = v;
                          _rebuildPlan();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      DropdownButton<String>(
                        value: provinces.contains(_province) ? _province : '전체',
                        underline: const SizedBox.shrink(),
                        items: provinces
                            .map((p) => DropdownMenuItem(value: p, child: Text(trRegion(p, lang), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _province = v;
                            _seedOffset = 0;
                            _rebuildPlan();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: TripTheme.values
                                .map((t) => Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                        label: Text(_themeLabel(t, lang), style: const TextStyle(fontSize: 12)),
                                        selected: _theme == t,
                                        onSelected: (_) => setState(() {
                                          _theme = t;
                                          _rebuildPlan();
                                        }),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Itinerary list
            Expanded(
              child: grouped.isEmpty
                  ? Center(
                      child: Text(pickLangText(
                        lang,
                        ko: '선택한 조건에 맞는 코스를 찾지 못했습니다. 지역을 변경해 보세요.',
                        en: 'No itinerary found for this selection. Try another region.',
                        ja: '条件に合うプランが見つかりませんでした。',
                        zh: '未找到匹配行程，请尝试切换地区。',
                      )),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: grouped.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F766E),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'DAY ${entry.key}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...entry.value.map((stop) {
                                final it = stop.item;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      Navigator.pop(context);
                                      widget.onOpenItem(it);
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: it.category.color.withValues(alpha: 0.14),
                                      child: Icon(
                                        stop.slotKey == 'stay'
                                            ? Icons.bed_rounded
                                            : stop.slotKey == 'lunch'
                                                ? Icons.restaurant_rounded
                                                : Icons.place_rounded,
                                        color: it.category.color,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      '${_slotLabel(stop.slotKey, lang)} · ${it.tTitle(lang)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                                    ),
                                    subtitle: Text(
                                      '${it.tRegionLabel(lang)} · ${it.tSubtitle(lang)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: IconButton(
                                      tooltip: pickLangText(lang, ko: '제거', en: 'Remove', ja: '削除', zh: '移除'),
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _plan = TripPlan(
                                            province: _plan.province,
                                            days: _plan.days,
                                            theme: _plan.theme,
                                            foreignerOnly: _plan.foreignerOnly,
                                            stops: _plan.stops.where((s) => !(s.day == stop.day && s.item.id == stop.item.id)).toList(),
                                          );
                                        });
                                      },
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const Divider(height: 1),
            // Footer Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _seedOffset += 1;
                      _rebuildPlan();
                    }),
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: Text(pickLangText(lang, ko: '다른 코스 추천', en: 'Regenerate', ja: '別プラン', zh: '换一批')),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const Key('copy_trip_plan_url_btn'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                    onPressed: () => _copyShareUrl(lang),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(pickLangText(lang, ko: '내 코스 공유(URL)', en: 'Share Trip URL', ja: 'プランを共有', zh: '分享行程链接')),
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
