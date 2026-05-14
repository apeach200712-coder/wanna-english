String _sgString(
  Map<String, dynamic> json,
  String key, [
  String fallback = '',
]) {
  final value = json[key];
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

int _sgInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double _sgDouble(Map<String, dynamic> json, String key, [double fallback = 0]) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

DateTime _sgDateTime(Map<String, dynamic> json, String key, DateTime fallback) {
  final value = json[key];
  if (value is String) return DateTime.tryParse(value) ?? fallback;
  return fallback;
}

class StudentGrade {
  final String studentId;
  final String name;
  final String className;
  final double score;
  final int timestamp;

  const StudentGrade({
    required this.studentId,
    required this.name,
    required this.className,
    required this.score,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'name': name,
      'className': className,
      'score': score,
      'timestamp': timestamp,
    };
  }

  factory StudentGrade.fromJson(Map<String, dynamic> json) {
    final className = _sgString(json, 'className');
    final name = _sgString(json, 'name');
    final fallbackStudentId = '${className}_$name';
    return StudentGrade(
      studentId: _sgString(json, 'studentId', fallbackStudentId),
      name: name,
      className: className,
      score: _sgDouble(json, 'score'),
      timestamp: _sgInt(json, 'timestamp'),
    );
  }

  StudentGrade copyWith({
    String? studentId,
    String? name,
    String? className,
    double? score,
    int? timestamp,
  }) {
    return StudentGrade(
      studentId: studentId ?? this.studentId,
      name: name ?? this.name,
      className: className ?? this.className,
      score: score ?? this.score,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

enum ExamType {
  vocabulary('단어'),
  grammar('어법어휘');

  final String label;
  const ExamType(this.label);
}

class GradeRecord {
  final String id;
  final String className;
  final DateTime examDate;
  final ExamType examType;
  final List<StudentGrade> grades;
  final int createdAt;
  final int updatedAt;

  const GradeRecord({
    required this.id,
    required this.className,
    required this.examDate,
    required this.examType,
    required this.grades,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'className': className,
      'examDate': examDate.toIso8601String(),
      'examType': examType.name,
      'grades': grades.map((g) => g.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory GradeRecord.fromJson(Map<String, dynamic> json) {
    final gradesJson = (json['grades'] as List<dynamic>?) ?? [];
    final now = DateTime.now();
    final examTypeRaw = _sgString(json, 'examType', ExamType.vocabulary.name);
    final examType =
        ExamType.values
            .where((value) => value.name == examTypeRaw)
            .firstOrNull ??
        ExamType.vocabulary;
    return GradeRecord(
      id: _sgString(json, 'id'),
      className: _sgString(json, 'className'),
      examDate: _sgDateTime(json, 'examDate', now),
      examType: examType,
      grades: gradesJson
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(StudentGrade.fromJson)
          .toList(),
      createdAt: _sgInt(json, 'createdAt'),
      updatedAt: _sgInt(json, 'updatedAt'),
    );
  }

  GradeRecord copyWith({
    String? id,
    String? className,
    DateTime? examDate,
    ExamType? examType,
    List<StudentGrade>? grades,
    int? createdAt,
    int? updatedAt,
  }) {
    return GradeRecord(
      id: id ?? this.id,
      className: className ?? this.className,
      examDate: examDate ?? this.examDate,
      examType: examType ?? this.examType,
      grades: grades ?? this.grades,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
