String _grString(
  Map<String, dynamic> json,
  String key, [
  String fallback = '',
]) {
  final value = json[key];
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

int _grInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _grDouble(Map<String, dynamic> json, String key, [double fallback = 0]) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

DateTime _grDateTime(Map<String, dynamic> json, String key, DateTime fallback) {
  final value = json[key];
  if (value is String) return DateTime.tryParse(value) ?? fallback;
  return fallback;
}

GradeLevel _grGradeLevel(Object? value, [GradeLevel fallback = GradeLevel.c]) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return fallback;
  return GradeLevel.values.where((item) => item.name == raw).firstOrNull ??
      fallback;
}

class AttendanceRecord {
  final String id;
  final String studentId;
  final String? classId;
  final String className;
  final DateTime date;
  final bool isPresent; // true: 출석, false: 결석
  final String? note;
  final int createdAt;

  const AttendanceRecord({
    required this.id,
    required this.studentId,
    this.classId,
    required this.className,
    required this.date,
    required this.isPresent,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'classId': classId,
      'className': className,
      'date': date.toIso8601String(),
      'isPresent': isPresent,
      'note': note,
      'createdAt': createdAt,
    };
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return AttendanceRecord(
      id: _grString(json, 'id'),
      studentId: _grString(json, 'studentId'),
      classId: json['classId']?.toString(),
      className: _grString(json, 'className'),
      date: _grDateTime(json, 'date', now),
      isPresent: json['isPresent'] as bool? ?? false,
      note: json['note']?.toString(),
      createdAt: _grInt(json, 'createdAt'),
    );
  }

  AttendanceRecord copyWith({
    String? id,
    String? studentId,
    String? classId,
    String? className,
    DateTime? date,
    bool? isPresent,
    String? note,
    int? createdAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      date: date ?? this.date,
      isPresent: isPresent ?? this.isPresent,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// ─── Homework sub-models ────────────────────────────────────────────────────

enum HomeworkCompletionMode { direct, auto }

/// One activated homework section (e.g. 교과서) for a single record.
class HomeworkSection {
  /// Stable identifier, lower-case ASCII slug (e.g. 'textbook', 'workbook').
  final String sectionId;

  /// Optional stable id for the parent category (class-specific). When null,
  /// legacy data groups rows by [sectionName] only.
  final String? categoryId;
  final String sectionName;
  final bool isDefault;

  /// Selected sub-section text, e.g. "본문 읽기". Null = not selected.
  final String? subSection;

  /// Optional free-text detail memo (the "..." field). Null = not entered.
  final String? detailMemo;

  /// Number of filled dots, 0–5.
  final int checkCount;

  const HomeworkSection({
    required this.sectionId,
    this.categoryId,
    required this.sectionName,
    this.isDefault = false,
    this.subSection,
    this.detailMemo,
    this.checkCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'sectionId': sectionId,
    if (categoryId != null) 'categoryId': categoryId,
    'sectionName': sectionName,
    'isDefault': isDefault,
    'subSection': subSection,
    'detailMemo': detailMemo,
    'checkCount': checkCount,
  };

  factory HomeworkSection.fromJson(Map<String, dynamic> json) =>
      HomeworkSection(
        sectionId:
            json['sectionId'] as String? ??
            (json['name'] as String? ?? 'unknown').toLowerCase().replaceAll(
              ' ',
              '_',
            ),
        categoryId: json['categoryId'] as String?,
        sectionName:
            json['sectionName'] as String? ?? json['name'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
        subSection: json['subSection'] as String?,
        detailMemo:
            json['detailMemo'] as String? ?? json['subContent'] as String?,
        checkCount: json['checkCount'] as int? ?? 0,
      );

  HomeworkSection copyWith({
    String? sectionId,
    Object? categoryId = _undefined,
    String? sectionName,
    bool? isDefault,
    Object? subSection = _undefined,
    Object? detailMemo = _undefined,
    int? checkCount,
  }) => HomeworkSection(
    sectionId: sectionId ?? this.sectionId,
    categoryId: identical(categoryId, _undefined)
        ? this.categoryId
        : categoryId as String?,
    sectionName: sectionName ?? this.sectionName,
    isDefault: isDefault ?? this.isDefault,
    subSection: identical(subSection, _undefined)
        ? this.subSection
        : subSection as String?,
    detailMemo: identical(detailMemo, _undefined)
        ? this.detailMemo
        : detailMemo as String?,
    checkCount: checkCount ?? this.checkCount,
  );

  static const Object _undefined = Object();
}

// ─── HomeworkRecord ──────────────────────────────────────────────────────────

class HomeworkRecord {
  final String id;
  final String studentId;
  final String? classId;
  final String className;
  final String title;

  /// Activated sections with their dot-check counts.
  final List<HomeworkSection> sections;

  final HomeworkCompletionMode completionMode;

  /// Set when mode == direct. Null otherwise.
  final int? manualCompletionRate;

  /// Auto-calculated from dot counts (always kept up to date).
  final int autoCompletionRate;

  /// The value that is shown externally and sent in notifications.
  final int finalCompletionRate;

  final DateTime dueDate;
  final DateTime submittedDate;
  final bool isSubmitted;
  final String? note;
  final int createdAt;

  /// Backwards-compat alias used by existing code that reads completionPercent.
  int get completionPercent => finalCompletionRate;

  const HomeworkRecord({
    required this.id,
    required this.studentId,
    this.classId,
    required this.className,
    required this.title,
    this.sections = const [],
    this.completionMode = HomeworkCompletionMode.auto,
    this.manualCompletionRate,
    this.autoCompletionRate = 0,
    this.finalCompletionRate = 0,
    required this.dueDate,
    required this.submittedDate,
    required this.isSubmitted,
    this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'classId': classId,
    'className': className,
    'title': title,
    'sections': sections.map((s) => s.toJson()).toList(),
    'completionMode': completionMode.name,
    'manualCompletionRate': manualCompletionRate,
    'autoCompletionRate': autoCompletionRate,
    'finalCompletionRate': finalCompletionRate,
    'dueDate': dueDate.toIso8601String(),
    'submittedDate': submittedDate.toIso8601String(),
    'isSubmitted': isSubmitted,
    'note': note,
    'createdAt': createdAt,
  };

  factory HomeworkRecord.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    final sections = (rawSections is List)
        ? rawSections
              .whereType<Map>()
              .map(
                (e) => HomeworkSection.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <HomeworkSection>[];

    HomeworkCompletionMode mode = HomeworkCompletionMode.auto;
    final rawMode = json['completionMode'] as String?;
    if (rawMode != null) {
      mode = HomeworkCompletionMode.values.firstWhere(
        (m) => m.name == rawMode,
        orElse: () => HomeworkCompletionMode.auto,
      );
      // Legacy: 'direct'/'calculated' mapping
      if (rawMode == 'direct') mode = HomeworkCompletionMode.direct;
      if (rawMode == 'calculated') mode = HomeworkCompletionMode.auto;
    }

    // Legacy: read old completionPercent field
    final legacyPct = _grInt(json, 'completionPercent', 0);
    final finalRate = _grInt(json, 'finalCompletionRate', legacyPct);
    final autoRate = _grInt(json, 'autoCompletionRate', finalRate);
    final manualRate = json['manualCompletionRate'] == null
        ? null
        : _grInt(json, 'manualCompletionRate');
    final now = DateTime.now();

    return HomeworkRecord(
      id: _grString(json, 'id'),
      studentId: _grString(json, 'studentId'),
      classId: json['classId']?.toString(),
      className: _grString(json, 'className'),
      title: _grString(json, 'title'),
      sections: sections,
      completionMode: mode,
      manualCompletionRate: manualRate,
      autoCompletionRate: autoRate,
      finalCompletionRate: finalRate,
      dueDate: _grDateTime(json, 'dueDate', now),
      submittedDate: _grDateTime(json, 'submittedDate', now),
      isSubmitted: json['isSubmitted'] as bool? ?? false,
      note: json['note']?.toString(),
      createdAt: _grInt(json, 'createdAt'),
    );
  }

  HomeworkRecord copyWith({
    String? id,
    String? studentId,
    String? classId,
    String? className,
    String? title,
    List<HomeworkSection>? sections,
    HomeworkCompletionMode? completionMode,
    Object? manualCompletionRate = _undefined,
    int? autoCompletionRate,
    int? finalCompletionRate,
    DateTime? dueDate,
    DateTime? submittedDate,
    bool? isSubmitted,
    String? note,
    int? createdAt,
  }) => HomeworkRecord(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    classId: classId ?? this.classId,
    className: className ?? this.className,
    title: title ?? this.title,
    sections: sections ?? this.sections,
    completionMode: completionMode ?? this.completionMode,
    manualCompletionRate: identical(manualCompletionRate, _undefined)
        ? this.manualCompletionRate
        : manualCompletionRate as int?,
    autoCompletionRate: autoCompletionRate ?? this.autoCompletionRate,
    finalCompletionRate: finalCompletionRate ?? this.finalCompletionRate,
    dueDate: dueDate ?? this.dueDate,
    submittedDate: submittedDate ?? this.submittedDate,
    isSubmitted: isSubmitted ?? this.isSubmitted,
    note: note ?? this.note,
    createdAt: createdAt ?? this.createdAt,
  );

  static const Object _undefined = Object();
}

enum GradeLevel { aPlus, a0, aMinus, bPlus, b0, bMinus, c }

extension GradeLevelExtension on GradeLevel {
  String get label {
    switch (this) {
      case GradeLevel.aPlus:
        return 'A+';
      case GradeLevel.a0:
        return 'A0';
      case GradeLevel.aMinus:
        return 'A-';
      case GradeLevel.bPlus:
        return 'B+';
      case GradeLevel.b0:
        return 'B0';
      case GradeLevel.bMinus:
        return 'B-';
      case GradeLevel.c:
        return 'C';
    }
  }
}

class WordExamRecord {
  final String id;
  final String studentId;
  final String? classId;
  final String className;
  final int score;
  final int totalScore;
  final double classAverage;
  final bool needsRetake;
  final int retakePassingScore; // 재시 기준
  final int? retakeScore;
  final DateTime createdAt;

  const WordExamRecord({
    required this.id,
    required this.studentId,
    this.classId,
    required this.className,
    required this.score,
    required this.totalScore,
    required this.classAverage,
    required this.needsRetake,
    required this.retakePassingScore,
    this.retakeScore,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'classId': classId,
      'className': className,
      'score': score,
      'totalScore': totalScore,
      'classAverage': classAverage,
      'needsRetake': needsRetake,
      'retakePassingScore': retakePassingScore,
      'retakeScore': retakeScore,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory WordExamRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return WordExamRecord(
      id: _grString(json, 'id'),
      studentId: _grString(json, 'studentId'),
      classId: json['classId']?.toString(),
      className: _grString(json, 'className'),
      score: _grInt(json, 'score'),
      totalScore: _grInt(json, 'totalScore'),
      classAverage: _grDouble(json, 'classAverage'),
      needsRetake: json['needsRetake'] as bool? ?? false,
      retakePassingScore: _grInt(json, 'retakePassingScore'),
      retakeScore: json['retakeScore'] == null
          ? null
          : _grInt(json, 'retakeScore'),
      createdAt: _grDateTime(json, 'createdAt', now),
    );
  }

  WordExamRecord copyWith({
    String? id,
    String? studentId,
    String? classId,
    String? className,
    int? score,
    int? totalScore,
    double? classAverage,
    bool? needsRetake,
    int? retakePassingScore,
    int? retakeScore,
    DateTime? createdAt,
  }) {
    return WordExamRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      score: score ?? this.score,
      totalScore: totalScore ?? this.totalScore,
      classAverage: classAverage ?? this.classAverage,
      needsRetake: needsRetake ?? this.needsRetake,
      retakePassingScore: retakePassingScore ?? this.retakePassingScore,
      retakeScore: retakeScore ?? this.retakeScore,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ReviewExamRecord {
  final String id;
  final String studentId;
  final String? classId;
  final String className;
  final GradeLevel grade; // A+, A0, A-, B+, B0, B-, C
  final GradeLevel classAverage;
  final bool needsRetake;
  final GradeLevel retakePassingGrade;
  final GradeLevel? retakeGrade;
  final DateTime createdAt;

  const ReviewExamRecord({
    required this.id,
    required this.studentId,
    this.classId,
    required this.className,
    required this.grade,
    required this.classAverage,
    required this.needsRetake,
    required this.retakePassingGrade,
    this.retakeGrade,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'classId': classId,
      'className': className,
      'grade': grade.name,
      'classAverage': classAverage.name,
      'needsRetake': needsRetake,
      'retakePassingGrade': retakePassingGrade.name,
      'retakeGrade': retakeGrade?.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ReviewExamRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ReviewExamRecord(
      id: _grString(json, 'id'),
      studentId: _grString(json, 'studentId'),
      classId: json['classId']?.toString(),
      className: _grString(json, 'className'),
      grade: _grGradeLevel(json['grade']),
      classAverage: _grGradeLevel(json['classAverage']),
      needsRetake: json['needsRetake'] as bool? ?? false,
      retakePassingGrade: _grGradeLevel(json['retakePassingGrade']),
      retakeGrade: json['retakeGrade'] != null
          ? _grGradeLevel(json['retakeGrade'])
          : null,
      createdAt: _grDateTime(json, 'createdAt', now),
    );
  }

  ReviewExamRecord copyWith({
    String? id,
    String? studentId,
    String? classId,
    String? className,
    GradeLevel? grade,
    GradeLevel? classAverage,
    bool? needsRetake,
    GradeLevel? retakePassingGrade,
    GradeLevel? retakeGrade,
    DateTime? createdAt,
  }) {
    return ReviewExamRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      grade: grade ?? this.grade,
      classAverage: classAverage ?? this.classAverage,
      needsRetake: needsRetake ?? this.needsRetake,
      retakePassingGrade: retakePassingGrade ?? this.retakePassingGrade,
      retakeGrade: retakeGrade ?? this.retakeGrade,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
