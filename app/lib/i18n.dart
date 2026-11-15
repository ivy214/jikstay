// 국내 및 해외(영어·일본어·번체중국어) 게스트 타겟팅 다국어 UI & 자동 번역 직거래 문의 브릿지.
import 'package:flutter/material.dart';

enum AppLang {
  ko('ko', '한국어', '🇰🇷 한국어'),
  en('en', 'EN', '🇺🇸 English'),
  ja('ja', '日本語', '🇯🇵 日本語'),
  zh('zh', '繁體', '🇹🇼 繁體中文');

  final String code;
  final String shortLabel;
  final String menuLabel;
  const AppLang(this.code, this.shortLabel, this.menuLabel);
}

final ValueNotifier<AppLang> appLangNotifier = ValueNotifier<AppLang>(AppLang.ko);

/// 언어 변경 시 온디맨드 번역 번들 로드 등을 연결하기 위한 콜백.
void Function(AppLang lang)? onAppLangSelected;

void selectAppLang(AppLang next) {
  appLangNotifier.value = next;
  onAppLangSelected?.call(next);
}

String pickLangText(
  AppLang lang, {
  required String ko,
  required String en,
  String? ja,
  String? zh,
}) {
  return switch (lang) {
    AppLang.ko => ko,
    AppLang.en => en,
    AppLang.ja => ja ?? en,
    AppLang.zh => zh ?? en,
  };
}

AppLang parseAppLang(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.startsWith('en')) return AppLang.en;
  if (s.startsWith('ja')) return AppLang.ja;
  if (s.startsWith('zh')) return AppLang.zh;
  return AppLang.ko;
}

const List<String> kLicenseCategories = [
  '전체',
  '농어촌민박업',
  '일반/생활숙박업',
  '한옥체험업',
  '외국인관광도시민박업',
];

String trProvince(String key, AppLang lang) {
  if (lang == AppLang.ko) return key;
  const map = <String, Map<AppLang, String>>{
    '전체': {AppLang.en: 'All Korea', AppLang.ja: '韓国全域', AppLang.zh: '韓國全區'},
    '서울': {AppLang.en: 'Seoul', AppLang.ja: 'ソウル', AppLang.zh: '首爾'},
    '부산': {AppLang.en: 'Busan', AppLang.ja: '釜山', AppLang.zh: '釜山'},
    '대구': {AppLang.en: 'Daegu', AppLang.ja: '大邱', AppLang.zh: '大邱'},
    '인천': {AppLang.en: 'Incheon', AppLang.ja: '仁川', AppLang.zh: '仁川'},
    '광주': {AppLang.en: 'Gwangju', AppLang.ja: '光州', AppLang.zh: '光州'},
    '대전': {AppLang.en: 'Daejeon', AppLang.ja: '大田', AppLang.zh: '大田'},
    '울산': {AppLang.en: 'Ulsan', AppLang.ja: '蔚山', AppLang.zh: '蔚山'},
    '세종': {AppLang.en: 'Sejong', AppLang.ja: '世宗', AppLang.zh: '世宗'},
    '경기': {AppLang.en: 'Gyeonggi', AppLang.ja: '京畿', AppLang.zh: '京畿'},
    '강원': {AppLang.en: 'Gangwon', AppLang.ja: '江原', AppLang.zh: '江原'},
    '충북': {AppLang.en: 'Chungbuk', AppLang.ja: '忠北', AppLang.zh: '忠北'},
    '충남': {AppLang.en: 'Chungnam', AppLang.ja: '忠南', AppLang.zh: '忠南'},
    '전북': {AppLang.en: 'Jeonbuk', AppLang.ja: '全北', AppLang.zh: '全北'},
    '전남': {AppLang.en: 'Jeonnam', AppLang.ja: '全南', AppLang.zh: '全南'},
    '경북': {AppLang.en: 'Gyeongbuk', AppLang.ja: '慶北', AppLang.zh: '慶北'},
    '경남': {AppLang.en: 'Gyeongnam', AppLang.ja: '慶南', AppLang.zh: '慶南'},
    '제주': {AppLang.en: 'Jeju', AppLang.ja: '済州', AppLang.zh: '濟州'},
  };
  return map[key]?[lang] ?? key;
}

String trRegion(String key, AppLang lang) {
  if (lang == AppLang.ko) return key;
  const map = {
    '전체': {AppLang.en: 'All Korea', AppLang.ja: '韓国全域', AppLang.zh: '韓國全區'},
    '제주': {AppLang.en: 'Jeju', AppLang.ja: '済州島', AppLang.zh: '濟州島'},
    '강원': {AppLang.en: 'Gangwon', AppLang.ja: '江原道', AppLang.zh: '江原道'},
    '부산/경상': {AppLang.en: 'Busan · Gyeongsang', AppLang.ja: '釜山・慶尚', AppLang.zh: '釜山・慶尚'},
    '전라/충청': {AppLang.en: 'Jeolla · Chungcheong', AppLang.ja: '全羅・忠清', AppLang.zh: '全羅・忠清'},
    '서울/경기': {AppLang.en: 'Seoul · Gyeonggi', AppLang.ja: 'ソウル・京畿', AppLang.zh: '首爾・京畿'},
  };
  return map[key]?[lang] ?? key;
}

String trLicenseCategory(String key, AppLang lang) {
  const koLabels = {
    '전체': '전체 업종',
    '농어촌민박업': '🏡 농어촌민박',
    '일반/생활숙박업': '🏢 일반·생활숙박',
    '한옥체험업': '🏯 한옥체험',
    '외국인관광도시민박업': '🌏 외국인도시민박',
  };
  if (lang == AppLang.ko) return koLabels[key] ?? key;
  const map = {
    '전체': {AppLang.en: 'All Legal Stays', AppLang.ja: '全カテゴリー', AppLang.zh: '全部合法類別'},
    '농어촌민박업': {AppLang.en: '🏡 Countryside Stay', AppLang.ja: '🏡 ローカル民宿', AppLang.zh: '🏡 鄉村獨棟民宿'},
    '일반/생활숙박업': {AppLang.en: '🏢 Hotel & Residence', AppLang.ja: '🏢 ホテル・レジデンス', AppLang.zh: '🏢 酒店・公寓式住宿'},
    '한옥체험업': {AppLang.en: '🏯 Traditional Hanok', AppLang.ja: '🏯 伝統韓屋ステイ', AppLang.zh: '🏯 傳統韓屋體驗'},
    '외국인관광도시민박업': {AppLang.en: '🌏 Foreigner Homestay', AppLang.ja: '🌏 外国人専用都市民宿', AppLang.zh: '🌏 外國旅客都市民宿'},
  };
  return map[key]?[lang] ?? key;
}

String trUi(String key, AppLang lang) {
  const table = <String, Map<AppLang, String>>{
    'brand_name': {
      AppLang.ko: '직스테이 로컬',
      AppLang.en: 'Jikstay Korea',
      AppLang.ja: 'Jikstay Korea',
      AppLang.zh: 'Jikstay 韓國',
    },
    'zero_fee_badge': {
      AppLang.ko: '전국 17개 시도 공식 가이드 · 볼거리 · 먹거리 · 안심숙소',
      AppLang.en: 'Verified Legal Stays · 0% Fee · 17-Province Guides',
      AppLang.ja: '韓国公認宿・仲介手数料0円・17市道公式ガイド',
      AppLang.zh: '韓國合法住宿・0%手續費・17市道官方指南',
    },
    'search_hint': {
      AppLang.ko: '지역·축제·볼거리·맛집·숙소 검색 (예: 무주, 강릉, 한우, 한옥)',
      AppLang.en: 'Search towns, festivals, food, sights, stays...',
      AppLang.ja: '地域・祭り・名所・グルメ・宿を検索',
      AppLang.zh: '搜尋地區、慶典、景點、美食、住宿...',
    },
    'cat_all': {
      AppLang.ko: '✨ 전체',
      AppLang.en: '✨ All',
      AppLang.ja: '✨ すべて',
      AppLang.zh: '✨ 全部',
    },
    'cat_event': {
      AppLang.ko: '🎉 이벤트·축제',
      AppLang.en: '🎉 Events',
      AppLang.ja: '🎉 イベント・祭り',
      AppLang.zh: '🎉 慶典活動',
    },
    'cat_attraction': {
      AppLang.ko: '🏞️ 볼거리',
      AppLang.en: '🏞️ Sights',
      AppLang.ja: '🏞️ 見どころ',
      AppLang.zh: '🏞️ 必訪景點',
    },
    'cat_food': {
      AppLang.ko: '🍲 먹거리',
      AppLang.en: '🍲 Local Food',
      AppLang.ja: '🍲 グルメ',
      AppLang.zh: '🍲 在地美食',
    },
    'cat_stay': {
      AppLang.ko: '🏡 안심숙소',
      AppLang.en: '🏡 Legal Stays',
      AppLang.ja: '🏡 公認宿',
      AppLang.zh: '🏡 合法住宿',
    },
    'cat_ebook': {
      AppLang.ko: '📖 관광지도·E-book',
      AppLang.en: '📖 Official Maps & PDF',
      AppLang.ja: '📖 観光地図・E-book',
      AppLang.zh: '📖 官方地圖・電子書',
    },
    'view_story_feed': {
      AppLang.ko: '📖 스토리·목록',
      AppLang.en: '📖 Stories & Feed',
      AppLang.ja: '📖 ストーリー・一覧',
      AppLang.zh: '📖 故事・列表',
    },
    'view_calendar': {
      AppLang.ko: '📅 캘린더 보기',
      AppLang.en: '📅 Calendar View',
      AppLang.ja: '📅 カレンダー表示',
      AppLang.zh: '📅 行事曆檢視',
    },
    'view_naver_map': {
      AppLang.ko: '🟢 네이버 지도 보기',
      AppLang.en: '🟢 Naver Map View',
      AppLang.ja: '🟢 NAVER地図で見る',
      AppLang.zh: '🟢 NAVER地圖檢視',
    },
    'featured_events_title': {
      AppLang.ko: '지금 주목할 대표 축제 · 지자체 공식 가이드북',
      AppLang.en: 'Featured Local Events & Official Tourist Maps',
      AppLang.ja: '注目の地域イベント＆自治体公式ガイドブック',
      AppLang.zh: '精選地方慶典＆政府官方旅遊地圖',
    },
    'live_feed_title': {
      AppLang.ko: '실시간 로컬 피드',
      AppLang.en: 'Live Local Feed',
      AppLang.ja: 'リアルタイム・ローカルフィード',
      AppLang.zh: '即時在地動態',
    },
    'connected_course_title': {
      AppLang.ko: '함께 방문하기 좋은 주변 연결 코스',
      AppLang.en: 'Naturally Connected Nearby Places',
      AppLang.ja: '一緒に巡りたい周辺おすすめコース',
      AppLang.zh: '順遊推薦：周邊串聯美食・景點・住宿',
    },
    'open_ebook_btn': {
      AppLang.ko: '공식 관광지도 · E-book 무료 열람',
      AppLang.en: 'Open Official Map / E-book (Free)',
      AppLang.ja: '公式観光地図・E-bookを無料閲覧',
      AppLang.zh: '免費開啟官方旅遊地圖／電子書',
    },
    'coupon_action_btn': {
      AppLang.ko: '🎁 방문 혜택 쿠폰 받기',
      AppLang.en: '🎁 Get Visit Perk Coupon',
      AppLang.ja: '🎁 来店特典クーポンを見る',
      AppLang.zh: '🎁 領取造訪優惠券',
    },
    'directions_btn': {
      AppLang.ko: '🗺️ 지도 · 길찾기',
      AppLang.en: '🗺️ Map & Directions',
      AppLang.ja: '🗺️ 地図・ルート案内',
      AppLang.zh: '🗺️ 地圖與導航',
    },
    'public_verified_badge': {
      AppLang.ko: '공공데이터 영업확인',
      AppLang.en: 'Gov-Registry Active',
      AppLang.ja: '公的データ営業確認',
      AppLang.zh: '政府資料營業中',
    },
    'claimed_verified_badge': {
      AppLang.ko: '공식 직거래 인증',
      AppLang.en: 'Verified Direct Host',
      AppLang.ja: '公式直取引ホスト',
      AppLang.zh: '官方直訂認證',
    },
    'naver_reviews_title': {
      AppLang.ko: '네이버 블로그 실방문 후기 · 소개 링크',
      AppLang.en: 'Local Korean Blog Reviews & Photos (Naver)',
      AppLang.ja: '韓国現地の宿泊ブログレビュー・写真リンク (Naver)',
      AppLang.zh: '韓國在地部落客真實住宿評價與照片連結 (Naver)',
    },
    'naver_reviews_sub': {
      AppLang.ko: '저작권 보호를 위해 본문·사진을 복제하지 않고 네이버 공식 검색 요약과 원문 바로가기만 제공합니다.',
      AppLang.en: 'Authentic reviews written by Korean travelers. Click any post to view photos in your browser.',
      AppLang.ja: '韓国人旅行者のリアルな訪問記です。クリックすると元のブログ記事と写真をご覧いただけます。',
      AppLang.zh: '由韓國旅客撰寫的真實遊記，點擊即可開啟原始部落格查看完整照片與介紹。',
    },
    'cta_public_map': {
      AppLang.ko: '네이버 지도·예약처 보기',
      AppLang.en: 'View on Naver Map / Place',
      AppLang.ja: 'NAVERマップ・予約窓口を見る',
      AppLang.zh: '開啟 NAVER 地圖與訂房資訊',
    },
    'cta_direct_book': {
      AppLang.ko: '수수료 0원 직거래 예약',
      AppLang.en: '0% Fee Direct Inquiry',
      AppLang.ja: '手数料0ウォン直取引予約',
      AppLang.zh: '0%手續費直接預訂諮詢',
    },
    'nav_stays': {
      AppLang.ko: '🏡 전국 합법숙소 탐색',
      AppLang.en: '🏡 Verified Stays',
      AppLang.ja: '🏡 公認宿を探す',
      AppLang.zh: '🏡 合法民宿搜尋',
    },
    'nav_travel_hub': {
      AppLang.ko: '🎁 반값여행 · 축제 · 공공매거진',
      AppLang.en: '🎁 50% Pass · Festivals · Guides',
      AppLang.ja: '🎁 半額支援・祭り・公式マガジン',
      AppLang.zh: '🎁 半價補助・慶典・官方旅遊誌',
    },
    'nearby_spots_title': {
      AppLang.ko: '숙소 반경 5km 추천 명소 · 맛집 (한국관광공사 공식)',
      AppLang.en: 'Official Nearby Attractions & Dining (within 5km · KTO)',
      AppLang.ja: '宿から半径5kmのおすすめ名所・グルメ（韓国観光公社公式）',
      AppLang.zh: '住宿半徑5km推薦景點與美食（韓國觀光公社官方資料）',
    },
    'user_reviews_title': {
      AppLang.ko: '방문자 별점 · 이용 후기',
      AppLang.en: 'Traveler Ratings & Reviews',
      AppLang.ja: '宿泊者の評価・口コミ',
      AppLang.zh: '旅客評分與真實評價',
    },
    'user_reviews_sub': {
      AppLang.ko: '실제 투숙·문의 경험을 별점(1~5점)과 함께 공유해 주세요. 다른 여행자에게 큰 도움이 됩니다.',
      AppLang.en: 'Share your stay or direct booking experience with a 1–5 star rating.',
      AppLang.ja: '宿泊や直取引予約の感想を星評価（1〜5点）と一緒に共有してください。',
      AppLang.zh: '歡迎分享您的實際住宿或直訂諮詢體驗（1～5顆星評分）。',
    },
    'write_review_title': {
      AppLang.ko: '별점 및 후기 남기기',
      AppLang.en: 'Write a Rating & Review',
      AppLang.ja: '評価・口コミを投稿する',
      AppLang.zh: '撰寫評分與評價',
    },
    'nickname_label': {
      AppLang.ko: '닉네임',
      AppLang.en: 'Nickname',
      AppLang.ja: 'ニックネーム',
      AppLang.zh: '暱稱',
    },
    'nickname_hint': {
      AppLang.ko: '예: 제주여행러 (1~24자)',
      AppLang.en: 'e.g. Alex (1-24 chars)',
      AppLang.ja: '例：ソウル旅 (1〜24文字)',
      AppLang.zh: '例：韓國自由行 (1-24字)',
    },
    'comment_hint': {
      AppLang.ko: '객실 청결도, 위치, 호스트 응대 등 솔직한 이용 후기를 남겨주세요 (4~600자)',
      AppLang.en: 'Share cleanliness, location, or host communication tips (4-600 chars)',
      AppLang.ja: '清潔さ・立地・ホストの対応など率直な感想をご記入ください（4〜600文字）',
      AppLang.zh: '請分享房間整潔度、交通位置或屋主聯繫體驗（4-600字）',
    },
    'submit_review_btn': {
      AppLang.ko: '별점 · 후기 등록',
      AppLang.en: 'Submit Review',
      AppLang.ja: '口コミを登録',
      AppLang.zh: '送出評價',
    },
    'review_empty': {
      AppLang.ko: '아직 등록된 방문자 후기가 없습니다. 첫 번째 별점과 후기를 남겨보세요!',
      AppLang.en: 'No traveler reviews yet. Be the first to rate this stay!',
      AppLang.ja: 'まだ口コミがありません。最初の評価を投稿してみましょう！',
      AppLang.zh: '目前尚無旅客評價，成為第一位留下評分的旅客吧！',
    },
    'review_submitted': {
      AppLang.ko: '소중한 별점과 후기가 등록되었습니다!',
      AppLang.en: 'Thank you! Your rating and review have been posted.',
      AppLang.ja: '評価と口コミが登録されました！',
      AppLang.zh: '感謝您！評分與評價已成功發佈。',
    },
    'review_validation_err': {
      AppLang.ko: '닉네임(1~24자)과 후기 내용(4~600자)을 확인해 주세요.',
      AppLang.en: 'Please enter a nickname (1–24 chars) and review (4–600 chars).',
      AppLang.ja: 'ニックネーム（1〜24文字）と口コミ本文（4〜600文字）をご確認ください。',
      AppLang.zh: '請確認暱稱（1-24字）與評價內容（4-600字）。',
    },
    'more_stories_title': {
      AppLang.ko: '📚 함께 읽어볼 지자체 가이드북 스토리',
      AppLang.en: '📚 More Municipal Guidebook Stories',
      AppLang.ja: '📚 あわせて読みたい自治体ガイドブック・ストーリー',
      AppLang.zh: '📚 更多地方政府官方旅遊指南故事',
    },
    'today_local_story': {
      AppLang.ko: '📖 오늘의 로컬 스토리',
      AppLang.en: '📖 Today’s Local Story',
      AppLang.ja: '📖 本日のローカルストーリー',
      AppLang.zh: '📖 今日在地故事',
    },
    'read_story_btn': {
      AppLang.ko: '스토리 상세 보기',
      AppLang.en: 'Read Story',
      AppLang.ja: 'ストーリーを読む',
      AppLang.zh: '閱讀完整故事',
    },
    'connected_nearby_hint': {
      AppLang.ko: '주변 맛집·명소·숙소 연결 보기',
      AppLang.en: 'Connected nearby places',
      AppLang.ja: '周辺のグルメ・名所・宿を見る',
      AppLang.zh: '查看周邊美食・景點・住宿',
    },
    'all_korea_curated': {
      AppLang.ko: '전국 큐레이션',
      AppLang.en: 'All Korea',
      AppLang.ja: '韓国全域',
      AppLang.zh: '韓國全區',
    },
    'back_btn': {
      AppLang.ko: '돌아가기',
      AppLang.en: 'Back',
      AppLang.ja: '戻る',
      AppLang.zh: '返回',
    },
    'share_btn': {
      AppLang.ko: '공유',
      AppLang.en: 'Share',
      AppLang.ja: '共有',
      AppLang.zh: '分享',
    },
    'link_copied': {
      AppLang.ko: '링크가 복사되었습니다!',
      AppLang.en: 'Link copied to clipboard!',
      AppLang.ja: 'リンクをコピーしました！',
      AppLang.zh: '已複製連結！',
    },
    'naver_map_reviews': {
      AppLang.ko: '네이버 정보·지도',
      AppLang.en: 'Map & Reviews',
      AppLang.ja: '地図・口コミ',
      AppLang.zh: '地圖與評價',
    },
    'open_naver_map_btn': {
      AppLang.ko: '🟢 네이버 지도로 크게 열기',
      AppLang.en: '🟢 Open in Naver Map',
      AppLang.ja: '🟢 NAVER地図で大きく開く',
      AppLang.zh: '🟢 在 NAVER 地圖中開啟',
    },
    'naver_map_food_btn': {
      AppLang.ko: '🍲 네이버지도 맛집 ↗',
      AppLang.en: '🍲 Naver Food ↗',
      AppLang.ja: '🍲 NAVER グルメ ↗',
      AppLang.zh: '🍲 NAVER 美食 ↗',
    },
    'naver_map_sight_btn': {
      AppLang.ko: '🏞️ 네이버지도 명소 ↗',
      AppLang.en: '🏞️ Naver Sights ↗',
      AppLang.ja: '🏞️ NAVER 名所 ↗',
      AppLang.zh: '🏞️ NAVER 景點 ↗',
    },
    'view_detail_btn': {
      AppLang.ko: '📖 상세 보기',
      AppLang.en: '📖 View Details',
      AppLang.ja: '📖 詳細を見る',
      AppLang.zh: '📖 查看詳情',
    },
    'naver_directions_btn': {
      AppLang.ko: '🟢 네이버 지도·길찾기 ↗',
      AppLang.en: '🟢 Naver Map & Directions ↗',
      AppLang.ja: '🟢 NAVER地図・ルート案内 ↗',
      AppLang.zh: '🟢 NAVER 地圖與導航 ↗',
    },
  };
  return table[key]?[lang] ?? table[key]?[AppLang.ko] ?? key;
}

String _translateProvinceShort(String d1, AppLang lang) {
  if (d1.startsWith('제주')) return lang == AppLang.en ? 'Jeju' : (lang == AppLang.ja ? '済州島' : '濟州島');
  if (d1.startsWith('강원')) return lang == AppLang.en ? 'Gangwon' : '江原道';
  if (d1.startsWith('부산')) return lang == AppLang.en ? 'Busan' : '釜山';
  if (d1.startsWith('서울')) return lang == AppLang.en ? 'Seoul' : (lang == AppLang.ja ? 'ソウル' : '首爾');
  if (d1.startsWith('경기')) return lang == AppLang.en ? 'Gyeonggi' : '京畿道';
  if (d1.startsWith('인천')) return lang == AppLang.en ? 'Incheon' : '仁川';
  if (d1.startsWith('전북') || d1.startsWith('전라북')) return lang == AppLang.en ? 'Jeonbuk' : '全北';
  if (d1.startsWith('전남') || d1.startsWith('전라남') || d1.startsWith('광주')) return lang == AppLang.en ? 'Jeonnam' : '全南';
  if (d1.startsWith('경북') || d1.startsWith('경상북') || d1.startsWith('대구')) return lang == AppLang.en ? 'Gyeongbuk' : '慶北';
  if (d1.startsWith('경남') || d1.startsWith('경상남') || d1.startsWith('울산')) return lang == AppLang.en ? 'Gyeongnam' : '慶南';
  if (d1.startsWith('충') || d1.startsWith('대전') || d1.startsWith('세종')) {
    return lang == AppLang.en ? 'Chungcheong' : (lang == AppLang.ja ? '忠清' : '忠清');
  }
  return '';
}

String localizedListingTitle(Map<String, dynamic> data, AppLang lang) {
  final base = (data['title'] ?? '').toString();
  if (lang == AppLang.ko) return base;
  final i18n = data['i18n'];
  if (i18n is Map && i18n[lang.code] is Map) {
    final t = (i18n[lang.code]['title'] ?? '').toString().trim();
    if (t.isNotEmpty) return t;
  }
  final prov = _translateProvinceShort((data['region_depth1'] ?? '').toString(), lang);
  if (prov.isNotEmpty) {
    return lang == AppLang.en ? '$base ($prov)' : '$base（$prov）';
  }
  return base;
}

String localizedListingStory(Map<String, dynamic> data, AppLang lang) {
  final base = (data['editorial_story'] ?? '').toString().trim();
  if (lang == AppLang.ko) return base;
  final i18n = data['i18n'];
  if (i18n is Map && i18n[lang.code] is Map) {
    final s = (i18n[lang.code]['summary'] ?? '').toString().trim();
    if (s.isNotEmpty) return '$s\n\n$base'.trim();
  }
  return base;
}

class LangSelectorButton extends StatelessWidget {
  const LangSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: appLangNotifier,
      builder: (context, lang, _) {
        return PopupMenuButton<AppLang>(
          tooltip: 'Language / 언어 선택',
          initialValue: lang,
          onSelected: selectAppLang,
          itemBuilder: (_) => AppLang.values
              .map((l) => PopupMenuItem<AppLang>(
                    value: l,
                    child: Text(l.menuLabel, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ))
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDDDDDD)),
              color: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language_rounded, size: 17, color: Color(0xFF333333)),
                const SizedBox(width: 5),
                Text(lang.shortLabel,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF222222))),
                const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Color(0xFF555555)),
              ],
            ),
          ),
        );
      },
    );
  }
}
