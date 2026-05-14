import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import 'class_service.dart';

class StudentService {
  static const String _studentsKey = 'students_v1';
  static const String _classMetaKey = 'class_meta_v1';
  static const String unassignedGroupLabel = '기타';
  static const _uuid = Uuid();
  static const Map<String, List<String>> _legacyMockStudents = {
    '이화여고 2학년': ['김민수', '박지아', '이서연', '최하준', '정민서'],
    '개포고 1학년': ['강윤아', '오지훈', '한서윤', '윤태민'],
    '고3 내신반': ['장도윤', '임채원', '서민재', '권하린'],
  };

  final SharedPreferences _prefs;

  const StudentService({required SharedPreferences prefs}) : _prefs = prefs;

  /// Save or update a student.
  Future<void> saveStudent(Student student) async {
    final students = (await getAllStudents()).toList();
    final index = students.indexWhere((s) => s.id == student.id);

    if (index >= 0) {
      students[index] = student;
    } else {
      students.add(student);
    }

    final json = jsonEncode(students.map((s) => s.toJson()).toList());
    await _prefs.setString(_studentsKey, json);
  }

  /// Get all students.
  Future<List<Student>> getAllStudents() async {
    await _migrateLegacyStudentClassRefs();

    final json = _prefs.getString(_studentsKey);
    if (json == null || json.trim().isEmpty) return [];

    try {
      final classes = await _readClassMeta();
      final namesById = {for (final item in classes) item.id: item.name};
      final decoded = jsonDecode(json);
      if (decoded is! List) return [];
      final out = <Student>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final map = Map<String, dynamic>.from(item);
          final classId = map['classId']?.toString();
          final model = Student.fromJson(
            map,
            resolvedClassName:
                namesById[classId] ?? map['className']?.toString(),
          );
          if (model.id.isEmpty || model.name.trim().isEmpty) continue;
          out.add(model);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<Student>> getStudentsByClassId(String classId) async {
    final all = await getAllStudents();
    return all.where((s) => s.classId == classId).toList();
  }

  /// Get students by resolved class name for legacy callers.
  ///
  /// [classKey] may be [ClassDisplayItem.displayName], [ClassMeta.name],
  /// or [ClassMeta.id] (UUID).
  Future<List<Student>> getStudentsByClass(String classKey) async {
    final trimmed = classKey.trim();
    if (trimmed.isEmpty) return const [];

    final all = await getAllStudents();
    final byCanonicalName = all.where((s) => s.className == trimmed).toList();
    if (byCanonicalName.isNotEmpty) return byCanonicalName;

    final cs = ClassService(prefs: _prefs);
    await cs.initializeFromMockIfNeeded();
    final items = await cs.getDisplayItems();
    for (final item in items) {
      if (item.displayName == trimmed || item.id == trimmed) {
        return all.where((s) => s.classId == item.id).toList();
      }
    }

    return const [];
  }

  /// 반 목록 (UI/선택용). 같은 이름의 반이 둘 이상이면 [ClassDisplayItem.displayName]으로 구분됩니다.
  Future<List<String>> getClassNames() async {
    final cs = ClassService(prefs: _prefs);
    await cs.initializeFromMockIfNeeded();
    final items = await cs.getDisplayItems();
    if (items.isNotEmpty) {
      return items.map((e) => e.displayName).toList();
    }

    final all = await getAllStudents();
    final names = all
        .map((s) => s.className?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();

    final classMetaRaw = _prefs.getString(_classMetaKey);
    if (classMetaRaw != null) {
      try {
        final decoded = jsonDecode(classMetaRaw);
        if (decoded is! List)
          throw const FormatException('class meta not list');
        for (final item in decoded.whereType<Map>()) {
          final map = Map<String, dynamic>.from(item);
          final name = map['name']?.toString().trim();
          if (name != null && name.isNotEmpty) {
            names.add(name);
          }
        }
      } catch (_) {
        // ignore malformed metadata cache
      }
    }

    final unique = names.toSet().toList()..sort();
    return unique;
  }

  /// 학생을 반별로 묶습니다. 키는 [ClassDisplayItem.displayName] (UI와 동일)입니다.
  Future<Map<String, List<Student>>> getStudentsGroupedByClass() async {
    final all = await getAllStudents();
    final cs = ClassService(prefs: _prefs);
    await cs.initializeFromMockIfNeeded();
    final items = await cs.getDisplayItems();
    final idToDisplay = {for (final i in items) i.id: i.displayName};

    final grouped = <String, List<Student>>{};
    for (final student in all) {
      final classId = student.classId.trim();
      final resolvedById = idToDisplay[classId];
      final label =
          resolvedById ??
          (classId.isEmpty
              ? ((student.className?.trim().isNotEmpty ?? false)
                    ? student.className!.trim()
                    : unassignedGroupLabel)
              : unassignedGroupLabel);
      if (label.isEmpty) continue;
      grouped.putIfAbsent(label, () => []).add(student);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    return {
      for (final key in sortedKeys)
        key: [...grouped[key]!]..sort((a, b) => a.name.compareTo(b.name)),
    };
  }

  /// Get student by ID.
  Future<Student?> getStudentById(String id) async {
    final all = await getAllStudents();
    try {
      return all.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Update student's parent phone.
  Future<void> updateParentPhone(String studentId, String phone) async {
    final student = await getStudentById(studentId);
    if (student == null) return;

    final updated = student.copyWith(
      parentPhone: phone,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await saveStudent(updated);
  }

  Future<void> updateStudentPhones({
    required String studentId,
    String? phone,
    String? parentPhone,
  }) async {
    final student = await getStudentById(studentId);
    if (student == null) return;

    final updated = student.copyWith(
      phone: phone,
      parentPhone: parentPhone,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await saveStudent(updated);
  }

  /// Delete a student.
  Future<void> deleteStudent(String studentId) async {
    final students = (await getAllStudents()).toList();
    students.removeWhere((s) => s.id == studentId);
    final json = jsonEncode(students.map((s) => s.toJson()).toList());
    await _prefs.setString(_studentsKey, json);
  }

  Future<void> initializeMockStudents() async {
    final existing = await getAllStudents();
    if (!_matchesLegacyMockStudents(existing)) {
      return;
    }

    await _prefs.remove(_studentsKey);
  }

  bool _matchesLegacyMockStudents(List<Student> students) {
    final expectedCount = _legacyMockStudents.values.fold<int>(
      0,
      (sum, names) => sum + names.length,
    );
    if (students.length != expectedCount) {
      return false;
    }

    final actual = <String, Set<String>>{};
    for (final student in students) {
      final className = student.className;
      if (className == null || className.isEmpty) {
        return false;
      }
      actual.putIfAbsent(className, () => <String>{}).add(student.name);
    }

    if (actual.length != _legacyMockStudents.length) {
      return false;
    }

    for (final entry in _legacyMockStudents.entries) {
      final actualNames = actual[entry.key];
      final expectedNames = entry.value.toSet();
      if (actualNames == null || actualNames.length != expectedNames.length) {
        return false;
      }
      if (!actualNames.containsAll(expectedNames)) {
        return false;
      }
    }

    return true;
  }

  Future<void> _migrateLegacyStudentClassRefs() async {
    final rawStudents = _prefs.getString(_studentsKey);
    if (rawStudents == null) return;

    try {
      final decoded = (jsonDecode(rawStudents) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (decoded.isEmpty) return;

      final classes = await _readClassMeta();
      final classesByName = <String, List<ClassMeta>>{};
      for (final item in classes) {
        classesByName.putIfAbsent(item.name.trim(), () => []).add(item);
      }

      var studentsChanged = false;
      var classesChanged = false;
      for (final item in decoded) {
        final classId = (item['classId'] as String?)?.trim();
        if (classId != null && classId.isNotEmpty) {
          item.remove('className');
          continue;
        }

        final legacyName = (item['className'] as String?)?.trim();
        if (legacyName == null || legacyName.isEmpty) continue;

        final matches = classesByName[legacyName] ?? <ClassMeta>[];
        ClassMeta target;
        if (matches.isNotEmpty) {
          target = matches.first;
        } else {
          final now = DateTime.now().millisecondsSinceEpoch;
          target = ClassMeta(
            id: _uuid.v4(),
            name: legacyName,
            meetingTime: null,
            weekdays: const [],
            colorValue: const Color(0xFF4DA3FF).toARGB32(),
            note: null,
            createdAt: now,
            updatedAt: now,
          );
          classes.add(target);
          classesByName.putIfAbsent(legacyName, () => []).add(target);
          classesChanged = true;
        }

        item['classId'] = target.id;
        item.remove('className');
        studentsChanged = true;
      }

      if (classesChanged) {
        classes.sort((a, b) {
          final byName = a.name.compareTo(b.name);
          if (byName != 0) return byName;
          final byCreated = a.createdAt.compareTo(b.createdAt);
          if (byCreated != 0) return byCreated;
          return a.id.compareTo(b.id);
        });
        await _prefs.setString(
          _classMetaKey,
          jsonEncode(classes.map((item) => item.toJson()).toList()),
        );
      }

      if (studentsChanged) {
        await _prefs.setString(_studentsKey, jsonEncode(decoded));
      }
    } catch (_) {
      return;
    }
  }

  Future<List<ClassMeta>> _readClassMeta() async {
    final raw = _prefs.getString(_classMetaKey);
    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ClassMeta.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
