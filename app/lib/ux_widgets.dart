// 사용자 편의 공통 UI: 찜(기기 저장) · 공유 · 상세 하단 고정 행동 바 · 핵심 정보 칩 · 출처/갱신일 표기
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'discovery_models.dart';
import 'hub_details.dart';
import 'i18n.dart';
import 'web_utils.dart';

// ---------------------------------------------------------------------------
// 찜 — 로그인 없이 이 기기(localStorage)에만 저장
// ---------------------------------------------------------------------------

class SavedPlaces {
  SavedPlaces._();

  static const _key = 'jikstay_saved_v1';
  static final ValueNotifier<List<String>> ids = ValueNotifier<List<String>>(_load());

  static List<String> _load() {
    try {
      final raw = storeGet(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.map((e) => e.toString()).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static bool contains(String id) => ids.value.contains(id);

  /// 찜 추가/해제. 추가되면 true.
  static bool toggle(String id) {
    final next = [...ids.value];
    final removed = next.remove(id);
    if (!removed) next.insert(0, id);
    ids.value = next;
    storeSet(_key, jsonEncode(next));
    trackPortalEvent(removed ? 'unsave_place' : 'save_place', {'item_id': id});
    return !removed;
  }

  static void resetForTest() => ids.value = const [];
}

// ---------------------------------------------------------------------------
// 공유 — 휴대폰은 기기 공유 시트, 그 외에는 링크 복사
// ---------------------------------------------------------------------------

Future<void> sharePlace(BuildContext context, {required String title, required String url, required AppLang lang}) async {
  trackPortalEvent('share_place', {'url': url});
  if (await nativeShare(title, url)) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(pickLangText(lang,
        ko: '링크를 복사했습니다. 카카오톡 등에 붙여 넣어 공유하세요.',
        en: 'Link copied. Paste it to share.',
        ja: 'リンクをコピーしました。',
        zh: '已複製連結，可貼上分享。')),
  ));
}

/// 찜 토글 + 안내 스낵바 (상단 바 버튼·하단 행동 바 공용). 담았으면 true.
bool toggleSavedWithSnack(BuildContext context, String itemId, AppLang lang) {
  final added = SavedPlaces.toggle(itemId);
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 2),
    content: Text(added
        ? pickLangText(lang,
            ko: '찜 목록에 담았습니다. 홈의 ‘찜’에서 다시 볼 수 있어요.',
            en: 'Saved. Find it under “Saved” on the home screen.',
            ja: '保存しました。ホームの「保存」から確認できます。',
            zh: '已收藏，可在首頁「收藏」查看。')
        : pickLangText(lang, ko: '찜을 해제했습니다.', en: 'Removed from saved.', ja: '保存を解除しました。', zh: '已取消收藏。')),
  ));
  return added;
}

/// 상세 상단 바용 찜 버튼 (넓은 화면에서는 하단 행동 바가 없으므로 여기서 찜한다).
class SaveAppBarButton extends StatelessWidget {
  const SaveAppBarButton({super.key, required this.itemId, required this.lang});

  final String itemId;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: SavedPlaces.ids,
      builder: (context, saved, _) {
        final on = saved.contains(itemId);
        return TextButton.icon(
          key: const Key('appbar_save_btn'),
          onPressed: () => toggleSavedWithSnack(context, itemId, lang),
          icon: Icon(on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 18, color: on ? const Color(0xFFE11D48) : const Color(0xFF334155)),
          label: Text(
            on
                ? pickLangText(lang, ko: '찜함', en: 'Saved', ja: '保存済', zh: '已收藏')
                : pickLangText(lang, ko: '찜하기', en: 'Save', ja: '保存', zh: '收藏'),
            style: TextStyle(color: on ? const Color(0xFFE11D48) : const Color(0xFF334155)),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 상세 하단 고정 행동 바 (모바일) — 길찾기를 스크롤 끝까지 찾지 않아도 되게
// ---------------------------------------------------------------------------

class DetailActionBar extends StatelessWidget {
  const DetailActionBar({
    super.key,
    required this.itemId,
    required this.lang,
    required this.onDirections,
    required this.onShare,
    this.phone = '',
    this.onCall,
    this.officialUrl = '',
    this.onOfficial,
    this.savable = true,
  });

  final String itemId;
  final AppLang lang;
  final VoidCallback onDirections;
  final VoidCallback onShare;
  final String phone;
  final VoidCallback? onCall;
  final String officialUrl;
  final VoidCallback? onOfficial;
  final bool savable;

  Widget _iconAction({required IconData icon, required String label, required VoidCallback onTap, Key? key, Color? color}) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 56,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color ?? const Color(0xFF334155)),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final directions = pickLangText(lang, ko: '길찾기', en: 'Directions', ja: 'ルート', zh: '導航');
    return Material(
      key: const Key('detail_action_bar'),
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              if (savable)
                ValueListenableBuilder<List<String>>(
                  valueListenable: SavedPlaces.ids,
                  builder: (context, saved, _) {
                    final on = saved.contains(itemId);
                    return _iconAction(
                      key: const Key('action_save_btn'),
                      icon: on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: on ? const Color(0xFFE11D48) : null,
                      label: on
                          ? pickLangText(lang, ko: '찜함', en: 'Saved', ja: '保存済', zh: '已收藏')
                          : pickLangText(lang, ko: '찜', en: 'Save', ja: '保存', zh: '收藏'),
                      onTap: () => toggleSavedWithSnack(context, itemId, lang),
                    );
                  },
                ),
              _iconAction(
                key: const Key('action_share_btn'),
                icon: Icons.ios_share_rounded,
                label: pickLangText(lang, ko: '공유', en: 'Share', ja: '共有', zh: '分享'),
                onTap: onShare,
              ),
              if (phone.isNotEmpty && onCall != null)
                _iconAction(
                  key: const Key('action_call_btn'),
                  icon: Icons.call_outlined,
                  label: pickLangText(lang, ko: '전화', en: 'Call', ja: '電話', zh: '電話'),
                  onTap: onCall!,
                ),
              if (officialUrl.isNotEmpty && onOfficial != null)
                _iconAction(
                  key: const Key('action_official_btn'),
                  icon: Icons.language_rounded,
                  label: pickLangText(lang, ko: '공식', en: 'Website', ja: '公式', zh: '官網'),
                  onTap: onOfficial!,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('action_directions_btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF03C75A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions_rounded, size: 20),
                    label: Text(directions, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 핵심 정보 칩 — 운영시간·휴무·주차·요금처럼 방문 결정에 필요한 정보를 제목 바로 아래에
// ---------------------------------------------------------------------------

const _factKeys = <(String, String)>[
  ('시간', '🕒'),
  ('휴무', '📅'),
  ('쉬는', '📅'),
  ('기간', '📅'),
  ('주차', '🅿️'),
  ('요금', '💳'),
  ('입장', '💳'),
  ('메뉴', '🍽️'),
];

/// 탐방정보 행에서 방문 결정용 핵심 항목을 최대 [max]개 고른다.
List<(String, PracticalInfoRow)> pickQuickFacts(List<PracticalInfoRow> rows, {int max = 4}) {
  final out = <(String, PracticalInfoRow)>[];
  final used = <String>{};
  for (final (key, emoji) in _factKeys) {
    for (final r in rows) {
      if (out.length >= max) return out;
      if (r.value.trim().isEmpty || used.contains(r.label) || !r.label.contains(key)) continue;
      used.add(r.label);
      out.add((emoji, r));
      break;
    }
  }
  return out;
}

class QuickFactsChips extends StatelessWidget {
  const QuickFactsChips({super.key, required this.rows});

  final List<PracticalInfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final facts = pickQuickFacts(rows);
    if (facts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      key: const Key('quick_facts'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (emoji, r) in facts)
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Text(
              '$emoji ${r.label} · ${r.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF14532D)),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 출처 · 갱신일 — 정보의 신뢰도를 사용자가 직접 판단할 수 있게
// ---------------------------------------------------------------------------

String itemSourceLabel(DiscoveryItem it, AppLang lang) {
  final raw = it.raw;
  if (it.category == DiscoveryCategory.stay) {
    final src = (raw['src'] ?? '').toString();
    final mng = (raw['public_mng_no'] ?? '').toString();
    final mois = src.isNotEmpty ? src == 'mois' : (mng.isNotEmpty && !mng.startsWith('KTO-'));
    return mois
        ? pickLangText(lang, ko: '행정안전부 인허가 데이터', en: 'MOIS license data', ja: '行政安全部 許認可データ', zh: '行政安全部許可資料')
        : pickLangText(lang, ko: '한국관광공사 TourAPI', en: 'Korea Tourism Organization', ja: '韓国観光公社', zh: '韓國觀光公社');
  }
  if (it.id.startsWith('spot_ev_nv_')) {
    return pickLangText(lang, ko: '네이버 검색 축제 정보', en: 'Naver festival search', ja: 'NAVER祭り検索', zh: 'Naver 慶典搜尋');
  }
  if (it.category == DiscoveryCategory.ebook) {
    return pickLangText(lang, ko: '지자체 공식 자료', en: 'Official municipal source', ja: '自治体公式資料', zh: '地方政府官方資料');
  }
  if (it.category == DiscoveryCategory.culture) {
    return raw['source'] == 'kopis'
        ? pickLangText(lang, ko: 'KOPIS 공연예술통합전산망', en: 'KOPIS (Korea Performing Arts Box Office)', ja: 'KOPIS 公演芸術統合電算網', zh: 'KOPIS 表演藝術整合網')
        : pickLangText(lang, ko: '한국문화정보원 문화정보', en: 'Korea Culture Information Service', ja: '韓国文化情報院', zh: '韓國文化資訊院');
  }
  return pickLangText(lang, ko: '한국관광공사 TourAPI', en: 'Korea Tourism Organization', ja: '韓国観光公社', zh: '韓國觀光公社');
}

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

class SourceLine extends StatelessWidget {
  const SourceLine({super.key, required this.item, required this.lang});

  final DiscoveryItem item;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final updated = HubDetailStore.updatedAtMs;
    final when = updated > 0
        ? pickLangText(lang,
            ko: ' · ${_fmtDate(updated)} 기준',
            en: ' · as of ${_fmtDate(updated)}',
            ja: ' · ${_fmtDate(updated)}時点',
            zh: ' · ${_fmtDate(updated)} 更新')
        : '';
    final label = pickLangText(lang, ko: '출처', en: 'Source', ja: '出典', zh: '資料來源');
    return Text(
      '$label: ${itemSourceLabel(item, lang)}$when',
      key: const Key('source_line'),
      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    );
  }
}

/// 상세 화면(스토리·장소)의 흰 카드 본문. 화면에 보이는 만큼만 배치한다 (SliverList).
/// SingleChildScrollView + Column 이면 화면 밖 긴 본문(한글 줄바꿈 계산 포함)까지 한꺼번에 배치해
/// 상세를 여는 탭이 수백 ms 걸렸다 (INP). 배치는 예전과 같다: 최대 760px 가운데, 항목은 왼쪽 정렬.
class DetailCardScrollView extends StatelessWidget {
  final ScrollController? controller;
  final bool isWide;
  final List<Widget> children;

  const DetailCardScrollView({super.key, this.controller, required this.isWide, required this.children});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final outer = isWide ? 28.0 : 16.0;
    final side = math.max(outer, (screenW - 760) / 2);
    final vertical = isWide ? 28.0 : 18.0;
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, vertical, side, vertical),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(color: Color(0x0A0F172A), blurRadius: 24, offset: Offset(0, 8)),
              ],
            ),
            sliver: SliverPadding(
              padding: EdgeInsets.all(isWide ? 34 : 20),
              sliver: SliverList.list(
                children: [
                  // Column(crossAxisAlignment: start) 와 같은 배치: 너비는 최대, 자식은 왼쪽 정렬
                  for (final c in children) Align(alignment: AlignmentDirectional.topStart, child: c),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
