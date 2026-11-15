// 홈 검색어 해석 · 매칭 · 관련도.
// - "전북 남원" 처럼 띄어 쓴 검색어는 낱말마다 따로 찾는다(모든 낱말이 맞아야 결과).
// - "남원여행" "남원 숙소" "남원맛집" 의 여행·숙소·맛집 같은 말은 검색어에서 떼어 내고, 숙소·맛집·축제·볼거리는 분류로 거른다.
// - 시·도 이름(전북·전라북도·전북특별자치도…)은 시·도 조건으로 해석한다.
// - "남원" 이 남원시(전북)와 남원읍(제주) 둘 다에 걸릴 때는 시·군 이름이 맞는 쪽을 앞에 둔다.
import 'discovery_models.dart';

class ParsedSearchQuery {
  /// 본문에서 찾을 낱말 (소문자)
  final List<String> terms;

  /// 검색어에 시·도 이름이 있으면 정규화한 시·도 키 (예: 전북)
  final String? province;

  /// 원래 입력한 시·도 낱말 (경기 광주시처럼 같은 이름의 시가 있을 때 본문 매칭용)
  final String? provinceWord;

  /// 검색어에 숙소·맛집·축제·볼거리 같은 분류 낱말이 있으면 그 분류
  final DiscoveryCategory? category;

  const ParsedSearchQuery({required this.terms, this.province, this.provinceWord, this.category});

  bool get isEmpty => terms.isEmpty && province == null && category == null;
}

const Map<String, String> _kProvinceAliases = {
  '서울': '서울', '서울시': '서울', '서울특별시': '서울',
  '부산': '부산', '부산시': '부산', '부산광역시': '부산',
  '대구': '대구', '대구시': '대구', '대구광역시': '대구',
  '인천': '인천', '인천시': '인천', '인천광역시': '인천',
  '광주': '광주', '광주광역시': '광주',
  '대전': '대전', '대전시': '대전', '대전광역시': '대전',
  '울산': '울산', '울산시': '울산', '울산광역시': '울산',
  '세종': '세종', '세종시': '세종', '세종특별자치시': '세종',
  '경기': '경기', '경기도': '경기',
  '강원': '강원', '강원도': '강원', '강원특별자치도': '강원',
  '충북': '충북', '충청북도': '충북',
  '충남': '충남', '충청남도': '충남',
  '전북': '전북', '전라북도': '전북', '전북특별자치도': '전북',
  '전남': '전남', '전라남도': '전남',
  '경북': '경북', '경상북도': '경북',
  '경남': '경남', '경상남도': '경남',
  '제주': '제주', '제주도': '제주', '제주특별자치도': '제주',
};

const Map<String, DiscoveryCategory> _kCategoryWords = {
  '숙소': DiscoveryCategory.stay,
  '숙박': DiscoveryCategory.stay,
  '잘곳': DiscoveryCategory.stay,
  '맛집': DiscoveryCategory.food,
  '먹거리': DiscoveryCategory.food,
  '음식': DiscoveryCategory.food,
  '식당': DiscoveryCategory.food,
  '축제': DiscoveryCategory.event,
  '행사': DiscoveryCategory.event,
  '볼거리': DiscoveryCategory.attraction,
  '명소': DiscoveryCategory.attraction,
  '관광지': DiscoveryCategory.attraction,
};

// 의미 없이 붙는 말 — 떼어 내고 버린다. 긴 말을 먼저 검사한다.
const List<String> _kNoiseWords = [
  '가볼만한곳', '가볼만한', '당일치기', '1박2일', '여행지', '여행코스', '여행', '관광', '투어', '나들이',
  '근처', '주변', '코스', '추천', '일정',
];

/// 낱말 끝에 붙은 여행·숙소 같은 말을 떼어 낸다. 남는 말이 두 글자 미만이면 떼지 않는다.
(String, DiscoveryCategory?, bool) _splitSuffix(String token) {
  for (final w in _kNoiseWords) {
    if (token.length - w.length >= 2 && token.endsWith(w)) {
      return (token.substring(0, token.length - w.length), null, true);
    }
  }
  for (final e in _kCategoryWords.entries) {
    if (token.length - e.key.length >= 2 && token.endsWith(e.key)) {
      return (token.substring(0, token.length - e.key.length), e.value, true);
    }
  }
  return (token, null, false);
}

ParsedSearchQuery parseSearchQuery(String raw) {
  final tokens = raw
      .toLowerCase()
      .split(RegExp(r'[\s,·/|]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  final terms = <String>[];
  String? province;
  String? provinceWord;
  DiscoveryCategory? category;

  for (var token in tokens) {
    // "남원여행맛집" 처럼 여러 개가 붙어도 떼어 낸다
    while (true) {
      final (rest, cat, changed) = _splitSuffix(token);
      if (!changed) break;
      category ??= cat;
      token = rest;
    }
    if (_kNoiseWords.contains(token)) continue;
    final cat = _kCategoryWords[token];
    if (cat != null) {
      category ??= cat;
      continue;
    }
    final prov = _kProvinceAliases[token];
    if (prov != null && province == null) {
      province = prov;
      provinceWord = token;
      continue;
    }
    terms.add(token);
  }
  return ParsedSearchQuery(terms: terms, province: province, provinceWord: provinceWord, category: category);
}

String _haystack(DiscoveryItem it) =>
    '${it.title} ${it.province} ${it.regionLabel} ${it.address} ${it.subtitle} ${it.couponTitle}'.toLowerCase();

bool _isCityLevelMatch(DiscoveryItem it, String term) {
  final place = '${it.regionLabel} ${it.address}';
  return place.contains('$term시') ||
      place.contains('$term군') ||
      place.contains('$term구') ||
      // "남원시" 처럼 시·군까지 써서 검색한 경우
      ((term.endsWith('시') || term.endsWith('군')) && place.contains(term));
}

/// 검색어와 맞지 않으면 null, 맞으면 관련도 (클수록 앞).
/// 시·군 이름이 맞으면 3점, 제목에 있으면 2점, 그 밖(읍·면·설명)에서 맞으면 1점.
int? searchRelevance(DiscoveryItem it, ParsedSearchQuery q) {
  if (q.category != null && it.category != q.category) return null;
  final hay = _haystack(it);
  var score = 0;
  if (q.province != null) {
    if (it.province == q.province) {
      score += 1;
    } else if (!hay.contains(q.provinceWord!)) {
      return null;
    }
  }
  for (final term in q.terms) {
    if (!hay.contains(term)) return null;
    if (_isCityLevelMatch(it, term)) {
      score += 3;
    } else if (it.title.toLowerCase().contains(term)) {
      score += 2;
    } else {
      score += 1;
    }
  }
  return score;
}

/// 검색 결과에서 가장 많이 나온 시·도 (오늘의 스토리를 검색 지역에 맞추는 데 쓴다)
String? dominantProvince(Iterable<DiscoveryItem> items, {int sample = 12}) {
  final counts = <String, int>{};
  for (final it in items.take(sample)) {
    counts[it.province] = (counts[it.province] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
