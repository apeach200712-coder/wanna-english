import 'grade_record_model.dart';

String _hwString(
  Map<String, dynamic> json,
  String key, [
  String fallback = '',
]) {
  final value = json[key];
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

int _hwInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

// ─── Resubmission ─────────────────────────────────────────────────────────────

enum ResubmissionStatus {
  none,
  resubmissionRequired,
  submittedAfterResubmission,
}

extension ResubmissionStatusLabel on ResubmissionStatus {
  String get displayLabel {
    switch (this) {
      case ResubmissionStatus.none:
        return '';
      case ResubmissionStatus.resubmissionRequired:
        return '재제출';
      case ResubmissionStatus.submittedAfterResubmission:
        return '제출';
    }
  }
}

/// Resubmission record for a student's entire homework evaluation.
class ResubmissionInfo {
  final ResubmissionStatus status;

  /// ISO datetime when the teacher marked resubmission required.
  final String? requiredAt;

  /// ISO date string e.g. "2026-05-13"
  final String? dueDate;

  /// ISO datetime when the teacher confirmed submission.
  final String? submittedAt;

  const ResubmissionInfo({
    this.status = ResubmissionStatus.none,
    this.requiredAt,
    this.dueDate,
    this.submittedAt,
  });

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'requiredAt': requiredAt,
    'dueDate': dueDate,
    'submittedAt': submittedAt,
  };

  factory ResubmissionInfo.fromJson(Map<String, dynamic> json) {
    final statusStr = _hwString(json, 'status', 'none');
    final status = ResubmissionStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => ResubmissionStatus.none,
    );
    return ResubmissionInfo(
      status: status,
      requiredAt: json['requiredAt']?.toString(),
      dueDate: json['dueDate']?.toString(),
      submittedAt: json['submittedAt']?.toString(),
    );
  }

  ResubmissionInfo copyWith({
    ResubmissionStatus? status,
    Object? requiredAt = _undef,
    Object? dueDate = _undef,
    Object? submittedAt = _undef,
  }) => ResubmissionInfo(
    status: status ?? this.status,
    requiredAt: identical(requiredAt, _undef)
        ? this.requiredAt
        : requiredAt as String?,
    dueDate: identical(dueDate, _undef) ? this.dueDate : dueDate as String?,
    submittedAt: identical(submittedAt, _undef)
        ? this.submittedAt
        : submittedAt as String?,
  );

  static const Object _undef = Object();
}

// ─── ClassHomeworkTemplate ────────────────────────────────────────────────────

/// The shared homework assignment for a class in a given week.
/// All students see the same sections; each student is evaluated individually.
class ClassHomeworkTemplate {
  final String classId;
  final String weekStartDate; // ISO date e.g. "2026-05-11"
  final List<HomeworkSection> sections;

  const ClassHomeworkTemplate({
    required this.classId,
    required this.weekStartDate,
    required this.sections,
  });

  Map<String, dynamic> toJson() => {
    'classId': classId,
    'weekStartDate': weekStartDate,
    'sections': sections.map((s) => s.toJson()).toList(),
  };

  factory ClassHomeworkTemplate.fromJson(Map<String, dynamic> json) =>
      ClassHomeworkTemplate(
        classId: _hwString(json, 'classId'),
        weekStartDate: _hwString(json, 'weekStartDate'),
        sections: (json['sections'] as List? ?? [])
            .whereType<Map>()
            .map((e) => HomeworkSection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  ClassHomeworkTemplate copyWith({
    String? classId,
    String? weekStartDate,
    List<HomeworkSection>? sections,
  }) => ClassHomeworkTemplate(
    classId: classId ?? this.classId,
    weekStartDate: weekStartDate ?? this.weekStartDate,
    sections: sections ?? this.sections,
  );
}

// ─── StudentHomeworkResult ────────────────────────────────────────────────────

/// Per-student evaluation result for one week.
class StudentHomeworkResult {
  final String id;
  final String classId;
  final String studentId;
  final String studentName;
  final String weekStartDate;
  final List<HomeworkSection> sections;
  final HomeworkCompletionMode calculationMode;
  final int? manualCompletionRate;
  final int autoCompletionRate;
  final int finalCompletionRate;
  final bool isEvaluated;
  final ResubmissionInfo resubmission;

  const StudentHomeworkResult({
    required this.id,
    required this.classId,
    required this.studentId,
    required this.studentName,
    required this.weekStartDate,
    required this.sections,
    required this.calculationMode,
    this.manualCompletionRate,
    required this.autoCompletionRate,
    required this.finalCompletionRate,
    required this.isEvaluated,
    this.resubmission = const ResubmissionInfo(),
  });

  /// Auto-rate formula: 100/n sections, /5 dots = pointsPerDot.
  /// Sum all dots * pointsPerDot, ceil to nearest 5%.
  static int computeAutoRate(List<HomeworkSection> sections) {
    if (sections.isEmpty) return 0;
    final n = sections.length;
    final pointsPerSection = 100.0 / n;
    final pointsPerDot = pointsPerSection / 5.0;
    final raw = sections.fold<double>(
      0.0,
      (s, sec) => s + sec.checkCount * pointsPerDot,
    );
    return ((raw / 5.0).ceil() * 5).clamp(0, 100).toInt();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'classId': classId,
    'studentId': studentId,
    'studentName': studentName,
    'weekStartDate': weekStartDate,
    'sections': sections.map((s) => s.toJson()).toList(),
    'calculationMode': calculationMode.name,
    'manualCompletionRate': manualCompletionRate,
    'autoCompletionRate': autoCompletionRate,
    'finalCompletionRate': finalCompletionRate,
    'isEvaluated': isEvaluated,
    'resubmission': resubmission.toJson(),
  };

  factory StudentHomeworkResult.fromJson(Map<String, dynamic> json) {
    final mode = HomeworkCompletionMode.values.firstWhere(
      (m) => m.name == json['calculationMode'],
      orElse: () => HomeworkCompletionMode.auto,
    );
    return StudentHomeworkResult(
      id: _hwString(json, 'id'),
      classId: _hwString(json, 'classId'),
      studentId: _hwString(json, 'studentId'),
      studentName: _hwString(json, 'studentName'),
      weekStartDate: _hwString(json, 'weekStartDate'),
      sections: (json['sections'] as List? ?? [])
          .whereType<Map>()
          .map((e) => HomeworkSection.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      calculationMode: mode,
      manualCompletionRate: json['manualCompletionRate'] == null
          ? null
          : _hwInt(json, 'manualCompletionRate'),
      autoCompletionRate: _hwInt(json, 'autoCompletionRate', 0),
      finalCompletionRate: _hwInt(json, 'finalCompletionRate', 0),
      isEvaluated: json['isEvaluated'] as bool? ?? false,
      resubmission: json['resubmission'] is Map
          ? ResubmissionInfo.fromJson(
              Map<String, dynamic>.from(json['resubmission'] as Map),
            )
          : const ResubmissionInfo(),
    );
  }

  StudentHomeworkResult copyWith({
    String? id,
    String? classId,
    String? studentId,
    String? studentName,
    String? weekStartDate,
    List<HomeworkSection>? sections,
    HomeworkCompletionMode? calculationMode,
    Object? manualCompletionRate = _undef,
    int? autoCompletionRate,
    int? finalCompletionRate,
    bool? isEvaluated,
    ResubmissionInfo? resubmission,
  }) => StudentHomeworkResult(
    id: id ?? this.id,
    classId: classId ?? this.classId,
    studentId: studentId ?? this.studentId,
    studentName: studentName ?? this.studentName,
    weekStartDate: weekStartDate ?? this.weekStartDate,
    sections: sections ?? this.sections,
    calculationMode: calculationMode ?? this.calculationMode,
    manualCompletionRate: identical(manualCompletionRate, _undef)
        ? this.manualCompletionRate
        : manualCompletionRate as int?,
    autoCompletionRate: autoCompletionRate ?? this.autoCompletionRate,
    finalCompletionRate: finalCompletionRate ?? this.finalCompletionRate,
    isEvaluated: isEvaluated ?? this.isEvaluated,
    resubmission: resubmission ?? this.resubmission,
  );

  static const Object _undef = Object();
}

// ─── HomeworkHistoryStudentResult ─────────────────────────────────────────────

class HomeworkHistoryStudentResult {
  final String studentId;
  final String studentName;
  final int? finalCompletionRate; // null = not evaluated
  final bool isEvaluated;
  final ResubmissionInfo resubmission;

  const HomeworkHistoryStudentResult({
    required this.studentId,
    required this.studentName,
    this.finalCompletionRate,
    required this.isEvaluated,
    this.resubmission = const ResubmissionInfo(),
  });

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'studentName': studentName,
    'finalCompletionRate': finalCompletionRate,
    'isEvaluated': isEvaluated,
    'resubmission': resubmission.toJson(),
  };

  factory HomeworkHistoryStudentResult.fromJson(Map<String, dynamic> json) =>
      HomeworkHistoryStudentResult(
        studentId: _hwString(json, 'studentId'),
        studentName: _hwString(json, 'studentName'),
        finalCompletionRate: json['finalCompletionRate'] == null
            ? null
            : _hwInt(json, 'finalCompletionRate'),
        isEvaluated: json['isEvaluated'] as bool? ?? false,
        resubmission: json['resubmission'] is Map
            ? ResubmissionInfo.fromJson(
                Map<String, dynamic>.from(json['resubmission'] as Map),
              )
            : const ResubmissionInfo(),
      );
}

// ─── HomeworkHistoryEntry ─────────────────────────────────────────────────────

/// One archived week, stored in LAST WEEKS.
class HomeworkHistoryEntry {
  final String classId;
  final String date; // "2026-05-04" (weekStartDate at time of archiving)
  final List<HomeworkSection> sections;
  final List<HomeworkHistoryStudentResult> studentResults;

  const HomeworkHistoryEntry({
    required this.classId,
    required this.date,
    required this.sections,
    required this.studentResults,
  });

  Map<String, dynamic> toJson() => {
    'classId': classId,
    'date': date,
    'sections': sections.map((s) => s.toJson()).toList(),
    'studentResults': studentResults.map((r) => r.toJson()).toList(),
  };

  factory HomeworkHistoryEntry.fromJson(Map<String, dynamic> json) =>
      HomeworkHistoryEntry(
        classId: _hwString(json, 'classId'),
        date: _hwString(json, 'date'),
        sections: (json['sections'] as List? ?? [])
            .whereType<Map>()
            .map((e) => HomeworkSection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        studentResults: (json['studentResults'] as List? ?? [])
            .whereType<Map>()
            .map(
              (e) => HomeworkHistoryStudentResult.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList(),
      );
}

// ─── Homework category (class-scoped parent group) ───────────────────────────

class HomeworkCategoryMeta {
  final String id;
  final String name;

  const HomeworkCategoryMeta({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory HomeworkCategoryMeta.fromJson(Map<String, dynamic> json) =>
      HomeworkCategoryMeta(
        id: _hwString(json, 'id'),
        name: _hwString(json, 'name'),
      );

  HomeworkCategoryMeta copyWith({String? name}) =>
      HomeworkCategoryMeta(id: id, name: name ?? this.name);
}

// ─── NextWeekHomework ─────────────────────────────────────────────────────────

class NextWeekHomework {
  final String classId;
  final String switchDay; // "monday" … "sunday"
  final List<String> items;
  final List<HomeworkSection>? sections;
  final String updatedAt; // ISO datetime

  const NextWeekHomework({
    required this.classId,
    required this.switchDay,
    required this.items,
    this.sections,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'classId': classId,
    'switchDay': switchDay,
    'items': items,
    if (sections != null && sections!.isNotEmpty)
      'sections': sections!.map((s) => s.toJson()).toList(),
    'updatedAt': updatedAt,
  };

  factory NextWeekHomework.fromJson(Map<String, dynamic> json) =>
      NextWeekHomework(
        classId: _hwString(json, 'classId'),
        switchDay: _hwString(json, 'switchDay', 'monday'),
        items: List<String>.from(json['items'] as List? ?? []),
        sections: (json['sections'] as List?)
            ?.whereType<Map>()
            .map((e) => HomeworkSection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        updatedAt: _hwString(json, 'updatedAt'),
      );

  NextWeekHomework copyWith({
    String? classId,
    String? switchDay,
    List<String>? items,
    List<HomeworkSection>? sections,
    String? updatedAt,
  }) => NextWeekHomework(
    classId: classId ?? this.classId,
    switchDay: switchDay ?? this.switchDay,
    items: items ?? this.items,
    sections: sections ?? this.sections,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
