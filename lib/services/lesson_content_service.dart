import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LessonContentService {
  static const _key = 'lesson_content_v1';

  final SharedPreferences _prefs;

  const LessonContentService({required SharedPreferences prefs})
    : _prefs = prefs;

  Future<List<String>> getLessonContent(String className) async {
    final all = _getAll();
    final value = all[className];
    if (value is List) {
      return value
          .whereType<String>()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<void> saveLessonContent(String className, List<String> items) async {
    final all = _getAll();
    all[className] = items
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    await _prefs.setString(_key, jsonEncode(all));
  }

  Future<void> renameClassContent(String oldName, String newName) async {
    final all = _getAll();
    if (!all.containsKey(oldName)) return;
    all[newName] = all.remove(oldName);
    await _prefs.setString(_key, jsonEncode(all));
  }

  Future<void> deleteClassContent(String className) async {
    final all = _getAll();
    all.remove(className);
    await _prefs.setString(_key, jsonEncode(all));
  }

  Map<String, dynamic> _getAll() {
    final raw = _prefs.getString(_key);
    if (raw == null) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
