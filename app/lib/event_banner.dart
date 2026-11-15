// 메인 화면 상단 이벤트 배너.
// - 오늘 날짜가 [start, end] 안에 드는 이벤트만 후보가 되고, 후보가 여럿이면 홈 화면을 열 때마다 하나를 무작위로 고른다.
// - 새 이벤트는 kPromoEvents 에 기간·이미지·문구만 추가하면 된다. 이미지는 app/web/assets/events/ 에 둔다.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'i18n.dart';

/// 배너를 눌렀을 때 여는 화면 종류
enum PromoEventAction {
  /// 반값여행(지역사랑 휴가지원) 상세 — PublicTravelHubView
  halfPriceTravel,

  /// 외부 공식 안내 페이지를 새 창으로 연다 (externalUrl 필수)
  externalUrl,
}

class PromoEvent {
  final String id;
  final String imageUrl;

  /// 시작일·종료일 (둘 다 포함, 날짜 단위)
  final DateTime start;
  final DateTime end;
  final PromoEventAction action;
  final String externalUrl;
  final Map<AppLang, String> title;
  final Map<AppLang, String> subtitle;
  final Color background;

  const PromoEvent({
    required this.id,
    required this.imageUrl,
    required this.start,
    required this.end,
    required this.action,
    required this.title,
    required this.subtitle,
    this.externalUrl = '',
    this.background = const Color(0xFF14B8A6),
  });

  bool isActiveOn(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  String titleFor(AppLang lang) => title[lang] ?? title[AppLang.ko] ?? '';
  String subtitleFor(AppLang lang) => subtitle[lang] ?? subtitle[AppLang.ko] ?? '';
}

final List<PromoEvent> kPromoEvents = [
  PromoEvent(
    id: 'half_price_travel_2026',
    imageUrl: 'assets/events/half_price_2026.png',
    start: DateTime(2026, 4, 1),
    end: DateTime(2026, 12, 31),
    action: PromoEventAction.halfPriceTravel,
    background: const Color(0xFF14B8A6),
    title: const {
      AppLang.ko: '2026 대한민국 반값여행 총정리',
      AppLang.en: '2026 Korea Half-Price Travel Guide',
      AppLang.ja: '2026 韓国半額旅行まとめ',
      AppLang.zh: '2026 韓國半價旅遊總整理',
    },
    subtitle: const {
      AppLang.ko: '여행경비 50% 지역화폐 환급 · 대상 지역 25곳 · 사전신청 방법과 지역별 숙소 바로 찾기',
      AppLang.en: '50% travel cashback in 25 towns — how to pre-register and find stays in each town',
      AppLang.ja: '旅費50%を地域通貨で還付・対象25地域・事前申請方法と地域別の宿',
      AppLang.zh: '旅費50%以地方貨幣退還・25個適用地區・事前申請方式與各地住宿',
    },
  ),
];

/// 오늘 진행 중인 이벤트 목록
List<PromoEvent> activePromoEvents(DateTime now, {List<PromoEvent>? events}) =>
    (events ?? kPromoEvents).where((e) => e.isActiveOn(now)).toList();

/// 진행 중인 이벤트 중 하나를 무작위로 고른다. 없으면 null.
PromoEvent? pickPromoEvent(DateTime now, {List<PromoEvent>? events, math.Random? random}) {
  final active = activePromoEvents(now, events: events);
  if (active.isEmpty) return null;
  return active[(random ?? math.Random()).nextInt(active.length)];
}

class PromoEventBanner extends StatelessWidget {
  final PromoEvent event;
  final AppLang lang;
  final VoidCallback onTap;

  const PromoEventBanner({super.key, required this.event, required this.lang, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final imgSize = narrow ? 104.0 : 150.0;
    return Material(
      color: event.background,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('promo_banner_${event.id}'),
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: imgSize,
              height: imgSize,
              child: Image.network(
                event.imageUrl,
                fit: BoxFit.cover,
                semanticLabel: event.titleFor(lang),
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0x33FFFFFF),
                  child: Center(child: Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 36)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        pickLangText(lang, ko: '진행 중 이벤트', en: 'Ongoing event', ja: '開催中イベント', zh: '進行中活動'),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.titleFor(lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: narrow ? 15.5 : 19,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.subtitleFor(lang),
                      maxLines: narrow ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: narrow ? 12 : 13.5,
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.9), size: 26),
            ),
          ],
        ),
      ),
    );
  }
}
