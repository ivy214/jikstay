// 에어비앤비 벤치마킹 기반 표준 Amenity(편의시설) 분류·아이콘 매핑·빠른 필터 유틸리티.
import 'package:flutter/material.dart';

class AmenityFilterTab {
  final String key;
  final String label;
  final IconData icon;
  final List<String> keywords;

  const AmenityFilterTab({
    required this.key,
    required this.label,
    required this.icon,
    required this.keywords,
  });
}

/// 홈 화면 상단 에어비앤비 스타일 아이콘 카테고리 바
const List<AmenityFilterTab> kAmenityFilterTabs = [
  AmenityFilterTab(key: '전체', label: '전체 숙소', icon: Icons.apps_rounded, keywords: []),
  AmenityFilterTab(
    key: '오션뷰·해변',
    label: '오션뷰·해변',
    icon: Icons.waves_rounded,
    keywords: ['오션뷰', '바다', '해변', '해수욕장', '워터프런트'],
  ),
  AmenityFilterTab(
    key: '자쿠지·욕조',
    label: '자쿠지·욕조',
    icon: Icons.hot_tub_rounded,
    keywords: ['자쿠지', '욕조', '스파', '온수풀', '수영장', '반신욕'],
  ),
  AmenityFilterTab(
    key: '독채',
    label: '프라이빗 독채',
    icon: Icons.home_work_outlined,
    keywords: ['독채', '단독', '펜션', '별장', '타운하우스'],
  ),
  AmenityFilterTab(
    key: '풀옵션 주방',
    label: '풀옵션 주방',
    icon: Icons.countertops_outlined,
    keywords: ['주방', '취사', '냉장고', '인덕션', '가스레인지', '전자레인지', '조리도구'],
  ),
  AmenityFilterTab(
    key: '가족·키즈',
    label: '가족·키즈 친화',
    icon: Icons.family_restroom_rounded,
    keywords: ['가족', '어린이', '유아', '키즈', '미끄럼틀', '아기', '저상'],
  ),
  AmenityFilterTab(
    key: '무료주차',
    label: '무료 주차',
    icon: Icons.local_parking_rounded,
    keywords: ['주차', '무료 주차', '전용 주차'],
  ),
  AmenityFilterTab(
    key: '셀프 체크인',
    label: '셀프 체크인',
    icon: Icons.dialpad_rounded,
    keywords: ['셀프 체크인', '도어록', '비대면', '키패드'],
  ),
];

/// 표준 편의시설 카테고리 정렬 우선순위
const List<String> kStandardAmenityCategories = [
  '전망 및 입지',
  '스파 및 부대시설',
  '주차 및 출입',
  '주방 및 다이닝',
  '가족 및 키즈',
  '객실 및 침구',
  '세탁 및 다림질',
  '엔터테인먼트·업무',
  '냉난방 및 안전',
  '기본 편의시설',
];

class AmenityCategoryGroup {
  final String category;
  final List<String> items;

  const AmenityCategoryGroup({required this.category, required this.items});
}

/// 편의시설 명칭에 가장 잘 어울리는 Material 아이콘 반환
IconData amenityIconFor(String rawName) {
  final s = rawName.toLowerCase();
  if (s.contains('오션뷰') || s.contains('바다') || s.contains('해변') || s.contains('워터프런트')) {
    return Icons.waves_rounded;
  }
  if (s.contains('마운틴') || s.contains('산') || s.contains('숲') || s.contains('가든') || s.contains('정원')) {
    return Icons.park_outlined;
  }
  if (s.contains('자쿠지') || s.contains('욕조') || s.contains('스파') || s.contains('반신욕')) {
    return Icons.hot_tub_rounded;
  }
  if (s.contains('수영장') || s.contains('풀빌라') || s.contains('온수풀')) {
    return Icons.pool_rounded;
  }
  if (s.contains('미끄럼틀') || s.contains('놀이') || s.contains('키즈')) {
    return Icons.toys_outlined;
  }
  if (s.contains('유아') || s.contains('어린이') || s.contains('아기')) {
    return Icons.child_care_rounded;
  }
  if (s.contains('바비큐') || s.contains('그릴') || s.contains('불멍')) {
    return Icons.outdoor_grill_outlined;
  }
  if (s.contains('마당') || s.contains('테라스') || s.contains('야외') || s.contains('발코니')) {
    return Icons.deck_outlined;
  }
  if (s.contains('주차')) return Icons.local_parking_rounded;
  if (s.contains('엘리베이터')) return Icons.elevator_outlined;
  if (s.contains('체크인') || s.contains('도어록') || s.contains('키패드')) return Icons.dialpad_rounded;
  if (s.contains('장기') || s.contains('한달')) return Icons.calendar_month_outlined;
  if (s.contains('편의점') || s.contains('마트')) return Icons.storefront_outlined;
  if (s.contains('와이파이') || s.contains('wi-fi') || s.contains('인터넷')) return Icons.wifi_rounded;
  if (s.contains('업무') || s.contains('책상') || s.contains('워케이션')) return Icons.laptop_mac_rounded;
  if (s.contains('tv') || s.contains('티비') || s.contains('빔프로젝터') || s.contains('넷플릭스')) {
    return Icons.tv_rounded;
  }
  if (s.contains('에어컨') || s.contains('냉방')) return Icons.ac_unit_rounded;
  if (s.contains('난방') || s.contains('보일러') || s.contains('온수')) return Icons.thermostat_rounded;
  if (s.contains('세탁기')) return Icons.local_laundry_service_outlined;
  if (s.contains('건조기') || s.contains('건조대')) return Icons.dry_cleaning_outlined;
  if (s.contains('다리미')) return Icons.iron_outlined;
  if (s.contains('드라이어') || s.contains('헤어')) return Icons.air_rounded;
  if (s.contains('샴푸') || s.contains('컨디셔너') || s.contains('클렌저') || s.contains('샤워') || s.contains('비누')) {
    return Icons.soap_outlined;
  }
  if (s.contains('침대') || s.contains('침구') || s.contains('베개') || s.contains('담요') || s.contains('시트')) {
    return Icons.bed_outlined;
  }
  if (s.contains('암막') || s.contains('커튼')) return Icons.blinds_closed_outlined;
  if (s.contains('옷걸이') || s.contains('옷장') || s.contains('보관')) return Icons.checkroom_outlined;
  if (s.contains('냉장고') || s.contains('냉동고')) return Icons.kitchen_outlined;
  if (s.contains('전자레인지') || s.contains('오븐') || s.contains('토스터')) return Icons.microwave_outlined;
  if (s.contains('가스레인지') || s.contains('인덕션') || s.contains('조리') || s.contains('주방') || s.contains('취사')) {
    return Icons.soup_kitchen_outlined;
  }
  if (s.contains('와인잔') || s.contains('커피') || s.contains('주전자') || s.contains('포트')) {
    return Icons.wine_bar_outlined;
  }
  if (s.contains('식기') || s.contains('수저') || s.contains('식탁') || s.contains('그릇')) {
    return Icons.restaurant_outlined;
  }
  if (s.contains('화재') || s.contains('일산화탄소') || s.contains('경보기') || s.contains('소화기')) {
    return Icons.health_and_safety_outlined;
  }
  if (s.contains('카메라') || s.contains('cctv') || s.contains('보안')) return Icons.videocam_outlined;
  if (s.contains('반려동물') || s.contains('애견')) return Icons.pets_outlined;
  if (s.contains('독채')) return Icons.home_outlined;
  return Icons.check_circle_outline_rounded;
}

/// 상세 상단 3대 핵심 하이라이트 아이콘 매핑
IconData highlightIconFor(String keyOrTitle) {
  final k = keyOrTitle.toLowerCase();
  if (k.contains('beach') || k.contains('해변') || k.contains('바다') || k.contains('오션')) return Icons.beach_access_outlined;
  if (k.contains('view') || k.contains('전망') || k.contains('뷰')) return Icons.landscape_outlined;
  if (k.contains('jacuzzi') || k.contains('자쿠지') || k.contains('욕조') || k.contains('미끄럼틀')) return Icons.hot_tub_outlined;
  if (k.contains('family') || k.contains('가족') || k.contains('어린이') || k.contains('호스트')) {
    return Icons.workspace_premium_outlined;
  }
  if (k.contains('checkin') || k.contains('체크인') || k.contains('도어록')) return Icons.door_front_door_outlined;
  if (k.contains('kitchen') || k.contains('주방') || k.contains('취사')) return Icons.countertops_outlined;
  if (k.contains('parking') || k.contains('주차')) return Icons.local_parking_outlined;
  if (k.contains('private') || k.contains('독채') || k.contains('단독')) return Icons.home_work_outlined;
  return Icons.auto_awesome_outlined;
}

String _inferLegacyCategory(String item) {
  final s = item.toLowerCase();
  if (s.contains('뷰') || s.contains('해변') || s.contains('바다') || s.contains('편의점') || s.contains('마당')) {
    return '전망 및 입지';
  }
  if (s.contains('자쿠지') || s.contains('욕조') || s.contains('바비큐') || s.contains('수영장') || s.contains('스파')) {
    return '스파 및 부대시설';
  }
  if (s.contains('주차') || s.contains('엘리베이터') || s.contains('체크인') || s.contains('도어록')) {
    return '주차 및 출입';
  }
  if (s.contains('주방') || s.contains('취사') || s.contains('냉장고') || s.contains('전자레인지') || s.contains('식기')) {
    return '주방 및 다이닝';
  }
  if (s.contains('세탁') || s.contains('건조') || s.contains('다리미')) return '세탁 및 다림질';
  if (s.contains('와이파이') || s.contains('wi-fi') || s.contains('tv') || s.contains('빔') || s.contains('업무')) {
    return '엔터테인먼트·업무';
  }
  if (s.contains('에어컨') || s.contains('난방') || s.contains('경보기')) return '냉난방 및 안전';
  return '기본 편의시설';
}

/// 신규 `amenities_by_category` 와 레거시 `options` 배열을 모두 표준 카테고리 구조로 정규화한다.
List<AmenityCategoryGroup> resolveAmenityGroups(Map<String, dynamic> data) {
  final rawGroups = data['amenities_by_category'];
  final Map<String, List<String>> grouped = {};

  if (rawGroups is List && rawGroups.isNotEmpty) {
    for (final entry in rawGroups) {
      if (entry is! Map) continue;
      final cat = (entry['category'] ?? '기본 편의시설').toString().trim();
      final rawItems = entry['items'];
      if (rawItems is! List) continue;
      final bucket = grouped.putIfAbsent(cat.isEmpty ? '기본 편의시설' : cat, () => []);
      for (final item in rawItems) {
        final s = item.toString().trim();
        if (s.isNotEmpty && !bucket.contains(s)) bucket.add(s);
      }
    }
  }

  if (grouped.isEmpty) {
    final legacyOptions = data['options'];
    if (legacyOptions is List) {
      for (final opt in legacyOptions) {
        final s = opt.toString().trim();
        if (s.isEmpty) continue;
        final cat = _inferLegacyCategory(s);
        final bucket = grouped.putIfAbsent(cat, () => []);
        if (!bucket.contains(s)) bucket.add(s);
      }
    }
  }

  final ordered = <AmenityCategoryGroup>[];
  for (final stdCat in kStandardAmenityCategories) {
    final items = grouped.remove(stdCat);
    if (items != null && items.isNotEmpty) {
      ordered.add(AmenityCategoryGroup(category: stdCat, items: items));
    }
  }
  for (final rest in grouped.entries) {
    if (rest.value.isNotEmpty) {
      ordered.add(AmenityCategoryGroup(category: rest.key, items: rest.value));
    }
  }
  return ordered;
}

/// 상세 페이지 본문에 먼저 보여줄 핵심 편의시설(기본 최대 10개)
List<String> extractTopAmenities(Map<String, dynamic> data, {int limit = 10}) {
  final groups = resolveAmenityGroups(data);
  final out = <String>[];
  // 각 주요 카테고리에서 최대 2개씩 먼저 골라 다양성을 확보한 뒤 나머지를 채운다.
  for (final g in groups) {
    for (final item in g.items.take(2)) {
      if (!out.contains(item)) out.add(item);
      if (out.length >= limit) return out;
    }
  }
  for (final g in groups) {
    for (final item in g.items.skip(2)) {
      if (!out.contains(item)) out.add(item);
      if (out.length >= limit) return out;
    }
  }
  return out;
}

int totalAmenityCount(Map<String, dynamic> data) {
  final seen = <String>{};
  for (final g in resolveAmenityGroups(data)) {
    seen.addAll(g.items);
  }
  return seen.length;
}

List<String> extractUnavailableAmenities(Map<String, dynamic> data) {
  final raw = data['unavailable_amenities'];
  if (raw is! List) return const [];
  return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toSet().toList();
}

/// 홈 화면 아이콘 필터 탭 일치 여부 판정
bool matchesAmenityTab(Map<String, dynamic> data, String tabKey) {
  if (tabKey == '전체' || tabKey.isEmpty) return true;
  final tab = kAmenityFilterTabs.where((t) => t.key == tabKey).firstOrNull;
  if (tab == null || tab.keywords.isEmpty) return true;

  final parts = <String>[
    (data['title'] ?? '').toString(),
    (data['accommodation_type'] ?? '').toString(),
    (data['editorial_story'] ?? '').toString(),
    ...((data['options'] as List?) ?? const []).map((e) => e.toString()),
    ...((data['summary_points'] as List?) ?? const []).map((e) => e.toString()),
  ];
  for (final g in resolveAmenityGroups(data)) {
    parts.addAll(g.items);
  }
  final rules = data['house_rules'];
  if (rules is Map && rules['self_check_in'] != null) {
    parts.add(rules['self_check_in'].toString());
  }
  final haystack = parts.join(' ').toLowerCase();
  return tab.keywords.any((kw) => haystack.contains(kw.toLowerCase()));
}
