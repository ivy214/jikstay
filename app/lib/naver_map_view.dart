// 네이버 지도 연동 & 한국어 인터랙티브 로컬 지도 탐색 뷰.
// 초기화면에서는 로드하지 않고 사용자가 '네이버 지도 보기'를 선택했을 때만 마운트되며,
// 국토교통부 한국어 베이스맵 핀 탐색과 네이버 지도(map.naver.com) 실시간 검색·길찾기·매거진 상세보기를 직결한다.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'detail_page.dart' show StorageImage;
import 'discovery_models.dart';
import 'i18n.dart';

class NaverLocalMapView extends StatefulWidget {
  final List<DiscoveryItem> items;
  final String selectedProvince;
  final DiscoveryCategory selectedCategory;
  final String query;
  final AppLang lang;
  final bool offlineMode;
  final ValueChanged<DiscoveryItem> onOpenDetailPage;
  final ValueChanged<String> onOpenExternalUrl;

  const NaverLocalMapView({
    super.key,
    required this.items,
    required this.selectedProvince,
    required this.selectedCategory,
    required this.query,
    required this.lang,
    required this.onOpenDetailPage,
    required this.onOpenExternalUrl,
    this.offlineMode = false,
  });

  @override
  State<NaverLocalMapView> createState() => _NaverLocalMapViewState();
}

class _NaverLocalMapViewState extends State<NaverLocalMapView> {
  static const double _tileSize = 256.0;

  late double _centerLat;
  late double _centerLng;
  late double _zoom;
  Offset? _lastFocalPoint;
  double? _scaleStartZoom;
  DiscoveryItem? _selectedPinItem;

  @override
  void initState() {
    super.initState();
    final meta = _provinceMeta(widget.selectedProvince);
    _centerLat = meta.lat;
    _centerLng = meta.lng;
    _zoom = meta.zoom;
    if (widget.items.isNotEmpty) {
      _selectedPinItem = widget.items.first;
    }
  }

  @override
  void didUpdateWidget(covariant NaverLocalMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProvince != widget.selectedProvince) {
      final meta = _provinceMeta(widget.selectedProvince);
      _centerLat = meta.lat;
      _centerLng = meta.lng;
      _zoom = meta.zoom;
      _selectedPinItem = widget.items.isNotEmpty ? widget.items.first : null;
    } else if (_selectedPinItem != null && !widget.items.any((e) => e.id == _selectedPinItem!.id)) {
      _selectedPinItem = widget.items.isNotEmpty ? widget.items.first : null;
    }
  }

  ProvinceMeta _provinceMeta(String key) {
    return kProvinceJumpList.firstWhere(
      (p) => p.key == key,
      orElse: () => kProvinceJumpList.first,
    );
  }

  double _lngToWorldX(double lng, double worldSize) => ((lng + 180.0) / 360.0) * worldSize;

  double _latToWorldY(double lat, double worldSize) {
    final clamped = lat.clamp(-85.05112878, 85.05112878);
    final rad = clamped * math.pi / 180.0;
    final merc = math.log(math.tan(math.pi / 4.0 + rad / 2.0));
    return (0.5 - merc / (2.0 * math.pi)) * worldSize;
  }

  double _worldXToLng(double wx, double worldSize) => (wx / worldSize) * 360.0 - 180.0;

  double _worldYToLat(double wy, double worldSize) {
    final n = math.pi - 2.0 * math.pi * (wy / worldSize);
    return (180.0 / math.pi) * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  MapViewportBounds _computeBounds(Size size) {
    final worldSize = _tileSize * math.pow(2.0, _zoom);
    final cx = _lngToWorldX(_centerLng, worldSize);
    final cy = _latToWorldY(_centerLat, worldSize);
    final halfW = size.width / 2.0;
    final halfH = size.height / 2.0;
    final minLng = _worldXToLng(cx - halfW, worldSize);
    final maxLng = _worldXToLng(cx + halfW, worldSize);
    final maxLat = _worldYToLat(cy - halfH, worldSize);
    final minLat = _worldYToLat(cy + halfH, worldSize);
    return MapViewportBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      zoom: _zoom,
    );
  }

  void _panByPixels(Offset delta) {
    final worldSize = _tileSize * math.pow(2.0, _zoom);
    final cx = _lngToWorldX(_centerLng, worldSize) - delta.dx;
    final cy = _latToWorldY(_centerLat, worldSize) - delta.dy;
    setState(() {
      _centerLng = _worldXToLng(cx, worldSize).clamp(124.2, 131.8);
      _centerLat = _worldYToLat(cy, worldSize).clamp(32.4, 38.9);
    });
  }

  void _changeZoom(double nextZoom) {
    setState(() {
      _zoom = nextZoom.clamp(6.3, 14.5);
    });
  }

  void _focusItemOnMap(DiscoveryItem it) {
    setState(() {
      _selectedPinItem = it;
      _centerLat = it.lat;
      _centerLng = it.lng;
      if (_zoom < 10.8) _zoom = 11.4;
    });
  }

  String _buildNaverRegionSearchUrl({String? customSuffix}) {
    final provWord = widget.selectedProvince == '전체' ? '대한민국' : widget.selectedProvince;
    if (customSuffix != null && customSuffix.isNotEmpty) {
      return 'https://map.naver.com/p/search/${Uri.encodeComponent('$provWord $customSuffix'.trim())}';
    }
    if (widget.query.trim().isNotEmpty) {
      final prefix = widget.selectedProvince == '전체' ? '' : widget.selectedProvince;
      return 'https://map.naver.com/p/search/${Uri.encodeComponent('$prefix ${widget.query.trim()}'.trim())}';
    }
    final catWord = switch (widget.selectedCategory) {
      DiscoveryCategory.event => '축제 행사',
      DiscoveryCategory.attraction => '가볼만한곳 명소',
      DiscoveryCategory.food => '로컬 맛집',
      DiscoveryCategory.market => '전통시장 5일장',
      DiscoveryCategory.culture => '공연 전시',
      DiscoveryCategory.stay => '펜션 민박 숙소',
      DiscoveryCategory.ebook => '관광안내소',
      DiscoveryCategory.all => '가볼만한곳 맛집',
    };
    return 'https://map.naver.com/p/search/${Uri.encodeComponent('$provWord $catWord'.trim())}';
  }

  Widget _buildMapCanvas(Size canvasSize, AppLang lang) {
    final int tileZ = _zoom.floor().clamp(6, 15);
    final double scale = math.pow(2.0, _zoom - tileZ).toDouble();
    final double scaledTileSize = _tileSize * scale;
    final double worldAtTileZ = _tileSize * math.pow(2.0, tileZ);
    final double centerTileX = _lngToWorldX(_centerLng, worldAtTileZ) / _tileSize;
    final double centerTileY = _latToWorldY(_centerLat, worldAtTileZ) / _tileSize;

    final int maxTileIndex = (1 << tileZ) - 1;
    final int halfTilesX = (canvasSize.width / (2.0 * scaledTileSize)).ceil() + 1;
    final int halfTilesY = (canvasSize.height / (2.0 * scaledTileSize)).ceil() + 1;
    final int baseTx = centerTileX.floor();
    final int baseTy = centerTileY.floor();

    final tileWidgets = <Widget>[];
    if (!widget.offlineMode) {
      for (int dx = -halfTilesX; dx <= halfTilesX; dx++) {
        for (int dy = -halfTilesY; dy <= halfTilesY; dy++) {
          final int tx = baseTx + dx;
          final int ty = baseTy + dy;
          if (tx < 0 || ty < 0 || tx > maxTileIndex || ty > maxTileIndex) continue;
          final double left = canvasSize.width / 2.0 + (tx - centerTileX) * scaledTileSize;
          final double top = canvasSize.height / 2.0 + (ty - centerTileY) * scaledTileSize;
          final vworldUrl = 'https://xdworld.vworld.kr/2d/Base/service/$tileZ/$tx/$ty.png';
          final osmUrl = 'https://tile.openstreetmap.org/$tileZ/$tx/$ty.png';

          tileWidgets.add(
            Positioned(
              left: left,
              top: top,
              width: scaledTileSize + 0.6,
              height: scaledTileSize + 0.6,
              child: Image.network(
                vworldUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Image.network(
                  osmUrl,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFEAF2EF)),
                ),
              ),
            ),
          );
        }
      }
    }

    // 충돌 방지 핀 배치
    final double worldSize = _tileSize * math.pow(2.0, _zoom);
    final double cx = _lngToWorldX(_centerLng, worldSize);
    final double cy = _latToWorldY(_centerLat, worldSize);
    final occupied = <Rect>[];
    final pinWidgets = <Widget>[];

    // 선택된 핀을 가장 마지막(최상단)에 그리기 위해 우선순위 정렬
    final ordered = [...widget.items];
    ordered.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    DiscoveryItem? activeOverlay;
    for (final it in ordered) {
      final px = canvasSize.width / 2.0 + (_lngToWorldX(it.lng, worldSize) - cx);
      final py = canvasSize.height / 2.0 + (_latToWorldY(it.lat, worldSize) - cy);
      if (px < -40 || px > canvasSize.width + 40 || py < -30 || py > canvasSize.height + 30) {
        continue;
      }
      final isSel = _selectedPinItem?.id == it.id;
      if (isSel) {
        activeOverlay = it;
        continue;
      }
      final box = Rect.fromCenter(center: Offset(px, py), width: 92, height: 28);
      if (occupied.any((r) => r.overlaps(box))) continue;
      occupied.add(box);
      if (occupied.length > 42) break;

      pinWidgets.add(
        Positioned(
          left: px - 52,
          top: py - 15,
          child: _MapPinPill(
            item: it,
            selected: false,
            onTap: () => setState(() => _selectedPinItem = it),
          ),
        ),
      );
    }

    if (activeOverlay != null) {
      final px = canvasSize.width / 2.0 + (_lngToWorldX(activeOverlay.lng, worldSize) - cx);
      final py = canvasSize.height / 2.0 + (_latToWorldY(activeOverlay.lat, worldSize) - cy);
      pinWidgets.add(
        Positioned(
          left: px - 58,
          top: py - 18,
          child: _MapPinPill(
            item: activeOverlay,
            selected: true,
            onTap: () => widget.onOpenDetailPage(activeOverlay!),
          ),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _changeZoom(_zoom + (event.scrollDelta.dy < 0 ? 0.55 : -0.55));
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _lastFocalPoint = details.localFocalPoint;
          _scaleStartZoom = _zoom;
        },
        onScaleUpdate: (details) {
          if (_lastFocalPoint != null) {
            final delta = details.localFocalPoint - _lastFocalPoint!;
            _lastFocalPoint = details.localFocalPoint;
            if (delta.distance > 0.2) {
              _panByPixels(delta);
            }
          }
          if (_scaleStartZoom != null && (details.scale - 1.0).abs() > 0.02) {
            _changeZoom(_scaleStartZoom! + math.log(details.scale) / math.ln2);
          }
        },
        child: ClipRect(
          child: Stack(
            key: const Key('interactive_korea_map_canvas'),
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFFE6EFEA)),
              ...tileWidgets,
              ...pinWidgets,

              // 우측 상단 확대·축소·초기화 컨트롤
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '확대',
                        onPressed: () => _changeZoom(_zoom + 0.8),
                        icon: const Icon(Icons.add_rounded, size: 20),
                      ),
                      const Divider(height: 1),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '축소',
                        onPressed: () => _changeZoom(_zoom - 0.8),
                        icon: const Icon(Icons.remove_rounded, size: 20),
                      ),
                      const Divider(height: 1),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '지역 중심 이동',
                        onPressed: () {
                          final meta = _provinceMeta(widget.selectedProvince);
                          setState(() {
                            _centerLat = meta.lat;
                            _centerLng = meta.lng;
                            _zoom = meta.zoom;
                          });
                        },
                        icon: const Icon(Icons.my_location_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // 선택된 핀 요약 카드 (매거진 상세 보기 + 네이버 지도 직결)
              if (_selectedPinItem != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFBBF7D0), width: 1.4),
                          boxShadow: const [
                            BoxShadow(color: Color(0x220F172A), blurRadius: 18, offset: Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 64,
                                height: 64,
                                child: _selectedPinItem!.imageUrl.isNotEmpty
                                    ? StorageImage(url: _selectedPinItem!.imageUrl, cacheWidth: 200)
                                    : Container(
                                        color: _selectedPinItem!.category.color.withValues(alpha: 0.12),
                                        alignment: Alignment.center,
                                        child: Icon(_selectedPinItem!.category.icon, color: _selectedPinItem!.category.color),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_selectedPinItem!.categoryEmoji} ${_selectedPinItem!.tRegionLabel(lang)} · ${_selectedPinItem!.categoryBadgeText(lang)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: _selectedPinItem!.category.color,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedPinItem!.tTitle(lang),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      FilledButton.tonal(
                                        key: const Key('map_pin_detail_btn'),
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        ),
                                        onPressed: () => widget.onOpenDetailPage(_selectedPinItem!),
                                        child: Text(
                                          trUi('view_detail_btn', lang),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      FilledButton(
                                        key: const Key('map_pin_naver_btn'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF03C75A),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        ),
                                        onPressed: () => widget.onOpenExternalUrl(_selectedPinItem!.naverRouteUrl),
                                        child: Text(
                                          lang == AppLang.ko ? '🟢 네이버 지도·길찾기 ↗' : '🟢 Naver Map ↗',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
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
                  ),
                ),

              // 하단 우측 출처 표기
              Positioned(
                right: 8,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '배경지도: 국토교통부 VWorld · OpenStreetMap | 길찾기·상세연동: NAVER 지도',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewportSideList(List<DiscoveryItem> visibleItems, AppLang lang) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang == AppLang.ko ? '📍 현재 지도 영역 장소' : '📍 Places in Map Area',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
                Text(
                  lang == AppLang.ko ? '${visibleItems.length}곳' : '${visibleItems.length} places',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                ),
              ],
            ),
          ),
          Expanded(
            child: visibleItems.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        lang == AppLang.ko
                            ? '현재 지도 화면 안에 표시할 항목이 없습니다.\n지도를 축소(-)하거나 다른 지역을 선택해 보세요.'
                            : 'No places in this map area. Zoom out or pick another region.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.5),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: math.min(visibleItems.length, 60),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final it = visibleItems[idx];
                      final isSel = _selectedPinItem?.id == it.id;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _focusItemOnMap(it),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSel ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                              width: isSel ? 1.6 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: it.imageUrl.isNotEmpty
                                      ? StorageImage(url: it.imageUrl, cacheWidth: 180)
                                      : Container(
                                          color: it.category.color.withValues(alpha: 0.1),
                                          alignment: Alignment.center,
                                          child: Icon(it.category.icon, size: 20, color: it.category.color),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${it.categoryEmoji} ${trProvince(it.province, lang)} · ${it.categoryBadgeText(lang)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: it.category.color,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      it.tTitle(lang),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        InkWell(
                                          onTap: () => widget.onOpenDetailPage(it),
                                          child: Text(
                                            lang == AppLang.ko ? '상세 보기 →' : 'Details →',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        InkWell(
                                          onTap: () => widget.onOpenExternalUrl(it.naverRouteUrl),
                                          child: Text(
                                            lang == AppLang.ko ? '🟢 네이버지도 ↗' : '🟢 Naver Map ↗',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF15803D),
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
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final screenW = MediaQuery.sizeOf(context).width;
    final isWide = screenW >= 900;

    return Column(
      children: [
        // 상단 네이버 지도 직결 바
        Container(
          key: const Key('naver_map_top_bar'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: const BoxDecoration(
            color: Color(0xFFF0FDF4),
            border: Border(bottom: BorderSide(color: Color(0xFFBBF7D0))),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_rounded, size: 18, color: Color(0xFF15803D)),
                  const SizedBox(width: 6),
                  Text(
                    lang == AppLang.ko
                        ? '${widget.selectedProvince == '전체' ? '전국' : widget.selectedProvince} 로컬 핀 지도 · 네이버 지도 연결'
                        : '${trProvince(widget.selectedProvince, lang)} Local Map · Synced with NAVER Map',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF14532D)),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    key: const Key('open_naver_map_region_btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF03C75A),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => widget.onOpenExternalUrl(_buildNaverRegionSearchUrl()),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15, color: Colors.white),
                    label: Text(
                      lang == AppLang.ko ? '🟢 네이버 지도로 크게 열기' : '🟢 Open Full NAVER Map',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('naver_quick_food_btn'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => widget.onOpenExternalUrl(_buildNaverRegionSearchUrl(customSuffix: '로컬 맛집')),
                    child: Text(
                      lang == AppLang.ko ? '🍲 네이버지도 맛집 ↗' : '🍲 NAVER Food ↗',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF166534)),
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('naver_quick_sight_btn'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => widget.onOpenExternalUrl(_buildNaverRegionSearchUrl(customSuffix: '가볼만한곳 축제')),
                    child: Text(
                      lang == AppLang.ko ? '🏞️ 네이버지도 명소 ↗' : '🏞️ NAVER Sights ↗',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 메인 스플릿 지도 + 영역 리스트
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mapWidth = isWide ? (constraints.maxWidth - 380).clamp(320.0, 4000.0) : constraints.maxWidth;
              final mapHeight = isWide ? constraints.maxHeight : (constraints.maxHeight * 0.56).clamp(220.0, 1200.0);
              final mapSize = Size(mapWidth, mapHeight);
              final bounds = _computeBounds(mapSize);
              final inBounds = widget.items.where((it) => bounds.contains(it.lat, it.lng)).toList();
              final sideItems = inBounds.isNotEmpty ? inBounds : widget.items;

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: _buildMapCanvas(mapSize, lang)),
                    Container(
                      width: 380,
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: _buildViewportSideList(sideItems, lang),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(height: mapHeight, width: double.infinity, child: _buildMapCanvas(mapSize, lang)),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: _buildViewportSideList(sideItems, lang),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MapPinPill extends StatelessWidget {
  final DiscoveryItem item;
  final bool selected;
  final VoidCallback onTap;

  const _MapPinPill({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 전통시장은 먹거리(주황)와 구분되게 갈색 🧺 핀
    final bgColor = selected ? const Color(0xFF0F172A) : (item.isMarket ? const Color(0xFF92400E) : item.category.color);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 8, vertical: selected ? 5 : 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white, width: selected ? 2.2 : 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x330F172A), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Text(
          item.pinShortLabel(appLangNotifier.value),
          maxLines: 1,
          style: TextStyle(
            fontSize: selected ? 12 : 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
