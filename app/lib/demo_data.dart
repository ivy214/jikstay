// ?demo=1 또는 ?id=stay_demo_... 진입 시 사용하는 레퍼런스 기반 미리보기 데이터.
// 분석한 해운대·송정 5층 오션뷰 레지던스의 실제 구조(54개 편의시설·7개 미제공 시설·객실 스펙·이용규칙·온수욕조 이벤트)를
// 직스테이 직거래 모델에 맞춰 검증용으로 구성하였다.

const String kDemoHaeundaeId = 'stay_demo_haeundae';

final Map<String, Map<String, dynamic>> kDemoListingsMap = {
  kDemoHaeundaeId: {
    'listing_id': kDemoHaeundaeId,
    'is_sponsored': true,
    'status': 'active',
    'title': '5층 파노라마 오션뷰 | 송정·해운대 해변 10초 자쿠지 레지던스',
    'i18n': {
      'en': {
        'title': '5F Oceanfront Panorama | Songjeong Beach Jacuzzi Residence (Busan)',
        'summary': '10-second walk to Songjeong Beach with private ocean-view jacuzzi & family loft slide bed. 0% booking fee.',
      },
      'ja': {
        'title': '5階オーシャンビュー｜松亭ビーチ徒歩10秒・大型ジャグジー宿（釜山）',
        'summary': '松亭海水浴場まで徒歩10秒。海を望むジャグジーとキッズ滑り台ベッド完備の公認レジデンス。',
      },
      'zh': {
        'title': '5樓海景第一排｜釜山松亭海灘步行10秒大型按摩浴缸美宿',
        'summary': '距離松亭海水浴場僅10秒步程，配備海景大型浴缸與親子溜滑梯床鋪，免平台手續費直訂。',
      },
    },
    'region_depth1': '부산광역시',
    'region_depth2': '해운대구 송정동',
    'accommodation_type': '오션뷰 레지던스 전체',
    'capacity_standard': 4,
    'capacity_max': 7,
    'license_type': '일반/생활숙박업',
    'license_number': '제6-58호 (해운대구)',
    'promo_title': '선착순 온수욕조 무료 이벤트 (3만 원 상당)',
    'promo_detail': '직거래 문의 메시지로 사전 신청 시 대형 자쿠지 온수 이용료(정상가 30,000원)를 무료로 지원해 드립니다.',
    'room_specs': {
      'bedrooms': 1,
      'beds': 2,
      'bed_summary': '저상형 퀸사이즈 침대 2개 + 어린이 미끄럼틀 복층 침대',
      'bathrooms': 1,
      'floor_info': '5층 단독 사용 (엘리베이터 완비 · 1층 이마트24 편의점)',
    },
    'editorial_story':
        '문을 여는 순간 전면 통유리창 너머로 송정해수욕장의 에메랄드빛 파도가 한눈에 펼쳐지는 5층 오션뷰 스테이입니다. '
        '유럽 감성의 따스한 우드·아이보리 톤 공간 안에 바다를 바라보며 반신욕을 즐기는 대형 자쿠지와 아이들이 열광하는 실내 미끄럼틀 복층 침대를 함께 담았습니다. '
        '해변 백사장까지 걸어서 단 10초, 건물 1층 편의점과 도보권 해변 카페거리까지 갖춰 가족 여행과 호캉스 모두에 완벽한 하루를 선사합니다.',
    'summary_points': [
      '송정해수욕장 백사장 바로 앞 도보 10초 · 전면 통창 파노라마 오션뷰',
      '바다 전망 대형 자쿠지 & 실내 미끄럼틀 복층침대 + 어린이 식기 완비',
      '1층 이마트24 편의점 입점 · 건물 내 무료 주차 · 해운대 차량 10분',
    ],
    'highlights': [
      {
        'icon_key': 'beach',
        'title': '송정해수욕장 백사장 도보 10초',
        'subtitle': '엘리베이터를 내려 건물 밖으로 나오면 바로 해변 산책로와 맛집·카페거리가 이어집니다.',
      },
      {
        'icon_key': 'jacuzzi',
        'title': '오션뷰 대형 자쿠지 & 실내 미끄럼틀',
        'subtitle': '통창 바다 전망 반신욕 자쿠지와 미끄럼틀 복층 침대가 있어 아이 동반 가족 만족도가 높습니다.',
      },
      {
        'icon_key': 'checkin',
        'title': '비대면 셀프 체크인 & 세심한 키즈 배려',
        'subtitle': '스마트 도어록으로 간편하게 입실하며, 유아용 식탁의자와 어린이 식기가 준비되어 있습니다.',
      },
    ],
    'options': [
      '오션뷰',
      '대형 욕조',
      '자쿠지',
      '실내 미끄럼틀',
      '해변 인접',
      '무료 주차',
      '풀옵션 주방',
      '셀프 체크인',
      '유아용 식탁의자',
      '무선 인터넷',
    ],
    'amenities_by_category': [
      {
        'category': '전망 및 입지',
        'items': ['파노라마 오션뷰', '해변으로 바로 연결 (도보 10초)', '워터프런트(해변가 위치)', '건물 1층 이마트24 편의점'],
      },
      {
        'category': '스파 및 부대시설',
        'items': ['통창 바다전망 대형 욕조(자쿠지)', '온수 완비', '실내 미끄럼틀 복층 구조', '공용 뒷마당', '야외 식사 공간'],
      },
      {
        'category': '주차 및 출입',
        'items': ['건물 부지 내 무료 주차', '엘리베이터', '셀프 체크인 (스마트 도어록 키패드)', '장기 숙박 가능 (28일 이상)', '전문 청소 지원'],
      },
      {
        'category': '주방 및 다이닝',
        'items': [
          '취사 가능 주방',
          '냉장고',
          '냉동고',
          '소형 냉장고',
          '전자레인지',
          '가스레인지',
          '전기주전자',
          '토스터',
          '기본 조리도구 (냄비·팬·오일·소금·후추)',
          '식기류 및 수저 세트',
          '와인잔',
          '다이닝 식탁',
        ],
      },
      {
        'category': '가족 및 키즈',
        'items': ['저상형 퀸사이즈 침대 2개', '유아용 식탁의자', '어린이용 식기 세트', '실내 미끄럼틀 침대'],
      },
      {
        'category': '객실 및 침구',
        'items': [
          '필수품 (수건·침대시트·비누·화장지)',
          '호텔식 침구',
          '여분의 베개와 담요',
          '암막 커튼',
          '옷걸이',
          '옷 보관 공간(옷장)',
          '헤어드라이어',
          '샴푸 · 컨디셔너 · 보디클렌저 · 샤워젤',
        ],
      },
      {
        'category': '세탁 및 다림질',
        'items': ['건조대', '다리미'],
      },
      {
        'category': '엔터테인먼트·업무',
        'items': ['스마트 TV', '초고속 무선 인터넷 (Wi-Fi)', '업무 전용 공간 (테이블 및 의자)'],
      },
      {
        'category': '냉난방 및 안전',
        'items': ['시스템 에어컨', '바닥 난방', '화재경보기', '일산화탄소 경보기', '건물 외부 보안 CCTV'],
      },
    ],
    'unavailable_amenities': [
      '세탁기 없음',
      '건조기 없음',
      '침실 독립 문 없음 (개방형 오픈 플랜 구조)',
      '단독 전용 출입문 없음 (엘리베이터 복도식 출입)',
      '반려동물 동반 입실 불가',
      '실내 벽난로 없음',
      '숙소 내부 보안 카메라 없음 (외부 복도만 운영)',
    ],
    'house_rules': {
      'check_in_time': '15:00 이후',
      'check_out_time': '11:00 이전',
      'self_check_in': '스마트 도어록 비밀번호 입실 (당일 안내)',
      'quiet_hours': '22:00 ~ 08:00 (매너타임 엄수)',
      'smoking_policy': '실내 절대 금연 (전자담배 포함 · 위반 시 특수청소비 10만 원)',
      'pet_policy': '반려동물 동반 입실 불가',
      'extra_rules': [
        '예약된 인원 외 방문객 입실 불가 (외부 CCTV 확인 시 즉시 퇴실 조치)',
        '미성년자 단독 예약·투숙 절대 불가 (보호자 동반 필수)',
        '염색약·와인·음식물 등으로 침구·타일·가구 오염/파손 시 실비 복구비 청구',
      ],
    },
    'location_info': {
      'display_address': '부산광역시 해운대구 송정해변로 (송정해수욕장 백사장 바로 앞)',
      'nearby_spots': '송정해수욕장 도보 10초 · 건물 1층 이마트24 · 송정 서핑거리 & 해변 카페 도보 2분 · 해운대/롯데월드 차량 10분',
      'parking_note': '건물 부지 내 무료 주차 지원 (만차 시 인근 공영주차장 안내)',
    },
    'pricing': {
      'nightly_min': 249600,
      'weekly_price': 1490000,
      'monthly_price': 4200000,
      'price_note': '금·토 주말 및 성수기 요금 변동 가능 · 기준 4인 (최대 7인, 인원 추가 시 호스트 문의)',
    },
    'images': [
      {
        'url': 'https://a0.muscache.com/im/pictures/hosting/Hosting-1581124778614232116/original/035ff800-9b50-4e23-8ab1-f33190c771eb.jpeg',
        'space_tag': '외관/뷰',
        'caption': '통유리 파노라마 송정 오션뷰 거실',
      },
      {
        'url': 'https://a0.muscache.com/im/pictures/hosting/Hosting-1581124778614232116/original/4bb0f142-4bcb-43dd-812d-d1848988d8e1.jpeg',
        'space_tag': '자쿠지/부대시설',
        'caption': '바다를 보며 즐기는 대형 온수 자쿠지',
      },
      {
        'url': 'https://a0.muscache.com/im/pictures/hosting/Hosting-1581124778614232116/original/47676432-8c9c-4fad-9c0d-6af9a05f79cc.jpeg',
        'space_tag': '침실',
        'caption': '저상형 퀸베드 2개 & 아늑한 조명',
      },
      {
        'url': 'https://a0.muscache.com/im/pictures/hosting/Hosting-1581124778614232116/original/e0075b76-6b1e-42fa-809a-3f81ce3b1b8f.jpeg',
        'space_tag': '주방',
        'caption': '유럽 감성 다이닝 식탁과 풀옵션 주방',
      },
      {
        'url': 'https://a0.muscache.com/im/pictures/hosting/Hosting-1581124778614232116/original/c528179f-ba4c-42d9-895f-cd1ea9b4f65a.jpeg',
        'space_tag': '거실',
        'caption': '실내 미끄럼틀 복층 침대 & 플레이 공간',
      },
    ],
    'direct_booking_url': 'https://booking.naver.com/',
    'source_blog_url': 'https://blog.naver.com/',
    'outbound_clicks': 128,
    'review_count': 2,
    'score_sum': 10,
    'demo_reviews': [
      {
        'nickname': '부산가족여행',
        'score': 5,
        'visit_tag': '가족여행',
        'comment': '창문 열자마자 송정 바다가 한눈에 들어오고 아이들이 실내 미끄럼틀을 정말 좋아했어요!',
        'lang': 'ko',
        'date_label': '2026.11.10',
      },
      {
        'nickname': 'Emily',
        'score': 5,
        'visit_tag': '커플·우정',
        'comment': 'Direct booking was super easy and the oceanfront jacuzzi view was unforgettable.',
        'lang': 'en',
        'date_label': '2026.11.02',
      },
    ],
    'created_at': 1763100000000,
  },
  'stay_demo_jeju': {
    'listing_id': 'stay_demo_jeju',
    'status': 'active',
    'title': '애월 돌담 너머 잔디마당 독채 | 워케이션 & 한달살기 스테이',
    'region_depth1': '제주특별자치도',
    'region_depth2': '제주시 애월읍',
    'accommodation_type': '프라이빗 독채 민박',
    'capacity_standard': 2,
    'capacity_max': 4,
    'license_type': '농어촌민박업',
    'license_number': '제2026-제주애월-042호',
    'promo_title': '7박 이상 연박 시 공항 픽업 또는 웰컴 원두 증정',
    'promo_detail': '직거래로 일주일·한달살기 예약 시 호스트가 직접 로스팅한 드립백 세트를 드립니다.',
    'room_specs': {
      'bedrooms': 2,
      'beds': 2,
      'bed_summary': '퀸사이즈 침대 1개 + 슈퍼싱글 침대 1개',
      'bathrooms': 1,
      'floor_info': '단층 독채 전체 및 단독 잔디마당 40평',
    },
    'editorial_story':
        '조용한 애월 중산간 돌담길 끝자락, 오직 한 팀만 머무는 제주 전통 돌집 리모델링 독채입니다. '
        '세탁기와 건조기, 광폭 원목 데스크가 완비되어 있어 일주일 살기와 워케이션 게스트에게 특히 사랑받습니다.',
    'summary_points': [
      '단독 잔디마당과 감귤나무 뷰를 독점하는 프라이빗 독채',
      '세탁기·건조기·풀옵션 주방·모니터 데스크 완비 (한달살기 최적화)',
      '곽지·협재 해수욕장 차량 12분 · 전용 주차 2대',
    ],
    'highlights': [
      {'icon_key': 'private', 'title': '우리 일행만 쓰는 돌담 독채', 'subtitle': '이웃 간섭 없이 단독 마당과 테라스를 온전히 누립니다.'},
      {'icon_key': 'kitchen', 'title': '세탁·건조기 & 풀옵션 주방', 'subtitle': '장기 체류에 필수적인 드럼세탁기, 건조기, 3구 인덕션을 갖췄습니다.'},
      {'icon_key': 'parking', 'title': '대문 앞 전용 주차 2대', 'subtitle': '짐 옮기기 편한 평지 전용 주차 공간을 무료로 제공합니다.'},
    ],
    'options': ['독채', '마당', '세탁기', '건조기', '풀옵션 주방', '업무 전용 공간', '무료 주차', '셀프 체크인'],
    'amenities_by_category': [
      {'category': '전망 및 입지', 'items': ['돌담 가든뷰', '단독 잔디마당']},
      {'category': '주차 및 출입', 'items': ['전용 무료 주차 2대', '셀프 체크인 (도어록)', '장기 숙박 가능']},
      {'category': '주방 및 다이닝', 'items': ['취사 가능 주방', '대형 냉장고', '3구 인덕션', '전자레인지', '발뮤다 토스터', '조리도구·식기류']},
      {'category': '세탁 및 다림질', 'items': ['드럼 세탁기', '건조기', '다리미']},
      {'category': '엔터테인먼트·업무', 'items': ['초고속 Wi-Fi', '업무 전용 원목 데스크 & 체어', '빔프로젝터']},
      {'category': '냉난방 및 안전', 'items': ['시스템 에어컨', '난방', '화재경보기', '일산화탄소 경보기', '소화기']},
    ],
    'unavailable_amenities': ['반려동물 동반 불가', '실내 흡연 불가'],
    'house_rules': {
      'check_in_time': '16:00 이후',
      'check_out_time': '11:00 이전',
      'self_check_in': '스마트 도어록 비대면 입실',
      'quiet_hours': '21:30 ~ 08:00 (조용한 마을 에티켓)',
      'smoking_policy': '전 구역 금연',
      'pet_policy': '반려동물 동반 불가',
      'extra_rules': ['마당 내 직화 숯불 바비큐 불가 (화재 예방)'],
    },
    'location_info': {
      'display_address': '제주특별자치도 제주시 애월읍 중산간서로 인근',
      'nearby_spots': '애월 하나로마트 차량 5분 · 한담해안산책로 차량 10분 · 제주공항 차량 25분',
      'parking_note': '독채 대문 앞 전용 주차공간 2대 무료',
    },
    'pricing': {
      'nightly_min': 180000,
      'weekly_price': 1050000,
      'monthly_price': 2900000,
      'price_note': '한달살기 공과금 별도 정산 없음(포함가)',
    },
    'images': [
      {
        'url': 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '외관/뷰',
        'caption': '햇살 가득한 단독 마당과 독채 외관',
      },
      {
        'url': 'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '거실',
        'caption': '우드톤 채광 거실과 통창 정원뷰',
      },
      {
        'url': 'https://images.unsplash.com/photo-1556911220-bff31c812dba?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '주방',
        'caption': '한달살기에 부족함 없는 풀옵션 주방',
      },
      {
        'url': 'https://images.unsplash.com/photo-1616594039964-ae9021a400a0?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '침실',
        'caption': '호텔식 침구와 암막 커튼 마스터룸',
      },
      {
        'url': 'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '욕실',
        'caption': '모던하고 청결한 건식 세면대 & 욕실',
      },
    ],
    'direct_booking_url': 'https://pf.kakao.com/',
    'source_blog_url': 'https://blog.naver.com/',
    'outbound_clicks': 84,
    'created_at': 1763050000000,
  },
  'stay_demo_gyeongju': {
    'listing_id': 'stay_demo_gyeongju',
    'status': 'active',
    'title': '황리단길 고요한 중정 독채 한옥 | 노천 히노끼 자쿠지 스테이',
    'region_depth1': '경상북도',
    'region_depth2': '경주시 황남동',
    'accommodation_type': '독채 한옥 스테이',
    'capacity_standard': 2,
    'capacity_max': 4,
    'license_type': '한옥체험업',
    'license_number': '제2026-경주-019호',
    'promo_title': '평일 직거래 예약 시 다도 웰컴 티세트 무료 제공',
    'promo_detail': '호스트 직거래 링크로 평일 숙박 신청 시 수제 다과와 전통 차 세트를 준비해 드립니다.',
    'room_specs': {
      'bedrooms': 1,
      'beds': 2,
      'bed_summary': '퀸 매트리스 2개',
      'bathrooms': 1,
      'floor_info': '단층 독채 한옥 및 프라이빗 중정',
    },
    'editorial_story':
        '기와지붕 처마 아래 계절의 바람이 머무는 황남동 독채 한옥입니다. '
        '서까래의 고즈넉한 멋은 살리고 사계절 따뜻한 노천 히노끼 자쿠지와 현대식 냉난방을 더해 편안한 쉼을 완성했습니다.',
    'summary_points': [
      '황리단길·대릉원 도보 5분 거리이면서 골목 안쪽 고요한 독채',
      '사계절 프라이빗 노천 히노끼 자쿠지 무료 이용',
      '전용 주차 1대 완비 · 비대면 셀프 체크인',
    ],
    'highlights': [
      {'icon_key': 'jacuzzi', 'title': '프라이빗 노천 히노끼 자쿠지', 'subtitle': '추가 요금 없이 밤하늘을 보며 따뜻한 반신욕을 즐길 수 있습니다.'},
      {'icon_key': 'private', 'title': '황리단길 도보 5분 독채 한옥', 'subtitle': '대릉원·첨성대 산책 코스와 가까우며 우리 일행만 단독 사용합니다.'},
      {'icon_key': 'checkin', 'title': '전용 주차 & 셀프 체크인', 'subtitle': '황남동에서 귀한 숙소 바로 앞 전용 주차장을 제공합니다.'},
    ],
    'options': ['독채', '자쿠지', '마당', '무료 주차', '셀프 체크인', '와이파이', '다도세트'],
    'amenities_by_category': [
      {'category': '스파 및 부대시설', 'items': ['노천 히노끼 자쿠지', '단독 한옥 중정 마당', '툇마루 다도 공간']},
      {'category': '주차 및 출입', 'items': ['숙소 앞 전용 무료 주차 1대', '셀프 체크인 (도어록)']},
      {'category': '주방 및 다이닝', 'items': ['냉장고', '전자레인지', '발뮤다 전기포트', '드립커피 & 다도 세트', '와인잔']},
      {'category': '객실 및 침구', 'items': ['구스다운 침구', '수건·어메니티 완비', '다이슨 헤어드라이어']},
      {'category': '냉난방 및 안전', 'items': ['시스템 에어컨 2대', '온돌 바닥 난방', '화재경보기', '소화기']},
    ],
    'unavailable_amenities': ['육류·생선 조리 불가 (간단 데우기만 가능)', '세탁기 없음', '반려동물 동반 불가'],
    'house_rules': {
      'check_in_time': '15:00 이후',
      'check_out_time': '11:00 이전',
      'self_check_in': '스마트 도어록 키패드',
      'quiet_hours': '22:00 ~ 08:00',
      'smoking_policy': '목조 한옥 특성상 전 구역 절대 금연',
      'pet_policy': '반려동물 동반 불가',
      'extra_rules': ['화재 예방을 위해 촛불·향·휴대용 버너 반입 금지'],
    },
    'location_info': {
      'display_address': '경상북도 경주시 황남동 (황리단길·대릉원 도보 5분)',
      'nearby_spots': '황리단길 메인거리 도보 4분 · 대릉원 도보 6분 · 첨성대 도보 12분',
      'parking_note': '대문 옆 전용 주차 구획 1대 무료',
    },
    'pricing': {
      'nightly_min': 220000,
      'weekly_price': 1320000,
      'monthly_price': null,
      'price_note': '히노끼 자쿠지 온수 무료 포함',
    },
    'images': [
      {
        'url': 'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '침실',
        'caption': '서까래 아래 포근한 구스다운 침실',
      },
      {
        'url': 'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '자쿠지/부대시설',
        'caption': '따뜻한 김이 피어오르는 히노끼 스파',
      },
      {
        'url': 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '거실',
        'caption': '중정 햇살이 들어오는 다도 마루',
      },
      {
        'url': 'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=1200&q=80',
        'space_tag': '욕실',
        'caption': '모던하게 리모델링된 호텔식 욕실',
      },
    ],
    'direct_booking_url': 'https://booking.naver.com/',
    'source_blog_url': 'https://blog.naver.com/',
    'outbound_clicks': 63,
    'created_at': 1763000000000,
  },
  'stay_demo_pub_seoul': {
    'listing_id': 'stay_demo_pub_seoul',
    'src': 'mois',
    'is_sponsored': false,
    'status': 'active',
    'title': '연남 아틀리에 하우스 (공공API 선별 예시)',
    'region_depth1': '서울특별시',
    'region_depth2': '마포구 연남동',
    'accommodation_type': '외국인 전용 도시민박',
    'license_type': '외국인관광도시민박업',
    'license_number': '공공데이터 확인 (마포-2025-018)',
    'room_specs': {
      'bedrooms': 3,
      'bathrooms': 2,
      'floor_info': '단독주택 2층 · 연면적 약 85㎡',
    },
    'editorial_story':
        '서울특별시 마포구 연남동에 위치한 합법 등록 외국인관광도시민박업 숙소입니다. '
        '행정안전부 공공 인허가 데이터를 기반으로 자동 선별되었으며, 아래 네이버 블로그 후기 링크와 지도 바로가기를 통해 '
        '방문기와 예약 창구를 확인하실 수 있습니다.',
    'summary_points': [
      "행정안전부 지방인허가 데이터 기준 '외국인관광도시민박업' 영업/정상 확인 업소",
      '위치: 서울특별시 마포구 연남동 경의선숲길 인접',
      '네이버 블로그 언급·후기 28건 검색됨 (원문 링크 바로가기 지원)',
    ],
    'highlights': [
      {
        'icon_key': 'verified',
        'title': '외국인관광도시민박업 공공 인허가 확인',
        'subtitle': '지자체 인허가 데이터에서 정상 영업 상태가 확인된 외국인 전용 합법 숙소입니다.',
      },
      {
        'icon_key': 'location',
        'title': '서울 마포구 연남동 · 홍대입구역 인접',
        'subtitle': '공항철도 홍대입구역 및 연트럴파크 도보권 로컬 스테이',
      },
    ],
    'options': ['지자체 영업신고 적법 업소', '소화기 비치 확인(공공데이터)', '화재경보기(단독경보형감지기)', '조식 제공 가능'],
    'amenities_by_category': [
      {'category': '주방 및 다이닝', 'items': ['조식 제공 가능']},
      {'category': '냉난방 및 안전', 'items': ['지자체 영업신고 적법 업소', '소화기 비치 확인(공공데이터)', '화재경보기(단독경보형감지기)']},
    ],
    'unavailable_amenities': [],
    'house_rules': {
      'check_in_time': '호스트 예약창구 확인',
      'check_out_time': '호스트 예약창구 확인',
      'smoking_policy': '실내 금연 권장',
      'pet_policy': '사전 문의 필수',
      'extra_rules': [
        '본 숙소는 행정안전부 공공데이터 및 공개 관광정보를 바탕으로 자동 구성되었습니다.',
      ],
    },
    'location_info': {
      'display_address': '서울특별시 마포구 성미산로 일대 (연남동)',
      'nearby_spots': '홍대입구역 공항철도 · 경의선숲길 · 연남동 카페거리',
      'parking_note': '인근 공영주차장 이용 권장',
    },
    'pricing': {},
    'images': [],
    'naver_blog_total': 28,
    'naver_reviews': [
      {
        'title': '서울 연남동 감성 도시민박 외국인 친구 숙소 추천 방문기',
        'summary': '홍대입구역에서 걸어가기 편하고 조용한 주택가라 해외 친구들이 정말 만족했던 합법 도시민박입니다.',
        'blogger_name': '서울트래블러',
        'postdate': '20261021',
        'link': 'https://section.blog.naver.com/',
      },
      {
        'title': '연트럴파크 도보 3분 아늑한 연남 스테이 공간 기록',
        'summary': '깔끔한 침구와 채광 좋은 거실 공간이 인상적이었던 마포구 정식 등록 숙소 소개.',
        'blogger_name': '스테이노트',
        'postdate': '20260915',
        'link': 'https://section.blog.naver.com/',
      },
    ],
    'naver_map_url': 'https://map.naver.com/p/search/%EC%97%B0%EB%82%A8%EB%8F%99%20%EA%B2%8C%EC%8A%A4%ED%8A%B8%ED%95%98%EC%9A%B0%EC%8A%A4',
    'naver_search_url': 'https://search.naver.com/search.naver?query=%EC%97%B0%EB%82%A8%EB%8F%99+%EB%8F%84%EC%8B%9C%EB%AF%BC%EB%B0%95',
    'direct_booking_url': 'https://map.naver.com/p/search/%EC%97%B0%EB%82%A8%EB%8F%99%20%EA%B2%8C%EC%8A%A4%ED%8A%B8%ED%95%98%EC%9A%B0%EC%8A%A4',
    'i18n': {
      'en': {
        'title': 'Yeonnam Atelier House (Seoul Hongdae)',
        'summary': 'Licensed Foreigner City Homestay near Hongik Univ. Station & Yeontral Park.',
      },
      'ja': {
        'title': '延南アトリエハウス（ソウル弘大・延南洞）',
        'summary': '弘大入口駅近くの政府公認・外国人専用都市型ゲストハウス。',
      },
      'zh': {
        'title': '延南洞藝術家民宿（首爾弘大入口站）',
        'summary': '鄰近弘大入口站與延南洞林蔭道的韓國政府合法認證外國旅客都市民宿。',
      },
    },
    'outbound_clicks': 19,
    'created_at': 1762900000000,
  },
};

Map<String, dynamic>? findDemoListing(String listingId) => kDemoListingsMap[listingId];

List<MapEntry<String, Map<String, dynamic>>> demoListingEntries() =>
    kDemoListingsMap.entries.map((e) => MapEntry(e.key, e.value)).toList();
