import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/student_model.dart';
import 'report_message_builder.dart';

/// 학생별 학부모 문자 초안 (기기 문자 앱 body용).
/// 본문은 [ReportMessageBuilder]와 동일 경로로 생성합니다.
class ParentSmsDraftBuilder {
  ParentSmsDraftBuilder._();

  static Future<String> build({
    required Student student,
    required SharedPreferences prefs,
  }) {
    return ReportMessageBuilder.buildReportMessage(
      student: student,
      prefs: prefs,
    );
  }
}
