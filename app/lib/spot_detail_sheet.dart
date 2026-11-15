// 축제·볼거리·먹거리·지자체 E-book 매거진형 전체 상세 페이지 (팝업 제거 · StoryDetailPage 동일 포맷).
// 가독성(본문 폭 760px, 줄간격 1.88), 핵심 탐방·메뉴 정보 박스(《장수여행》 p.9 모델),
// 카카오 플레이스·네이버 플레이스·네이버 블로그 방문기 연동, 인라인 방문쿠폰, 주변 동선 연결을 통합한다.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'detail_page.dart' show ListingDetailPage, StorageImage, validateUserReviewInput;
import 'discovery_models.dart';
import 'hub_details.dart';
import 'i18n.dart';
import 'naver_place_info.dart';
import 'review_auth.dart';
import 'translation_store.dart';
import 'web_utils.dart';

typedef SpotDetailPage = SpotDetailSheet;

Future<void> recordOutboundVisitClick(DiscoveryItem item, {bool offlineMode = false}) async {
  if (offlineMode || item.category == DiscoveryCategory.ebook) return;
  final colName = item.category == DiscoveryCategory.stay ? 'listings' : 'spots';
  try {
    await FirebaseFirestore.instance
        .collection(colName)
        .doc(item.id)
        .update({'outbound_clicks': FieldValue.increment(1)})
        .timeout(const Duration(seconds: 2));
  } catch (_) {}
}

class SpotDetailSheet extends StatefulWidget {
  final DiscoveryItem item;
  final List<DiscoveryItem> allItems;
  final AppLang lang;
  final bool offlineMode;
  final ValueChanged<DiscoveryItem> onSelectConnectedItem;
  final ValueChanged<String>? onOpenFullStayPage;
  final ValueChanged<String>? onOpenStoryPage;
  final WidgetBuilder? homeBuilder;
  final void Function(String itemId, int reviewCount, int scoreSum)? onStatsUpdated;

  const SpotDetailSheet({
    super.key,
    required this.item,
    required this.allItems,
    required this.lang,
    required this.onSelectConnectedItem,
    this.offlineMode = false,
    this.onOpenFullStayPage,
    this.onOpenStoryPage,
    this.homeBuilder,
    this.onStatsUpdated,
  });

  @override
  State<SpotDetailSheet> createState() => _SpotDetailSheetState();
}

class _SpotDetailSheetState extends State<SpotDetailSheet> {
  late DiscoveryItem _current;
  int _heroIndex = 0;
  bool _couponExpanded = false;
  int _selectedScore = 5;
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _nickCtrl = TextEditingController();
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submittingReview = false;
  List<Map<String, dynamic>> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _current = widget.item;
    _onEnterSpot(_current);
  }

  @override
  void didUpdateWidget(covariant SpotDetailSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _switchSpot(widget.item, scrollToTop: true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _nickCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _onEnterSpot(DiscoveryItem sp) {
    syncPortalParams(
      region: sp.province,
      spotId: sp.category == DiscoveryCategory.stay ? null : sp.id,
    );
    trackPortalEvent('view_spot_page', {
      'item_id': sp.id,
      'category': sp.category.name,
      'province': sp.province,
      'title': sp.title,
    });
    _loadReviews();
    _hydrateDetails(sp);
  }

  /// 첫 화면에서 빠진 상세 필드(본문·방문기·탐방정보·갤러리)를 시·도별 상세 파일에서 채운다.
  Future<void> _hydrateDetails(DiscoveryItem sp) async {
    final full = await hydrateDiscoveryItem(sp);
    if (!mounted || identical(full, sp) || _current.id != sp.id) return;
    setState(() {
      _current = full.copyWithStats(
        reviewCount: _current.reviewCount,
        scoreSum: _current.scoreSum,
        outboundClicks: _current.outboundClicks,
      );
    });
  }

  void _switchSpot(DiscoveryItem next, {bool scrollToTop = true}) {
    if (next.category == DiscoveryCategory.stay) {
      if (widget.onOpenFullStayPage != null) {
        widget.onOpenFullStayPage!(next.id);
        return;
      }
      if (widget.homeBuilder != null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ListingDetailPage(
            listingId: next.id,
            homeBuilder: widget.homeBuilder!,
          ),
        ));
        return;
      }
    }
    if (next.raw['is_story'] == true && widget.onOpenStoryPage != null) {
      widget.onOpenStoryPage!(next.id);
      return;
    }

    setState(() {
      _current = next;
      _heroIndex = 0;
      _couponExpanded = false;
      _reviews = const [];
    });
    widget.onSelectConnectedItem(next);
    _onEnterSpot(next);
    if (scrollToTop && _scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _loadReviews() async {
    if (widget.offlineMode || _current.category == DiscoveryCategory.ebook) return;
    final colName = _current.category == DiscoveryCategory.stay ? 'listings' : 'spots';
    try {
      final snap = await FirebaseFirestore.instance
          .collection(colName)
          .doc(_current.id)
          .collection('reviews')
          .orderBy('created_at', descending: true)
          .limit(15)
          .get();
      if (!mounted) return;
      setState(() {
        _reviews = snap.docs.map((d) => d.data()).toList();
      });
    } catch (_) {}
  }

  Future<void> _openExternal(String rawUrl, {bool trackClick = true, String eventTag = 'external_open'}) async {
    trackPortalEvent(eventTag, {
      'item_id': _current.id,
      'province': _current.province,
      'url': rawUrl,
    });
    if (trackClick) {
      await recordOutboundVisitClick(_current, offlineMode: widget.offlineMode);
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'tel')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyShareLink() async {
    final shareUrl = 'https://jikstay-lkxu1.web.app/?spot=${Uri.encodeComponent(_current.id)}';
    await Clipboard.setData(ClipboardData(text: shareUrl));
    trackPortalEvent('share_spot_link', {'item_id': _current.id});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.lang == AppLang.ko
              ? '상세 페이지 링크가 복사되었습니다. 동행에게 바로 공유해 보세요!'
              : 'Page link copied to clipboard!',
        ),
      ),
    );
  }

  void _revealInlineCoupon() {
    trackPortalEvent('claim_visit_coupon', {
      'item_id': _current.id,
      'province': _current.province,
      'title': _current.title,
    });
    recordOutboundVisitClick(_current, offlineMode: widget.offlineMode);
    setState(() => _couponExpanded = true);
  }

  Future<void> _submitReview() async {
    final err = validateUserReviewInput(
      nickname: _nickCtrl.text,
      comment: _commentCtrl.text,
      score: _selectedScore,
    );
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_validation_err', widget.lang))),
      );
      return;
    }

    final nick = _nickCtrl.text.trim();
    final comment = _commentCtrl.text.trim();
    setState(() => _submittingReview = true);

    try {
      if (!widget.offlineMode) {
        final isStay = _current.category == DiscoveryCategory.stay;
        final colName = isStay ? 'listings' : 'spots';
        final idField = isStay ? 'listing_id' : 'spot_id';
        final result = await submitReviewBatch(
          collection: colName,
          targetId: _current.id,
          targetIdField: idField,
          score: _selectedScore,
          payload: {
            'nickname': nick,
            'comment': comment,
            'lang': widget.lang.code,
          },
        );
        if (result == ReviewSubmitResult.alreadyReviewed) {
          if (!mounted) return;
          setState(() => _submittingReview = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trUi('review_already_posted', widget.lang))),
          );
          return;
        }
      }

      if (!mounted) return;
      final nextCount = _current.reviewCount + 1;
      final nextSum = _current.scoreSum + _selectedScore;
      setState(() {
        _current = _current.copyWithStats(reviewCount: nextCount, scoreSum: nextSum);
        _reviews = [
          {
            'nickname': nick,
            'score': _selectedScore,
            'comment': comment,
            'lang': widget.lang.code,
          },
          ..._reviews,
        ];
        _nickCtrl.clear();
        _commentCtrl.clear();
        _submittingReview = false;
      });
      trackPortalEvent('submit_review', {
        'item_id': _current.id,
        'province': _current.province,
        'score': _selectedScore,
      });
      widget.onStatsUpdated?.call(_current.id, nextCount, nextSum);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trUi('review_submitted', widget.lang))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submittingReview = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 오프라인/미동기화 항목이거나 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  String _fmtDateRange(String s, String e) {
    String fmt(String d) => d.length == 8 ? '${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6, 8)}' : d;
    if (s.isEmpty && e.isEmpty) return '';
    if (e.isEmpty) return fmt(s);
    return '${fmt(s)} ~ ${fmt(e)}';
  }

  String _fmtPostDate(String raw) {
    if (raw.length == 8) {
      return '${raw.substring(0, 4)}.${raw.substring(4, 6)}.${raw.substring(6, 8)}';
    }
    return raw;
  }

  String _effectivePullQuote(DiscoveryItem item, String dateRange, AppLang lang) {
    final pq = item.tPullQuote(lang);
    if (pq.isNotEmpty) return pq;
    final cp = item.tCouponTitle(lang);
    if (cp.isNotEmpty) return cp;
    final reg = item.tRegionLabel(lang);
    if (item.category == DiscoveryCategory.event && dateRange.isNotEmpty) {
      return pickLangText(
        lang,
        ko: '$reg 대표 계절 행사 · $dateRange 개최',
        en: '$reg Seasonal Festival · $dateRange',
        ja: '$reg 季節の祭り・イベント · $dateRange',
        zh: '$reg 季節慶典活動 · $dateRange',
      );
    }
    final sub = item.tSubtitle(lang);
    final addr = item.tAddress(lang);
    if (sub.isNotEmpty && sub != addr) {
      return sub.length > 110 ? '${sub.substring(0, 110)}…' : sub;
    }
    return switch (item.category) {
      DiscoveryCategory.food => pickLangText(
          lang,
          ko: '$reg 여행 동선에서 함께 들르기 좋은 지역 대표 로컬 식도락 명소',
          en: 'Beloved local dining spot in $reg along your travel route.',
          ja: '$reg の旅ルートで立ち寄りたい人気のローカルグルメスポット。',
          zh: '造訪 $reg 不可錯過的在地人氣美食餐廳。',
        ),
      DiscoveryCategory.event => pickLangText(
          lang,
          ko: '$reg의 계절 풍경과 지역 문화를 오감으로 만나는 현장 축제',
          en: 'Experience seasonal scenery and local culture at this festival in $reg.',
          ja: '$reg の季節の風景と地域文化を体感できる現地フェスティバル。',
          zh: '親身感受 $reg 季節風景與在地文化的地方慶典。',
        ),
      DiscoveryCategory.ebook => pickLangText(
          lang,
          ko: '${trProvince(item.province, lang)} 지자체가 직접 발행한 공식 관광안내도와 추천 여행 가이드북',
          en: 'Official tourist map & guidebook published by ${trProvince(item.province, lang)}.',
          ja: '${trProvince(item.province, lang)} 自治体公式の観光案内図・旅行ガイドブック。',
          zh: '${trProvince(item.province, lang)} 地方政府發行的官方旅遊地圖與指南。',
        ),
      _ => pickLangText(
          lang,
          ko: '$reg의 자연과 이야기를 가까이에서 만나는 로컬 추천 명소',
          en: 'Discover nature and local heritage up close in $reg.',
          ja: '$reg の自然と物語に出会えるおすすめ観光スポット。',
          zh: '近距離感受 $reg 自然風光與故事的精選景點。',
        ),
    };
  }

  List<String> _effectiveParagraphs(DiscoveryItem item, String dateRange, AppLang lang) {
    final ps = item.tParagraphs(lang);
    if (ps.isNotEmpty) return ps;
    final out = <String>[];
    final sub = item.tSubtitle(lang);
    final addr = item.tAddress(lang);
    if (sub.isNotEmpty && sub != addr) {
      out.add(sub);
    }
    final reg = item.tRegionLabel(lang);
    switch (item.category) {
      case DiscoveryCategory.food:
        out.add(
          pickLangText(
            lang,
            ko: '$reg 일대 여행객과 현지인이 즐겨 찾는 로컬 식도락 장소입니다. 계절이나 재료 소진 상황에 따라 운영시간·세부 메뉴 가격이 달라질 수 있으므로, 방문 전 아래 카카오 플레이스 또는 네이버 플레이스 바로가기를 통해 최신 메뉴판과 실시간 영업 여부를 함께 확인하시면 더욱 편리합니다.',
            en: 'A popular local eatery in $reg loved by travelers and residents alike. Hours and menu prices may vary by season—check Kakao Place or Naver Place below for the latest menu and live opening status.',
            ja: '$reg エリアで旅行者と地元民に親しまれているローカルグルメスポットです。季節や仕入れ状況により営業時間やメニューが異なる場合がありますので、下記のKakao・NAVERプレイスから最新情報をご確認ください。',
            zh: '$reg 一帶深受旅客與在地人喜愛的美食名店。營業時間與餐點價格可能依季節調整，建議出發前透過下方 Kakao Place 或 NAVER Place 確認最新菜單與營業狀態。',
          ),
        );
        break;
      case DiscoveryCategory.event:
        out.add(
          pickLangText(
            lang,
            ko: '$reg에서 진행되는 지역 문화·관광 행사${dateRange.isNotEmpty ? "($dateRange)" : ""}입니다. 현장 세부 타임테이블, 임시 주차장, 우천 시 운영 여부는 아래 네이버 검색·카카오 플레이스 및 지자체 공식 관광안내도를 통해 한눈에 확인하실 수 있습니다.',
            en: 'A regional cultural festival in $reg${dateRange.isNotEmpty ? " ($dateRange)" : ""}. Check the links below for detailed schedules, temporary parking, and weather updates.',
            ja: '$reg で開催される地域文化・観光イベント${dateRange.isNotEmpty ? "（$dateRange）" : ""}です。タイムテーブルや臨時駐車場などは下記リンクからご確認いただけます。',
            zh: '於 $reg 舉辦的地方文化觀光慶典${dateRange.isNotEmpty ? "（$dateRange）" : ""}，詳細活動時刻表與停車資訊可透過下方連結查詢。',
          ),
        );
        break;
      case DiscoveryCategory.ebook:
        out.add(
          pickLangText(
            lang,
            ko: '회원가입이나 별도 앱 설치 없이 지자체 문화관광 누리집이 발행한 고화질 원본 관광안내지도와 권역별 트레킹·맛집 코스를 즉시 열람하실 수 있습니다.',
            en: 'Open the official high-resolution municipal tourist map, trekking routes, and local dining guides instantly without sign-up.',
            ja: '会員登録やアプリ不要で、自治体公式の高画質観光地図・トレッキングコース・グルメガイドをすぐにご覧いただけます。',
            zh: '免註冊、免下載 App，即可立即瀏覽地方政府官方發行的高畫質旅遊地圖與推薦步道、美食路線。',
          ),
        );
        break;
      default:
        out.add(
          pickLangText(
            lang,
            ko: '$reg을 대표하는 탐방 명소로, 주변 로컬 식당·계절 축제·합법 인증 숙소와 함께 엮어 여유로운 여행 코스를 구성하기 좋습니다.',
            en: 'A signature attraction in $reg—pair it with nearby local restaurants, seasonal events, and government-licensed stays for a relaxed itinerary.',
            ja: '$reg を代表する見どころスポットです。周辺のローカル食堂や季節の祭り、公認宿泊施設と合わせてゆったり巡るのがおすすめです。',
            zh: '$reg 的代表性觀光景點，非常適合搭配周邊在地美食、季節慶典與合法認證住宿，規劃悠閒的一日行程。',
          ),
        );
        break;
    }
    return out;
  }

  List<PracticalInfoRow> _effectivePracticalRows(DiscoveryItem item, String dateRange, AppLang lang) {
    final tInfo = item.tPracticalInfo(lang);
    if (tInfo.isNotEmpty) return tInfo;
    final rows = <PracticalInfoRow>[];
    if (dateRange.isNotEmpty) {
      rows.add(PracticalInfoRow(
        label: pickLangText(lang, ko: '행사 기간', en: 'Dates', ja: '開催期間', zh: '活動期間'),
        value: dateRange,
      ));
    }
    final addr = item.tAddress(lang);
    if (addr.isNotEmpty) {
      rows.add(PracticalInfoRow(
        label: pickLangText(lang, ko: '위치 주소', en: 'Address', ja: '住所', zh: '地址'),
        value: addr,
      ));
    }
    if (item.phone.isNotEmpty) {
      rows.add(PracticalInfoRow(
        label: pickLangText(lang, ko: '문의 전화', en: 'Phone', ja: 'お問い合わせ', zh: '聯絡電話'),
        value: item.phone,
      ));
    }
    final cp = item.tCouponTitle(lang);
    if (cp.isNotEmpty) {
      rows.add(PracticalInfoRow(
        label: pickLangText(lang, ko: '방문 혜택', en: 'Visit Perk', ja: '来店特典', zh: '造訪優惠'),
        value: cp,
      ));
    }
    return rows;
  }

  String _effectivePracticalHeader(DiscoveryItem item, AppLang lang) {
    final h = item.tPracticalHeader(lang);
    if (h.isNotEmpty) return h;
    return switch (item.category) {
      DiscoveryCategory.food => pickLangText(
          lang,
          ko: '방문 전 필수 확인 · 대표 메뉴 · 영업시간 · 편의안내',
          en: 'Essential Info · Signature Menu · Hours · Access',
          ja: '訪問前の確認事項・看板メニュー・営業時間',
          zh: '行前必看資訊・招牌餐點・營業時間',
        ),
      DiscoveryCategory.event => pickLangText(
          lang,
          ko: '행사 관람 필수 확인 · 일정 · 장소 · 관람안내',
          en: 'Festival Guide · Schedule · Venue · Info',
          ja: 'イベント案内・日程・会場・アクセス',
          zh: '活動指南・日期・地點・參觀資訊',
        ),
      DiscoveryCategory.ebook => pickLangText(
          lang,
          ko: '지자체 공식 가이드북 · 원본 PDF 이용 안내',
          en: 'Official Municipal Guidebook & PDF Info',
          ja: '自治体公式ガイドブック・PDF利用案内',
          zh: '地方政府官方旅遊指南・PDF 使用說明',
        ),
      _ => pickLangText(
          lang,
          ko: '탐방 전 필수 확인 · 위치 · 운영 · 편의안내',
          en: 'Essential Visitor Info · Hours · Access',
          ja: '訪問前の確認事項・場所・営業時間',
          zh: '行前必看資訊・位置・開放時間',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appLangNotifier, translationRevisionNotifier]),
      builder: (context, _) => _buildContent(context, appLangNotifier.value),
    );
  }

  Widget _buildContent(BuildContext context, AppLang lang) {
    final bundle = buildConnectedBundle(_current, widget.allItems, limitPerType: 8);
    final dateRange = _fmtDateRange(_current.startDate, _current.endDate);
    final gallery = _current.effectiveGallery;
    final activeHero = (gallery.isNotEmpty && _heroIndex < gallery.length) ? gallery[_heroIndex] : '';
    final pullQuote = _effectivePullQuote(_current, dateRange, lang);
    final paragraphs = _effectiveParagraphs(_current, dateRange, lang);
    final practicalRows = _effectivePracticalRows(_current, dateRange, lang);
    final practicalHeader = _effectivePracticalHeader(_current, lang);
    final freshBadge = _current.dynamicFreshnessBadge(lang);
    final tTitle = _current.tTitle(lang);
    final tAddr = _current.tAddress(lang);
    final tRegion = _current.tRegionLabel(lang);

    final screenW = MediaQuery.sizeOf(context).width;
    final isWide = screenW >= 720;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFBF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        leading: IconButton(
          key: const Key('spot_back_btn'),
          tooltip: trUi('back_btn', lang),
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (widget.homeBuilder != null) {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: widget.homeBuilder!));
            }
          },
        ),
        title: Text(
          '$tRegion · ${_current.categoryBadgeText(lang)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LangSelectorButton(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              key: const Key('spot_share_btn'),
              onPressed: _copyShareLink,
              icon: const Icon(Icons.ios_share_rounded, size: 17),
              label: Text(trUi('share_btn', lang)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 16, vertical: isWide ? 28 : 18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              padding: EdgeInsets.all(isWide ? 34 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A0F172A), blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 카테고리·선도·방문혜택·평점 태그 & 지역 출처 표기 (StoryDetailPage 상단 동일 포맷)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Text(
                          '${_current.categoryEmoji} ${trProvince(_current.province, lang)} · ${_current.categoryBadgeText(lang)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                        ),
                      ),
                      if (freshBadge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            freshBadge,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFB91C1C)),
                          ),
                        ),
                      if (_current.isSponsored)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            pickLangText(
                              lang,
                              ko: '🎁 지역 상생 추천 · 방문혜택',
                              en: '🎁 Local Partner · Visit Perk',
                              ja: '🎁 地域パートナー・来店特典',
                              zh: '🎁 在地合作推薦・造訪優惠',
                            ),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                          ),
                        ),
                      if (_current.reviewCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            '★ ${_current.averageRating.toStringAsFixed(1)} (${_current.reviewCount})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                          ),
                        ),
                      Text(
                        '$tRegion · ${pickLangText(lang, ko: '공식 관광데이터 & 로컬 플레이스 연동', en: 'Official Tourism Data & Local Place', ja: '公式観光データ＆ローカル連携', zh: '官方觀光資料與在地情報串聯')}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. 매거진 화보형 포토 그리드 (대표 사진 + 클릭형 썸네일 갤러리)
                  if (activeHero.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: isWide ? 350 : 225,
                        width: double.infinity,
                        child: StorageImage(url: activeHero, cacheWidth: 1080),
                      ),
                    ),
                    if (gallery.length > 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: isWide ? 84 : 74,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: gallery.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, idx) {
                            final selected = idx == _heroIndex;
                            return InkWell(
                              onTap: () => setState(() => _heroIndex = idx),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: isWide ? 116 : 96,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                                    width: selected ? 2.5 : 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: StorageImage(url: gallery[idx], cacheWidth: 320),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],

                  // 3. 매거진 타이틀 & 지자체 책자 스타일 부제(주소·행사기간 + 그린 언더라인)
                  Text(
                    tTitle,
                    style: TextStyle(
                      fontSize: isWide ? 28 : 22.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF14532D),
                      height: 1.28,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFBBF7D0), width: 1.5)),
                    ),
                    child: Text(
                      [
                        if (tAddr.isNotEmpty) tAddr,
                        if (dateRange.isNotEmpty) '${pickLangText(lang, ko: '행사기간', en: 'Dates', ja: '開催期間', zh: '活動期間')}: $dateRange',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. 핵심 한 줄 콜아웃 (Pull-Quote — 대표 메뉴 / 축제 테마 / 명소 한 줄 요약)
                  if (pullQuote.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(left: BorderSide(color: Color(0xFF10B981), width: 4)),
                      ),
                      child: Text(
                        '“$pullQuote”',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                          height: 1.65,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // 5. 매거진 스토리 본문 (가독성 최우선: 16.5px · 줄간격 1.88)
                  ...paragraphs.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        p,
                        style: const TextStyle(
                          fontSize: 16.5,
                          color: Color(0xFF1E293B),
                          height: 1.88,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 6. 방문 전 꼭 필요한 '핵심 탐방·메뉴·편의 정보 박스' (《장수여행》 p.9 초록 박스 모델)
                  if (practicalRows.isNotEmpty) ...[
                    Container(
                      key: const Key('spot_practical_box'),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FEE7).withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC), width: 1.3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(12.5)),
                            ),
                            child: Text(
                              '🌿 $practicalHeader',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: practicalRows
                                  .map(
                                    (row) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: RichText(
                                        text: TextSpan(
                                          style: const TextStyle(fontSize: 14, height: 1.55, color: Color(0xFF1E293B)),
                                          children: [
                                            TextSpan(
                                              text: '• ${row.label} : ',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF15803D),
                                              ),
                                            ),
                                            TextSpan(text: row.value),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // 7. 카카오 플레이스 & 네이버 검색 상세 정보 확장 (실제 블로그 방문기 + 실시간 메뉴·후기 직결)
                  if (_current.category != DiscoveryCategory.ebook) ...[
                    Container(
                      key: const Key('spot_place_search_box'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.travel_explore_rounded, size: 19, color: Color(0xFF0F172A)),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  lang == AppLang.ko
                                      ? '카카오 플레이스 & 네이버 방문기 · 실시간 상세정보'
                                      : 'Kakao Place & Naver Live Reviews · Menus & Hours',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            lang == AppLang.ko
                                ? '메뉴 가격표, 브레이크타임, 실제 방문객 사진·블로그 후기가 더 필요하시면 아래에서 바로 확인하세요.'
                                : 'Check real-time menus, opening hours, and visitor photo reviews directly.',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.45),
                          ),
                          if (_current.naverReviews.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            ..._current.naverReviews.map(
                              (rv) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openExternal(rv.link, eventTag: 'open_naver_blog_review'),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDCFCE7),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'N 블로그 방문기',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF15803D),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                [
                                                  if (rv.blogger.isNotEmpty) rv.blogger,
                                                  if (rv.postdate.isNotEmpty) _fmtPostDate(rv.postdate),
                                                ].join(' · '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                              ),
                                            ),
                                            const Icon(Icons.open_in_new_rounded, size: 14, color: Color(0xFF64748B)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          rv.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        if (rv.summary.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            rv.summary,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF475569),
                                              height: 1.5,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                key: const Key('spot_kakao_place_btn'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFEF3C7),
                                  foregroundColor: const Color(0xFF92400E),
                                ),
                                onPressed: () => _openExternal(_current.kakaoPlaceUrl, eventTag: 'open_kakao_place'),
                                icon: const Icon(Icons.place_rounded, size: 17),
                                label: Text(
                                  lang == AppLang.ko ? '🟡 카카오 플레이스 상세·별점' : '🟡 Kakao Place Details',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                key: const Key('spot_naver_place_btn'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDCFCE7),
                                  foregroundColor: const Color(0xFF166534),
                                ),
                                onPressed: () => _openExternal(_current.naverPlaceUrl, eventTag: 'open_naver_place'),
                                icon: const Icon(Icons.storefront_rounded, size: 17),
                                label: Text(
                                  lang == AppLang.ko ? '🟢 네이버 플레이스 메뉴·리뷰' : '🟢 Naver Place Menu',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                              OutlinedButton.icon(
                                key: const Key('spot_naver_search_btn'),
                                onPressed: () => _openExternal(_current.naverSearchUrl, eventTag: 'open_naver_search'),
                                icon: const Icon(Icons.search_rounded, size: 17, color: Color(0xFF03C75A)),
                                label: Text(
                                  lang == AppLang.ko ? '🔍 네이버 최신 방문기 검색' : '🔍 Search Naver Reviews',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                              ),
                              if (_current.externalUrl.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => _openExternal(_current.externalUrl, eventTag: 'open_official_site'),
                                  icon: const Icon(Icons.language_rounded, size: 17),
                                  label: Text(lang == AppLang.ko ? '공식 홈페이지' : 'Official Website'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],

                  // 8. 방문 혜택 쿠폰 (팝업 대신 페이지 내 인라인 바우처로 즉시 펼침) & 원본 PDF 버튼
                  if (_current.isSponsored ||
                      _current.couponTitle.isNotEmpty ||
                      _current.pdfLinks.isNotEmpty ||
                      (_current.category == DiscoveryCategory.ebook && _current.externalUrl.isNotEmpty)) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_current.isSponsored || _current.couponTitle.isNotEmpty)
                          FilledButton.icon(
                            key: const Key('sheet_coupon_btn'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                            ),
                            onPressed: _revealInlineCoupon,
                            icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                            label: Text(trUi('coupon_action_btn', lang)),
                          ),
                        if (_current.pdfLinks.isNotEmpty)
                          ..._current.pdfLinks.map(
                            (pl) => FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              ),
                              onPressed: () => _openExternal(
                                pl.url,
                                trackClick: false,
                                eventTag: 'open_municipal_pdf',
                              ),
                              icon: const Icon(Icons.menu_book_rounded, size: 17),
                              label: Text(pl.localizedLabel(lang)),
                            ),
                          )
                        else if (_current.category == DiscoveryCategory.ebook && _current.externalUrl.isNotEmpty)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            ),
                            onPressed: () => _openExternal(
                              _current.externalUrl,
                              trackClick: false,
                              eventTag: 'open_municipal_pdf',
                            ),
                            icon: const Icon(Icons.menu_book_rounded, size: 18),
                            label: Text(trUi('open_ebook_btn', lang)),
                          ),
                      ],
                    ),
                    if (_couponExpanded) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFCD34D), width: 1.4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('🎁 ', style: TextStyle(fontSize: 20)),
                                Expanded(
                                  child: Text(
                                    lang == AppLang.ko ? '직스테이 로컬 방문 혜택 쿠폰' : 'Jikstay Korea Visit Coupon',
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() => _couponExpanded = false),
                                  child: Text(lang == AppLang.ko ? '닫기' : 'Close'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _current.couponTitle.isNotEmpty
                                  ? _current.couponTitle
                                  : '현장 방문 시 직스테이 로컬 화면을 제시해 주세요.',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF78350F),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lang == AppLang.ko
                                  ? '• 별도 회원가입이나 수수료 결제 없이 현장 주문 시 이 화면을 보여주시면 됩니다.'
                                  : '• Simply show this screen upon ordering. No sign-up or fee required.',
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],

                  // 9. 정돈된 1줄 대중교통·내비 길찾기 바 (StoryDetailPage 동일 포맷)
                  Text(
                    lang == AppLang.ko ? '바로 떠나기 · 대중교통 및 내비게이션 경로' : 'Directions & Public Transit',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('sheet_directions_btn'),
                        onPressed: () => _openExternal(_current.naverRouteUrl, eventTag: 'click_transit_naver'),
                        icon: const Icon(Icons.map_outlined, size: 17, color: Color(0xFF03C75A)),
                        label: Text(lang == AppLang.ko ? '🟢 네이버지도 · 길찾기' : '🟢 Naver Map'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('sheet_kakao_route_btn'),
                        onPressed: () => _openExternal(_current.kakaoRouteUrl, eventTag: 'click_transit_kakao'),
                        icon: const Icon(Icons.directions_bus_filled_rounded, size: 17, color: Color(0xFFD97706)),
                        label: Text(lang == AppLang.ko ? '🟡 카카오 대중교통 · 내비' : '🟡 Kakao Transit'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('sheet_google_transit_btn'),
                        onPressed: () => _openExternal(_current.googleTransitUrl, eventTag: 'click_transit_google'),
                        icon: const Icon(Icons.train_rounded, size: 17, color: Color(0xFF2563EB)),
                        label: Text(lang == AppLang.ko ? '🔵 Google 대중교통' : '🔵 Google Transit'),
                      ),
                      if (_current.phone.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openExternal('tel:${_current.phone.replaceAll(' ', '')}', eventTag: 'click_phone'),
                          icon: const Icon(Icons.call_outlined, size: 17),
                          label: Text(_current.phone),
                        ),
                    ],
                  ),
                  if (_current.raw['naver_category'] != null || _current.raw['naver_link'] != null) ...[
                    const SizedBox(height: 12),
                    NaverPlaceInfo(data: _current.raw, lang: lang, itemId: _current.id),
                  ],

                  // 10. 해당 지자체 공식 관광지도 / 가이드북 PDF 연결
                  if (_current.category != DiscoveryCategory.ebook && bundle.ebooks.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Divider(height: 1),
                    ),
                    Text(
                      lang == AppLang.ko
                          ? '📖 ${_current.province} 지자체 발행 공식 관광지도 · 가이드북 (원본 PDF 즉시 열람)'
                          : '📖 Official ${_current.province} Municipal Tourist Maps & Direct PDFs',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 10),
                    ...bundle.ebooks.map(
                      (eb) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, color: Color(0xFF2563EB), size: 21),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        eb.title,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E3A8A),
                                        ),
                                      ),
                                      if (eb.address.isNotEmpty)
                                        Text(
                                          eb.address,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF3B82F6)),
                                        ),
                                    ],
                                  ),
                                ),
                                if (eb.pdfLinks.isEmpty) ...[
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () => _openExternal(
                                      eb.externalUrl,
                                      trackClick: false,
                                      eventTag: 'open_municipal_pdf',
                                    ),
                                    child: Text(lang == AppLang.ko ? '바로 열람' : 'Open PDF'),
                                  ),
                                ],
                              ],
                            ),
                            if (eb.pdfLinks.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: eb.pdfLinks
                                    .map(
                                      (pl) => FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: () => _openExternal(
                                          pl.url,
                                          trackClick: false,
                                          eventTag: 'open_municipal_pdf',
                                        ),
                                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                        label: Text(
                                          pl.localizedLabel(lang),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 11. 함께 방문하기 좋은 주변 연결 코스 (팝업 없이 전체 상세 페이지 전환)
                  if (bundle.totalNearbyCount > 0) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(height: 1),
                    ),
                    Text(
                      '✨ ${trUi('connected_course_title', lang)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lang == AppLang.ko
                          ? '선택한 장소와 가까운 로컬 식당, 계절 축제, 볼거리, 합법 인증 안심숙소 상세 페이지로 바로 이어집니다.'
                          : 'Seamlessly explore nearby local restaurants, festivals, sights, and licensed stays.',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 14),
                    _ConnectedHorizontalRow(
                      title: lang == AppLang.ko ? '🍲 근처 로컬 먹거리 · 맛집' : '🍲 Nearby Local Food',
                      items: bundle.foods,
                      anchor: _current,
                      onTap: _switchSpot,
                    ),
                    _ConnectedHorizontalRow(
                      title: lang == AppLang.ko ? '🏞️ 함께 들를 볼거리 · 명소' : '🏞️ Nearby Attractions',
                      items: bundle.attractions,
                      anchor: _current,
                      onTap: _switchSpot,
                    ),
                    _ConnectedHorizontalRow(
                      title: lang == AppLang.ko ? '🎉 주변 진행·예정 축제' : '🎉 Nearby Festivals & Events',
                      items: bundle.events,
                      anchor: _current,
                      onTap: _switchSpot,
                    ),
                    _ConnectedHorizontalRow(
                      title: lang == AppLang.ko ? '🏡 근처 합법 인증 안심숙소' : '🏡 Nearby Gov-Verified Stays',
                      items: bundle.stays,
                      anchor: _current,
                      onTap: _switchSpot,
                    ),
                  ],

                  // 12. 방문자 별점 & 한줄 후기 (E-book 제외 모든 장소 지원)
                  if (_current.category != DiscoveryCategory.ebook) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Divider(height: 1),
                    ),
                    Text(
                      '⭐ ${trUi('user_reviews_title', lang)}',
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              for (int s = 1; s <= 5; s++)
                                IconButton(
                                  key: Key('spot_star_$s'),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () => setState(() => _selectedScore = s),
                                  icon: Icon(
                                    s <= _selectedScore ? Icons.star_rounded : Icons.star_border_rounded,
                                    color: const Color(0xFFF59E0B),
                                    size: 26,
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Text(
                                '$_selectedScore.0 / 5.0',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              SizedBox(
                                width: isWide ? 150 : 112,
                                child: TextField(
                                  key: const Key('spot_review_nick'),
                                  controller: _nickCtrl,
                                  decoration: InputDecoration(
                                    hintText: trUi('nickname_label', lang),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  key: const Key('spot_review_comment'),
                                  controller: _commentCtrl,
                                  decoration: InputDecoration(
                                    hintText: lang == AppLang.ko ? '방문 후기 한줄 (4자 이상)' : 'Short visit tip (4+ chars)',
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                key: const Key('spot_review_submit'),
                                onPressed: _submittingReview ? null : _submitReview,
                                child: Text(lang == AppLang.ko ? '등록' : 'Post'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_reviews.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final rev in _reviews)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '★ ${(rev['score'] ?? 5)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFD97706)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${rev['nickname'] ?? '방문자'}: ${rev['comment'] ?? ''}',
                                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectedHorizontalRow extends StatelessWidget {
  final String title;
  final List<DiscoveryItem> items;
  final DiscoveryItem anchor;
  final ValueChanged<DiscoveryItem> onTap;

  const _ConnectedHorizontalRow({
    required this.title,
    required this.items,
    required this.anchor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final lang = appLangNotifier.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
          const SizedBox(height: 8),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final it = items[i];
                final dist = haversineKm(anchor.lat, anchor.lng, it.lat, it.lng);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(it),
                  child: Container(
                    width: 245,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: it.isSponsored ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 66,
                            height: 76,
                            child: it.imageUrl.isNotEmpty
                                ? StorageImage(url: it.imageUrl, cacheWidth: 220)
                                : Container(
                                    color: it.category.color.withValues(alpha: 0.1),
                                    alignment: Alignment.center,
                                    child: Icon(it.category.icon, color: it.category.color, size: 24),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (it.isSponsored)
                                const Text(
                                  '🎁 방문혜택',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                ),
                              Text(
                                it.tTitle(lang),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${dist < 1.0 ? "${(dist * 1000).round()}m" : "${dist.toStringAsFixed(1)}km"} · ${it.tRegionLabel(lang)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF94A3B8)),
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
}
