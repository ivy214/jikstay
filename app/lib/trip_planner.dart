// 주말 1박2일(한국인) & 3·5일(외국인) 여행 코스 자동 생성기 + URL 공유(딥링크) 모듈.
import 'package:material_ui/material_ui.dart';
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
  final String subRegion;
  final int days;
  final TripTheme theme;
  final bool foreignerOnly;
  final List<TripStop> stops;

  const TripPlan({
    required this.province,
    this.subRegion = '전체',
    required this.days,
    required this.theme,
    required this.foreignerOnly,
    required this.stops,
  });
}

/// 아이템의 `regionLabel` 또는 `address`에서 시·군·구 단위 세부 지역명을 추출한다.
String extractSubRegion(DiscoveryItem it) {
  final sources = [it.regionLabel, it.address];
  final re = RegExp(r'([가-힣]{1,6}(?:시|군|구))');
  for (final src in sources) {
    for (final m in re.allMatches(src)) {
      final token = m.group(1) ?? '';
      if (token.isEmpty) continue;
      if (token.endsWith('특별시') || token.endsWith('광역시') || token.endsWith('자치시')) {
        continue;
      }
      return token;
    }
  }
  return '';
}

/// 선택한 시·도 내에서 선택 가능한 세부 지역(시·군·구) 목록을 빈도순/가나다순으로 반환한다.
List<String> listSubRegions(List<DiscoveryItem> allItems, String province) {
  final prov = province.trim().isEmpty ? '전체' : province.trim();
  final counts = <String, int>{};
  for (final it in allItems) {
    if (prov != '전체' && it.province != prov) continue;
    final sub = extractSubRegion(it);
    if (sub.isNotEmpty) {
      counts[sub] = (counts[sub] ?? 0) + 1;
    }
  }
  final sorted = counts.keys.toList()
    ..sort((a, b) {
      final cmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  return ['전체', ...sorted.take(30)];
}

bool _isNightItem(DiscoveryItem it) {
  final text = '${it.title} ${it.subtitle}'.toLowerCase();
  const nightKeywords = ['야간', '밤길', '야경', '불빛', '별빛', '달빛', '야시장', '나이트', 'night'];
  return nightKeywords.any(text.contains);
}

bool _isMorningItem(DiscoveryItem it) {
  final text = '${it.title} ${it.subtitle}'.toLowerCase();
  const morningKeywords = ['모닝', '아침', '새벽', '일출', 'morning'];
  return morningKeywords.any(text.contains);
}

bool _isForeignerEligibleStay(DiscoveryItem s) {
  if (s.category != DiscoveryCategory.stay) return false;
  if (s.title.contains('내국인 전용')) return false;
  return true;
}

int _stayForeignerScore(DiscoveryItem s) {
  final lic = s.licenseType;
  if (lic.contains('외국인')) return 3;
  if (lic.contains('한옥') || lic.contains('호텔') || lic.contains('호스텔') || lic == '관광숙박업') return 2;
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

/// 선택한 지역(시/도 · 시/군/구)·일수·테마에 맞춰 근거리 동선으로 명소·맛집·축제·합법 숙소를 자동 조합한다.
TripPlan generateTripPlan({
  required List<DiscoveryItem> allItems,
  String province = '전체',
  String subRegion = '전체',
  int days = 2,
  TripTheme theme = TripTheme.all,
  bool foreignerOnly = false,
  int seedOffset = 0,
}) {
  final prov = province.trim().isEmpty ? '전체' : province.trim();
  final sub = subRegion.trim().isEmpty ? '전체' : subRegion.trim();
  final provPool = prov == '전체'
      ? allItems
      : allItems.where((it) => it.province == prov).toList();
  final subPool = sub == '전체'
      ? provPool
      : provPool.where((it) => extractSubRegion(it) == sub || it.regionLabel.contains(sub) || it.address.contains(sub)).toList();
  final anchorPool = subPool.isNotEmpty ? subPool : (provPool.isNotEmpty ? provPool : allItems);

  // 1. 앵커 후보군 선정: 임박/진행중 축제 > 명소·스토리
  final eventAnchors = anchorPool.where((it) => it.category == DiscoveryCategory.event).toList()
    ..sort((a, b) {
      final da = _daysUntilStart(a);
      final db = _daysUntilStart(b);
      if (da != db) return da.compareTo(db);
      return b.priorityScore.compareTo(a.priorityScore);
    });
  final spotAnchors = anchorPool
      .where((it) => it.category == DiscoveryCategory.attraction)
      .toList()
    ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

  final anchors = <DiscoveryItem>[
    if (theme == TripTheme.food || theme == TripTheme.hanok) ...spotAnchors else ...eventAnchors,
    if (theme == TripTheme.food || theme == TripTheme.hanok) ...eventAnchors else ...spotAnchors,
  ];
  if (anchors.isEmpty) {
    anchors.addAll(anchorPool.where((it) => it.category != DiscoveryCategory.ebook && it.category != DiscoveryCategory.stay));
  }

  final usedIds = <String>{};
  final nearbyPool = provPool.isNotEmpty ? provPool : allItems;

  DiscoveryItem? pickNearest(
    DiscoveryItem? dayAnchor,
    List<DiscoveryCategory> categories, {
    bool preferHanok = false,
    bool stayFilter = false,
    bool excludeNight = false,
    bool excludeMorning = false,
  }) {
    var candidates = nearbyPool.where((it) {
      if (usedIds.contains(it.id)) return false;
      if (!categories.contains(it.category)) return false;
      if (stayFilter && foreignerOnly && !_isForeignerEligibleStay(it)) return false;
      if (excludeNight && _isNightItem(it)) return false;
      if (excludeMorning && _isMorningItem(it)) return false;
      return true;
    }).toList();
    // 필터 후 후보가 전혀 없으면 시간대 제약만 완화
    if (candidates.isEmpty && (excludeNight || excludeMorning)) {
      candidates = nearbyPool.where((it) {
        if (usedIds.contains(it.id)) return false;
        if (!categories.contains(it.category)) return false;
        if (stayFilter && foreignerOnly && !_isForeignerEligibleStay(it)) return false;
        return true;
      }).toList();
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      if (preferHanok) {
        final ah = (a.title.contains('한옥') || a.licenseType.contains('한옥')) ? 1 : 0;
        final bh = (b.title.contains('한옥') || b.licenseType.contains('한옥')) ? 1 : 0;
        if (ah != bh) return bh.compareTo(ah);
      }
      if (sub != '전체') {
        final aSub = (extractSubRegion(a) == sub || a.address.contains(sub)) ? 1 : 0;
        final bSub = (extractSubRegion(b) == sub || b.address.contains(sub)) ? 1 : 0;
        if (aSub != bSub) return bSub.compareTo(aSub);
      }
      if (dayAnchor != null && dayAnchor.lat != 0 && a.lat != 0 && b.lat != 0) {
        final da = haversineKm(dayAnchor.lat, dayAnchor.lng, a.lat, a.lng);
        final db = haversineKm(dayAnchor.lat, dayAnchor.lng, b.lat, b.lng);
        // 같은 생활권(8km 이내)이면 우선순위·외국인 적합도 반영, 그 외에는 거리 최우선
        if (da <= 8.0 && db <= 8.0) {
          if (stayFilter && foreignerOnly) {
            final fs = _stayForeignerScore(b).compareTo(_stayForeignerScore(a));
            if (fs != 0) return fs;
          }
          return b.priorityScore.compareTo(a.priorityScore);
        }
        return da.compareTo(db);
      }
      return b.priorityScore.compareTo(a.priorityScore);
    });

    final chosen = candidates.first;
    usedIds.add(chosen.id);
    return chosen;
  }

  final stops = <TripStop>[];
  final clampedDays = days.clamp(1, 5);
  DiscoveryItem? prevStay;

  for (int d = 1; d <= clampedDays; d++) {
    // 첫날 앵커는 seedOffset 적용, 둘째 날부터는 전날 숙소/전날 앵커 기준 근거리 또는 다음 앵커 사용
    DiscoveryItem? dayAnchor = prevStay;
    if (dayAnchor == null && anchors.isNotEmpty) {
      dayAnchor = anchors[(seedOffset + d - 1) % anchors.length];
    }

    final morning = d == 1 &&
            dayAnchor != null &&
            !usedIds.contains(dayAnchor.id) &&
            dayAnchor.category != DiscoveryCategory.ebook &&
            !_isNightItem(dayAnchor)
        ? (() {
            usedIds.add(dayAnchor!.id);
            return dayAnchor;
          })()
        : (theme == TripTheme.festival
            ? pickNearest(dayAnchor, [DiscoveryCategory.event, DiscoveryCategory.attraction], excludeNight: true)
            : pickNearest(dayAnchor, [DiscoveryCategory.attraction, DiscoveryCategory.event], excludeNight: true));

    final anchorForDay = morning ?? dayAnchor;
    if (morning != null) stops.add(TripStop(day: d, slotKey: 'morning', item: morning));

    final lunch = pickNearest(anchorForDay, [DiscoveryCategory.food]);
    if (lunch != null) stops.add(TripStop(day: d, slotKey: 'lunch', item: lunch));

    final afternoon = theme == TripTheme.food
        ? pickNearest(anchorForDay, [DiscoveryCategory.food, DiscoveryCategory.event, DiscoveryCategory.attraction], excludeMorning: true)
        : pickNearest(anchorForDay, [DiscoveryCategory.event, DiscoveryCategory.attraction], excludeMorning: true);
    if (afternoon != null) stops.add(TripStop(day: d, slotKey: 'afternoon', item: afternoon));

    if (d < clampedDays) {
      final stay = pickNearest(
        anchorForDay,
        [DiscoveryCategory.stay],
        preferHanok: theme == TripTheme.hanok,
        stayFilter: true,
      );
      if (stay != null) {
        stops.add(TripStop(day: d, slotKey: 'stay', item: stay));
        prevStay = stay;
      }
    }
  }

  return TripPlan(
    province: prov,
    subRegion: sub,
    days: clampedDays,
    theme: theme,
    foreignerOnly: foreignerOnly,
    stops: stops,
  );
}

String encodeTripPlanParam(TripPlan plan) {
  final fFlag = plan.foreignerOnly ? '1' : '0';
  final encodedStops = plan.stops.map((s) => '${s.day}.${s.slotKey[0]}.${s.item.id}').join(',');
  return 'd${plan.days}:${plan.province}:${plan.subRegion}:${plan.theme.name}:$fFlag:$encodedStops';
}

TripPlan? decodeTripPlanParam(String raw, List<DiscoveryItem> allItems) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(':');
  if (parts.length < 5) return null;
  final days = int.tryParse(parts[0].replaceFirst('d', '')) ?? 2;
  final province = parts[1].isEmpty ? '전체' : parts[1];
  // 6파트(신규 subRegion 포함)와 5파트(하위 호환) 모두 지원
  final hasSub = parts.length >= 6;
  final subRegion = hasSub && parts[2].isNotEmpty ? parts[2] : '전체';
  final themeIdx = hasSub ? 3 : 2;
  final flagIdx = hasSub ? 4 : 3;
  final stopsIdx = hasSub ? 5 : 4;

  final theme = TripTheme.values.firstWhere(
    (t) => t.name == parts[themeIdx],
    orElse: () => TripTheme.all,
  );
  final foreignerOnly = parts[flagIdx] == '1';
  final byId = {for (final it in allItems) it.id: it};
  final stops = <TripStop>[];
  for (final token in parts.sublist(stopsIdx).join(':').split(',')) {
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
    subRegion: subRegion,
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
  late String _subRegion;
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
      _subRegion = init.subRegion;
      _days = init.days;
      _theme = init.theme;
      _foreignerOnly = init.foreignerOnly;
      _plan = init;
    } else {
      final lang = appLangNotifier.value;
      _province = widget.initialProvince;
      _subRegion = '전체';
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
      subRegion: _subRegion,
      days: _days,
      theme: _theme,
      foreignerOnly: _foreignerOnly,
      seedOffset: _seedOffset,
    );
  }

  String _slotLabel(TripStop stop, AppLang lang) => switch (stop.slotKey) {
        'morning' => pickLangText(lang, ko: '오전 코스', en: 'Morning', ja: '午前', zh: '上午'),
        'lunch' => pickLangText(lang, ko: '로컬 미식', en: 'Local Food', ja: 'ご当地グルメ', zh: '当地美食'),
        'afternoon' => _isNightItem(stop.item)
            ? pickLangText(lang, ko: '오후 · 야간', en: 'Afternoon / Night', ja: '午後・夜間', zh: '下午・夜间')
            : pickLangText(lang, ko: '오후 · 축제', en: 'Afternoon / Event', ja: '午後・祭り', zh: '下午・庆典'),
        'stay' => pickLangText(lang, ko: '수수료 0원 숙박', en: '0% Fee Stay', ja: '手数料0円宿', zh: '0手续费住宿'),
        _ => stop.slotKey,
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

  Widget _buildStyledDropdown({
    required Key key,
    required String value,
    required List<String> items,
    required String Function(String) labelBuilder,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: DropdownButton<String>(
        key: key,
        value: items.contains(value) ? value : items.first,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: items
            .map((v) => DropdownMenuItem(
                  value: v,
                  child: Text(labelBuilder(v), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final provinces = <String>['전체', ...kProvinceJumpList.where((p) => p.key != '전체').map((p) => p.key)];
    final subRegions = listSubRegions(widget.allItems, _province);
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
                            ja: '韓国 2日・3日・5日 旅行＆宿泊プランナー',
                            zh: '韩国 2日/3日/5日 行程与住宿规划',
                          ),
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          pickLangText(
                            lang,
                            ko: '원하는 지역(시·군·구)을 선택하면 근거리 동선(생활권 중심)으로 자동 연결합니다.',
                            en: 'Select a region & district to auto-build a compact, nearby route.',
                            ja: '地域・エリアを選ぶと近距離の効率的なルートを自動作成します。',
                            zh: '选择地区与区县后，自动串联近距离高效率路线。',
                          ),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildStyledDropdown(
                        key: const Key('plan_province_dropdown'),
                        value: _province,
                        items: provinces,
                        labelBuilder: (p) => p == '전체'
                            ? pickLangText(lang, ko: '시/도: 전체', en: 'Region: All', ja: '地域: すべて', zh: '地区: 全部')
                            : trRegion(p, lang),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _province = v;
                            _subRegion = '전체';
                            _seedOffset = 0;
                            _rebuildPlan();
                          });
                        },
                      ),
                      _buildStyledDropdown(
                        key: const Key('plan_subregion_dropdown'),
                        value: _subRegion,
                        items: subRegions,
                        labelBuilder: (s) => s == '전체'
                            ? pickLangText(lang, ko: '시/군/구: 전체', en: 'District: All', ja: '詳細エリア: すべて', zh: '区县: 全部')
                            : s,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _subRegion = v;
                            _seedOffset = 0;
                            _rebuildPlan();
                          });
                        },
                      ),
                      ...TripTheme.values.map((t) => ChoiceChip(
                            label: Text(_themeLabel(t, lang), style: const TextStyle(fontSize: 12)),
                            selected: _theme == t,
                            onSelected: (_) => setState(() {
                              _theme = t;
                              _rebuildPlan();
                            }),
                          )),
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
                                final iconColor = stop.slotKey == 'stay' ? const Color(0xFFE61E4D) : it.category.color;
                                final iconBg = stop.slotKey == 'stay'
                                    ? const Color(0xFFFFEEF2)
                                    : it.category.color.withValues(alpha: 0.14);
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
                                      backgroundColor: iconBg,
                                      child: Icon(
                                        stop.slotKey == 'stay'
                                            ? Icons.bed_rounded
                                            : stop.slotKey == 'lunch'
                                                ? Icons.restaurant_rounded
                                                : Icons.place_rounded,
                                        color: iconColor,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      '${_slotLabel(stop, lang)} · ${it.tTitle(lang)}',
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
                                            subRegion: _plan.subRegion,
                                            days: _plan.days,
                                            theme: _plan.theme,
                                            foreignerOnly: _plan.foreignerOnly,
                                            stops: _plan.stops
                                                .where((s) => !(s.day == stop.day && s.item.id == stop.item.id))
                                                .toList(),
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
