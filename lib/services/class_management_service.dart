import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/class_model.dart';
import '../data/models/homework_models.dart';
import 'announcement_service.dart';
import 'class_service.dart';
import 'class_exam_type_service.dart';
import 'exam_session_service.dart';
import 'grade_record_service.dart';
import 'grade_service.dart';
import 'lesson_content_service.dart';
import 'student_service.dart';

class ClassManagementService {
  static const _homeworkTemplateKey = 'hw_tmpl_v2';
  static const _homeworkResultsKey = 'hw_res_v2';
  static const _homeworkHistoryKey = 'hw_hist_v2';
  static const _nextWeekKey = 'hw_next_v2';
  static const _sendingScheduleKey = 'sending_schedule_v1';

  final SharedPreferences _prefs;
  late final ClassService _classService;
  late final StudentService _studentService;
  late final GradeService _gradeService;
  late final GradeRecordService _gradeRecordService;
  late final AnnouncementService _announcementService;
  late final ExamSessionService _examSessionService;
  late final ClassExamTypeService _classExamTypeService;
  late final LessonContentService _lessonContentService;

  ClassManagementService({required SharedPreferences prefs}) : _prefs = prefs {
    _classService = ClassService(prefs: prefs);
    _studentService = StudentService(prefs: prefs);
    _gradeService = GradeService(prefs: prefs);
    _gradeRecordService = GradeRecordService(prefs: prefs);
    _announcementService = AnnouncementService(prefs: prefs);
    _examSessionService = ExamSessionService(prefs: prefs);
    _classExamTypeService = ClassExamTypeService(prefs: prefs);
    _lessonContentService = LessonContentService(prefs: prefs);
  }

  Future<void> createClass(String className) async {
    await _classService.createClass(className: className);
  }

  Future<void> saveClass({
    required ClassMeta updated,
    String? previousName,
  }) async {
    final oldName = (previousName ?? updated.name).trim();
    final newName = updated.name.trim();
    if (newName.isEmpty) return;

    await _classService.upsertClass(updated);
    if (oldName == newName) return;

    await _syncStudentClassDisplayNames(
      classId: updated.id,
      newClassLabel: newName,
    );

    await _renameGradeRecords(oldName, newName);
    await _renameGradeSnapshotRecords(oldName, newName);
    await _renameAnnouncements(oldName, newName);
    await _renameHomeworkPageRecords(oldName, newName);
    await _renameExamSessions(oldName, newName);
    await _lessonContentService.renameClassContent(oldName, newName);
  }

  Future<void> deleteClass(ClassMeta item) async {
    final className = item.name.trim();
    final classId = item.id.trim();

    await _detachStudentsByClassId(item.id);
    await _deleteGradeRecords(className);
    await _deleteGradeSnapshotRecords(className);
    await _deleteAnnouncements(className);
    await _deleteHomeworkPageRecords(className);
    if (classId.isNotEmpty && classId != className) {
      await _deleteHomeworkPageRecords(classId);
    }
    await _deleteExamSessions(className);
    await _classExamTypeService.removeAllForClass(classId);
    await _lessonContentService.deleteClassContent(className);
    await _classService.deleteClass(item.id);
  }

  Future<void> ensureClassMetaForStudentNames() async {
    final studentNames = await _studentService.getClassNames();
    final classes = await _classService.getAllClasses();
    final existing = classes.map((e) => e.name).toSet();
    for (final name in studentNames) {
      if (!existing.contains(name)) {
        await _classService.createClass(className: name);
      }
    }
  }

  Future<void> _syncStudentClassDisplayNames({
    required String classId,
    required String newClassLabel,
  }) async {
    final id = classId.trim();
    if (id.isEmpty) return;
    final students = await _studentService.getAllStudents();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final s in students.where((s) => s.classId.trim() == id)) {
      if (s.className == newClassLabel) continue;
      await _studentService.saveStudent(
        s.copyWith(className: newClassLabel, updatedAt: now),
      );
    }
  }

  Future<void> _detachStudentsByClassId(String classId) async {
    final students = await _studentService.getAllStudents();
    for (final student in students.where((s) => s.classId == classId)) {
      await _studentService.saveStudent(
        student.copyWith(
          classId: '',
          className: null,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> _renameGradeRecords(String oldName, String newName) async {
    final records = await _gradeService.getAllGradeRecords();
    for (final record in records.where((r) => r.className == oldName)) {
      final updated = record.copyWith(
        className: newName,
        grades: record.grades
            .map((g) => g.copyWith(className: newName))
            .toList(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _gradeService.saveGradeRecord(updated);
    }
  }

  Future<void> _deleteGradeRecords(String className) async {
    final records = await _gradeService.getAllGradeRecords();
    for (final record in records.where((r) => r.className == className)) {
      await _gradeService.deleteGradeRecord(record.id);
    }
  }

  Future<void> _renameGradeSnapshotRecords(
    String oldName,
    String newName,
  ) async {
    final attendance = await _gradeRecordService.getAllAttendance();
    await _writeJsonList(
      GradeRecordServiceAttendanceKey.value,
      attendance.map((record) {
        if (record.className != oldName) return record.toJson();
        return record.copyWith(className: newName).toJson();
      }).toList(),
    );

    final homework = await _gradeRecordService.getAllHomework();
    await _writeJsonList(
      GradeRecordServiceHomeworkKey.value,
      homework.map((record) {
        if (record.className != oldName) return record.toJson();
        return record.copyWith(className: newName).toJson();
      }).toList(),
    );

    final wordExams = await _gradeRecordService.getAllWordExams();
    await _writeJsonList(
      GradeRecordServiceWordExamKey.value,
      wordExams.map((record) {
        if (record.className != oldName) return record.toJson();
        return record.copyWith(className: newName).toJson();
      }).toList(),
    );

    final reviewExams = await _gradeRecordService.getAllReviewExams();
    await _writeJsonList(
      GradeRecordServiceReviewExamKey.value,
      reviewExams.map((record) {
        if (record.className != oldName) return record.toJson();
        return record.copyWith(className: newName).toJson();
      }).toList(),
    );
  }

  Future<void> _deleteGradeSnapshotRecords(String className) async {
    final attendance = await _gradeRecordService.getAllAttendance();
    await _writeJsonList(
      GradeRecordServiceAttendanceKey.value,
      attendance
          .where((record) => record.className != className)
          .map((record) => record.toJson())
          .toList(),
    );

    final homework = await _gradeRecordService.getAllHomework();
    await _writeJsonList(
      GradeRecordServiceHomeworkKey.value,
      homework
          .where((record) => record.className != className)
          .map((record) => record.toJson())
          .toList(),
    );

    final wordExams = await _gradeRecordService.getAllWordExams();
    await _writeJsonList(
      GradeRecordServiceWordExamKey.value,
      wordExams
          .where((record) => record.className != className)
          .map((record) => record.toJson())
          .toList(),
    );

    final reviewExams = await _gradeRecordService.getAllReviewExams();
    await _writeJsonList(
      GradeRecordServiceReviewExamKey.value,
      reviewExams
          .where((record) => record.className != className)
          .map((record) => record.toJson())
          .toList(),
    );
  }

  Future<void> _renameAnnouncements(String oldName, String newName) async {
    final announcements = await _announcementService.getAllAnnouncements();
    await _writeJsonList(
      AnnouncementServiceAnnouncementKey.value,
      announcements.map((announcement) {
        if (announcement.className != oldName) return announcement.toJson();
        return announcement.copyWith(className: newName).toJson();
      }).toList(),
    );

    await _renameStoredMapEntry(
      key: _sendingScheduleKey,
      oldName: oldName,
      newName: newName,
    );
  }

  Future<void> _deleteAnnouncements(String className) async {
    final announcements = await _announcementService.getAllAnnouncements();
    await _writeJsonList(
      AnnouncementServiceAnnouncementKey.value,
      announcements
          .where((announcement) => announcement.className != className)
          .map((announcement) => announcement.toJson())
          .toList(),
    );

    await _removeStoredMapEntry(key: _sendingScheduleKey, name: className);
  }

  Future<void> _renameHomeworkPageRecords(
    String oldName,
    String newName,
  ) async {
    await _renameHomeworkTemplateMap(oldName, newName);
    await _renameHomeworkResultsMap(oldName, newName);
    await _renameHomeworkHistoryMap(oldName, newName);
    await _renameNextWeekMap(oldName, newName);
  }

  Future<void> _deleteHomeworkPageRecords(String className) async {
    await _deleteHomeworkTemplateMap(className);
    await _deleteHomeworkResultsMap(className);
    await _deleteHomeworkHistoryMap(className);
    await _deleteNextWeekMap(className);
  }

  Future<void> _renameHomeworkTemplateMap(
    String oldName,
    String newName,
  ) async {
    await _renameStoredMapEntry(
      key: _homeworkTemplateKey,
      oldName: oldName,
      newName: newName,
      transform: (data) => ClassHomeworkTemplate.fromJson(
        Map<String, dynamic>.from(data as Map),
      ).copyWith(classId: newName).toJson(),
    );
  }

  Future<void> _deleteHomeworkTemplateMap(String className) async {
    await _removeStoredMapEntry(key: _homeworkTemplateKey, name: className);
  }

  Future<void> _renameHomeworkResultsMap(String oldName, String newName) async {
    await _rewriteStoredMap(_homeworkResultsKey, (outer) {
      final updated = <String, dynamic>{};
      for (final entry in outer.entries) {
        final key = entry.key;
        final renamedKey = key.startsWith('${oldName}_')
            ? '${newName}_${key.substring(oldName.length + 1)}'
            : key;
        final list = (entry.value as List? ?? [])
            .map(
              (e) => StudentHomeworkResult.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .map((e) => e.classId == oldName ? e.copyWith(classId: newName) : e)
            .map((e) => e.toJson())
            .toList();
        updated[renamedKey] = list;
      }
      return updated;
    });
  }

  Future<void> _deleteHomeworkResultsMap(String className) async {
    await _rewriteStoredMap(_homeworkResultsKey, (outer) {
      outer.removeWhere(
        (key, _) => key == className || key.startsWith('${className}_'),
      );
      return outer;
    });
  }

  Future<void> _renameHomeworkHistoryMap(String oldName, String newName) async {
    await _renameStoredMapEntry(
      key: _homeworkHistoryKey,
      oldName: oldName,
      newName: newName,
      transform: (data) => (data as List)
          .map(
            (e) => HomeworkHistoryEntry.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .map(
            (e) => HomeworkHistoryEntry(
              classId: newName,
              date: e.date,
              sections: e.sections,
              studentResults: e.studentResults,
            ),
          )
          .map((e) => e.toJson())
          .toList(),
    );
  }

  Future<void> _deleteHomeworkHistoryMap(String className) async {
    await _removeStoredMapEntry(key: _homeworkHistoryKey, name: className);
  }

  Future<void> _renameNextWeekMap(String oldName, String newName) async {
    await _renameStoredMapEntry(
      key: _nextWeekKey,
      oldName: oldName,
      newName: newName,
      transform: (data) => NextWeekHomework.fromJson(
        Map<String, dynamic>.from(data as Map),
      ).copyWith(classId: newName).toJson(),
    );
  }

  Future<void> _deleteNextWeekMap(String className) async {
    await _removeStoredMapEntry(key: _nextWeekKey, name: className);
  }

  Future<void> _renameExamSessions(String oldName, String newName) async {
    final sessions = _examSessionService.getAllSessions();
    for (final session in sessions.where((s) => s.className == oldName)) {
      await _examSessionService.saveSession(
        session.copyWith(className: newName),
      );
    }
  }

  Future<void> _deleteExamSessions(String className) async {
    final sessions = _examSessionService.getAllSessions();
    for (final session in sessions.where((s) => s.className == className)) {
      await _examSessionService.deleteSession(session.id);
    }
  }

  Future<void> _writeJsonList(
    String key,
    List<Map<String, dynamic>> data,
  ) async {
    await _prefs.setString(key, jsonEncode(data));
  }

  Future<void> _renameStoredMapEntry({
    required String key,
    required String oldName,
    required String newName,
    Object? Function(Object? data)? transform,
  }) async {
    await _updateStoredMap(key, (map) {
      if (!map.containsKey(oldName)) return false;

      final rawData = map.remove(oldName);
      if (rawData == null) return true;

      map[newName] = transform?.call(rawData) ?? rawData;
      return true;
    });
  }

  Future<void> _removeStoredMapEntry({
    required String key,
    required String name,
  }) async {
    await _updateStoredMap(key, (map) => map.remove(name) != null);
  }

  Future<void> _updateStoredMap(
    String key,
    bool Function(Map<String, dynamic> map) mutate,
  ) async {
    final raw = _prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final didChange = mutate(map);
      if (!didChange) return;
      await _prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> _rewriteStoredMap(
    String key,
    Map<String, dynamic> Function(Map<String, dynamic> map) rewrite,
  ) async {
    final raw = _prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final updated = rewrite(map);
      await _prefs.setString(key, jsonEncode(updated));
    } catch (_) {}
  }
}

class GradeRecordServiceAttendanceKey {
  static const value = 'attendance_v1';
}

class GradeRecordServiceHomeworkKey {
  static const value = 'homework_v1';
}

class GradeRecordServiceWordExamKey {
  static const value = 'word_exam_v1';
}

class GradeRecordServiceReviewExamKey {
  static const value = 'review_exam_v1';
}

class AnnouncementServiceAnnouncementKey {
  static const value = 'announcements_v1';
}
