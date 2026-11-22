// 홈 탐색 바의 카테고리 묶음: 9개 분류를 큰 분류 5개(+관광지도 링크)로 묶고, 큰 분류를 고르면 세부 칩을 보여 준다.
// 데이터 분류(DiscoveryCategory)는 그대로 두고 화면에서만 묶는다 → 검색어·공유 링크·여행코스는 영향 없음.
import 'package:material_ui/material_ui.dart';

import 'discovery_models.dart';
import 'i18n.dart';

enum CategoryGroup { all, events, sights, food, stays, guides }

String _sub(DiscoveryItem it) => (it.raw['sub'] ?? '').toString();
bool _isCamp(DiscoveryItem it) => it.category == DiscoveryCategory.outdoor && _sub(it) == 'camping';

class CategorySub {
  const CategorySub(this.key, this.ko, this.en, this.ja, this.zh, this.test, this.single);

  final String key;
  final String ko, en, ja, zh;
  final bool Function(DiscoveryItem) test;

  /// 이 칩이 데이터 분류 하나와 같으면 그 분류 (지도 검색어·캘린더 판단용)
  final DiscoveryCategory single;

  String label(AppLang lang) => pickLangText(lang, ko: ko, en: en, ja: ja, zh: zh);
}

class CategoryGroupSpec {
  const CategoryGroupSpec(this.group, this.ko, this.en, this.ja, this.zh, this.color, this.subs);

  final CategoryGroup group;
  final String ko, en, ja, zh;
  final Color color;

  /// 첫 칩이 '전체'(묶음 전체)
  final List<CategorySub> subs;

  String label(AppLang lang) => pickLangText(lang, ko: ko, en: en, ja: ja, zh: zh);
}

final List<CategoryGroupSpec> kCategoryGroups = [
  CategoryGroupSpec(CategoryGroup.all, '✨ 전체', '✨ All', '✨ すべて', '✨ 全部', const Color(0xFF1E293B), [
    CategorySub('all', '전체', 'All', 'すべて', '全部', (_) => true, DiscoveryCategory.all),
  ]),
  CategoryGroupSpec(CategoryGroup.events, '🎉 축제·공연', '🎉 Festivals & Shows', '🎉 祭り・公演', '🎉 慶典・演出',
      const Color(0xFF7C3AED), [
    CategorySub('events', '전체', 'All', 'すべて', '全部',
        (it) => it.category == DiscoveryCategory.event || it.category == DiscoveryCategory.culture, DiscoveryCategory.event),
    CategorySub('event', '축제·행사', 'Festivals', '祭り・イベント', '慶典活動', (it) => it.category == DiscoveryCategory.event,
        DiscoveryCategory.event),
    CategorySub('culture', '공연·전시', 'Shows & Exhibitions', '公演・展示', '演出・展覽',
        (it) => it.category == DiscoveryCategory.culture, DiscoveryCategory.culture),
  ]),
  CategoryGroupSpec(CategoryGroup.sights, '🏞️ 볼거리·자연', '🏞️ Sights & Outdoors', '🏞️ 見どころ・自然', '🏞️ 景點・自然',
      const Color(0xFF059669), [
    CategorySub('sights', '전체', 'All', 'すべて', '全部',
        (it) => it.category == DiscoveryCategory.attraction || (it.category == DiscoveryCategory.outdoor && !_isCamp(it)),
        DiscoveryCategory.attraction),
    CategorySub('attraction', '볼거리', 'Sights', '観光名所', '景點', (it) => it.category == DiscoveryCategory.attraction,
        DiscoveryCategory.attraction),
    CategorySub('trail', '🥾 걷기길', '🥾 Trails', '🥾 ウォーキング', '🥾 步道',
        (it) => it.category == DiscoveryCategory.outdoor && _sub(it) == 'trail', DiscoveryCategory.outdoor),
    CategorySub('activity', '🏄 레포츠·체험', '🏄 Activities', '🏄 アクティビティ', '🏄 戶外體驗',
        (it) => it.category == DiscoveryCategory.outdoor && _sub(it) == 'activity', DiscoveryCategory.outdoor),
    CategorySub('forest', '🌲 자연휴양림', '🌲 Forests', '🌲 自然休養林', '🌲 自然休養林',
        (it) => it.category == DiscoveryCategory.outdoor && _sub(it) == 'forest', DiscoveryCategory.outdoor),
  ]),
  CategoryGroupSpec(CategoryGroup.food, '🍲 먹거리·시장', '🍲 Food & Markets', '🍲 グルメ・市場', '🍲 美食・市場',
      const Color(0xFFD97706), [
    CategorySub('foods', '전체', 'All', 'すべて', '全部',
        (it) => it.category == DiscoveryCategory.food || it.category == DiscoveryCategory.market || it.isMarket,
        DiscoveryCategory.food),
    CategorySub('food', '먹거리', 'Food', 'グルメ', '美食', (it) => it.category == DiscoveryCategory.food && !it.isMarket,
        DiscoveryCategory.food),
    CategorySub('market', '🧺 전통시장', '🧺 Markets', '🧺 伝統市場', '🧺 傳統市場',
        (it) => it.category == DiscoveryCategory.market || it.isMarket, DiscoveryCategory.market),
  ]),
  CategoryGroupSpec(CategoryGroup.stays, '🏡 숙소·캠핑', '🏡 Stays & Camping', '🏡 宿泊・キャンプ', '🏡 住宿・露營',
      const Color(0xFFE11D48), [
    CategorySub('stays', '전체', 'All', 'すべて', '全部', (it) => it.category == DiscoveryCategory.stay || _isCamp(it),
        DiscoveryCategory.stay),
    CategorySub('stay', '숙소', 'Stays', '宿泊', '住宿', (it) => it.category == DiscoveryCategory.stay, DiscoveryCategory.stay),
    CategorySub('camping', '⛺ 캠핑장', '⛺ Campsites', '⛺ キャンプ場', '⛺ 露營地', _isCamp, DiscoveryCategory.outdoor),
    CategorySub('glamping', '글램핑·카라반', 'Glamping & Caravans', 'グランピング・キャラバン', '豪華露營・露營車',
        (it) => _isCamp(it) && RegExp('글램핑|카라반').hasMatch((it.raw['camp_type'] ?? '').toString()),
        DiscoveryCategory.outdoor),
    CategorySub('pet', '🐶 반려동물 동반', '🐶 Pet-friendly', '🐶 ペット同伴', '🐶 可帶寵物',
        (it) => _isCamp(it) && it.raw['pet'] == true, DiscoveryCategory.outdoor),
  ]),
  CategoryGroupSpec(CategoryGroup.guides, '📖 공식 관광지도', '📖 Official Guides', '📖 公式ガイド', '📖 官方指南',
      const Color(0xFF2563EB), [
    CategorySub('guides', '전체', 'All', 'すべて', '全部', (it) => it.category == DiscoveryCategory.ebook,
        DiscoveryCategory.ebook),
  ]),
];

CategoryGroupSpec categoryGroupSpec(CategoryGroup g) => kCategoryGroups.firstWhere((s) => s.group == g);

/// 지금 선택: 큰 분류 + 세부 칩. 세부를 고르지 않으면 묶음 전체(첫 칩).
class CategorySelection {
  const CategorySelection(this.group, [this.subKey = '']);

  static const all = CategorySelection(CategoryGroup.all);

  final CategoryGroup group;
  final String subKey;

  CategoryGroupSpec get spec => categoryGroupSpec(group);

  CategorySub get sub => spec.subs.firstWhere((s) => s.key == subKey, orElse: () => spec.subs.first);

  bool get isAll => group == CategoryGroup.all;

  bool matches(DiscoveryItem it) => sub.test(it);

  /// 지도 검색어·캘린더 전환 판단 등 데이터 분류 하나가 필요한 곳에 쓰는 대표 분류
  DiscoveryCategory get primary => sub.single;

  /// 기본 피드에서 빼 두는 항목(전통시장·공연·전시·캠핑장 등)을 이 선택에서는 보여 줘도 되는지
  bool get showsMarkets => group == CategoryGroup.food && sub.key != 'food';
  bool get showsCulture => group == CategoryGroup.events && sub.key != 'event';
  bool get showsListOnlyOutdoor => group == CategoryGroup.sights || group == CategoryGroup.stays;

  /// 캘린더(축제·장날 달력)에서 의미 있는 선택인지
  bool get fitsCalendar => isAll || group == CategoryGroup.events || (group == CategoryGroup.food && sub.key != 'food');

  /// 통계·로그용 이름 (예: 'sights.trail')
  String get logName => isAll ? 'all' : '${group.name}.${sub.key}';
}
