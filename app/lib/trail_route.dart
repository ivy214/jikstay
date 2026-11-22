// 걷기길(두루누비) 경로 그림: 허브의 'route'(Google encoded polyline, backend/refresh_trails.py 가 GPX 를 30여 점으로 줄여 만듦)를
// 배경 지도 없이 선으로 그린다. 사진이 없는 코스의 카드·상세에서 사진 자리를 대신하고, 상세에는 항상 '코스 경로'로 보여 준다.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'discovery_models.dart';
import 'i18n.dart';

/// Google encoded polyline (정밀도 1e-5) → [(위도, 경도)]. backend/refresh_trails.py encode_polyline 과 짝.
List<(double, double)> decodePolyline(String s) {
  final out = <(double, double)>[];
  var i = 0, lat = 0, lng = 0;
  try {
    while (i < s.length) {
      final vals = <int>[];
      for (var n = 0; n < 2; n++) {
        var shift = 0, res = 0, b = 0;
        do {
          b = s.codeUnitAt(i++) - 63;
          res |= (b & 0x1F) << shift;
          shift += 5;
        } while (b >= 0x20);
        vals.add((res & 1) != 0 ? ~(res >> 1) : res >> 1);
      }
      lat += vals[0];
      lng += vals[1];
      out.add((lat / 1e5, lng / 1e5));
    }
  } on RangeError {
    return const [];
  }
  return out;
}

String itemRoute(DiscoveryItem it) {
  final r = it.raw['route'];
  return r is String ? r : '';
}

/// 사진이 없을 때 쓸 경로 그림 (경로가 없으면 null → 기존 아이콘 자리표시).
Widget? routeThumbOrNull(DiscoveryItem it) {
  final r = itemRoute(it);
  return r.isEmpty ? null : TrailRouteView(route: r, color: it.category.color, compact: true);
}

/// 코스 위 볼거리 사진이면 그 설명 ("코스 위 볼거리: 신선대"). 코스 자체 사진이면 빈 문자열.
String imagePlaceCaption(DiscoveryItem it, AppLang lang) {
  final place = (it.raw['image_place'] ?? '').toString().trim();
  if (place.isEmpty) return '';
  return pickLangText(lang,
      ko: '코스 위 볼거리: $place', en: 'On the route: $place', ja: 'コース上の見どころ: $place', zh: '沿途景點: $place');
}

class TrailRouteView extends StatelessWidget {
  const TrailRouteView({super.key, required this.route, required this.color, this.compact = false});

  final String route;
  final Color color;

  /// 썸네일: 여백·두께를 줄이고 시작·끝 점만.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pts = decodePolyline(route);
    return Container(
      color: color.withValues(alpha: 0.07),
      child: pts.length < 2
          ? Center(child: Icon(Icons.hiking_rounded, color: color, size: compact ? 24 : 40))
          : CustomPaint(painter: _RoutePainter(pts, color, compact), size: Size.infinite),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.pts, this.color, this.compact);

  final List<(double, double)> pts;
  final Color color;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    // 위도에 따른 경도 축척을 보정해 실제 모양대로 (가로·세로 비율 유지)
    final lat0 = pts.map((p) => p.$1).reduce((a, b) => a + b) / pts.length;
    final kx = math.cos(lat0 * math.pi / 180);
    final xs = pts.map((p) => p.$2 * kx).toList();
    final ys = pts.map((p) => p.$1).toList();
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final pad = compact ? 9.0 : 22.0;
    final w = size.width - pad * 2, h = size.height - pad * 2;
    final spanX = math.max(maxX - minX, 1e-6), spanY = math.max(maxY - minY, 1e-6);
    final scale = math.min(w / spanX, h / spanY);
    final offX = pad + (w - spanX * scale) / 2, offY = pad + (h - spanY * scale) / 2;
    Offset at(int i) => Offset(offX + (xs[i] - minX) * scale, offY + (maxY - ys[i]) * scale);

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final stroke = compact ? 2.6 : 4.0;
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke + 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    final r = compact ? 3.6 : 6.0;
    final edge = Paint()..color = Colors.white;
    canvas.drawCircle(at(pts.length - 1), r + 1.6, edge);
    canvas.drawCircle(at(pts.length - 1), r, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(at(0), r + 1.6, edge);
    canvas.drawCircle(at(0), r, Paint()..color = const Color(0xFF16A34A));
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.pts != pts || old.color != color;
}

/// 상세 화면의 '코스 경로' 칸: 경로 그림 + 시작(초록)·끝(검정) 범례.
class TrailRoutePanel extends StatelessWidget {
  const TrailRoutePanel({super.key, required this.item, required this.lang, this.height = 190});

  final DiscoveryItem item;
  final AppLang lang;
  final double height;

  @override
  Widget build(BuildContext context) {
    final r = itemRoute(item);
    if (r.isEmpty) return const SizedBox.shrink();
    Widget dot(Color c) => Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    const legend = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF475569));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(pickLangText(lang, ko: '코스 경로', en: 'Route', ja: 'コースルート', zh: '路線'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(height: height, width: double.infinity, child: TrailRouteView(route: r, color: item.category.color)),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(const Color(0xFF16A34A)),
          const SizedBox(width: 4),
          Text(pickLangText(lang, ko: '시작', en: 'Start', ja: 'スタート', zh: '起點'), style: legend),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          dot(const Color(0xFF0F172A)),
          const SizedBox(width: 4),
          Text(pickLangText(lang, ko: '끝', en: 'Finish', ja: 'ゴール', zh: '終點'), style: legend),
        ]),
        Text(pickLangText(lang, ko: '두루누비 GPX 기준 · 지도 없이 모양만', en: 'From Durunubi GPX · shape only',
            ja: 'ドゥルヌビGPXより・形のみ', zh: '依 Durunubi GPX・僅示意'), style: legend.copyWith(color: const Color(0xFF94A3B8))),
      ]),
    ]);
  }
}
