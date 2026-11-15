// 네이버 지역 검색으로 보강한 업종 분류·공식 링크 표시 (backend/enrich_naver_local.py 가 채우는 필드)
//   naver_category  예: "한식>감자탕", "숙박>펜션"
//   naver_link      공식 홈페이지 / 인스타그램 / 네이버 톡톡 등 (OTA 링크는 백엔드에서 제외)
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'i18n.dart';
import 'web_utils.dart';

enum OfficialLinkKind { website, instagram, naverTalk, blog, youtube, store, reservation }

OfficialLinkKind officialLinkKind(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  if (host.contains('instagram.com')) return OfficialLinkKind.instagram;
  if (host.contains('talk.naver.com')) return OfficialLinkKind.naverTalk;
  if (host.contains('blog.naver.com') || host.contains('tistory.com') || host.contains('brunch.co.kr')) {
    return OfficialLinkKind.blog;
  }
  if (host.contains('youtube.com') || host.contains('youtu.be')) return OfficialLinkKind.youtube;
  if (host.contains('smartstore.naver.com')) return OfficialLinkKind.store;
  if (host.contains('catchtable.co.kr') || host.contains('booking') || host.contains('onda.me') || host.contains('h2yo.kr')) {
    return OfficialLinkKind.reservation;
  }
  return OfficialLinkKind.website;
}

String officialLinkLabel(String url, AppLang lang) {
  const labels = <OfficialLinkKind, Map<AppLang, String>>{
    OfficialLinkKind.website: {AppLang.ko: '공식 홈페이지', AppLang.en: 'Official website', AppLang.ja: '公式サイト', AppLang.zh: '官方網站'},
    OfficialLinkKind.instagram: {AppLang.ko: '공식 인스타그램', AppLang.en: 'Instagram', AppLang.ja: 'Instagram', AppLang.zh: 'Instagram'},
    OfficialLinkKind.naverTalk: {AppLang.ko: '네이버 톡톡 문의', AppLang.en: 'Naver TalkTalk', AppLang.ja: 'NAVERトークトーク', AppLang.zh: 'Naver TalkTalk'},
    OfficialLinkKind.blog: {AppLang.ko: '운영자 블로그', AppLang.en: 'Owner blog', AppLang.ja: '運営者ブログ', AppLang.zh: '業者部落格'},
    OfficialLinkKind.youtube: {AppLang.ko: '유튜브 채널', AppLang.en: 'YouTube', AppLang.ja: 'YouTube', AppLang.zh: 'YouTube'},
    OfficialLinkKind.store: {AppLang.ko: '스마트스토어', AppLang.en: 'Online store', AppLang.ja: 'オンラインストア', AppLang.zh: '線上商店'},
    OfficialLinkKind.reservation: {AppLang.ko: '예약 페이지', AppLang.en: 'Reservation page', AppLang.ja: '予約ページ', AppLang.zh: '預約頁面'},
  };
  final kind = officialLinkKind(url);
  return labels[kind]![lang] ?? labels[kind]![AppLang.ko]!;
}

IconData _iconFor(OfficialLinkKind kind) {
  switch (kind) {
    case OfficialLinkKind.instagram:
      return Icons.camera_alt_outlined;
    case OfficialLinkKind.naverTalk:
      return Icons.chat_bubble_outline_rounded;
    case OfficialLinkKind.blog:
      return Icons.article_outlined;
    case OfficialLinkKind.youtube:
      return Icons.smart_display_outlined;
    case OfficialLinkKind.store:
      return Icons.storefront_outlined;
    case OfficialLinkKind.reservation:
      return Icons.event_available_outlined;
    case OfficialLinkKind.website:
      return Icons.language_rounded;
  }
}

/// 업종 분류 칩 + 공식 링크 버튼 + "정보 출처: 네이버" 표기. 표시할 값이 없으면 아무것도 그리지 않는다.
class NaverPlaceInfo extends StatelessWidget {
  const NaverPlaceInfo({super.key, required this.data, required this.lang, this.itemId = ''});

  final Map<String, dynamic> data;
  final AppLang lang;
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final link = (data['naver_link'] ?? '').toString().trim();
    final category = (data['naver_category'] ?? '').toString().trim();
    final uri = Uri.tryParse(link);
    final validLink = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (category.isEmpty && !validLink) return const SizedBox.shrink();

    final source = switch (lang) {
      AppLang.ko => '정보 출처: 네이버',
      AppLang.en => 'Source: NAVER',
      AppLang.ja => '情報提供: NAVER',
      AppLang.zh => '資料來源：NAVER',
    };

    return Column(
      key: const Key('naver_place_info'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (category.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  category.replaceAll('>', ' › '),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
              ),
            if (validLink)
              OutlinedButton.icon(
                key: const Key('naver_official_link_btn'),
                onPressed: () {
                  trackPortalEvent('open_official_link', {'item_id': itemId, 'kind': officialLinkKind(link).name});
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: Icon(_iconFor(officialLinkKind(link)), size: 17),
                label: Text(officialLinkLabel(link, lang), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(source, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }
}
