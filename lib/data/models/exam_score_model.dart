import 'dart:math' as math;

String _examString(
  Map<String, dynamic> json,
  String key, [
  String fallback = '',
]) {
  final value = json[key];
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

double? _examNullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _examNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool _examBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return fallback;
}

DateTime _examDateTime(Object? value, DateTime fallback) {
  if (value is String) return DateTime.tryParse(value) ?? fallback;
  return fallback;
}

// Data models for the grade-input / exam-score screen.
// Designed to be DB-agnostic so they can be persisted to
// SharedPreferences, Firebase, or Supabase without changing callers.

// ─── Exam category (legacy JSON / migration only) ────────────────────────────

enum ExamCategory {
  vocabulary('단어시험'),
  reviewTest('리뷰테스트'),
  regularExam('모의고사'),
  internalExam('내신직보시험');

  final String label;
  const ExamCategory(this.label);

  /// Whether this category uses a simple pass/retake threshold model.
  bool get isSimpleType =>
      this == ExamCategory.vocabulary || this == ExamCategory.reviewTest;
}

// ─── Per-class exam type (id + display name + form) ───────────────────────────

enum ExamFormType {
  gradeBased('grade_based'),
  thresholdBased('threshold_based');

  final String wireName;
  const ExamFormType(this.wireName);

  static ExamFormType fromWire(String? raw) {
    if (raw == null) return ExamFormType.gradeBased;
    return ExamFormType.values.firstWhere(
      (e) => e.wireName == raw || e.name == raw,
      orElse: () => ExamFormType.gradeBased,
    );
  }
}

/// Built-in type ids (stable across renames of default labels).
abstract final class ClassExamTypeIds {
  static const vocabulary = 'et_builtin_vocabulary';
  static const reviewTest = 'et_builtin_review';
  static const mockExam = 'et_builtin_mock';
  static const internal = 'et_builtin_internal';

  static const Set<String> allBuiltIn = {
    vocabulary,
    reviewTest,
    mockExam,
    internal,
  };

  static ExamFormType formForBuiltinId(String id) {
    switch (id) {
      case vocabulary:
      case reviewTest:
        return ExamFormType.thresholdBased;
      default:
        return ExamFormType.gradeBased;
    }
  }

  static ExamCategory legacyCategoryForBuiltinId(String id) {
    switch (id) {
      case vocabulary:
        return ExamCategory.vocabulary;
      case reviewTest:
        return ExamCategory.reviewTest;
      case mockExam:
        return ExamCategory.regularExam;
      case internal:
        return ExamCategory.internalExam;
      default:
        return ExamCategory.vocabulary;
    }
  }

  static String builtinIdFromLegacyCategory(ExamCategory c) {
    switch (c) {
      case ExamCategory.vocabulary:
        return vocabulary;
      case ExamCategory.reviewTest:
        return reviewTest;
      case ExamCategory.regularExam:
        return mockExam;
      case ExamCategory.internalExam:
        return internal;
    }
  }
}

class ClassExamTypeDef {
  final String id;
  final String className;
  final String displayName;
  final ExamFormType formType;

  const ClassExamTypeDef({
    required this.id,
    required this.className,
    required this.displayName,
    required this.formType,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'className': className,
    'displayName': displayName,
    'formType': formType.wireName,
  };

  factory ClassExamTypeDef.fromJson(Map<String, dynamic> json) =>
      ClassExamTypeDef(
        id: _examString(json, 'id'),
        className: _examString(json, 'className'),
        displayName: _examString(json, 'displayName'),
        formType: ExamFormType.fromWire(_examString(json, 'formType')),
      );

  ClassExamTypeDef copyWith({
    String? id,
    String? className,
    String? displayName,
    ExamFormType? formType,
  }) => ClassExamTypeDef(
    id: id ?? this.id,
    className: className ?? this.className,
    displayName: displayName ?? this.displayName,
    formType: formType ?? this.formType,
  );

  static List<ClassExamTypeDef> defaultTypesForClass(String className) => [
    ClassExamTypeDef(
      id: ClassExamTypeIds.vocabulary,
      className: className,
      displayName: ExamCategory.vocabulary.label,
      formType: ExamFormType.thresholdBased,
    ),
    ClassExamTypeDef(
      id: ClassExamTypeIds.reviewTest,
      className: className,
      displayName: ExamCategory.reviewTest.label,
      formType: ExamFormType.thresholdBased,
    ),
    ClassExamTypeDef(
      id: ClassExamTypeIds.mockExam,
      className: className,
      displayName: ExamCategory.regularExam.label,
      formType: ExamFormType.gradeBased,
    ),
    ClassExamTypeDef(
      id: ClassExamTypeIds.internal,
      className: className,
      displayName: ExamCategory.internalExam.label,
      formType: ExamFormType.gradeBased,
    ),
  ];
}

// ─── Per-student score entry ──────────────────────────────────────────────────

class ExamStudentScore {
  final String studentId;
  final String studentName;

  /// Null means the score has not been entered yet.
  final double? score;

  /// Only used for regularExam / internalExam.
  final int? grade; // 등급 1–9
  final double? percentile; // 백분위

  /// Optional retake/final score (mainly for review tests).
  final double? retakeScore;

  const ExamStudentScore({
    required this.studentId,
    required this.studentName,
    this.score,
    this.grade,
    this.percentile,
    this.retakeScore,
  });

  ExamStudentScore copyWith({
    String? studentId,
    String? studentName,
    Object? score = _undefined,
    Object? grade = _undefined,
    Object? percentile = _undefined,
    Object? retakeScore = _undefined,
  }) {
    return ExamStudentScore(
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      score: identical(score, _undefined) ? this.score : score as double?,
      grade: identical(grade, _undefined) ? this.grade : grade as int?,
      percentile: identical(percentile, _undefined)
          ? this.percentile
          : percentile as double?,
      retakeScore: identical(retakeScore, _undefined)
          ? this.retakeScore
          : retakeScore as double?,
    );
  }

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'studentName': studentName,
    'score': score,
    'grade': grade,
    'percentile': percentile,
    'retakeScore': retakeScore,
  };

  factory ExamStudentScore.fromJson(Map<String, dynamic> json) =>
      ExamStudentScore(
        studentId: _examString(json, 'studentId'),
        studentName: _examString(json, 'studentName'),
        score: _examNullableDouble(json['score']),
        grade: _examNullableInt(json['grade']),
        percentile: _examNullableDouble(json['percentile']),
        retakeScore: _examNullableDouble(json['retakeScore']),
      );

  static const Object _undefined = Object();
}

// ─── Exam session (one exam taken on one date by one class) ───────────────────

class ExamSession {
  final String id;
  final String className;
  final DateTime examDate;

  /// Stable type id (per class definitions in [ClassExamTypeDef]).
  final String examTypeId;

  /// Persisted snapshot so records stay readable if the type is deleted/renamed.
  final String examTypeDisplayName;

  /// Which input/analytics form this session uses.
  final ExamFormType formType;

  /// e.g. '단어시험 Day 12'
  final String examName;

  // ── Simple type fields (vocabulary / reviewTest) ──
  final double? maxScore;
  final double? retakeThreshold;
  final List<DateTime?> retakeScheduledDates;

  // ── Complex type fields (regular / internal) ──
  final double? schoolAverage;
  final double? standardDeviation;
  final bool hasGrade;
  final bool hasPercentile;

  final List<ExamStudentScore> scores;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExamSession({
    required this.id,
    required this.className,
    required this.examDate,
    required this.examTypeId,
    required this.examTypeDisplayName,
    required this.formType,
    required this.examName,
    this.maxScore,
    this.retakeThreshold,
    this.retakeScheduledDates = const [],
    this.schoolAverage,
    this.standardDeviation,
    this.hasGrade = false,
    this.hasPercentile = false,
    required this.scores,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isThresholdBased => formType == ExamFormType.thresholdBased;
  bool get isGradeBased => formType == ExamFormType.gradeBased;

  /// Legacy routing for features that still branch on the old four categories.
  ExamCategory get legacyCategory {
    if (ClassExamTypeIds.allBuiltIn.contains(examTypeId)) {
      return ClassExamTypeIds.legacyCategoryForBuiltinId(examTypeId);
    }
    return isThresholdBased
        ? ExamCategory.vocabulary
        : ExamCategory.regularExam;
  }

  ExamSession copyWith({
    String? id,
    String? className,
    DateTime? examDate,
    String? examTypeId,
    String? examTypeDisplayName,
    ExamFormType? formType,
    String? examName,
    Object? maxScore = _undefined,
    Object? retakeThreshold = _undefined,
    List<DateTime?>? retakeScheduledDates,
    Object? schoolAverage = _undefined,
    Object? standardDeviation = _undefined,
    bool? hasGrade,
    bool? hasPercentile,
    List<ExamStudentScore>? scores,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExamSession(
      id: id ?? this.id,
      className: className ?? this.className,
      examDate: examDate ?? this.examDate,
      examTypeId: examTypeId ?? this.examTypeId,
      examTypeDisplayName: examTypeDisplayName ?? this.examTypeDisplayName,
      formType: formType ?? this.formType,
      examName: examName ?? this.examName,
      maxScore: identical(maxScore, _undefined)
          ? this.maxScore
          : maxScore as double?,
      retakeThreshold: identical(retakeThreshold, _undefined)
          ? this.retakeThreshold
          : retakeThreshold as double?,
      retakeScheduledDates: retakeScheduledDates ?? this.retakeScheduledDates,
      schoolAverage: identical(schoolAverage, _undefined)
          ? this.schoolAverage
          : schoolAverage as double?,
      standardDeviation: identical(standardDeviation, _undefined)
          ? this.standardDeviation
          : standardDeviation as double?,
      hasGrade: hasGrade ?? this.hasGrade,
      hasPercentile: hasPercentile ?? this.hasPercentile,
      scores: scores ?? this.scores,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'className': className,
    'examDate': examDate.toIso8601String(),
    'examTypeId': examTypeId,
    'examTypeDisplayName': examTypeDisplayName,
    'formType': formType.wireName,
    'category': legacyCategory.name,
    'examName': examName,
    'maxScore': maxScore,
    'retakeThreshold': retakeThreshold,
    'retakeScheduledDates': retakeScheduledDates
        .map((date) => date?.toIso8601String())
        .toList(),
    'schoolAverage': schoolAverage,
    'standardDeviation': standardDeviation,
    'hasGrade': hasGrade,
    'hasPercentile': hasPercentile,
    'scores': scores.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ExamSession.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final legacyCat = ExamCategory.values.firstWhere(
      (e) => e.name == json['category'],
      orElse: () => ExamCategory.vocabulary,
    );
    final examTypeId =
        (json['examTypeId']?.toString().trim().isNotEmpty ?? false)
        ? json['examTypeId'].toString().trim()
        : ClassExamTypeIds.builtinIdFromLegacyCategory(legacyCat);
    final formType = json['formType'] != null
        ? ExamFormType.fromWire(json['formType']?.toString())
        : (legacyCat.isSimpleType
              ? ExamFormType.thresholdBased
              : ExamFormType.gradeBased);
    final examTypeDisplayName =
        json['examTypeDisplayName']?.toString() ?? legacyCat.label;
    return ExamSession(
      id: _examString(json, 'id'),
      className: _examString(json, 'className'),
      examDate: _examDateTime(json['examDate'], now),
      examTypeId: examTypeId,
      examTypeDisplayName: examTypeDisplayName,
      formType: formType,
      examName: _examString(json, 'examName'),
      maxScore: _examNullableDouble(json['maxScore']),
      retakeThreshold: _examNullableDouble(json['retakeThreshold']),
      retakeScheduledDates:
          ((json['retakeScheduledDates'] as List?) ?? const [])
              .map(
                (value) =>
                    value == null ? null : DateTime.tryParse(value.toString()),
              )
              .toList(),
      schoolAverage: _examNullableDouble(json['schoolAverage']),
      standardDeviation: _examNullableDouble(json['standardDeviation']),
      hasGrade: _examBool(json['hasGrade']),
      hasPercentile: _examBool(json['hasPercentile']),
      scores: ((json['scores'] as List?) ?? const [])
          .whereType<Map>()
          .map((s) => ExamStudentScore.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
      createdAt: _examDateTime(json['createdAt'], now),
      updatedAt: _examDateTime(json['updatedAt'], now),
    );
  }

  static const Object _undefined = Object();
}

// ─── Analysis results ─────────────────────────────────────────────────────────

class SimpleExamAnalysis {
  final double? average;
  final double? highest;
  final double? lowest;
  final int retakeCount;
  final int unentered;
  final List<ExamStudentScore> retakeStudents;

  const SimpleExamAnalysis({
    this.average,
    this.highest,
    this.lowest,
    required this.retakeCount,
    required this.unentered,
    required this.retakeStudents,
  });

  static SimpleExamAnalysis compute(
    List<ExamStudentScore> scores,
    double? threshold,
  ) {
    final entered = scores.where((s) => s.score != null).toList();
    final unentered = scores.length - entered.length;
    if (entered.isEmpty) {
      return SimpleExamAnalysis(
        retakeCount: 0,
        unentered: unentered,
        retakeStudents: [],
      );
    }
    final values = entered.map((s) => s.score!).toList();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final highest = values.reduce((a, b) => a > b ? a : b);
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final retakes = threshold == null
        ? <ExamStudentScore>[]
        : entered.where((s) => s.score! < threshold).toList();
    return SimpleExamAnalysis(
      average: avg,
      highest: highest,
      lowest: lowest,
      retakeCount: retakes.length,
      unentered: unentered,
      retakeStudents: retakes,
    );
  }
}

class ComplexExamAnalysis {
  final double? classAverage;
  final double? standardDeviation;
  final double? averageGrade;
  final double? highest;
  final double? lowest;
  final int unentered;

  const ComplexExamAnalysis({
    this.classAverage,
    this.standardDeviation,
    this.averageGrade,
    this.highest,
    this.lowest,
    required this.unentered,
  });

  static ComplexExamAnalysis compute(List<ExamStudentScore> scores) {
    final entered = scores.where((s) => s.score != null).toList();
    final unentered = scores.length - entered.length;
    if (entered.isEmpty) {
      return ComplexExamAnalysis(unentered: unentered);
    }
    final values = entered.map((s) => s.score!).toList();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) /
        values.length;
    final stdDev = variance <= 0 ? 0.0 : math.sqrt(variance);
    final highest = values.reduce((a, b) => a > b ? a : b);
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final gradeEntries = entered.where((s) => s.grade != null).toList();
    final avgGrade = gradeEntries.isEmpty
        ? null
        : gradeEntries.map((s) => s.grade!).reduce((a, b) => a + b) /
              gradeEntries.length;
    return ComplexExamAnalysis(
      classAverage: avg,
      standardDeviation: stdDev,
      averageGrade: avgGrade,
      highest: highest,
      lowest: lowest,
      unentered: unentered,
    );
  }
}
