// 초기 로딩 경량화: 첫 화면은 data/hub/core.json(목록·카드용)만 받고,
// 본문 문단·네이버 방문기·탐방정보·갤러리 같은 상세 필드는 상세 화면을 열 때
// 해당 시·도의 data/hub/details_{code}.json 을 1회만 받아 합친다. (backend/split_hub.py 가 생성)
import 'discovery_models.dart';
import 'web_utils.dart';

/// backend/split_hub.py 의 PROVINCE_CODES 와 같아야 한다.
const Map<String, String> kProvinceDetailCodes = {
  '서울': 'seoul', '부산': 'busan', '대구': 'daegu', '인천': 'incheon', '광주': 'gwangju',
  '대전': 'daejeon', '울산': 'ulsan', '세종': 'sejong', '경기': 'gyeonggi', '강원': 'gangwon',
  '충북': 'chungbuk', '충남': 'chungnam', '전북': 'jeonbuk', '전남': 'jeonnam', '경북': 'gyeongbuk',
  '경남': 'gyeongnam', '제주': 'jeju',
};

/// 첫 화면용 허브 JSON. 분할 파일이 없으면(로컬 개발 등) 원본 전체 파일로 대체한다.
Future<Map<String, dynamic>?> fetchHubCore({String cacheBust = ''}) async {
  final q = cacheBust.isEmpty ? '' : '?v=$cacheBust';
  final core = await fetchWebJson('data/hub/core.json$q');
  if (core != null) return core;
  HubDetailStore.splitAvailable = false;
  return fetchWebJson('data/public_travel_hub.json$q');
}

class HubDetailStore {
  HubDetailStore._();

  /// core.json 대신 원본 전체 파일을 받은 경우 상세 파일이 없으므로 조회하지 않는다.
  static bool splitAvailable = true;

  static final Map<String, Map<String, dynamic>> _byCode = {};
  static final Map<String, Future<Map<String, dynamic>>> _inflight = {};

  /// 테스트·오프라인 시드용으로 상세 데이터를 직접 넣는다.
  static void seed(String code, Map<String, dynamic> details) => _byCode[code] = details;

  static void clearForTest() {
    _byCode.clear();
    _inflight.clear();
    splitAvailable = true;
  }

  static Future<Map<String, dynamic>> _load(String code) {
    final cached = _byCode[code];
    if (cached != null) return Future.value(cached);
    return _inflight.putIfAbsent(code, () async {
      final data = await fetchWebJson('data/hub/details_$code.json') ?? const <String, dynamic>{};
      _byCode[code] = data;
      _inflight.remove(code);
      return data;
    });
  }

  static Future<Map<String, dynamic>?> detailFor(String id, String province) async {
    final code = kProvinceDetailCodes[province] ?? 'etc';
    if (!splitAvailable && !_byCode.containsKey(code)) return null;
    final all = await _load(code);
    final d = all[id];
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }
}

/// 상세 필드가 분리된 항목이면 해당 시·도 상세 파일을 합쳐 완전한 항목을 돌려준다.
/// 실시간 통계(평점·클릭·쿠폰)는 현재 항목 값을 유지한다.
Future<DiscoveryItem> hydrateDiscoveryItem(DiscoveryItem item) async {
  if (item.raw['has_details'] != true) return item;
  final detail = await HubDetailStore.detailFor(item.id, item.province);
  if (detail == null || detail.isEmpty) return item;
  final merged = <String, dynamic>{...item.raw, ...detail}..remove('has_details');
  final parsed = parseSpotJson(merged, fallbackCategory: item.category);
  if (parsed == null) return item;
  return parsed.copyWithStats(
    outboundClicks: item.outboundClicks,
    reviewCount: item.reviewCount,
    scoreSum: item.scoreSum,
    isSponsored: item.isSponsored,
    couponTitle: item.couponTitle,
  );
}
