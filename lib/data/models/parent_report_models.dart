import 'package:flutter/foundation.dart';

/// 클래스별 리포트 기본 설정 (로컬 저장; 추후 DB로 교체 시 동일 필드 매핑).
@immutable
class ClassReportSettings {
  final String classKey;
  final String greetingTemplate;
  final String closingText;
  final bool includeHomeworkCompletion;
  final bool includeHomeworkWeakParts;
  final bool includeHomeworkResubmissionDeadline;

  const ClassReportSettings({
    required this.classKey,
    required this.greetingTemplate,
    required this.closingText,
    this.includeHomeworkCompletion = true,
    this.includeHomeworkWeakParts = true,
    this.includeHomeworkResubmissionDeadline = true,
  });

  ClassReportSettings copyWith({
    String? classKey,
    String? greetingTemplate,
    String? closingText,
    bool? includeHomeworkCompletion,
    bool? includeHomeworkWeakParts,
    bool? includeHomeworkResubmissionDeadline,
  }) {
    return ClassReportSettings(
      classKey: classKey ?? this.classKey,
      greetingTemplate: greetingTemplate ?? this.greetingTemplate,
      closingText: closingText ?? this.closingText,
      includeHomeworkCompletion:
          includeHomeworkCompletion ?? this.includeHomeworkCompletion,
      includeHomeworkWeakParts:
          includeHomeworkWeakParts ?? this.includeHomeworkWeakParts,
      includeHomeworkResubmissionDeadline:
          includeHomeworkResubmissionDeadline ??
          this.includeHomeworkResubmissionDeadline,
    );
  }

  Map<String, dynamic> toJson() => {
    'classKey': classKey,
    'greetingTemplate': greetingTemplate,
    'closingText': closingText,
    'includeHomeworkCompletion': includeHomeworkCompletion,
    'includeHomeworkWeakParts': includeHomeworkWeakParts,
    'includeHomeworkResubmissionDeadline': includeHomeworkResubmissionDeadline,
  };

  factory ClassReportSettings.fromJson(Map<String, dynamic> json) {
    return ClassReportSettings(
      classKey: json['classKey'] as String,
      greetingTemplate: json['greetingTemplate'] as String? ?? '',
      closingText: json['closingText'] as String? ?? '',
      includeHomeworkCompletion:
          json['includeHomeworkCompletion'] as bool? ?? true,
      includeHomeworkWeakParts: json['includeHomeworkWeakParts'] as bool? ?? true,
      includeHomeworkResubmissionDeadline:
          json['includeHomeworkResubmissionDeadline'] as bool? ?? true,
    );
  }
}

/// 이번 발송 건만 유지되는 옵션 (오늘 수업·다음주 숙제·시험 선택).
@immutable
class ReportSendOptions {
  final bool includeTodayLesson;
  final bool includeNextHomework;
  final Set<String> selectedExamSessionIds;

  const ReportSendOptions({
    required this.includeTodayLesson,
    required this.includeNextHomework,
    required this.selectedExamSessionIds,
  });
}

enum ReportSendStatus { success, noPhone, smsFailed }

@immutable
class ReportSendResult {
  final String studentId;
  final String studentName;
  final ReportSendStatus status;
  final String? messageBody;
  final String? errorDetail;

  const ReportSendResult({
    required this.studentId,
    required this.studentName,
    required this.status,
    this.messageBody,
    this.errorDetail,
  });
}
