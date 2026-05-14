import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/grade_record_model.dart';
import 'class_service.dart';

class GradeRecordService {
  static const String _attendanceKey = 'attendance_v1';
  static const String _homeworkKey = 'homework_v1';
  static const String _wordExamKey = 'word_exam_v1';
  static const String _reviewExamKey = 'review_exam_v1';

  final SharedPreferences _prefs;

  const GradeRecordService({required SharedPreferences prefs}) : _prefs = prefs;

  Future<GradeRecordSnapshot> getSnapshot() async {
    await _ensureClassIdMigration();
    final attendanceJson = _prefs.getString(_attendanceKey);
    final homeworkJson = _prefs.getString(_homeworkKey);
    final wordExamJson = _prefs.getString(_wordExamKey);
    final reviewExamJson = _prefs.getString(_reviewExamKey);

    return GradeRecordSnapshot(
      attendance: _decodeList(attendanceJson, AttendanceRecord.fromJson),
      homework: _decodeList(homeworkJson, HomeworkRecord.fromJson),
      wordExams: _decodeList(wordExamJson, WordExamRecord.fromJson),
      reviewExams: _decodeList(reviewExamJson, ReviewExamRecord.fromJson),
    );
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <T>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ============ Attendance ============
  Future<void> saveAttendance(AttendanceRecord record) async {
    final records = await getAllAttendance();
    final index = records.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }
    await _prefs.setString(
      _attendanceKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  Future<List<AttendanceRecord>> getAllAttendance() async {
    await _ensureClassIdMigration();
    final json = _prefs.getString(_attendanceKey);
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(AttendanceRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AttendanceRecord>> getStudentAttendance(String studentId) async {
    final all = await getAllAttendance();
    return all.where((r) => r.studentId == studentId).toList();
  }

  Future<List<AttendanceRecord>> getClassAttendance(
    String className,
    DateTime date,
  ) async {
    final all = await getAllAttendance();
    final dateOnly = DateTime(date.year, date.month, date.day);
    return all
        .where(
          (r) =>
              r.className == className &&
              DateTime(r.date.year, r.date.month, r.date.day) == dateOnly,
        )
        .toList();
  }

  // ============ Homework ============
  Future<void> saveHomework(HomeworkRecord record) async {
    final records = await getAllHomework();
    final index = records.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }
    await _prefs.setString(
      _homeworkKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  Future<List<HomeworkRecord>> getAllHomework() async {
    await _ensureClassIdMigration();
    final json = _prefs.getString(_homeworkKey);
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(HomeworkRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<HomeworkRecord>> getStudentHomework(String studentId) async {
    final all = await getAllHomework();
    return all.where((r) => r.studentId == studentId).toList();
  }

  Future<HomeworkRecord?> getLatestHomework(String studentId) async {
    final records = await getStudentHomework(studentId);
    if (records.isEmpty) return null;
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records.first;
  }

  // ============ Word Exam ============
  Future<void> saveWordExam(WordExamRecord record) async {
    final records = await getAllWordExams();
    final index = records.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }
    await _prefs.setString(
      _wordExamKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  Future<List<WordExamRecord>> getAllWordExams() async {
    await _ensureClassIdMigration();
    final json = _prefs.getString(_wordExamKey);
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(WordExamRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<WordExamRecord?> getStudentWordExam(String studentId) async {
    final all = await getAllWordExams();
    final filtered = all.where((r) => r.studentId == studentId).toList();
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered.first;
  }

  // ============ Review Exam ============
  Future<void> saveReviewExam(ReviewExamRecord record) async {
    final records = await getAllReviewExams();
    final index = records.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      records[index] = record;
    } else {
      records.add(record);
    }
    await _prefs.setString(
      _reviewExamKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  Future<List<ReviewExamRecord>> getAllReviewExams() async {
    await _ensureClassIdMigration();
    final json = _prefs.getString(_reviewExamKey);
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(ReviewExamRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<ReviewExamRecord?> getStudentReviewExam(String studentId) async {
    final all = await getAllReviewExams();
    final filtered = all.where((r) => r.studentId == studentId).toList();
    if (filtered.isEmpty) return null;
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered.first;
  }

  Future<void> _ensureClassIdMigration() async {
    final classService = ClassService(prefs: _prefs);
    final classMap = {
      for (final item in await classService.getAllClasses())
        item.name.trim(): item.id,
    };

    await _migrateListClassIds(_attendanceKey, classMap);
    await _migrateListClassIds(_homeworkKey, classMap);
    await _migrateListClassIds(_wordExamKey, classMap);
    await _migrateListClassIds(_reviewExamKey, classMap);
  }

  Future<void> _migrateListClassIds(
    String key,
    Map<String, String> classMap,
  ) async {
    final raw = _prefs.getString(key);
    if (raw == null) return;

    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return;
      final decoded = parsed
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      var changed = false;
      for (final item in decoded) {
        final existingId = (item['classId'] as String?)?.trim();
        if (existingId != null && existingId.isNotEmpty) continue;
        final className = (item['className'] as String?)?.trim();
        if (className == null || className.isEmpty) continue;
        final mappedId = classMap[className];
        if (mappedId == null || mappedId.isEmpty) continue;
        item['classId'] = mappedId;
        changed = true;
      }
      if (changed) {
        await _prefs.setString(key, jsonEncode(decoded));
      }
    } catch (_) {
      return;
    }
  }
}

class GradeRecordSnapshot {
  final List<AttendanceRecord> attendance;
  final List<HomeworkRecord> homework;
  final List<WordExamRecord> wordExams;
  final List<ReviewExamRecord> reviewExams;

  const GradeRecordSnapshot({
    required this.attendance,
    required this.homework,
    required this.wordExams,
    required this.reviewExams,
  });
}
