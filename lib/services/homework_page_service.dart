import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/homework_models.dart';

class HomeworkPageService {
  static const _templateKey = 'hw_tmpl_v2';
  static const _resultsKey = 'hw_res_v2';
  static const _historyKey = 'hw_hist_v2';
  static const _nextWeekKey = 'hw_next_v2';
  static const _inspectionKey = 'hw_insp_v1';
  static const _catMetaKey = 'hw_catmeta_v1';

  final SharedPreferences _prefs;

  HomeworkPageService({required SharedPreferences prefs}) : _prefs = prefs;

  Map<String, dynamic> _decodeOuterMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Iterable<String> _candidateKeys(
    String primaryKey,
    Iterable<String> fallbackKeys,
  ) sync* {
    final seen = <String>{};
    for (final key in [primaryKey, ...fallbackKeys]) {
      final normalized = key.trim();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      yield normalized;
    }
  }

  // ── Class homework template ───────────────────────────────────────────────

  ClassHomeworkTemplate? getTemplate(
    String classId, {
    Iterable<String> fallbackKeys = const [],
  }) {
    final map = _decodeOuterMap(_prefs.getString(_templateKey));
    for (final key in _candidateKeys(classId, fallbackKeys)) {
      final data = map[key];
      if (data is! Map) continue;
      try {
        return ClassHomeworkTemplate.fromJson(Map<String, dynamic>.from(data));
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveTemplate(ClassHomeworkTemplate t) async {
    final raw = _prefs.getString(_templateKey);
    final map = <String, dynamic>{};
    if (raw != null) {
      try {
        map.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    map[t.classId] = t.toJson();
    await _prefs.setString(_templateKey, jsonEncode(map));
  }

  // ── Student results ───────────────────────────────────────────────────────

  /// Returns all student results for a class/week combination.
  List<StudentHomeworkResult> getStudentResults(
    String classId,
    String weekStartDate, {
    Iterable<String> fallbackKeys = const [],
  }) {
    final outer = _decodeOuterMap(_prefs.getString(_resultsKey));
    for (final key in _candidateKeys(classId, fallbackKeys)) {
      final list = outer['${key}_$weekStartDate'];
      if (list is! List) continue;
      final out = <StudentHomeworkResult>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          out.add(
            StudentHomeworkResult.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {}
      }
      return out;
    }
    return [];
  }

  List<StudentHomeworkResult> getAllStudentResults() {
    final raw = _prefs.getString(_resultsKey);
    if (raw == null) return const [];
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      return outer.values
          .whereType<List>()
          .expand(
            (list) => list.map(
              (e) => StudentHomeworkResult.fromJson(e as Map<String, dynamic>),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveStudentResults(
    String classId,
    String weekStartDate,
    List<StudentHomeworkResult> results,
  ) async {
    final raw = _prefs.getString(_resultsKey);
    final outer = <String, dynamic>{};
    if (raw != null) {
      try {
        outer.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    final key = '${classId}_$weekStartDate';
    outer[key] = results.map((r) => r.toJson()).toList();
    await _prefs.setString(_resultsKey, jsonEncode(outer));
  }

  // ── History (LAST WEEKS) ──────────────────────────────────────────────────

  List<HomeworkHistoryEntry> getHistory(
    String classId, {
    Iterable<String> fallbackKeys = const [],
  }) {
    final outer = _decodeOuterMap(_prefs.getString(_historyKey));
    for (final key in _candidateKeys(classId, fallbackKeys)) {
      final list = outer[key];
      if (list is! List) continue;
      final out = <HomeworkHistoryEntry>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          out.add(
            HomeworkHistoryEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {}
      }
      return out;
    }
    return [];
  }

  List<HomeworkHistoryEntry> getAllHistoryEntries() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return const [];
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      return outer.values
          .whereType<List>()
          .expand(
            (list) => list.map(
              (e) => HomeworkHistoryEntry.fromJson(e as Map<String, dynamic>),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> archiveEntry(HomeworkHistoryEntry entry) async {
    final raw = _prefs.getString(_historyKey);
    final outer = <String, dynamic>{};
    if (raw != null) {
      try {
        outer.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    final existing = (outer[entry.classId] as List? ?? [])
        .map((e) => HomeworkHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final idx = existing.indexWhere((e) => e.date == entry.date);
    if (idx >= 0) {
      existing[idx] = entry;
    } else {
      existing.add(entry);
    }
    outer[entry.classId] = existing.map((e) => e.toJson()).toList();
    await _prefs.setString(_historyKey, jsonEncode(outer));
  }

  // ── NEXT WEEK ─────────────────────────────────────────────────────────────

  NextWeekHomework? getNextWeek(
    String classId, {
    Iterable<String> fallbackKeys = const [],
  }) {
    final map = _decodeOuterMap(_prefs.getString(_nextWeekKey));
    for (final key in _candidateKeys(classId, fallbackKeys)) {
      final data = map[key];
      if (data is! Map) continue;
      try {
        return NextWeekHomework.fromJson(Map<String, dynamic>.from(data));
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveNextWeek(NextWeekHomework nw) async {
    final raw = _prefs.getString(_nextWeekKey);
    final map = <String, dynamic>{};
    if (raw != null) {
      try {
        map.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    map[nw.classId] = nw.toJson();
    await _prefs.setString(_nextWeekKey, jsonEncode(map));
  }

  // ── Inspection (검사 완료) per class + week ───────────────────────────────

  String _inspectionFieldKey(String classId, String weekStartDate) =>
      '${classId.trim()}_$weekStartDate';

  bool getInspectionComplete(
    String classId,
    String weekStartDate, {
    Iterable<String> fallbackKeys = const [],
  }) {
    final raw = _prefs.getString(_inspectionKey);
    if (raw == null) return false;
    try {
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      for (final key in _candidateKeys(classId, fallbackKeys)) {
        final v = outer[_inspectionFieldKey(key, weekStartDate)];
        if (v is bool) return v;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveInspectionComplete(
    String classId,
    String weekStartDate,
    bool complete,
  ) async {
    final raw = _prefs.getString(_inspectionKey);
    final outer = <String, dynamic>{};
    if (raw != null) {
      try {
        outer.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    outer[_inspectionFieldKey(classId, weekStartDate)] = complete;
    await _prefs.setString(_inspectionKey, jsonEncode(outer));
  }

  // ── Class-scoped homework category groups (상위 항목) ─────────────────────

  List<HomeworkCategoryMeta> getCategoryMetas(
    String classId, {
    Iterable<String> fallbackKeys = const [],
  }) {
    final outer = _decodeOuterMap(_prefs.getString(_catMetaKey));
    for (final key in _candidateKeys(classId, fallbackKeys)) {
      final list = outer[key];
      if (list is! List) continue;
      final out = <HomeworkCategoryMeta>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          out.add(
            HomeworkCategoryMeta.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {}
      }
      return out;
    }
    return [];
  }

  Future<void> saveCategoryMetas(
    String classId,
    List<HomeworkCategoryMeta> metas,
  ) async {
    final raw = _prefs.getString(_catMetaKey);
    final outer = <String, dynamic>{};
    if (raw != null) {
      try {
        outer.addAll(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    outer[classId.trim()] = metas.map((m) => m.toJson()).toList();
    await _prefs.setString(_catMetaKey, jsonEncode(outer));
  }
}
