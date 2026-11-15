// 법적 고지 및 개인정보처리방침 요약 (공공데이터 기반 숙소 정보 제공 + 방문자 별점·후기 운영 모델)
import 'package:material_ui/material_ui.dart';

const kConsentVersion = '2026-11-15.3';

// 전자상거래법상 사업자 정보 표시 (사이트 하단)
const kBizName = '[상호]';
const kBizCeo = '[대표자명]';
const kBizRegNo = '[사업자등록번호]';
const kBizMailOrderNo = '[통신판매업 신고번호]';
const kBizAddress = '[사업장 주소]';
const kBizEmail = '[문의·삭제요청 이메일]';

const kPrivacyPolicy = '''개인정보처리방침 (요약, 버전 $kConsentVersion)

1. 처리 목적: 행정안전부·한국관광공사 공공데이터 기반 합법 숙소 정보 제공, 방문자 별점·후기 게시, 직거래 연결 통계 집계 및 문의 응대
2. 처리 항목:
   - 숙소 탐색·직거래 이동 시: 개인정보를 수집하지 않으며 숙소별 외부 연결 클릭 횟수만 집계합니다.
   - 별점·후기 작성 시: 작성자가 직접 입력한 닉네임(실명 불요), 별점(1~5점), 방문 유형, 후기 본문, 작성 일시, 그리고 "장소당 1회 작성" 확인을 위해 브라우저에 발급되는 무작위 익명 식별자(Firebase 익명 인증 ID)
3. 보유·파기: 작성된 후기와 익명 식별자는 서비스 운영 기간 동안 보관·공개되며, 권리침해·허위·욕설 신고 또는 삭제 요청($kBizEmail) 접수 시 검토 후 즉시 삭제합니다.
4. 처리 위탁·국외 이전: Google Firebase(데이터 저장 — 서울 리전 asia-northeast3, 익명 인증 — Firebase Authentication)
5. 정보주체의 권리: 게시물 정정·삭제 요청을 $kBizEmail 로 접수할 수 있습니다.
6. 개인정보 보호책임자: [성명], $kBizEmail''';

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
              '본 서비스는 행정안전부·한국관광공사 공공데이터로 확인된 합법 숙소 정보제공 채널이며 통신판매의 당사자가 아닙니다. '
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
