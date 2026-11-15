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
import 'translation_store.dart';
import 'web_utils.dart';

bool isPublicUnclaimed(Map<String, dynamic> data) {
  final tier = (data['listing_tier'] ?? '').toString();
  final appId = (data['application_id'] ?? '').toString();
  return tier == 'public' && appId.isEmpty;
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
  if (data != null && isPublicUnclaimed(data)) {
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
    // 실서비스 환경에서는 Cloud Functions /go 엔드포인트를 경유해
    // 검색봇 제외·24시간 중복 클릭 차단·호스트 CPC 크레딧(클릭당 300원) 차감을 원자적으로 처리한다.
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

class ListingDetailPage extends StatefulWidget {
  final String listingId;
  final WidgetBuilder homeBuilder;
  final Map<String, dynamic>? initialData;

  const ListingDetailPage({
    super.key,
    required this.listingId,
    required this.homeBuilder,
    this.initialData,
  });

  @override
  State<ListingDetailPage> createState() => _ListingDetailPageState();
}

class _ListingDetailPageState extends State<ListingDetailPage> {
  Future<Map<String, dynamic>?>? _future;

  // 일정·인원·이벤트 신청 상태 (상세페이지 & 모바일 하단바 공유)
  DateTimeRange? _dateRange;
  int _adults = 2;
  int _children = 0;
  bool _includePromo = true;
  int _localAddedCount = 0;
  int _localAddedScore = 0;

  @override
  void initState() {
    super.initState();
    syncListingUrl(widget.listingId);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));
    _dateRange = DateTimeRange(start: start, end: start.add(const Duration(days: 2)));
    _future = _loadListing();
  }

  Future<Map<String, dynamic>?> _loadListing() async {
    if (widget.initialData != null) return widget.initialData;
    final demo = findDemoListing(widget.listingId);
    if (demo != null) return demo;
    final snap = await FirebaseFirestore.instance.collection('listings').doc(widget.listingId).get();
    return snap.data();
  }

  void _back(BuildContext context) {
    syncListingUrl(null);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: widget.homeBuilder));
    }
  }

  Future<void> _copyShareLink(BuildContext context) async {
    final shareUrl = '${currentSiteOrigin()}/?id=${Uri.encodeComponent(widget.listingId)}';
    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (context.mounted) {
      final lang = appLangNotifier.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pickLangText(
            lang,
            ko: '숙소 링크가 복사되었습니다. 카카오톡 등에 붙여넣어 공유하세요!',
            en: 'Stay link copied to clipboard.',
            ja: '宿泊施設のリンクをコピーしました。',
            zh: '已复制住宿链接。',
          )),
        ),
      );
    }
  }

  Future<void> _pickDates(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lang = appLangNotifier.value;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      helpText: pickLangText(
        lang,
        ko: '체크인 · 체크아웃 날짜 선택',
        en: 'Select Check-in & Check-out Dates',
        ja: 'チェックイン・チェックアウト日を選択',
        zh: '选择入住与退房日期',
      ),
      saveText: pickLangText(lang, ko: '일정 적용', en: 'Apply', ja: '適用', zh: '应用'),
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 940;
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLangNotifier,
      builder: (context, lang, _) {
        if (lang != AppLang.ko && !TranslationStore.isLoaded(lang)) {
          TranslationStore.ensureLoaded(lang);
        }
        return ValueListenableBuilder<int>(
          valueListenable: translationRevisionNotifier,
          builder: (context, _, _) => FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              final data = snap.data;
              final hasData = snap.connectionState == ConnectionState.done && !snap.hasError && data != null;
              return Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 0,
                  shape: const Border(bottom: BorderSide(color: Color(0xFFEBEBEB))),
                  leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _back(context)),
                  title: Text(
                    hasData
                        ? _tStayTitle(widget.listingId, data, lang)
                        : pickLangText(lang, ko: '숙소 상세', en: 'Stay Details', ja: '宿泊詳細', zh: '住宿详情'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  actions: [
                    const LangSelectorButton(),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: () => _copyShareLink(context),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: Text(pickLangText(lang, ko: '공유하기', en: 'Share', ja: '共有', zh: '分享')),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: Builder(builder: (context) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError || data == null) {
                    return Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(pickLangText(
                          lang,
                          ko: '공개 중인 숙소를 찾을 수 없습니다.',
                          en: 'Listing not found.',
                          ja: '公開中の宿泊施設が見つかりません。',
                          zh: '未找到公开中的住宿。',
                        )),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _back(context),
                          child: Text(pickLangText(lang, ko: '전체 숙소 보기', en: 'Browse All Stays', ja: '宿泊一覧へ', zh: '查看全部住宿')),
                        ),
                      ]),
                    );
                  }
                  return ListView(
                    children: [
                      if (widget.listingId.startsWith('stay_demo_'))
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFFFF8E6),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Center(
                            child: Text(
                              pickLangText(
                                lang,
                                ko: '미리보기 데모 화면입니다 · 실제 운영 시 영업신고 대조를 마친 숙소 및 공공 API 선별 정보가 표시됩니다.',
                                en: 'Preview demo listing · Live listings display verified municipal registrations and public API data.',
                                ja: 'デモプレビュー画面です · 本番時は営業届出照合済みの宿泊施設と公的API情報が表示されます。',
                                zh: '此为演示预览页面 · 正式页面展示经官方营业核验与公共API筛选的住宿信息。',
                              ),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF856404)),
                            ),
                          ),
                        ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: ListingDetailBody(
                        listingId: widget.listingId,
                        data: {
                          ...data,
                          if (_localAddedCount > 0) ...{
                            'review_count': ((data['review_count'] as num?)?.toInt() ?? 0) + _localAddedCount,
                            'score_sum': ((data['score_sum'] as num?)?.toInt() ?? 0) + _localAddedScore,
                          },
                        },
                        isOfflineDemo: widget.initialData != null || widget.listingId.startsWith('stay_demo_'),
                        onReviewAdded: (addedScore) => setState(() {
                          _localAddedCount += 1;
                          _localAddedScore += addedScore;
                        }),
                        dateRange: _dateRange,
                        adults: _adults,
                        children: _children,
                        includePromo: _includePromo,
                        onPickDates: () => _pickDates(context),
                        onGuestsChanged: (a, c) => setState(() {
                          _adults = a;
                          _children = c;
                        }),
                        onIncludePromoChanged: (v) => setState(() => _includePromo = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const LegalFooter(),
                ],
              );
            }),
            bottomNavigationBar: (!hasData || isDesktop)
                ? null
                : _MobileStickyBookingBar(
                    listingId: widget.listingId,
                    data: data,
                    dateRange: _dateRange,
                    adults: _adults,
                    children: _children,
                    includePromo: _includePromo,
                    onPickDates: () => _pickDates(context),
                  ),
              );
            },
          ),
        );
      },
    );
  }
}

class ListingDetailBody extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final bool isOfflineDemo;
  final ValueChanged<int>? onReviewAdded;
  final DateTimeRange? dateRange;
  final int adults;
  final int children;
  final bool includePromo;
  final VoidCallback onPickDates;
  final void Function(int adults, int children) onGuestsChanged;
  final ValueChanged<bool> onIncludePromoChanged;

  const ListingDetailBody({
    super.key,
    required this.listingId,
    required this.data,
    this.isOfflineDemo = false,
    this.onReviewAdded,
    required this.dateRange,
    required this.adults,
    required this.children,
    required this.includePromo,
    required this.onPickDates,
    required this.onGuestsChanged,
    required this.onIncludePromoChanged,
  });

  Future<void> _openExternal(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _buildSpecsLine(AppLang lang) {
    final specs = data['room_specs'] is Map ? Map<String, dynamic>.from(data['room_specs'] as Map) : const {};
    final capStd = data['capacity_standard'];
    final capMax = data['capacity_max'];
    final parts = <String>[
      if (capMax != null)
        pickLangText(lang, ko: '최대 $capMax명', en: 'Max $capMax guests', ja: '最大$capMax名', zh: '最多$capMax人')
      else if (capStd != null)
        pickLangText(lang, ko: '기준 $capStd명', en: 'Standard $capStd guests', ja: '基準$capStd名', zh: '标准$capStd人'),
      if (capStd != null && capMax != null && capStd != capMax)
        pickLangText(lang, ko: '(기준 $capStd명)', en: '(Std $capStd)', ja: '（基準$capStd名）', zh: '（标准$capStd人）'),
      if (specs['bedrooms'] != null)
        pickLangText(lang, ko: '침실 ${specs['bedrooms']}개', en: '${specs['bedrooms']} bedroom(s)', ja: '寝室${specs['bedrooms']}', zh: '${specs['bedrooms']}间卧室'),
      if (specs['beds'] != null)
        pickLangText(lang, ko: '침대 ${specs['beds']}개', en: '${specs['beds']} bed(s)', ja: 'ベッド${specs['beds']}', zh: '${specs['beds']}张床'),
      if (specs['bathrooms'] != null)
        pickLangText(lang, ko: '욕실 ${specs['bathrooms']}개', en: '${specs['bathrooms']} bath(s)', ja: 'バスルーム${specs['bathrooms']}', zh: '${specs['bathrooms']}间卫浴'),
    ];
    return parts.join(' · ');
  }

  List<Map<String, String>> _resolveHighlights() {
    final raw = data['highlights'];
    final out = <Map<String, String>>[];
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        if (item is Map) {
          final t = (item['title'] ?? '').toString().trim();
          final sub = (item['subtitle'] ?? '').toString().trim();
          final iconKey = (item['icon_key'] ?? t).toString();
          if (t.isNotEmpty) {
            out.add({'icon_key': iconKey, 'title': t, 'subtitle': sub});
          }
        }
      }
    }
    if (out.isEmpty) {
      final pts = List<String>.from(data['summary_points'] ?? const []);
      for (final p in pts.take(3)) {
        out.add({'icon_key': p, 'title': p, 'subtitle': '호스트 소개 자료에서 확인된 숙소 주요 매력입니다.'});
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 940;
    final images = List<Map<String, dynamic>>.from(
      ((data['images'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final naverReviews = List<Map<String, dynamic>>.from(
      ((data['naver_reviews'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final promoTitle = (data['promo_title'] ?? '').toString().trim();
    final promoDetail = (data['promo_detail'] ?? '').toString().trim();
    final editorialStory = localizedListingStory(data, lang);
    final points = List<String>.from(data['summary_points'] ?? const []);
    final highlights = _resolveHighlights();
    final amenityGroups = resolveAmenityGroups(data);
    final topAmenities = extractTopAmenities(data, limit: 10);
    final totalAmenities = totalAmenityCount(data);
    final unavailable = extractUnavailableAmenities(data);
    final pricing = data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : <String, dynamic>{};
    final specs = data['room_specs'] is Map ? Map<String, dynamic>.from(data['room_specs'] as Map) : <String, dynamic>{};
    final houseRules =
        data['house_rules'] is Map ? Map<String, dynamic>.from(data['house_rules'] as Map) : <String, dynamic>{};
    final locationInfo =
        data['location_info'] is Map ? Map<String, dynamic>.from(data['location_info'] as Map) : <String, dynamic>{};
    final isForeignOnly = data['license_type'] == kForeignOnly;
    final blogUrl = (data['source_blog_url'] ?? '').toString().trim();
    final specsLine = _buildSpecsLine(lang);
    final regionLabel = _tStayRegion(listingId, data, lang);
    final accommType = _tAccommodationType((data['accommodation_type'] ?? '').toString(), lang);

    final bookingCard = _DirectBookingConversionCard(
      listingId: listingId,
      data: data,
      dateRange: dateRange,
      adults: adults,
      children: children,
      includePromo: includePromo,
      onPickDates: onPickDates,
      onGuestsChanged: onGuestsChanged,
      onIncludePromoChanged: onIncludePromoChanged,
    );

    final mainDetailsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 서브타이틀 & 객실 물리 스펙
        Text(
          [
            regionLabel,
            if (accommType.isNotEmpty) accommType,
          ].where((s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF222222)),
        ),
        if (specsLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(specsLine, style: const TextStyle(fontSize: 14.5, color: Color(0xFF555555))),
        ],
        if ((specs['bed_summary'] ?? '').toString().isNotEmpty || (specs['floor_info'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            [specs['bed_summary'], specs['floor_info']]
                .where((e) => e != null && e.toString().trim().isNotEmpty)
                .join(' · '),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 18),

        // 2. 에어비앤비 '게스트 선호' 스타일 합법 인증 & 수수료 0원 배지 바
        _VerifiedTrustBar(data: data, isForeignOnly: isForeignOnly),
        const SizedBox(height: 24),

        // 3. 호스트 직거래 전용 프로모션 배너 (있는 경우)
        if (promoTitle.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFF0F3), Color(0xFFFFF8F6)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFCCD5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.card_giftcard_rounded, color: kBrand, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickLangText(
                          lang,
                          ko: '호스트 직거래 신청 이벤트 · $promoTitle',
                          en: 'Host Direct Booking Promo · $promoTitle',
                          ja: 'ホスト直接予約特典 · $promoTitle',
                          zh: '房东直订专享优惠 · $promoTitle',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF222222)),
                      ),
                      if (promoDetail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(promoDetail, style: const TextStyle(fontSize: 13.5, color: Color(0xFF495057), height: 1.4)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 4. 3대 핵심 하이라이트 블록
        if (highlights.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFEBEBEB)),
          const SizedBox(height: 22),
          ...highlights.map((h) {
                final th = _tHighlight(h, data, listingId, lang);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(highlightIconFor(h['icon_key'] ?? ''), size: 26, color: const Color(0xFF222222)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(th.title,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: Color(0xFF222222))),
                            if (th.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(th.subtitle, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
        ],

        // 5. 공간 이야기 & 매력 요약
        if (editorialStory.isNotEmpty || points.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFEBEBEB)),
          const SizedBox(height: 24),
          Text(
            pickLangText(lang, ko: '숙소 소개', en: 'About this stay', ja: '宿泊施設のご案内', zh: '住宿介绍'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (editorialStory.isNotEmpty)
            Text(
              editorialStory,
              style: const TextStyle(fontSize: 15, height: 1.75, color: Color(0xFF2B2E33)),
            ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: points
                    .map((p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('✓ ', style: TextStyle(color: kBrand, fontWeight: FontWeight.bold)),
                              Expanded(child: Text(p, style: const TextStyle(fontSize: 14, height: 1.45))),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (blogUrl.startsWith('http')) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openExternal(blogUrl),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: Text(pickLangText(
                lang,
                ko: '호스트 원문 소개글 보기',
                en: 'Read Original Host Post',
                ja: 'ホストの元記事を見る',
                zh: '查看房东原文介绍',
              )),
            ),
          ],
          const SizedBox(height: 24),
        ],

        // 5-A. 사용자 직접 참여 별점(1~5점) · 이용 후기 섹션
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        UserReviewsSection(
          listingId: listingId,
          data: data,
          lang: lang,
          isOfflineDemo: isOfflineDemo,
          onReviewSubmitted: onReviewAdded,
        ),
        const SizedBox(height: 24),

        // 5-B. 네이버 블로그 검색 보완 후기 섹션 (무단 복제 없이 공식 검색 요약·원문 링크만 연결)
        if (naverReviews.isNotEmpty || (data['naver_search_url'] ?? '').toString().startsWith('http')) ...[
          const Divider(height: 1, color: Color(0xFFEBEBEB)),
          const SizedBox(height: 24),
          _NaverReviewsSection(
            data: data,
            reviews: naverReviews,
            lang: lang,
            onOpenExternal: _openExternal,
          ),
          const SizedBox(height: 24),
        ],

        // 모바일일 때는 예약·신청 위젯을 편의시설 바로 위에 한 번 배치해 전환 접근성을 높인다.
        if (!isDesktop) ...[
          bookingCard,
          const SizedBox(height: 28),
        ],

        // 6. 숙소 편의시설 (Amenity 핵심 섹션)
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '숙소 편의시설', en: 'Amenities', ja: '設備・アメニティ', zh: '住宿设施与服务'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          pickLangText(
            lang,
            ko: '호스트가 제공하는 필수 편의시설과 미제공 시설을 사전에 투명하게 확인하세요.',
            en: 'Check included and unavailable amenities provided by the host in advance.',
            ja: 'ホストが提供する設備・非対応設備を事前にご確認いただけます。',
            zh: '提前透明了解房东提供及未提供的设施与服务。',
          ),
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        if (topAmenities.isEmpty)
          Text(pickLangText(
            lang,
            ko: '등록된 편의시설 상세 정보가 없습니다. 호스트 예약 창구에서 확인해 주세요.',
            en: 'Detailed amenity info is not listed. Please check on the host booking page.',
            ja: '設備詳細情報が登録されていません。ホストの予約窓口でご確認ください。',
            zh: '暂无详细设施信息，请在房东预订页面确认。',
          ))
        else
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: topAmenities
                .map((item) => SizedBox(
                      width: isDesktop ? 290 : (math.max(240, (width - 56) / 2)),
                      child: Row(
                        children: [
                          Icon(amenityIconFor(item), size: 22, color: const Color(0xFF222222)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(item, style: const TextStyle(fontSize: 14.5, color: Color(0xFF222222))),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: unavailable
                .take(2)
                .map((u) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.not_interested_rounded, size: 18, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Text(
                          u,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.grey.shade600,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ))
                .toList(),
          ),
        ],
        if (totalAmenities > 0 || unavailable.isNotEmpty) ...[
          const SizedBox(height: 18),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF222222),
              side: const BorderSide(color: Color(0xFF222222), width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _showAllAmenitiesDialog(context, amenityGroups, unavailable, totalAmenities),
            child: Text(
              pickLangText(
                lang,
                ko: '편의시설 $totalAmenities개 모두 보기',
                en: 'Show all $totalAmenities amenities',
                ja: '設備・アメニティ $totalAmenities件をすべて見る',
                zh: '查看全部 $totalAmenities 项设施',
              ),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
          ),
        ],
        const SizedBox(height: 28),

        // 7. 직거래 요금 안내 테이블
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '직거래 기준 요금 안내', en: 'Direct Booking Base Rates', ja: '直接予約 基準料金のご案内', zh: '直订参考房价'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _PricingTableCard(pricing: pricing),
        const SizedBox(height: 28),

        // 8. 숙소 이용규칙 및 체크인 안내
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '알아두어야 할 사항 (숙소 이용규칙)', en: 'Things to Know (House Rules)', ja: 'ご案内事項（ハウスルール）', zh: '入住须知（房屋守则）'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _HouseRulesSection(houseRules: houseRules, isForeignOnly: isForeignOnly),
        const SizedBox(height: 28),

        // 9. 위치 및 주변 안내
        const Divider(height: 1, color: Color(0xFFEBEBEB)),
        const SizedBox(height: 24),
        Text(
          pickLangText(lang, ko: '위치 및 주변 정보', en: 'Location & Nearby', ja: '所在地・周辺案内', zh: '位置与周边信息'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _LocationSection(data: data, locationInfo: locationInfo, listingId: listingId),

        // 9-2. 한국관광공사(locationBasedList2) 반경 5km 공식 주변 명소·맛집
        if ((data['nearby_places'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 24),
          _TourNearbyPlacesSection(
            places: (data['nearby_places'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
            lang: lang,
            onOpenExternal: _openExternal,
          ),
        ],
      ],
    );

    final rating = extractListingRating(data);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 숙소 타이틀 헤더
          if (promoTitle.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFCCD5)),
              ),
              child: Text('🎁 $promoTitle',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBrand)),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _tStayTitle(listingId, data, lang),
                style: TextStyle(fontSize: isDesktop ? 26 : 21, fontWeight: FontWeight.w800, color: const Color(0xFF222222)),
              ),
              if (rating.count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 17, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 3),
                      Text(
                        '${rating.average.toStringAsFixed(1)} (${rating.count})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 에어비앤비 스타일 5분할 벤토 포토 그리드(외부 이미지 URL 링크) 또는 공공숙소 비주얼 히어로
          if (images.isNotEmpty) ...[
            _BentoGallery(images: images, title: _tStayTitle(listingId, data, lang)),
            const SizedBox(height: 28),
          ] else ...[
            _PublicStayVisualHero(data: data, onOpenExternal: _openExternal),
            const SizedBox(height: 28),
          ],

          // 데스크톱 2단 레이아웃 vs 모바일 단일 컬럼
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: mainDetailsColumn),
                const SizedBox(width: 48),
                SizedBox(width: 372, child: bookingCard),
              ],
            )
          else
            mainDetailsColumn,
        ],
      ),
    );
  }
}

class _VerifiedTrustBar extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isForeignOnly;

  const _VerifiedTrustBar({required this.data, required this.isForeignOnly});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final rawUrl = (data['direct_booking_url'] ?? data['naver_map_url'] ?? '').toString();
    final channel = bookingChannelName(rawUrl, lang: lang);
    final publicTier = isPublicUnclaimed(data);
    final licenseLabel = _tLicenseType((data['license_type'] ?? '').toString(), lang);
    final licenseNum = (data['license_number'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDDDDD)),
          ),
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    publicTier ? Icons.assured_workload_rounded : Icons.verified_rounded,
                    color: const Color(0xFF198754),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        publicTier
                            ? pickLangText(
                                lang,
                                ko: '행정안전부 공공데이터 영업확인 업소',
                                en: 'Verified Public Lodging Data (MOIS)',
                                ja: '韓国行政安全部 公共データ営業確認済み',
                                zh: '韩国行政安全部公共数据营业核验住宿',
                              )
                            : pickLangText(
                                lang,
                                ko: '지자체 영업신고 확인 완료',
                                en: 'Municipal Business Registration Verified',
                                ja: '自治体 営業届出確認済み',
                                zh: '地方政府营业备案已核验',
                              ),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        licenseNum.isNotEmpty ? '$licenseLabel · $licenseNum' : licenseLabel,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.savings_outlined, color: kBrand, size: 24),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickLangText(
                          lang,
                          ko: '게스트 중개수수료 0원',
                          en: '0% Guest Service Fee',
                          ja: 'ゲスト仲介手数料 0ウォン',
                          zh: '旅客平台服务费 0韩元',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      Text(
                        pickLangText(
                          lang,
                          ko: '연결 창구: $channel',
                          en: 'Channel: $channel',
                          ja: '予約窓口: $channel',
                          zh: '预订渠道: $channel',
                        ),
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isForeignOnly) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFF664D03)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pickLangText(
                      lang,
                      ko: '외국인 전용 숙소 (외국인관광도시민박업 · 내국인 투숙 불가)',
                      en: 'Foreign Visitors Only (Licensed Urban Homestay · Domestic Korean guests not eligible)',
                      ja: '外国人専用宿泊施設（外国人観光都市民泊業・韓国国内居住者は宿泊不可）',
                      zh: '仅限外籍旅客入住（外国人观光城市民宿 · 韩国本国居民不可入住）',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 우측 고정형 직거래 예약·문의 신청 전환 카드 (Airbnb Sticky Reservation Widget 참조)
class _DirectBookingConversionCard extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final DateTimeRange? dateRange;
  final int adults;
  final int children;
  final bool includePromo;
  final VoidCallback onPickDates;
  final void Function(int adults, int children) onGuestsChanged;
  final ValueChanged<bool> onIncludePromoChanged;

  const _DirectBookingConversionCard({
    required this.listingId,
    required this.data,
    required this.dateRange,
    required this.adults,
    required this.children,
    required this.includePromo,
    required this.onPickDates,
    required this.onGuestsChanged,
    required this.onIncludePromoChanged,
  });

  void _showGuestPicker(BuildContext context, int maxGuests) {
    final lang = appLangNotifier.value;
    int tempAdults = adults;
    int tempChildren = children;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final total = tempAdults + tempChildren;
          return AlertDialog(
            title: Text(
              pickLangText(
                lang,
                ko: '인원 선택 (최대 $maxGuests명)',
                en: 'Select Guests (Max $maxGuests)',
                ja: '人数選択（最大$maxGuests名）',
                zh: '选择人数（最多$maxGuests人）',
              ),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GuestStepperRow(
                  label: pickLangText(lang, ko: '성인', en: 'Adults', ja: '大人', zh: '成人'),
                  subtitle: pickLangText(lang, ko: '만 13세 이상', en: 'Ages 13 or above', ja: '13歳以上', zh: '13岁及以上'),
                  value: tempAdults,
                  canDec: tempAdults > 1,
                  canInc: total < maxGuests,
                  onChanged: (v) => setModalState(() => tempAdults = v),
                ),
                const Divider(),
                _GuestStepperRow(
                  label: pickLangText(lang, ko: '어린이', en: 'Children', ja: '子供', zh: '儿童'),
                  subtitle: pickLangText(lang, ko: '만 2~12세', en: 'Ages 2–12', ja: '2〜12歳', zh: '2–12岁'),
                  value: tempChildren,
                  canDec: tempChildren > 0,
                  canInc: total < maxGuests,
                  onChanged: (v) => setModalState(() => tempChildren = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(pickLangText(lang, ko: '취소', en: 'Cancel', ja: 'キャンセル', zh: '取消')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kBrand),
                onPressed: () {
                  onGuestsChanged(tempAdults, tempChildren);
                  Navigator.pop(ctx);
                },
                child: Text(pickLangText(lang, ko: '적용', en: 'Apply', ja: '適用', zh: '应用')),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final pricing = data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : null;
    final est = calculateStayEstimate(pricing, dateRange: dateRange);
    final rawUrl = (data['direct_booking_url'] ?? '').toString();
    final channel = bookingChannelName(rawUrl, lang: lang);
    final promoTitle = (data['promo_title'] ?? '').toString().trim();
    final maxGuests = (data['capacity_max'] as num?)?.toInt() ?? 10;
    final totalGuests = adults + children;
    final guestSummary = lang == AppLang.ko
        ? '게스트 $totalGuests명 (성인 $adults${children > 0 ? ', 어린이 $children' : ''})'
        : pickLangText(
            lang,
            ko: '',
            en: '$totalGuests guest${totalGuests > 1 ? 's' : ''} ($adults adult${adults > 1 ? 's' : ''}${children > 0 ? ', $children child' : ''})',
            ja: 'ゲスト$totalGuests名（大人$adults${children > 0 ? '・子供$children' : ''}）',
            zh: '$totalGuests位房客（成人$adults${children > 0 ? '，儿童$children' : ''}）',
          );
    final selectDateLabel = pickLangText(lang, ko: '날짜 선택', en: 'Select date', ja: '日付を選択', zh: '选择日期');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDDDDD)),
        boxShadow: const [
          BoxShadow(color: Color(0x18000000), blurRadius: 20, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 수수료 절감 배지 (Airbnb '60일 평균보다 낮음' 전환 배지 벤치마킹)
          if (est.estimatedFeeSaved != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded, size: 16, color: kBrand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pickLangText(
                        lang,
                        ko: '일반 숙박앱 대비 수수료 약 ${formatWon(est.estimatedFeeSaved!)} 절약',
                        en: 'Save approx. ${formatWon(est.estimatedFeeSaved!)} in OTA fees',
                        ja: '一般予約サイト比で手数料 約${formatWon(est.estimatedFeeSaved!)}お得',
                        zh: '相比常规平台可省约 ${formatWon(est.estimatedFeeSaved!)} 服务费',
                      ),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kBrand),
                    ),
                  ),
                ],
              ),
            ),

          // 대표 예상 요금
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                est.estimatedAmount != null ? formatWon(est.estimatedAmount!) : shortPrice(pricing, lang: lang),
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  est.estimatedAmount != null ? '· ${est.unitLabel}' : '',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 에어비앤비 스타일 2단 일정·인원 선택 박스
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB0B0B0)),
            ),
            child: Column(
              children: [
                InkWell(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  onTap: onPickDates,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickLangText(lang, ko: '체크인', en: 'CHECK-IN', ja: 'チェックイン', zh: '入住'),
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateRange != null ? _fmtDate(dateRange!.start) : selectDateLabel,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, height: 44, color: const Color(0xFFB0B0B0)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickLangText(lang, ko: '체크아웃', en: 'CHECK-OUT', ja: 'チェックアウト', zh: '退房'),
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateRange != null ? _fmtDate(dateRange!.end) : selectDateLabel,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFB0B0B0)),
                InkWell(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  onTap: () => _showGuestPicker(context, maxGuests),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pickLangText(lang, ko: '인원', en: 'GUESTS', ja: '人数', zh: '人数'),
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(guestSummary, style: const TextStyle(fontSize: 13.5)),
                          ],
                        ),
                        const Icon(Icons.keyboard_arrow_down_rounded),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 직거래 혜택 자동 포함 체크박스
          if (promoTitle.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onIncludePromoChanged(!includePromo),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE9ECEF)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: includePromo,
                        activeColor: kBrand,
                        onChanged: (v) => onIncludePromoChanged(v ?? true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickLangText(
                          lang,
                          ko: '문의 시 [$promoTitle] 함께 신청',
                          en: 'Include [$promoTitle] in inquiry',
                          ja: 'お問い合わせ時に[$promoTitle]も申請',
                          zh: '咨询时一并申请[$promoTitle]',
                        ),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 풀와이드 마젠타/코랄 메인 신청 CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kBrand,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => goDirectBooking(
                context,
                listingId,
                data,
                dateRange: dateRange,
                adults: adults,
                children: children,
                includePromo: includePromo,
              ),
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: Text(
                bookingCtaLabel(rawUrl, data: data, lang: lang),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              pickLangText(
                lang,
                ko: '예약 확정 전에는 요금이 청구되지 않습니다.',
                en: 'You won\'t be charged before confirmation.',
                ja: '予約確定前に料金が請求されることはありません。',
                zh: '在预订确认前不会向您收取费用。',
              ),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF555555)),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              pickLangText(
                lang,
                ko: '선택한 일정·인원이 자동 복사되어 $channel 창구로 연결됩니다.',
                en: 'Selected dates & guests are copied and linked to $channel.',
                ja: '選択した日程・人数が自動コピーされ、$channel窓口へ接続されます。',
                zh: '所选日期与人数将自动复制并跳转至$channel。',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                pickLangText(lang, ko: '직스테이 중개수수료', en: 'Jikstay Service Fee', ja: 'ジクステイ仲介手数料', zh: 'Jikstay 平台服务费'),
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF495057)),
              ),
              Text(
                pickLangText(lang, ko: '0원 (무료 직결)', en: '₩0 (Direct Free)', ja: '0ウォン（無料直結）', zh: '0韩元（免费直连）'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF198754)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuestStepperRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final int value;
  final bool canDec;
  final bool canInc;
  final ValueChanged<int> onChanged;

  const _GuestStepperRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.canDec,
    required this.canInc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          Row(
            children: [
              IconButton.outlined(
                visualDensity: VisualDensity.compact,
                onPressed: canDec ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove, size: 16),
              ),
              SizedBox(
                width: 34,
                child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton.outlined(
                visualDensity: VisualDensity.compact,
                onPressed: canInc ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileStickyBookingBar extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final DateTimeRange? dateRange;
  final int adults;
  final int children;
  final bool includePromo;
  final VoidCallback onPickDates;

  const _MobileStickyBookingBar({
    required this.listingId,
    required this.data,
    required this.dateRange,
    required this.adults,
    required this.children,
    required this.includePromo,
    required this.onPickDates,
  });

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final pricing = data['pricing'] is Map ? Map<String, dynamic>.from(data['pricing'] as Map) : null;
    final est = calculateStayEstimate(pricing, dateRange: dateRange);
    final rawUrl = (data['direct_booking_url'] ?? '').toString();
    final channel = bookingChannelName(rawUrl, lang: lang);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3E5E8))),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onPickDates,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      est.estimatedAmount != null ? formatWon(est.estimatedAmount!) : shortPrice(pricing, lang: lang),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF222222)),
                    ),
                    Text(
                      dateRange != null
                          ? pickLangText(
                              lang,
                              ko: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 수수료 0원',
                              en: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 0% Fee',
                              ja: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 手数料0ウォン',
                              zh: '${_fmtDate(dateRange!.start)} ~ ${_fmtDate(dateRange!.end)} · 0服务费',
                            )
                          : pickLangText(
                              lang,
                              ko: '중개수수료 0원 · $channel',
                              en: '0% Fee · $channel',
                              ja: '仲介手数料0ウォン · $channel',
                              zh: '0平台费 · $channel',
                            ),
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kBrand,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => goDirectBooking(
                  context,
                  listingId,
                  data,
                  dateRange: dateRange,
                  adults: adults,
                  children: children,
                  includePromo: includePromo,
                ),
                child: Text(
                  bookingCtaLabel(rawUrl, data: data, lang: appLangNotifier.value),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingTableCard extends StatelessWidget {
  final Map<String, dynamic> pricing;

  const _PricingTableCard({required this.pricing});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final rows = <(String, num)>[
      if (pricing['nightly_min'] is num)
        (pickLangText(lang, ko: '1박 (최저 기준)', en: '1 night (from)', ja: '1泊（最低基準）', zh: '每晚（最低参考）'), pricing['nightly_min'] as num),
      if (pricing['weekly_price'] is num)
        (pickLangText(lang, ko: '일주일 (6~7박 연박)', en: '1 week (6–7 nights)', ja: '1週間（6〜7泊）', zh: '一周（6~7晚连住）'), pricing['weekly_price'] as num),
      if (pricing['monthly_price'] is num)
        (pickLangText(lang, ko: '한달살기 (28박 이상)', en: 'Monthly (28+ nights)', ja: '1ヶ月（28泊以上）', zh: '月租（28晚以上）'), pricing['monthly_price'] as num),
    ];
    final note = (pricing['price_note'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Text(
              pickLangText(
                lang,
                ko: '호스트 예약 창구에서 일정별 정확한 직거래 요금을 확인하세요.',
                en: 'Check exact direct rates for your dates on the host booking page.',
                ja: 'ホストの予約窓口で日程別の正確な直接料金をご確認ください。',
                zh: '请在房东预订渠道查询具体日期的直订房价。',
              ),
              style: const TextStyle(fontSize: 14),
            )
          else
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r.$1, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                      Text(formatWon(r.$2), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                )),
          if (note.isNotEmpty) ...[
            const Divider(height: 18),
            Text('· $note', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 8),
          Text(
            pickLangText(
              lang,
              ko: '· 일반 숙박 플랫폼의 게스트 서비스 수수료(약 14~16%) 없이 호스트에게 직접 예약합니다.',
              en: '· Book directly with the host without typical OTA guest service fees (~14–16%).',
              ja: '· 一般的な宿泊サイトのゲスト手数料（約14〜16%）なしでホストへ直接予約します。',
              zh: '· 无需支付常规订房平台约14~16%的旅客服务费，直接联系房东预订。',
            ),
            style: const TextStyle(fontSize: 12.5, color: kBrand, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _HouseRulesSection extends StatelessWidget {
  final Map<String, dynamic> houseRules;
  final bool isForeignOnly;

  const _HouseRulesSection({required this.houseRules, required this.isForeignOnly});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final checkIn = (houseRules['check_in_time'] ?? '').toString().trim();
    final checkOut = (houseRules['check_out_time'] ?? '').toString().trim();
    final selfCheckIn = (houseRules['self_check_in'] ?? '').toString().trim();
    final quietHours = (houseRules['quiet_hours'] ?? '').toString().trim();
    final smoking = (houseRules['smoking_policy'] ?? '').toString().trim();
    final pets = (houseRules['pet_policy'] ?? '').toString().trim();
    final extras = List<String>.from(houseRules['extra_rules'] ?? const []);

    final items = <(IconData, String, String)>[
      if (checkIn.isNotEmpty) (Icons.login_rounded, pickLangText(lang, ko: '체크인', en: 'Check-in', ja: 'チェックイン', zh: '入住'), checkIn),
      if (checkOut.isNotEmpty) (Icons.logout_rounded, pickLangText(lang, ko: '체크아웃', en: 'Check-out', ja: 'チェックアウト', zh: '退房'), checkOut),
      if (selfCheckIn.isNotEmpty) (Icons.dialpad_rounded, pickLangText(lang, ko: '체크인 방식', en: 'Check-in Method', ja: 'チェックイン方法', zh: '入住方式'), selfCheckIn),
      if (quietHours.isNotEmpty) (Icons.nightlight_outlined, pickLangText(lang, ko: '매너타임', en: 'Quiet Hours', ja: 'クワイエットアワー', zh: '安静时段'), quietHours),
      if (smoking.isNotEmpty) (Icons.smoke_free_rounded, pickLangText(lang, ko: '금연 안내', en: 'Smoking Policy', ja: '喫煙ポリシー', zh: '禁烟规定'), smoking),
      if (pets.isNotEmpty) (Icons.pets_outlined, pickLangText(lang, ko: '반려동물', en: 'Pets', ja: 'ペット', zh: '宠物政策'), pets),
    ];

    if (items.isEmpty && extras.isEmpty && !isForeignOnly) {
      return Text(
        pickLangText(
          lang,
          ko: '상세 체크인·체크아웃 시간 및 환불 규정은 호스트 직거래 예약 창구에서 확인해 주세요.',
          en: 'Please confirm exact check-in/out times and cancellation rules on the host booking page.',
          ja: 'チェックイン・アウト時間やキャンセル規定の詳細はホストの予約窓口でご確認ください。',
          zh: '具体入住/退房时间及退改规则请在房东直订页面确认。',
        ),
        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isNotEmpty)
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: items
                .map((it) => Container(
                      width: 310,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE9ECEF)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(it.$1, size: 20, color: const Color(0xFF222222)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(it.$3, style: const TextStyle(fontSize: 13.5, color: Color(0xFF343A40))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...extras.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF6C757D)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 13.5, height: 1.45))),
                  ],
                ),
              )),
        ],
      ],
    );
  }
}

class _LocationSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic> locationInfo;
  final String listingId;

  const _LocationSection({required this.data, required this.locationInfo, this.listingId = ''});

  @override
  Widget build(BuildContext context) {
    final lang = appLangNotifier.value;
    final addr = (locationInfo['display_address'] ?? '').toString().trim();
    final fallbackAddr = _tStayRegion(listingId, data, lang);
    final displayAddr = lang == AppLang.ko
        ? (addr.isNotEmpty ? addr : fallbackAddr)
        : (fallbackAddr.isNotEmpty ? fallbackAddr : addr);
    final nearby = (locationInfo['nearby_spots'] ?? '').toString().trim();
    final parking = (locationInfo['parking_note'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: kBrand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(displayAddr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (nearby.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('· 주변 환경: $nearby', style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ],
          if (parking.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('· 주차 안내: $parking', style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final q = Uri.encodeComponent(displayAddr.isNotEmpty ? displayAddr : '${data['title'] ?? ''}');
                  final uri = Uri.parse('https://map.naver.com/p/search/$q');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.map_outlined, size: 17, color: Color(0xFF03C75A)),
                label: Text(pickLangText(
                  lang,
                  ko: '네이버 지도에서 주변 위치 보기',
                  en: 'View Location on Naver Map',
                  ja: 'Naverマップで周辺を見る',
                  zh: '在 Naver 地图查看位置',
                )),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final lat = (data['lat'] as num?)?.toDouble() ?? (locationInfo['lat'] as num?)?.toDouble();
                  final lng = (data['lng'] as num?)?.toDouble() ?? (locationInfo['lng'] as num?)?.toDouble();
                  final titleEnc = Uri.encodeComponent((data['title'] ?? displayAddr).toString());
                  final url = (lat != null && lng != null)
                      ? 'https://map.kakao.com/link/to/$titleEnc,${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
                      : 'https://map.kakao.com/?q=${Uri.encodeComponent(displayAddr)}';
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.directions_bus_filled_rounded, size: 17, color: Color(0xFFD97706)),
                label: const Text('카카오 대중교통 · 내비 길찾기'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final lat = (data['lat'] as num?)?.toDouble() ?? (locationInfo['lat'] as num?)?.toDouble();
                  final lng = (data['lng'] as num?)?.toDouble() ?? (locationInfo['lng'] as num?)?.toDouble();
                  final dest = (lat != null && lng != null)
                      ? '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
                      : Uri.encodeComponent(displayAddr);
                  final url = 'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=transit';
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.train_rounded, size: 17, color: Color(0xFF2563EB)),
                label: const Text('Google 대중교통 경로'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 편의시설 전체 보기 모달 (카테고리별 그룹 + 하단 취소선 미제공 시설)
void _showAllAmenitiesDialog(
  BuildContext context,
  List<AmenityCategoryGroup> groups,
  List<String> unavailable,
  int totalCount,
) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('숙소 편의시설 ($totalCount개)',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  ...groups.map((g) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.category, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            ...g.items.map((item) => Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Row(
                                        children: [
                                          Icon(amenityIconFor(item), size: 22, color: const Color(0xFF222222)),
                                          const SizedBox(width: 14),
                                          Expanded(child: Text(item, style: const TextStyle(fontSize: 14.5))),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1, color: Color(0xFFF1F3F5)),
                                  ],
                                )),
                          ],
                        ),
                      )),
                  if (unavailable.isNotEmpty) ...[
                    const Text('숙소에 없는 시설 · 제한 사항',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ...unavailable.map((item) => Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Icon(Icons.not_interested_rounded, size: 20, color: Colors.grey.shade500),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        color: Colors.grey.shade600,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F3F5)),
                          ],
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 에어비앤비 스타일 데스크톱 5분할 벤토 그리드 + 모바일 스와이프 갤러리 + 공간별 포토 투어 모달
class _BentoGallery extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final String title;

  const _BentoGallery({required this.images, required this.title});

  @override
  State<_BentoGallery> createState() => _BentoGalleryState();
}

class _BentoGalleryState extends State<_BentoGallery> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openTour(BuildContext context, {String? initialTag}) {
    final tags = <String>{'전체'};
    for (final im in widget.images) {
      final t = (im['space_tag'] ?? '').toString().trim();
      if (t.isNotEmpty) tags.add(t);
    }
    String selectedTag = initialTag ?? '전체';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filtered = selectedTag == '전체'
              ? widget.images
              : widget.images.where((im) => (im['space_tag'] ?? '').toString() == selectedTag).toList();
          return Dialog.fullscreen(
            backgroundColor: Colors.white,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pickLangText(
                              appLangNotifier.value,
                              ko: '사진 투어 · ${widget.title}',
                              en: 'Photo Tour · ${widget.title}',
                              ja: '写真ツアー · ${widget.title}',
                              zh: '照片导览 · ${widget.title}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tags.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: tags
                            .map((t) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(t),
                                    selected: selectedTag == t,
                                    onSelected: (_) => setModalState(() => selectedTag = t),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 24),
                      itemBuilder: (_, i) {
                        final im = filtered[i];
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 540),
                                    child: StorageImage(
                                      path: im['path']?.toString(),
                                      url: im['url']?.toString(),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorIconSize: 40,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  [
                                    if ((im['space_tag'] ?? '').toString().isNotEmpty) '[${im['space_tag']}]',
                                    if ((im['caption'] ?? '').toString().isNotEmpty) im['caption'].toString(),
                                  ].join(' '),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
            ),
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> im) {
    return InkWell(
      onTap: () => _openTour(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          StorageImage(
            path: im['path']?.toString(),
            url: im['url']?.toString(),
            fit: BoxFit.cover,
            width: double.infinity,
            errorIconSize: 36,
          ),
          if ((im['space_tag'] ?? '').toString().isNotEmpty)
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  im['space_tag'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;
    final imgs = widget.images;

    if (isWide && imgs.length >= 3) {
      final sub = imgs.skip(1).take(4).toList();
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 400,
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(flex: 5, child: _tile(context, imgs.first)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: sub.length >= 4
                        ? Column(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(child: _tile(context, sub[0])),
                                    const SizedBox(width: 8),
                                    Expanded(child: _tile(context, sub[1])),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(child: _tile(context, sub[2])),
                                    const SizedBox(width: 8),
                                    Expanded(child: _tile(context, sub[3])),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              for (int i = 0; i < sub.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                Expanded(child: _tile(context, sub[i])),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF222222),
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF222222)),
                    ),
                  ),
                  onPressed: () => _openTour(context),
                  icon: const Icon(Icons.grid_view_rounded, size: 17),
                  label: Text(
                    pickLangText(
                      appLangNotifier.value,
                      ko: '사진 모두 보기 (${imgs.length}장)',
                      en: 'Show all photos (${imgs.length})',
                      ja: '写真をすべて見る (${imgs.length}枚)',
                      zh: '查看全部照片 (${imgs.length}张)',
                    ),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final current = imgs[_page];
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 300,
        child: Stack(
          children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: imgs.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _openTour(context),
                child: StorageImage(
                  path: imgs[i]['path']?.toString(),
                  url: imgs[i]['url']?.toString(),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorIconSize: 40,
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                child: Text(
                  '${current['space_tag'] ?? ''} ${current['caption'] ?? ''} (${_page + 1}/${imgs.length})'.trim(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.tonalIcon(
                onPressed: () => _openTour(context),
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: Text(
                  pickLangText(appLangNotifier.value, ko: '사진 투어', en: 'Photo Tour', ja: '写真ツアー', zh: '照片导览'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 외부 공식 이미지 URL(Image.network) 전용 경량 이미지 위젯 (Storage 업로드 폐지에 맞춰 슬림화)
class StorageImage extends StatelessWidget {
  final String? path;
  final String? url;
  final BoxFit fit;
  final double? width;
  final int? cacheWidth;
  final double errorIconSize;

  const StorageImage({
    super.key,
    this.path,
    this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.cacheWidth,
    this.errorIconSize = 24,
  });

  Widget _broken() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1F4F8), Color(0xFFE6ECF5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.villa_outlined, size: errorIconSize + 8, color: const Color(0xFF6C7A89)),
              const SizedBox(height: 4),
              const Text('합법 등록 스테이', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF5A6877))),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return _broken();
    return Image.network(
      u,
      key: ValueKey(u),
      fit: fit,
      width: width,
      cacheWidth: cacheWidth,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, _, _) => _broken(),
    );
  }
}

/// 외부 사진 링크가 아직 없는 공공API 선별 숙소용 고신뢰 비주얼 배너
class _PublicStayVisualHero extends StatelessWidget {
  final Map<String, dynamic> data;
  final Future<void> Function(String url) onOpenExternal;

  const _PublicStayVisualHero({required this.data, required this.onOpenExternal});

  @override
  Widget build(BuildContext context) {
    final mapUrl = (data['naver_map_url'] ?? '').toString();
    final searchUrl = (data['naver_search_url'] ?? '').toString();
    final blogTotal = (data['naver_blog_total'] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F2937), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF34D399)),
                  ),
                  child: Text(
                    '✓ 행정안전부 인허가 영업확인 · ${data['license_type'] ?? '합법 숙소'}',
                    style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${data['region_depth1'] ?? ''} ${data['region_depth2'] ?? ''} 합법 등록 숙소',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  blogTotal > 0
                      ? '무단 이미지 복제 없이 공식 데이터와 네이버 방문 후기 $blogTotal건을 안전하게 연결합니다.'
                      : '공공 인허가 데이터를 기반으로 등록된 숙소입니다. 네이버 지도·플레이스에서 현장 사진과 예약처를 바로 확인하세요.',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (mapUrl.startsWith('http'))
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF03C75A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onPressed: () => onOpenExternal(mapUrl),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('네이버 지도·플레이스 사진 보기', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              if (searchUrl.startsWith('http'))
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onPressed: () => onOpenExternal(searchUrl),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('네이버 통합검색'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 네이버 블로그 검색 오픈 API 메타데이터 기반 후기·소개 아웃링크 섹션
class _NaverReviewsSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> reviews;
  final AppLang lang;
  final Future<void> Function(String url) onOpenExternal;

  const _NaverReviewsSection({
    required this.data,
    required this.reviews,
    required this.lang,
    required this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    final blogTotal = (data['naver_blog_total'] as num?)?.toInt() ?? reviews.length;
    final searchUrl = (data['naver_search_url'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF03C75A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('N 블로그', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                trUi('naver_reviews_title', lang),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            if (blogTotal > 0)
              Text('검색 $blogTotal건', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          trUi('naver_reviews_sub', lang),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        ...reviews.map((r) {
          final link = (r['link'] ?? '').toString();
          final blogger = (r['blogger_name'] ?? '').toString();
          final date = (r['postdate'] ?? '').toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: link.startsWith('http') ? () => onOpenExternal(link) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (r['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFF6B7280)),
                      ],
                    ),
                    if ((r['summary'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        (r['summary'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFF4B5563), height: 1.45),
                      ),
                    ],
                    if (blogger.isNotEmpty || date.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [if (blogger.isNotEmpty) '블로그: $blogger', if (date.isNotEmpty) date].join(' · '),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
        if (searchUrl.startsWith('http'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton.icon(
              onPressed: () => onOpenExternal(searchUrl),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('네이버에서 방문 후기·요금 정보 더 보기'),
            ),
          ),
      ],
    );
  }
}

/// 한국관광공사(KorService2/locationBasedList2) 반경 5km 주변 명소·맛집 추천 섹션
class _TourNearbyPlacesSection extends StatelessWidget {
  final List<Map<String, dynamic>> places;
  final AppLang lang;
  final Future<void> Function(String url) onOpenExternal;

  const _TourNearbyPlacesSection({
    required this.places,
    required this.lang,
    required this.onOpenExternal,
  });

  String _fmtDist(dynamic raw) {
    final m = (raw as num?)?.toInt() ?? 0;
    if (m <= 0) return '';
    if (m < 1000) return '${m}m';
    return '${(m / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trUi('nearby_spots_title', lang),
          style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: places.take(4).map((p) {
            final dist = _fmtDist(p['distance_m']);
            final mapUrl = (p['map_url'] ?? '').toString();
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: mapUrl.startsWith('http') ? () => onOpenExternal(mapUrl) : null,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 62,
                          height: 62,
                          child: StorageImage(
                            url: (p['image_url'] ?? '').toString(),
                            cacheWidth: 220,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                (p['category'] ?? '명소').toString(),
                                if (dist.isNotEmpty) dist,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F766E)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              (p['title'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              (p['addr'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// 사용자 참여형 별점(score 1~5) 및 후기(review) 작성·열람 섹션
class UserReviewsSection extends StatefulWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final AppLang lang;
  final bool isOfflineDemo;
  final ValueChanged<int>? onReviewSubmitted;

  const UserReviewsSection({
    super.key,
    required this.listingId,
    required this.data,
    required this.lang,
    this.isOfflineDemo = false,
    this.onReviewSubmitted,
  });

  @override
  State<UserReviewsSection> createState() => _UserReviewsSectionState();
}

class _UserReviewsSectionState extends State<UserReviewsSection> {
  static const List<String> _visitTags = ['커플·2인', '가족여행', '혼행·워케이션', '단기숙박', '한달살기'];

  final TextEditingController _nickCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();

  int _selectedScore = 5;
  String _selectedTag = '커플·2인';
  bool _submitting = false;
  bool _loadingRemote = false;
  final List<Map<String, dynamic>> _localPrepended = [];
  List<Map<String, dynamic>> _remoteReviews = const [];

  @override
  void initState() {
    super.initState();
    if (!widget.isOfflineDemo && !widget.listingId.startsWith('stay_demo_')) {
      _fetchRemoteReviews();
    }
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRemoteReviews() async {
    setState(() => _loadingRemote = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .collection('reviews')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();
      if (!mounted) return;
      setState(() {
        _remoteReviews = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      });
    } catch (_) {
      // 오프라인이나 초기 무후기 상태는 빈 목록으로 처리
    } finally {
      if (mounted) setState(() => _loadingRemote = false);
    }
  }

  String _scoreDescription(int s, AppLang lang) {
    if (lang != AppLang.ko) return '$s / 5';
    return switch (s) {
      5 => '5점 · 최고예요! 다시 찾고 싶어요',
      4 => '4점 · 만족스러운 숙소였어요',
      3 => '3점 · 무난하고 괜찮았어요',
      2 => '2점 · 조금 아쉬운 점이 있었어요',
      _ => '1점 · 개선이 필요해요',
    };
  }

  String _formatReviewDate(Map<String, dynamic> r) {
    final preset = (r['date_label'] ?? '').toString().trim();
    if (preset.isNotEmpty) return preset;
    final ts = r['created_at'];
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    if (ts is DateTime) dt = ts;
    if (dt == null) return '방금 전';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submitReview() async {
    final nick = _nickCtrl.text.trim();
    final body = _commentCtrl.text.trim();
    final err = validateUserReviewInput(nickname: nick, score: _selectedScore, comment: body);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_validation_err', widget.lang))),
      );
      return;
    }

    final scoreToSave = _selectedScore;
    final tagToSave = _selectedTag;
    final langCode = widget.lang.code;

    setState(() => _submitting = true);
    try {
      if (!widget.isOfflineDemo && !widget.listingId.startsWith('stay_demo_')) {
        final db = FirebaseFirestore.instance;
        final listingRef = db.collection('listings').doc(widget.listingId);
        final revRef = listingRef.collection('reviews').doc();
        final batch = db.batch();
        batch.set(revRef, <String, dynamic>{
          'listing_id': widget.listingId,
          'nickname': nick,
          'score': scoreToSave,
          'comment': body,
          if (tagToSave.isNotEmpty) 'visit_tag': tagToSave,
          'lang': langCode,
          'created_at': FieldValue.serverTimestamp(),
        });
        batch.update(listingRef, <String, dynamic>{
          'review_count': FieldValue.increment(1),
          'score_sum': FieldValue.increment(scoreToSave),
          'last_review_id': revRef.id,
        });
        await batch.commit();
      }

      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _localPrepended.insert(0, {
          'nickname': nick,
          'score': scoreToSave,
          'visit_tag': tagToSave,
          'comment': body,
          'lang': langCode,
          'created_at': now,
        });
        _commentCtrl.clear();
        _selectedScore = 5;
      });
      widget.onReviewSubmitted?.call(scoreToSave);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_submitted', widget.lang))),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('후기 등록 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rating = extractListingRating(widget.data);
    final demoItems = (widget.data['demo_reviews'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    final allReviews = <Map<String, dynamic>>[
      ..._localPrepended,
      ..._remoteReviews,
      if (_remoteReviews.isEmpty) ...demoItems,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 헤더 & 평균 별점 요약 카드
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_rounded, color: Color(0xFFF59E0B), size: 24),
                const SizedBox(width: 8),
                Text(
                  trUi('user_reviews_title', widget.lang),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
                ),
              ],
            ),
            if (rating.count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 19),
                    const SizedBox(width: 4),
                    Text(
                      '${rating.average.toStringAsFixed(1)} / 5.0',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF92400E)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${rating.count}건)',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          trUi('user_reviews_sub', widget.lang),
          style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),

        // 2. 대화형 별점(1~5) 및 후기 입력 카드
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trUi('write_review_title', widget.lang),
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF222222)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (int s = 1; s <= 5; s++)
                    InkWell(
                      key: Key('review_star_$s'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: _submitting ? null : () => setState(() => _selectedScore = s),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          s <= _selectedScore ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 32,
                          color: s <= _selectedScore ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _scoreDescription(_selectedScore, widget.lang),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.lang == AppLang.ko) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _visitTags.map((tag) {
                    final active = _selectedTag == tag;
                    return ChoiceChip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      selected: active,
                      visualDensity: VisualDensity.compact,
                      selectedColor: const Color(0xFFFFF0F3),
                      side: BorderSide(color: active ? kBrand : const Color(0xFFDDDDDD)),
                      labelStyle: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                        color: active ? kBrand : const Color(0xFF495057),
                      ),
                      showCheckmark: false,
                      onSelected: _submitting ? null : (_) => setState(() => _selectedTag = tag),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const Key('review_nickname_input'),
                      controller: _nickCtrl,
                      enabled: !_submitting,
                      maxLength: 24,
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        labelText: trUi('nickname_label', widget.lang),
                        hintText: trUi('nickname_hint', widget.lang),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('review_comment_input'),
                controller: _commentCtrl,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 600,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: trUi('comment_hint', widget.lang),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('review_submit_btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrand,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _submitting ? null : _submitReview,
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(
                    trUi('submit_review_btn', widget.lang),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. 등록된 후기 목록
        if (_loadingRemote && allReviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (allReviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEBEBEB)),
            ),
            child: Text(
              trUi('review_empty', widget.lang),
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
            ),
          )
        else
          ...allReviews.map((r) {
            final sc = ((r['score'] as num?)?.toInt() ?? 5).clamp(1, 5);
            final nick = (r['nickname'] ?? '여행자').toString();
            final tag = (r['visit_tag'] ?? '').toString().trim();
            final comment = (r['comment'] ?? '').toString();
            final initial = nick.isNotEmpty ? nick.characters.first.toUpperCase() : 'G';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFFFF0F3),
                        child: Text(
                          initial,
                          style: const TextStyle(color: kBrand, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(nick, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (tag.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(tag, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                              ),
                          ],
                        ),
                      ),
                      Text(_formatReviewDate(r), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (int i = 1; i <= 5; i++)
                        Icon(
                          i <= sc ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 16,
                          color: i <= sc ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                        ),
                      const SizedBox(width: 6),
                      Text('$sc.0', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(comment, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155))),
                ],
              ),
            );
          }),
      ],
    );
  }
}
