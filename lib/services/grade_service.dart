import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/student_grade_model.dart';

class GradeService {
  static const String _gradeRecordsKey = 'grade_records_v2';

  final SharedPreferences _prefs;

  const GradeService({required SharedPreferences prefs}) : _prefs = prefs;

  /// Save or update a grade record for a class.
  Future<void> saveGradeRecord(GradeRecord record) async {
    final records = await getAllGradeRecords();
    final index = records.indexWhere((r) => r.id == record.id);

    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }

    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    await _prefs.setString(_gradeRecordsKey, json);
  }

  /// Update a single student grade within a record.
  Future<void> updateStudentGrade(
    String recordId,
    String studentId,
    String studentName,
    double score,
  ) async {
    final records = await getAllGradeRecords();
    final recordIndex = records.indexWhere((r) => r.id == recordId);

    if (recordIndex < 0) return;

    final record = records[recordIndex];
    final studentIndex = record.grades.indexWhere(
      (g) => g.studentId == studentId || g.name == studentName,
    );

    final updatedGrades = [...record.grades];
    if (studentIndex >= 0) {
      updatedGrades[studentIndex] = updatedGrades[studentIndex].copyWith(
        studentId: studentId,
        name: studentName,
        score: score,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      updatedGrades.add(
        StudentGrade(
          studentId: studentId,
          name: studentName,
          className: record.className,
          score: score,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    final updatedRecord = record.copyWith(
      grades: updatedGrades,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    records[recordIndex] = updatedRecord;
    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    await _prefs.setString(_gradeRecordsKey, json);
  }

  /// Create or update a single student grade while loading the full record list only once.
  Future<void> upsertStudentGrade({
    required String className,
    required DateTime examDate,
    required ExamType examType,
    required String studentId,
    required String studentName,
    required double score,
  }) async {
    final records = await getAllGradeRecords();
    final dateOnly = DateTime(examDate.year, examDate.month, examDate.day);

    final recordIndex = records.indexWhere((record) {
      final recordDateOnly = DateTime(
        record.examDate.year,
        record.examDate.month,
        record.examDate.day,
      );
      return record.className == className &&
          recordDateOnly == dateOnly &&
          record.examType == examType;
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    final record = recordIndex >= 0
        ? records[recordIndex]
        : GradeRecord(
            id: '${className}_${examDate.year}${examDate.month.toString().padLeft(2, '0')}${examDate.day.toString().padLeft(2, '0')}_${examType.name}',
            className: className,
            examDate: examDate,
            examType: examType,
            grades: const [],
            createdAt: now,
            updatedAt: now,
          );

    final updatedGrades = [...record.grades];
    final studentIndex = updatedGrades.indexWhere(
      (grade) => grade.studentId == studentId || grade.name == studentName,
    );
    if (studentIndex >= 0) {
      updatedGrades[studentIndex] = updatedGrades[studentIndex].copyWith(
        studentId: studentId,
        name: studentName,
        score: score,
        timestamp: now,
      );
    } else {
      updatedGrades.add(
        StudentGrade(
          studentId: studentId,
          name: studentName,
          className: className,
          score: score,
          timestamp: now,
        ),
      );
    }

    final updatedRecord = record.copyWith(
      grades: updatedGrades,
      updatedAt: now,
    );
    if (recordIndex >= 0) {
      records[recordIndex] = updatedRecord;
    } else {
      records.add(updatedRecord);
    }

    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    await _prefs.setString(_gradeRecordsKey, json);
  }

  /// Get all grade records.
  Future<List<GradeRecord>> getAllGradeRecords() async {
    final json = _prefs.getString(_gradeRecordsKey);
    if (json == null || json.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      final out = <GradeRecord>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(GradeRecord.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Get grade record by class, date, and exam type.
  Future<GradeRecord?> getGradeRecord({
    required String className,
    required DateTime examDate,
    required ExamType examType,
  }) async {
    final records = await getAllGradeRecords();
    final dateOnly = DateTime(examDate.year, examDate.month, examDate.day);
    final filtered = records.where((r) {
      final rDateOnly = DateTime(
        r.examDate.year,
        r.examDate.month,
        r.examDate.day,
      );
      return r.className == className &&
          rDateOnly == dateOnly &&
          r.examType == examType;
    }).toList();
    if (filtered.isEmpty) return null;
    return filtered.first;
  }

  /// Create a new grade record for a class/date/exam type.
  Future<GradeRecord> createGradeRecord({
    required String className,
    required DateTime examDate,
    required ExamType examType,
  }) async {
    final recordId =
        '${className}_${examDate.year}${examDate.month.toString().padLeft(2, '0')}${examDate.day.toString().padLeft(2, '0')}_${examType.name}';
    final now = DateTime.now().millisecondsSinceEpoch;

    return GradeRecord(
      id: recordId,
      className: className,
      examDate: examDate,
      examType: examType,
      grades: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Delete a grade record.
  Future<void> deleteGradeRecord(String recordId) async {
    final records = await getAllGradeRecords();
    records.removeWhere((r) => r.id == recordId);
    final json = jsonEncode(records.map((r) => r.toJson()).toList());
    await _prefs.setString(_gradeRecordsKey, json);
  }
}
