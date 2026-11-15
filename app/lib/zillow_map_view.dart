// Zillow 스타일 인터랙티브 로컬 디스커버리 맵 (무의존성 Web Mercator 타일 + 충돌 방지 알약 핀).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'detail_page.dart' show StorageImage;
import 'discovery_models.dart';
import 'i18n.dart';

class ZillowMapController extends ChangeNotifier {
  double _lat = 36.15;
  double _lng = 127.75;
  double _zoom = 6.8;

  double get lat => _lat;
  double get lng => _lng;
  double get zoom => _zoom;

  void moveTo(double lat, double lng, {double? zoom}) {
    _lat = lat.clamp(32.5, 38.9);
    _lng = lng.clamp(124.5, 131.5);
    if (zoom != null) {
      _zoom = zoom.clamp(6.0, 14.2);
    }
    notifyListeners();
  }
}

class ZillowMapView extends StatefulWidget {
  final ZillowMapController controller;
  final List<DiscoveryItem> items;
  final String? selectedItemId;
  final String? hoveredItemId;
  final AppLang lang;
  final ValueChanged<MapViewportBounds> onViewportChanged;
  final ValueChanged<DiscoveryItem> onPinTapped;
  final ValueChanged<DiscoveryItem> onOpenDetailSheet;

  const ZillowMapView({
    super.key,
    required this.controller,
    required this.items,
    required this.lang,
    required this.onViewportChanged,
    required this.onPinTapped,
    required this.onOpenDetailSheet,
    this.selectedItemId,
    this.hoveredItemId,
  });

  @override
  State<ZillowMapView> createState() => _ZillowMapViewState();
}

class _ZillowMapViewState extends State<ZillowMapView> {
  static const double _tileSize = 256.0;

  late double _centerLat;
  late double _centerLng;
  late double _zoom;
  Offset? _lastFocalPoint;
  double? _scaleStartZoom;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _centerLat = widget.controller.lat;
    _centerLng = widget.controller.lng;
    _zoom = widget.controller.zoom;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ZillowMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _centerLat = widget.controller.lat;
      _centerLng = widget.controller.lng;
      _zoom = widget.controller.zoom;
    });
    _emitBounds(_lastSize);
  }

  static double _lngToWorldX(double lng, double worldScale) {
    return (lng + 180.0) / 360.0 * worldScale;
  }

  static double _latToWorldY(double lat, double worldScale) {
    final clat = lat.clamp(-85.0511, 85.0511);
    final sinLat = math.sin(clat * math.pi / 180.0);
    return (0.5 - math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) * worldScale;
  }

  static double _worldXToLng(double wx, double worldScale) {
    return (wx / worldScale) * 360.0 - 180.0;
  }

  static double _worldYToLat(double wy, double worldScale) {
    final n = math.pi - 2.0 * math.pi * (wy / worldScale);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  MapViewportBounds _computeBounds(Size size) {
    final w = size.width <= 0 ? 600.0 : size.width;
    final h = size.height <= 0 ? 500.0 : size.height;
    final worldScale = _tileSize * math.pow(2.0, _zoom);
    final cx = _lngToWorldX(_centerLng, worldScale);
    final cy = _latToWorldY(_centerLat, worldScale);
    final minLng = _worldXToLng(cx - w / 2, worldScale);
    final maxLng = _worldXToLng(cx + w / 2, worldScale);
    final maxLat = _worldYToLat(cy - h / 2, worldScale);
    final minLat = _worldYToLat(cy + h / 2, worldScale);
    return MapViewportBounds(
      minLat: math.min(minLat, maxLat),
      maxLat: math.max(minLat, maxLat),
      minLng: math.min(minLng, maxLng),
      maxLng: math.max(minLng, maxLng),
      zoom: _zoom,
    );
  }

  void _emitBounds(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final b = _computeBounds(size);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onViewportChanged(b);
    });
  }

  void _zoomBy(double delta) {
    final next = (_zoom + delta).clamp(6.0, 14.2);
    if (next == _zoom) return;
    setState(() => _zoom = next);
    _emitBounds(_lastSize);
  }

  void _panByPixels(Offset delta) {
    final worldScale = _tileSize * math.pow(2.0, _zoom);
    final cx = _lngToWorldX(_centerLng, worldScale) - delta.dx;
    final cy = _latToWorldY(_centerLat, worldScale) - delta.dy;
    setState(() {
      _centerLng = _worldXToLng(cx, worldScale).clamp(124.2, 131.8);
      _centerLat = _worldYToLat(cy, worldScale).clamp(32.2, 39.0);
    });
    _emitBounds(_lastSize);
  }

  List<(DiscoveryItem, Offset)> _selectDeclusteredPins(Size size) {
    final worldScale = _tileSize * math.pow(2.0, _zoom);
    final cx = _lngToWorldX(_centerLng, worldScale);
    final cy = _latToWorldY(_centerLat, worldScale);

    final inView = <(DiscoveryItem, Offset)>[];
    DiscoveryItem? forcedSelected;
    Offset? forcedOffset;

    for (final it in widget.items) {
      final px = _lngToWorldX(it.lng, worldScale) - cx + size.width / 2;
      final py = _latToWorldY(it.lat, worldScale) - cy + size.height / 2;
      if (px < -40 || px > size.width + 40 || py < -30 || py > size.height + 30) {
        continue;
      }
      if (it.id == widget.selectedItemId || it.id == widget.hoveredItemId) {
        forcedSelected = it;
        forcedOffset = Offset(px, py);
      } else {
        inView.add((it, Offset(px, py)));
      }
    }

    inView.sort((a, b) => b.$1.priorityScore.compareTo(a.$1.priorityScore));

    final accepted = <(DiscoveryItem, Offset)>[];
    if (forcedSelected != null && forcedOffset != null) {
      accepted.add((forcedSelected, forcedOffset));
    }

    // 화면 복잡도를 막기 위해 줌 레벨에 따라 최대 34개까지만 겹치지 않게 배치
    final maxPins = _zoom < 7.6 ? 26 : (_zoom < 9.5 ? 32 : 40);
    const minDx = 84.0;
    const minDy = 32.0;

    for (final cand in inView) {
      if (accepted.length >= maxPins) break;
      final pos = cand.$2;
      final collides = accepted.any((ex) => (ex.$2.dx - pos.dx).abs() < minDx && (ex.$2.dy - pos.dy).abs() < minDy);
      if (!collides) {
        accepted.add(cand);
      }
    }

    // 선택된 핀이 가장 위에 그려지도록 마지막에 배치
    return accepted.reversed.toList();
  }

  Widget _buildRasterTiles(Size size) {
    final tileZ = _zoom.floor().clamp(6, 14);
    final scaleFactor = math.pow(2.0, _zoom - tileZ).toDouble();
    final intScale = _tileSize * (1 << tileZ);
    final cx = _lngToWorldX(_centerLng, intScale);
    final cy = _latToWorldY(_centerLat, intScale);

    final halfW = (size.width / scaleFactor) / 2.0;
    final halfH = (size.height / scaleFactor) / 2.0;

    final minTileX = ((cx - halfW) / _tileSize).floor();
    final maxTileX = ((cx + halfW) / _tileSize).floor();
    final minTileY = ((cy - halfH) / _tileSize).floor();
    final maxTileY = ((cy + halfH) / _tileSize).floor();
    final maxIndex = (1 << tileZ) - 1;

    final tileWidgets = <Widget>[];
    for (int tx = minTileX; tx <= maxTileX; tx++) {
      if (tx < 0 || tx > maxIndex) continue;
      for (int ty = minTileY; ty <= maxTileY; ty++) {
        if (ty < 0 || ty > maxIndex) continue;
        final left = (tx * _tileSize - cx) * scaleFactor + size.width / 2.0;
        final top = (ty * _tileSize - cy) * scaleFactor + size.height / 2.0;
        final drawSize = _tileSize * scaleFactor + 0.8;
        final subdomain = const ['a', 'b', 'c', 'd'][(tx + ty).abs() % 4];
        final url = 'https://$subdomain.basemaps.cartocdn.com/rastertiles/voyager/$tileZ/$tx/$ty.png';

        tileWidgets.add(
          Positioned(
            key: ValueKey('tile_${tileZ}_${tx}_$ty'),
            left: left,
            top: top,
            width: drawSize,
            height: drawSize,
            child: Image.network(
              url,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );
      }
    }
    return Stack(clipBehavior: Clip.hardEdge, children: tileWidgets);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastSize != size && size.width > 0 && size.height > 0) {
          _lastSize = size;
          _emitBounds(size);
        }

        final visiblePins = _selectDeclusteredPins(size);
        DiscoveryItem? selectedItem;
        if (widget.selectedItemId != null) {
          for (final it in widget.items) {
            if (it.id == widget.selectedItemId) {
              selectedItem = it;
              break;
            }
          }
        }

        return ClipRect(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _zoomBy(event.scrollDelta.dy < 0 ? 0.45 : -0.45);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (d) {
                _lastFocalPoint = d.localFocalPoint;
                _scaleStartZoom = _zoom;
              },
              onScaleUpdate: (d) {
                if (_lastFocalPoint != null) {
                  final delta = d.localFocalPoint - _lastFocalPoint!;
                  _lastFocalPoint = d.localFocalPoint;
                  if (delta.distance > 0.5) {
                    _panByPixels(delta);
                  }
                }
                if (_scaleStartZoom != null && (d.scale - 1.0).abs() > 0.02) {
                  final nextZoom = (_scaleStartZoom! + math.log(d.scale) / math.ln2).clamp(6.0, 14.2);
                  setState(() => _zoom = nextZoom);
                  _emitBounds(size);
                }
              },
              child: Stack(
                children: [
                  // 1. 오프라인·초기 로딩용 깔끔한 배경 그리드 캔버스
                  Positioned.fill(
                    child: CustomPaint(painter: _CleanMapBackdropPainter(zoom: _zoom)),
                  ),

                  // 2. CartoDB Voyager 도로·지명 타일 레이어
                  Positioned.fill(child: _buildRasterTiles(size)),

                  // 3. Zillow 스타일 알약 마커 핀 레이어
                  for (final (item, offset) in visiblePins)
                    Positioned(
                      left: offset.dx - 54,
                      top: offset.dy - 16,
                      child: _ZillowPillPin(
                        key: ValueKey('map_pin_${item.id}'),
                        item: item,
                        isSelected: item.id == widget.selectedItemId,
                        isHovered: item.id == widget.hoveredItemId,
                        onTap: () => widget.onPinTapped(item),
                      ),
                    ),

                  // 4. 좌상단 심플 범례 캡슐 (복잡하지 않게 한 줄 요약)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Text(
                        widget.lang == AppLang.ko
                            ? '🎉축제 · 📖공식지도 · 🏞️볼거리 · 🍲먹거리 · 🏡숙소 (지도 이동 시 우측 피드 자동 갱신)'
                            : '🎉Event · 📖Map · 🏞️Sight · 🍲Food · 🏡Stay (Pan/zoom updates feed)',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                    ),
                  ),

                  // 5. 우상단 확대/축소 & 전국 리셋 컨트롤
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        _MapControlBtn(
                          key: const Key('map_zoom_in_btn'),
                          icon: Icons.add_rounded,
                          tooltip: '확대',
                          onTap: () => _zoomBy(0.7),
                        ),
                        const SizedBox(height: 6),
                        _MapControlBtn(
                          key: const Key('map_zoom_out_btn'),
                          icon: Icons.remove_rounded,
                          tooltip: '축소',
                          onTap: () => _zoomBy(-0.7),
                        ),
                        const SizedBox(height: 6),
                        _MapControlBtn(
                          key: const Key('map_reset_korea_btn'),
                          icon: Icons.fullscreen_exit_rounded,
                          tooltip: '전국 한눈에',
                          onTap: () => widget.controller.moveTo(36.15, 127.75, zoom: 6.8),
                        ),
                      ],
                    ),
                  ),

                  // 6. 우하단 OSM/CARTO 저작권 표기
                  Positioned(
                    right: 8,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '© OpenStreetMap · © CARTO · 한국관광공사 TourAPI',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),

                  // 7. 핀 선택 시 하단 플로팅 미니 프리뷰 카드 (Zillow 스타일)
                  if (selectedItem != null)
                    Positioned(
                      left: 14,
                      right: size.width > 520 ? null : 14,
                      bottom: 24,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 370),
                        child: _SelectedPinFloatingCard(
                          item: selectedItem,
                          lang: widget.lang,
                          onOpenDetail: () => widget.onOpenDetailSheet(selectedItem!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZillowPillPin extends StatelessWidget {
  final DiscoveryItem item;
  final bool isSelected;
  final bool isHovered;
  final VoidCallback onTap;

  const _ZillowPillPin({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isHovered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = isSelected || isHovered;
    final bg = active
        ? const Color(0xFF0F172A)
        : (item.isSponsored ? const Color(0xFFB45309) : item.category.color);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: active ? 10 : 8, vertical: active ? 6 : 4.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: item.isSponsored ? const Color(0xFFFDE68A) : Colors.white,
            width: active ? 2.2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: active ? 0.28 : 0.16),
              blurRadius: active ? 10 : 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          item.pinShortLabel(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: active ? 12 : 11,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _SelectedPinFloatingCard extends StatelessWidget {
  final DiscoveryItem item;
  final AppLang lang;
  final VoidCallback onOpenDetail;

  const _SelectedPinFloatingCard({
    required this.item,
    required this.lang,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 74,
                  height: 74,
                  child: item.imageUrl.isNotEmpty
                      ? StorageImage(url: item.imageUrl, cacheWidth: 240)
                      : Container(
                          color: item.category.color.withValues(alpha: 0.12),
                          alignment: Alignment.center,
                          child: Icon(item.category.icon, color: item.category.color, size: 30),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.category.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${item.province} · ${item.categoryBadgeText(lang)}',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: item.category.color),
                          ),
                        ),
                        if (item.isSponsored) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '🎁 방문혜택',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.couponTitle.isNotEmpty ? item.couponTitle : item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          lang == AppLang.ko ? '주변 맛집·명소·숙소 연결 보기 →' : 'See connected nearby places →',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF2563EB)),
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

class _MapControlBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapControlBtn({super.key, required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: const Color(0xFF1E293B)),
          ),
        ),
      ),
    );
  }
}

class _CleanMapBackdropPainter extends CustomPainter {
  final double zoom;
  const _CleanMapBackdropPainter({required this.zoom});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFE8F1F8);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFD5E3EE)
      ..strokeWidth = 1.0;
    const step = 64.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CleanMapBackdropPainter oldDelegate) => oldDelegate.zoom != zoom;
}
