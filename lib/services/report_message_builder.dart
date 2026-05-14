import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/models/student_model.dart';
import 'class_report_draft_service.dart';
import 'class_report_settings_service.dart';
import 'parent_report_message_builder.dart';

/// 리포트 문자 본문 단일 진입점. 항상 디스크에 저장된 최신 설정·초안을 읽습니다.
class ReportMessageBuilder {
  ReportMessageBuilder._();

  static Future<String> buildReportMessage({
    required Student student,
    required SharedPreferences prefs,
    DateTime? referenceDate,
  }) async {
    final className = student.className?.trim();
    if (className == null || className.isEmpty) {
      return _fallbackNoClassBody(student.name);
    }

    final settingsService = ClassReportSettingsService(prefs: prefs);
    final draftService = ClassReportDraftService(prefs: prefs);
    final settings = await settingsService.load(className);
    final draft = await draftService.load(className);

    return ParentReportMessageBuilder.build(
      student: student,
      className: className,
      classSettings: settings,
      sendOptions: draft.toSendOptions(),
      extraNoticeRaw: draft.extraNotice,
      prefs: prefs,
      referenceDate: referenceDate,
    );
  }

  static String _fallbackNoClassBody(String studentName) {
    return '''
안녕하세요, ${AppConstants.academyName} ${AppConstants.academyBranch}입니다.
$studentName 학생 관련 안내드립니다.

오늘 앱에 저장된 수업·숙제·성적 안내가 없습니다. 필요하시면 학원으로 연락 주세요.

감사합니다.'''
        .trim();
  }
}
