// 법적 고지 및 개인정보처리방침 요약 (공공데이터 기반 숙소 정보 제공 + 방문자 별점·후기 운영 모델)
import 'package:material_ui/material_ui.dart';

const kConsentVersion = '2026-11-17.1';

// 전자상거래법상 사업자 정보 표시 (사이트 하단)
const kBizName = '[상호]';
const kBizCeo = '[대표자명]';
const kBizRegNo = '[사업자등록번호]';
const kBizMailOrderNo = '[통신판매업 신고번호]';
const kBizAddress = '[사업장 주소]';
const kBizEmail = '[문의·삭제요청 이메일]';

// 초안 (2026-11-17) — 법률 검토 전. [ ] 자리표시자와 시행일은 사업자 정보 확정 후 채운다.
// 문구를 바꾸면 kConsentVersion 을 올린다.
const kPrivacyPolicy = '''개인정보처리방침 (버전 $kConsentVersion)

직스테이 로컬(이하 "서비스")은 회원가입 없이 이용하는 여행 정보 서비스로, 개인정보를 최소한으로만 처리합니다.

1. 처리 목적
   - 공공데이터 기반 숙소·볼거리·축제·전통시장 정보 제공
   - 방문자 별점·후기 게시 및 장소당 1인 1회 작성 확인
   - 서비스 보안(자동화된 악성 요청 차단)과 이용 통계 분석을 통한 서비스 개선
   - 게시물 정정·삭제 요청 등 문의 응대

2. 처리하는 개인정보 항목
   가. 회원가입·로그인: 없음 (이름·전화번호·이메일 등을 받지 않습니다)
   나. 별점·후기 작성 시(선택): 작성자가 입력한 닉네임(실명 불요), 별점, 방문 유형, 후기 본문, 작성 언어·일시,
       그리고 1인 1회 작성 확인을 위해 이 브라우저에 발급되는 무작위 익명 식별자(Firebase 익명 인증 ID).
       닉네임과 후기 본문은 누구나 볼 수 있게 공개되므로 연락처 등 개인정보를 적지 마세요.
   다. 서비스 이용 중 자동으로 생성되는 정보: 접속 IP 주소, 브라우저·기기 종류, 접속 일시, 요청한 페이지 주소
       (서버 접속 기록 및 보안 확인 과정에서 생성)
   라. 이용 통계(Google Analytics 사용 시): 쿠키·기기 식별값, 대략적인 지역(국가·도시 수준), 방문 페이지,
       서비스 안 행동(검색어, 지역 선택, 공유·길찾기·예약 버튼 클릭 등). 광고 목적의 개인 맞춤 신호는 사용하지 않습니다.
   마. 수집하지 않는 정보: '내 주변' 기능의 위치 정보는 기기 안에서 거리 계산에만 쓰고 서버로 보내거나 저장하지 않습니다.
       '찜' 목록과 언어 설정은 이 브라우저에만 저장되며 서비스가 수집하지 않습니다.
       숙소 예약·결제는 각 숙소 운영자 채널에서 이루어지며, 서비스는 숙소별 외부 연결 클릭 횟수만 셉니다(누가 눌렀는지는 남기지 않음).

3. 보유 기간 및 파기
   - 후기와 익명 식별자: 게시물을 운영하는 동안 보관하고, 삭제 요청 또는 권리침해·허위·욕설 신고가 확인되면 지체 없이 삭제합니다.
   - 서버 접속 기록: [30]일 보관 후 자동 삭제
   - 이용 통계(Google Analytics): 사용자 단위 데이터 [2]개월 보관 후 자동 삭제
   - 전자적 파일은 복구할 수 없는 방법으로 삭제합니다.

4. 개인정보의 제3자 제공: 하지 않습니다.

5. 처리 위탁 및 국외 이전
   서비스 운영을 위해 아래 업체에 처리를 맡기며, 일부는 국외에서 처리됩니다.
   - Google LLC (미국) / Google Cloud·Firebase: 데이터 저장(서울 리전), 웹 호스팅, 익명 인증, 서버 접속 기록
   - Google LLC (미국) / reCAPTCHA Enterprise·Firebase App Check: 자동화된 악성 요청 차단(접속 시 브라우저·기기 정보와 IP 주소 처리)
   - Google LLC (미국) / Google Analytics: 이용 통계 분석 (사용 시)
   - 이전 시기·방법: 서비스 이용 시점에 네트워크를 통해 전송
   - 보유 기간: 위 3항 또는 위탁 계약 종료 시까지
   국외 이전을 원하지 않으면 서비스 이용을 중단하거나, 아래 7항의 방법으로 통계 수집을 거부할 수 있습니다.
   다만 보안 확인(reCAPTCHA)은 서비스 제공에 필요하여 거부할 경우 일부 기능(후기 작성 등)을 이용할 수 없습니다.

6. 정보주체의 권리와 행사 방법
   자신이 작성한 후기의 열람·정정·삭제와 처리 정지를 $kBizEmail 로 요청할 수 있습니다.
   익명 식별자만으로는 작성자를 확인하기 어려우므로, 요청 시 해당 장소와 작성 일시·닉네임을 알려 주세요.

7. 개인정보 자동 수집 장치(쿠키 등)의 설치·운영 및 거부
   - 이용 통계를 위해 Google Analytics 쿠키를, 보안 확인을 위해 reCAPTCHA 관련 저장값을 사용합니다.
   - 브라우저 설정에서 쿠키 저장을 거부하거나 삭제할 수 있고,
     Google Analytics 차단 부가기능(https://tools.google.com/dlpage/gaoptout)으로 통계 수집만 거부할 수 있습니다.

8. 안전성 확보 조치
   전송 구간 암호화(HTTPS), 데이터베이스 보안 규칙에 따른 쓰기 제한(후기 항목·길이 제한, 1인 1회),
   관리자 키 접근 통제, 자동화된 악성 요청 차단(App Check)

9. 개인정보 보호책임자
   성명: [성명] / 연락처: $kBizEmail

10. 변경 고지
   이 방침이 바뀌면 시행 7일 전부터 서비스 화면을 통해 알립니다. 시행일: [2026년 ○월 ○일]''';

void showLegalDialog(BuildContext context, String title, String body) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: Text(body, style: const TextStyle(fontSize: 13, height: 1.5))),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
    ),
  );
}

class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white70, fontSize: 12, height: 1.6);
    return Container(
      width: double.infinity,
      color: const Color(0xFF222222),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(children: [
            const Text(
              '본 서비스는 행정안전부·한국관광공사 공공데이터에 등록된 숙소 정보제공 채널이며 통신판매의 당사자가 아닙니다. '
              '예약·결제·환불의 의무와 책임은 각 숙소 운영자에게 있습니다.',
              style: style,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '$kBizName · 대표 $kBizCeo · 사업자등록번호 $kBizRegNo · 통신판매업 신고 $kBizMailOrderNo\n'
              '$kBizAddress · 정보 정정/게시물 삭제 요청 $kBizEmail',
              style: style,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => showLegalDialog(context, '개인정보처리방침', kPrivacyPolicy),
              child: const Text('개인정보처리방침',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }
}
