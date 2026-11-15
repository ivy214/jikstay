// 에어비앤비 벤치마킹 숙소 상세페이지 + 고전환 직거래 예약·문의 신청 유도 모듈.
// - ?id=stay_xxx 로 들어오면 상세페이지를 바로 연다 (?id=stay_demo_haeundae 데모 미리보기 지원)
// - 데스크톱 5분할 벤토 포토 그리드 + 공간별 사진 투어 모달
// - 카테고리별 표준 Amenity 모달 + 미제공 시설(취소선) 명시
// - 데스크톱 2단 레이아웃 + 우측 Sticky 일정·인원 선택 및 직거래 신청 유도 카드
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'amenities.dart';
import 'demo_data.dart';
import 'i18n.dart';
import 'legal.dart';
import 'naver_place_info.dart';
import 'review_auth.dart';
import 'translation_store.dart';
import 'web_utils.dart';

part 'detail/listing_detail_page.dart';
part 'detail/booking_widgets.dart';
part 'detail/info_sections.dart';
part 'detail/gallery.dart';
part 'detail/reviews_nearby.dart';

/// 운영자 직거래 창구(홈페이지·예약 링크)가 있는 숙소인지.
/// 공공 숙소 문서의 direct_booking_url 에는 네이버 지도 검색 URL이 들어 있을 수 있어 그 경우는 제외한다.
/// (Cloud Functions /go 의 directBookingUrl 과 같은 기준)
bool hasDirectBookingUrl(Map<String, dynamic> data) {
  final uri = Uri.tryParse((data['direct_booking_url'] ?? '').toString().trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return false;
  return !uri.host.toLowerCase().contains('map.naver.');
}

/// 숙소 문서에서 누적 평점(평균 별점 · 후기 수)을 안전하게 추출한다.
({double average, int count, int scoreSum}) extractListingRating(Map<String, dynamic> data) {
  final count = (data['review_count'] as num?)?.toInt() ?? 0;
  final sum = (data['score_sum'] as num?)?.toInt() ?? 0;
  if (count <= 0 || sum <= 0) {
    return (average: 0.0, count: 0, scoreSum: 0);
  }
  final avg = (sum / count).clamp(1.0, 5.0);
  return (average: avg, count: count, scoreSum: sum);
}

/// firestore.rules 의 리뷰 입력 제약과 동일한 클라이언트 사전 검증
String? validateUserReviewInput({
  required String nickname,
  required int score,
  required String comment,
}) {
  final nick = nickname.trim();
  final body = comment.trim();
  if (score < 1 || score > 5) return 'score_range';
  if (nick.isEmpty || nick.length > 24) return 'nickname_length';
  if (body.length < 4 || body.length > 600) return 'comment_length';
  return null;
}

const kBrand = Color(0xFFE61E4D);
const kForeignOnly = '외국인관광도시민박업';

enum StayPeriod {
  all('전체'),
  nightly('1박'),
  weekly('일주일'),
  monthly('한달살기');

  final String label;
  const StayPeriod(this.label);
}

String formatWon(num v) =>
    '${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';

/// 카드·상세 대표 요금 텍스트. period 를 주면 해당 기간 요금을 우선 표시한다.
String shortPrice(Map<String, dynamic>? p, {StayPeriod period = StayPeriod.all, AppLang lang = AppLang.ko}) {
  final inquiry = pickLangText(
    lang,
    ko: '요금 직접 문의',
    en: 'Inquire for Rates',
    ja: '料金を直接お問い合わせ',
    zh: '直接咨询房价',
  );
  if (p == null) return inquiry;
  String man(num v) => lang == AppLang.ko
      ? '${(v / 10000).round()}만 원'
      : formatWon(v);
  switch (period) {
    case StayPeriod.nightly:
      return p['nightly_min'] is num
          ? pickLangText(lang,
              ko: '1박 ${man(p['nightly_min'])}~',
              en: 'From ${man(p['nightly_min'])} / night',
              ja: '1泊 ${man(p['nightly_min'])}〜',
              zh: '每晚 ${man(p['nightly_min'])}起')
          : inquiry;
    case StayPeriod.weekly:
      return p['weekly_price'] is num
          ? pickLangText(lang,
              ko: '일주일 ${man(p['weekly_price'])}',
              en: '${man(p['weekly_price'])} / week',
              ja: '1週間 ${man(p['weekly_price'])}',
              zh: '每周 ${man(p['weekly_price'])}')
          : inquiry;
    case StayPeriod.monthly:
      return p['monthly_price'] is num
          ? pickLangText(lang,
              ko: '한달 ${man(p['monthly_price'])}',
              en: '${man(p['monthly_price'])} / month',
              ja: '1ヶ月 ${man(p['monthly_price'])}',
              zh: '每月 ${man(p['monthly_price'])}')
          : inquiry;
    case StayPeriod.all:
      if (p['monthly_price'] is num) return shortPrice(p, period: StayPeriod.monthly, lang: lang);
      if (p['weekly_price'] is num) return shortPrice(p, period: StayPeriod.weekly, lang: lang);
      if (p['nightly_min'] is num) return shortPrice(p, period: StayPeriod.nightly, lang: lang);
      return inquiry;
  }
}

/// 직거래 링크 도메인으로 예약 창구 유형을 판별한다.
String bookingChannelName(String rawUrl, {AppLang lang = AppLang.ko}) {
  final host = (Uri.tryParse(rawUrl.trim())?.host ?? '').toLowerCase();
  if (host.contains('map.naver.')) {
    return pickLangText(lang, ko: '네이버 지도·플레이스', en: 'Naver Map / Place', ja: 'Naverマップ・プレイス', zh: 'Naver地图·Place');
  }
  if (host.contains('booking.naver.') || host == 'naver.me') {
    return pickLangText(lang, ko: '네이버 예약', en: 'Naver Booking', ja: 'Naver予約', zh: 'Naver预订');
  }
  if (host.contains('blog.naver.')) {
    return pickLangText(lang, ko: '네이버 블로그', en: 'Naver Blog', ja: 'Naverブログ', zh: 'Naver博客');
  }
  if (host.contains('kakao.')) {
    return pickLangText(lang, ko: '카카오톡 채널', en: 'KakaoTalk Channel', ja: 'KakaoTalkチャンネル', zh: 'KakaoTalk频道');
  }
  if (host.contains('instagram.')) {
    return pickLangText(lang, ko: '인스타그램', en: 'Instagram', ja: 'Instagram', zh: 'Instagram');
  }
  return pickLangText(lang, ko: '호스트 직거래', en: 'Host Direct', ja: 'ホスト直接予約', zh: '房东直订');
}

String bookingCtaLabel(String rawUrl, {Map<String, dynamic>? data, AppLang lang = AppLang.ko}) {
  if (data != null && !hasDirectBookingUrl(data)) {
    return trUi('cta_public_map', lang);
  }
  if (lang != AppLang.ko) {
    return trUi('cta_direct_book', lang);
  }
  final ch = bookingChannelName(rawUrl);
  if (ch == '네이버 지도·플레이스') return '네이버 지도·예약처 보기';
  if (ch == '네이버 예약') return '수수료 0원 네이버 예약 신청';
  if (ch == '카카오톡 채널') return '수수료 0원 카카오톡 예약 문의';
  if (ch == '인스타그램') return '수수료 0원 인스타그램 DM 문의';
  return '수수료 0원 직거래 예약 신청';
}

String _tStayTitle(String listingId, Map<String, dynamic> data, AppLang lang) {
  if (lang != AppLang.ko && listingId.isNotEmpty) {
    final fromStore = TranslationStore.field(lang, 'stays', listingId, 'title', '');
    if (fromStore.isNotEmpty) return fromStore;
  }
  return localizedListingTitle(data, lang);
}

String _tStayRegion(String listingId, Map<String, dynamic> data, AppLang lang) {
  final koRegion = '${data['region_depth1'] ?? ''} ${data['region_depth2'] ?? ''}'.trim();
  if (lang == AppLang.ko) return koRegion;
  if (listingId.isNotEmpty) {
    final fromStore = TranslationStore.field(lang, 'stays', listingId, 'region', '');
    if (fromStore.isNotEmpty) return fromStore;
  }
  final d1 = (data['region_depth1'] ?? '').toString();
  final prov = trRegion(d1, lang);
  final d2 = (data['region_depth2'] ?? '').toString().trim();
  return d2.isNotEmpty && prov != d1 ? '$prov ($d2)' : koRegion;
}

String _tLicenseType(String raw, AppLang lang) {
  if (lang == AppLang.ko || raw.isEmpty) return raw;
  const map = <String, Map<AppLang, String>>{
    '외국인관광도시민박업': {
      AppLang.en: 'Foreign-Friendly Urban Homestay',
      AppLang.ja: '外国人観光都市民泊業',
      AppLang.zh: '外国人观光城市民宿业',
    },
    '한옥체험업': {
      AppLang.en: 'Hanok Experience Stay',
      AppLang.ja: '韓屋体験業',
      AppLang.zh: '韩屋体验住宿',
    },
    '숙박업': {
      AppLang.en: 'Licensed Lodging Business',
      AppLang.ja: '宿泊業',
      AppLang.zh: '持牌住宿业',
    },
    '농어촌민박업': {
      AppLang.en: 'Rural Homestay Business',
      AppLang.ja: '農漁村ペンション・民泊',
      AppLang.zh: '农渔村合法民宿',
    },
    '호스텔업': {
      AppLang.en: 'Licensed Hostel',
      AppLang.ja: 'ホステル業',
      AppLang.zh: '持牌旅舍',
    },
  };
  return map[raw]?[lang] ?? raw;
}

String _tAccommodationType(String raw, AppLang lang) {
  if (lang == AppLang.ko || raw.isEmpty) return raw;
  if (raw.contains('외국인 전용 도시민박') || raw.contains('외국인관광도시민박')) {
    return pickLangText(lang, ko: raw, en: 'Foreign-Only Urban Homestay', ja: '外国人専用都市民泊', zh: '外国人专用城市民宿');
  }
  if (raw.contains('한옥')) {
    return pickLangText(lang, ko: raw, en: 'Hanok Stay', ja: '韓屋ステイ', zh: '韩屋住宿');
  }
  if (raw.contains('펜션')) {
    return pickLangText(lang, ko: raw, en: 'Pension / Villa', ja: 'ペンション', zh: '度假别墅');
  }
  if (raw.contains('게스트하우스')) {
    return pickLangText(lang, ko: raw, en: 'Guesthouse', ja: 'ゲストハウス', zh: '青年旅舍');
  }
  if (raw.contains('호텔')) {
    return pickLangText(lang, ko: raw, en: 'Hotel', ja: 'ホテル', zh: '酒店');
  }
  return pickLangText(lang, ko: raw, en: 'Licensed Local Stay', ja: '公認ローカルステイ', zh: '官方认证当地住宿');
}

({String title, String subtitle}) _tHighlight(
  Map<String, String> h,
  Map<String, dynamic> data,
  String listingId,
  AppLang lang,
) {
  final rawTitle = h['title'] ?? '';
  final rawSub = h['subtitle'] ?? '';
  if (lang == AppLang.ko) return (title: rawTitle, subtitle: rawSub);

  String title = rawTitle;
  if (rawTitle.contains('공공 인허가 확인')) {
    title = pickLangText(
      lang,
      ko: rawTitle,
      en: 'Verified Public Lodging License',
      ja: '公的許認可・営業登録の確認済み',
      zh: '已核验官方营业许可',
    );
  } else if (rawTitle.contains('로컬 스테이')) {
    final region = _tStayRegion(listingId, data, lang);
    title = region.isNotEmpty
        ? pickLangText(lang, ko: rawTitle, en: '$region Local Stay', ja: '$region ローカルステイ', zh: '$region 当地住宿')
        : pickLangText(lang, ko: rawTitle, en: 'Local Stay', ja: 'ローカルステイ', zh: '当地住宿');
  } else if (rawTitle.contains('네이버 블로그 방문 후기')) {
    title = pickLangText(
      lang,
      ko: rawTitle,
      en: 'Naver Blog Visitor Reviews & Guides',
      ja: 'Naverブログの訪問レビュー・案内',
      zh: 'Naver 博客访客评价与指南',
    );
  }

  String sub = rawSub;
  final ktoMatch = RegExp(r'콘텐츠\s*#?(\d+)').firstMatch(rawSub);
  if (ktoMatch != null) {
    final cid = ktoMatch.group(1) ?? '';
    sub = pickLangText(
      lang,
      ko: rawSub,
      en: 'Verified legal stay registered with Korea Tourism Organization (Content #$cid).',
      ja: '韓国観光公社（コンテンツ #$cid）に登録・検証された合法宿泊施設です。',
      zh: '已在韩国观光公社（内容编号 #$cid）备案认证的合法住宿。',
    );
  } else if (rawSub.contains('실제 여행객 후기 및 안내글')) {
    final cntMatch = RegExp(r'(\d+)건').firstMatch(rawSub);
    final cnt = cntMatch?.group(1) ?? '1';
    sub = pickLangText(
      lang,
      ko: rawSub,
      en: 'Open $cnt real traveler review(s) and guide post(s) directly from this page.',
      ja: '実際の旅行者レビュー・案内記事（$cnt件）をこのページからすぐにご覧いただけます。',
      zh: '可在本页面直接查看 $cnt 篇真实旅客评价与攻略文章。',
    );
  } else if (rawSub == '호스트 소개 자료에서 확인된 숙소 주요 매력입니다.') {
    sub = pickLangText(
      lang,
      ko: rawSub,
      en: 'Key stay highlight verified from host information.',
      ja: 'ホスト紹介資料で確認された宿泊施設の主な魅力です。',
      zh: '由房东介绍资料确认的住宿核心亮点。',
    );
  } else if (listingId.isNotEmpty) {
    final storeSummary = TranslationStore.field(lang, 'stays', listingId, 'summary', '');
    if (storeSummary.isNotEmpty && rawSub == (data['location_info'] is Map ? (data['location_info']['display_address'] ?? '') : '')) {
      sub = storeSummary.replaceAll(RegExp(r"^\['|'\]$"), '');
    }
  }
  return (title: title, subtitle: sub);
}

String _fmtDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

/// 선택한 일정·인원·혜택·언어를 바탕으로 호스트에게 바로 붙여넣을 수 있는 신청 문구를 생성한다.
/// 해외 게스트(en/ja/zh) 선택 시 한국인 호스트를 위한 한국어 문구와 외국어 원문을 자동 병기한다.
String buildBookingInquiryTemplate(
  Map<String, dynamic> data, {
  DateTimeRange? dateRange,
  int adults = 2,
  int children = 0,
  bool includePromo = true,
  AppLang lang = AppLang.ko,
}) {
  final title = (data['title'] ?? '숙소').toString();
  final promo = (data['promo_title'] ?? '').toString().trim();
  final lines = <String>[
    lang == AppLang.ko
        ? "안녕하세요! 직스테이에서 '$title' 숙소를 보고 직거래 예약 문의드립니다."
        : "[직스테이 글로벌 예약 문의 / JikStay Direct Inquiry]\n안녕하세요 사장님! 직스테이(JikStay)에서 '$title' 숙소를 보고 해외 여행객이 예약 문의드립니다.",
  ];
  if (dateRange != null) {
    final nights = math.max(1, dateRange.duration.inDays);
    final suffix = lang == AppLang.ko ? '$nights박' : '$nights박 / $nights nights';
    lines.add('· 희망 일정: ${_fmtDate(dateRange.start)} ~ ${_fmtDate(dateRange.end)} ($suffix)');
  }
  final guestParts = <String>['성인 $adults명', if (children > 0) '어린이 $children명'];
  lines.add('· 인원: ${guestParts.join(', ')}${lang == AppLang.ko ? '' : ' (Adults: $adults${children > 0 ? ', Children: $children' : ''})'}');
  if (includePromo && promo.isNotEmpty) {
    lines.add('· 이벤트 신청: $promo');
  }
  lines.add('예약 가능 여부와 직거래 안내 부탁드립니다. 감사합니다!');

  if (lang == AppLang.en) {
    lines.add("(Hello! I found your government-verified stay '$title' on JikStay and would like to inquire about availability & direct booking. Thank you!)");
  } else if (lang == AppLang.ja) {
    lines.add("(こんにちは！韓国公認宿検索『JikStay』で「$title」を拝見し、空室状況と予約方法をお伺いしたくご連絡いたしました。)");
  } else if (lang == AppLang.zh) {
    lines.add("(您好！我們在韓國合法民宿平台 JikStay 看到「$title」，想詢問空房與直接預訂方式，謝謝您！)");
  }
  return lines.join('\n');
}

/// 선택한 숙박 일수에 따른 예상 직거래 요금 및 일반 플랫폼 수수료(약 14%) 절감 예상액 계산
({int? estimatedAmount, String unitLabel, int? estimatedFeeSaved}) calculateStayEstimate(
  Map<String, dynamic>? pricing, {
  DateTimeRange? dateRange,
}) {
  if (pricing == null) {
    return (estimatedAmount: null, unitLabel: '요금 직접 문의', estimatedFeeSaved: null);
  }
  final nightly = (pricing['nightly_min'] as num?)?.round();
  final weekly = (pricing['weekly_price'] as num?)?.round();
  final monthly = (pricing['monthly_price'] as num?)?.round();
  final nights = dateRange != null ? math.max(1, dateRange.duration.inDays) : null;

  int? est;
  String label = '기준 요금';

  if (nights != null) {
    if (nights >= 28 && monthly != null) {
      est = ((monthly / 30) * nights).round();
      label = '$nights박 (한달살기 특가 기준)';
    } else if (nights >= 7 && weekly != null) {
      est = ((weekly / 7) * nights).round();
      label = '$nights박 (일주일 연박 기준)';
    } else if (nightly != null) {
      est = nightly * nights;
      label = '$nights박 예상 직거래가';
    }
  }

  if (est == null) {
    if (nightly != null) {
      est = nightly;
      label = '1박 최저 기준';
    } else if (weekly != null) {
      est = weekly;
      label = '일주일 기준';
    } else if (monthly != null) {
      est = monthly;
      label = '한달살기 기준';
    }
  }

  final saved = est != null ? ((est * 0.142) / 1000).round() * 1000 : null;
  return (estimatedAmount: est, unitLabel: label, estimatedFeeSaved: (saved != null && saved >= 5000) ? saved : null);
}

/// 신청 문구 자동 복사 + 합법 인허가 확인 브릿지 모달 → 클릭 +1 → 호스트 예약 창구 연결
Future<void> goDirectBooking(
  BuildContext context,
  String docId,
  Map<String, dynamic> data, {
  DateTimeRange? dateRange,
  int adults = 2,
  int children = 0,
  bool includePromo = true,
}) async {
  final lang = appLangNotifier.value;
  final isForeignOnly = data['license_type'] == kForeignOnly;
  final explicitUrl = (data['direct_booking_url'] ?? data['naver_map_url'] ?? '').toString().trim();
  final rawUrl = explicitUrl.isNotEmpty
      ? explicitUrl
      : 'https://map.naver.com/p/search/${Uri.encodeComponent('${data['region_depth2'] ?? ''} ${data['title'] ?? ''}'.trim())}';
  final channel = bookingChannelName(rawUrl);
  final inquiryText = buildBookingInquiryTemplate(
    data,
    dateRange: dateRange,
    adults: adults,
    children: children,
    includePromo: includePromo,
    lang: lang,
  );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.verified_user_rounded, color: kBrand, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$channel 신청 페이지로 연결', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text('중개수수료 0원 · 지금 이동해도 바로 결제되지 않습니다',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.normal)),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('자동 복사될 예약·문의 메시지',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF212529))),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: inquiryText));
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('문의 문구가 복사되었습니다.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: const Text('복사', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(inquiryText, style: const TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xFF495057))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1FBF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC3E6CB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, size: 16, color: Color(0xFF198754)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '인허가 확인: ${data['license_type']} (${data['license_number'] ?? '확인완료'})',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '· 연결 창구: $channel (호스트 공식 예약·문의 채널)\n'
                      '· 직스테이는 예약·결제 당사자가 아니므로 결제 전 상호·예금주 일치를 확인하세요.',
                      style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF343A40)),
                    ),
                  ],
                ),
              ),
              if (isForeignOnly) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '외국인관광도시민박업은 관련 법령상 외국인 게스트만 투숙할 수 있습니다.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('닫기')),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kBrand,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.open_in_new_rounded, size: 17),
          label: Text('문구 복사 후 $channel 열기', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (ok != true) return;

  await Clipboard.setData(ClipboardData(text: inquiryText));

  final uri = Uri.tryParse(rawUrl);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('유효하지 않은 직거래 링크입니다.')));
    }
    return;
  }

  final hostName = Uri.base.host.toLowerCase();
  final isLocalOrDemo = docId.startsWith('stay_demo_') || hostName == 'localhost' || hostName == '127.0.0.1';
  Uri targetUri = uri;

  if (!isLocalOrDemo) {
    // 실서비스 환경에서는 Cloud Functions /go 를 경유해 외부 연결 클릭 수를 집계한다(검색봇 제외, 과금 없음).
    // 이동 대상은 /go 가 다시 결정한다: 운영자 직거래 링크 → 없으면 네이버 지도 검색.
    targetUri = Uri.parse('${currentSiteOrigin()}/go?id=${Uri.encodeComponent(docId)}');
  } else if (!docId.startsWith('stay_demo_')) {
    try {
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(docId)
          .update({'outbound_clicks': FieldValue.increment(1)});
    } catch (_) {
      // 통계 기록 실패는 이동을 막지 않는다.
    }
  }
  try {
    final launched = await launchUrl(targetUri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('예약 페이지를 열 수 없습니다.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('예약 페이지를 열 수 없습니다.')));
    }
  }
}
