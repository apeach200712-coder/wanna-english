import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/models/class_model.dart';
import 'class_display_migration.dart';
import 'class_management_service.dart';

/// 내신/기타 클래스 중복 판별·표시 이름 번호 부여
class ClassIdentityUtils {
  ClassIdentityUtils._();

  static List<ClassMeta> findInternalDuplicates({
    required List<ClassMeta> all,
    required String schoolName,
    required String grade,
    String? excludeId,
  }) {
    final s = schoolName.trim();
    final g = grade.trim();
    return all
        .where(
          (c) =>
              c.id != excludeId &&
              c.programType == ClassProgramType.internalExam &&
              (c.schoolName?.trim() ?? '') == s &&
              (c.grade?.trim() ?? '') == g,
        )
        .toList();
  }

  static List<ClassMeta> findCustomDuplicates({
    required List<ClassMeta> all,
    required String baseLessonName,
    String? excludeId,
  }) {
    final b = baseLessonName.trim();
    return all.where((c) {
      if (c.id == excludeId) return false;
      if (c.programType != ClassProgramType.custom) return false;
      final key =
          (c.customClassName != null && c.customClassName!.trim().isNotEmpty)
          ? c.customClassName!.trim()
          : c.name.trim();
      return key == b;
    }).toList();
  }

  /// [base] 또는 [base (k)] 형태 중 사용되지 않는 전체 표시 문자열
  static String allocateNumberedDisplayName(
    String base,
    Set<String> occupiedNames,
  ) {
    final trimmed = base.trim();
    if (!occupiedNames.contains(trimmed)) return trimmed;
    var k = 1;
    while (occupiedNames.contains('$trimmed ($k)')) {
      k++;
    }
    return '$trimmed ($k)';
  }
}

class ClassService {
  static const _key = 'class_meta_v1';
  static const _uuid = Uuid();
  static const Map<String, _LegacyMockClassSeed> _legacyMockClasses = {
    '이화여고 2학년': _LegacyMockClassSeed(
      id: 'ewha_2',
      weekdays: [1, 3, 5],
      time: '18:00',
    ),
    '개포고 1학년': _LegacyMockClassSeed(
      id: 'gaepo_1',
      weekdays: [2, 4],
      time: '17:00',
    ),
    '고3 내신반': _LegacyMockClassSeed(
      id: 'grade_3',
      weekdays: [1, 4, 6],
      time: '16:00',
    ),
  };

  final SharedPreferences _prefs;

  const ClassService({required SharedPreferences prefs}) : _prefs = prefs;

  Future<void> initializeFromMockIfNeeded() async {
    final existing = await getAllClasses();
    if (!_matchesLegacyMockClasses(existing)) {
      return;
    }

    await _prefs.remove(_key);
  }

  Future<List<ClassMeta>> _loadClassesDecoded() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final items = <ClassMeta>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final model = ClassMeta.fromJson(Map<String, dynamic>.from(item));
          if (model.id.isEmpty || model.name.trim().isEmpty) continue;
          items.add(model);
        } catch (_) {}
      }
      _sortClasses(items);
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<List<ClassMeta>> getAllClasses() async {
    var items = await _loadClassesDecoded();
    if (items.isEmpty) return items;

    final mgmt = ClassManagementService(prefs: _prefs);
    var anyMigrated = false;
    for (final m in items) {
      final n = applyInternalClassDisplayMigration(m);
      if (n.name != m.name || n.grade != m.grade) {
        await mgmt.saveClass(updated: n, previousName: m.name);
        anyMigrated = true;
      }
    }
    if (anyMigrated) {
      items = await _loadClassesDecoded();
    }
    return items;
  }

  Future<List<ClassDisplayItem>> getDisplayItems() async {
    final items = await getAllClasses();
    return buildDisplayItems(items);
  }

  Future<String?> getDisplayNameById(String classId) async {
    final items = await getDisplayItems();
    try {
      return items.firstWhere((item) => item.id == classId).displayName;
    } catch (_) {
      return null;
    }
  }

  List<ClassDisplayItem> buildDisplayItems(List<ClassMeta> classes) {
    final ordered = [...classes];
    _sortClasses(ordered);

    final grouped = <String, List<ClassMeta>>{};
    for (final item in ordered) {
      grouped.putIfAbsent(item.name.trim(), () => []).add(item);
    }

    final result = <ClassDisplayItem>[];
    for (final item in ordered) {
      final group = grouped[item.name.trim()] ?? const <ClassMeta>[];
      final index = group.indexWhere((entry) => entry.id == item.id);
      final displayName = group.length <= 1
          ? item.name
          : '${item.name} (${index + 1})';
      result.add(
        ClassDisplayItem(
          id: item.id,
          name: item.name,
          displayName: displayName,
          meta: item,
        ),
      );
    }
    return result;
  }

  Future<ClassMeta?> getClassById(String id) async {
    final all = await getAllClasses();
    try {
      return all.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<ClassMeta?> getFirstClassByName(String className) async {
    final trimmed = className.trim();
    if (trimmed.isEmpty) return null;
    final all = await getAllClasses();
    try {
      return all.firstWhere((item) => item.name.trim() == trimmed);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getClassIdByName(String className) async {
    return (await getFirstClassByName(className))?.id;
  }

  Future<void> upsertClass(ClassMeta item) async {
    final all = (await _loadClassesDecoded()).toList();
    final idx = all.indexWhere((c) => c.id == item.id);
    if (idx >= 0) {
      all[idx] = item;
    } else {
      all.add(item);
    }
    await _saveAll(all);
  }

  Future<void> createClass({required String className}) async {
    final trimmed = className.trim();
    if (trimmed.isEmpty) return;

    final existing = await getAllClasses();

    final now = DateTime.now().millisecondsSinceEpoch;
    final newItem = ClassMeta(
      id: _uuid.v4(),
      name: trimmed,
      programType: ClassProgramType.custom,
      schoolName: null,
      grade: null,
      customClassName: trimmed,
      meetingTime: null,
      weekdays: const [],
      colorValue: const Color(0xFF4DA3FF).toARGB32(),
      note: null,
      createdAt: now,
      updatedAt: now,
    );
    await _saveAll([...existing, newItem]);
  }

  Future<void> deleteClass(String id) async {
    final all = (await _loadClassesDecoded()).toList();
    all.removeWhere((item) => item.id == id);
    await _saveAll(all);
  }

  Future<void> _saveAll(List<ClassMeta> items) async {
    _sortClasses(items);
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, raw);
  }

  void _sortClasses(List<ClassMeta> items) {
    items.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      final byCreated = a.createdAt.compareTo(b.createdAt);
      if (byCreated != 0) return byCreated;
      return a.id.compareTo(b.id);
    });
  }

  bool _matchesLegacyMockClasses(List<ClassMeta> classes) {
    if (classes.length != _legacyMockClasses.length) {
      return false;
    }

    for (final item in classes) {
      final seed = _legacyMockClasses[item.name];
      if (seed == null) {
        return false;
      }
      if (item.id != seed.id || item.meetingTime != seed.time) {
        return false;
      }
      if (item.weekdays.length != seed.weekdays.length) {
        return false;
      }
      for (int index = 0; index < item.weekdays.length; index++) {
        if (item.weekdays[index] != seed.weekdays[index]) {
          return false;
        }
      }
    }

    return true;
  }
}

class ClassDisplayItem {
  final String id;
  final String name;
  final String displayName;
  final ClassMeta meta;

  const ClassDisplayItem({
    required this.id,
    required this.name,
    required this.displayName,
    required this.meta,
  });
}

class _LegacyMockClassSeed {
  final String id;
  final List<int> weekdays;
  final String time;

  const _LegacyMockClassSeed({
    required this.id,
    required this.weekdays,
    required this.time,
  });
}
