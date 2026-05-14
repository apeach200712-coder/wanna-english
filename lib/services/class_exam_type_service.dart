import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/models/exam_score_model.dart';
import 'class_service.dart';

/// Per-class configurable exam types (display name + form), persisted locally.
///
/// Storage is keyed by **class id** ([ClassMeta.id]), not display name, so each
/// class keeps its own type list and custom types never leak across classes.
class ClassExamTypeService {
  static const String _prefsKey = 'class_exam_types_v1';
  static const int _formatVersion = 2;

  final SharedPreferences _prefs;

  ClassExamTypeService({required SharedPreferences prefs}) : _prefs = prefs;

  Map<String, List<ClassExamTypeDef>>? _memCache;

  static bool _looksLikeUuid(String s) {
    final t = s.trim();
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(t);
  }

  Map<String, List<ClassExamTypeDef>> _parseByIdJson(
    Map<String, dynamic> byId,
  ) {
    final out = <String, List<ClassExamTypeDef>>{};
    for (final e in byId.entries) {
      final rawList = e.value;
      if (rawList is! List) continue;
      final list = <ClassExamTypeDef>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        try {
          final def = ClassExamTypeDef.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (def.id.isEmpty || def.displayName.isEmpty) continue;
          list.add(def);
        } catch (_) {}
      }
      if (list.isNotEmpty) out[e.key] = list;
    }
    return out;
  }

  Future<Map<String, List<ClassExamTypeDef>>> _migrateLegacyFlatMap(
    Map<String, dynamic> decoded,
  ) async {
    final legacy = <String, List<ClassExamTypeDef>>{};
    for (final e in decoded.entries) {
      final list = (e.value as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(ClassExamTypeDef.fromJson)
          .toList();
      if (list != null) legacy[e.key] = list;
    }

    final cs = ClassService(prefs: _prefs);
    await cs.initializeFromMockIfNeeded();
    final items = await cs.getDisplayItems();
    final displayToId = {for (final i in items) i.displayName: i.id};
    final idsByName = <String, List<String>>{};
    for (final i in items) {
      idsByName.putIfAbsent(i.name.trim(), () => []).add(i.id);
    }
    String? displayForClassId(String classId) {
      for (final i in items) {
        if (i.id == classId) return i.displayName;
      }
      return null;
    }

    final out = <String, List<ClassExamTypeDef>>{};
    for (final e in legacy.entries) {
      final key = e.key.trim();
      String? classId;
      if (_looksLikeUuid(key)) {
        classId = key;
      } else {
        classId = displayToId[key];
        classId ??= () {
          final ids = idsByName[key] ?? const <String>[];
          if (ids.length == 1) return ids.single;
          return null;
        }();
      }
      if (classId == null) continue;

      final label =
          displayForClassId(classId) ??
          (e.value.isNotEmpty ? e.value.first.className : key);
      final migrated = e.value
          .map((d) => d.copyWith(className: label))
          .toList();
      out.putIfAbsent(classId, () => []).addAll(migrated);
    }

    for (final id in out.keys.toList()) {
      out[id] = _dedupeByTypeId(out[id]!);
    }
    return out;
  }

  List<ClassExamTypeDef> _dedupeByTypeId(List<ClassExamTypeDef> list) {
    final seen = <String>{};
    final out = <ClassExamTypeDef>[];
    for (final t in list) {
      if (seen.add(t.id)) out.add(t);
    }
    return out;
  }

  Future<void> _writeV2(Map<String, List<ClassExamTypeDef>> byId) async {
    final enc = <String, dynamic>{
      'v': _formatVersion,
      'byId': {
        for (final e in byId.entries)
          e.key: e.value.map((t) => t.toJson()).toList(),
      },
    };
    await _prefs.setString(_prefsKey, jsonEncode(enc));
    _memCache = byId;
  }

  Future<Map<String, List<ClassExamTypeDef>>> _loadAll() async {
    if (_memCache != null) return _memCache!;

    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _memCache = {};
      return _memCache!;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _memCache = {};
        return _memCache!;
      }
      final data = Map<String, dynamic>.from(decoded);
      if (data['v'] == _formatVersion) {
        final byId = data['byId'];
        if (byId is! Map) {
          _memCache = {};
          return _memCache!;
        }
        _memCache = _parseByIdJson(Map<String, dynamic>.from(byId));
        return _memCache!;
      }
      final migrated = await _migrateLegacyFlatMap(data);
      await _writeV2(migrated);
      return _memCache!;
    } catch (_) {
      _memCache = {};
      return _memCache!;
    }
  }

  /// Ensures defaults exist for [classId] and returns defs (with fresh [displayNameForDefs]).
  Future<List<ClassExamTypeDef>> getTypesForClass({
    required String classId,
    required String displayNameForDefs,
  }) async {
    final trimmedId = classId.trim();
    if (trimmedId.isEmpty) return const [];

    var all = await _loadAll();
    var list = all[trimmedId];
    if (list == null || list.isEmpty) {
      list = ClassExamTypeDef.defaultTypesForClass(displayNameForDefs);
      all = Map<String, List<ClassExamTypeDef>>.from(all);
      all[trimmedId] = list;
      await _writeV2(all);
    }
    return list.map((t) => t.copyWith(className: displayNameForDefs)).toList();
  }

  Future<void> upsertType({
    required String classId,
    required ClassExamTypeDef def,
  }) async {
    final cid = classId.trim();
    if (cid.isEmpty) return;
    var all = await _loadAll();
    all = Map<String, List<ClassExamTypeDef>>.from(all);
    final list = List<ClassExamTypeDef>.from(all[cid] ?? []);
    final i = list.indexWhere((t) => t.id == def.id);
    if (i >= 0) {
      list[i] = def;
    } else {
      list.add(def);
    }
    all[cid] = list;
    await _writeV2(all);
  }

  Future<void> updateDisplayName({
    required String classId,
    required String typeId,
    required String displayName,
  }) async {
    final cid = classId.trim();
    if (cid.isEmpty) return;
    final trimmed = displayName.trim();
    if (trimmed.isEmpty || trimmed.length > 10) return;
    var all = await _loadAll();
    all = Map<String, List<ClassExamTypeDef>>.from(all);
    final list = List<ClassExamTypeDef>.from(all[cid] ?? []);
    final i = list.indexWhere((t) => t.id == typeId);
    if (i < 0) return;
    list[i] = list[i].copyWith(displayName: trimmed);
    all[cid] = list;
    await _writeV2(all);
  }

  Future<bool> removeType({
    required String classId,
    required String typeId,
  }) async {
    final cid = classId.trim();
    if (cid.isEmpty) return false;
    var all = await _loadAll();
    all = Map<String, List<ClassExamTypeDef>>.from(all);
    final list = List<ClassExamTypeDef>.from(all[cid] ?? []);
    final next = list.where((t) => t.id != typeId).toList();
    if (next.length == list.length) return false;
    all[cid] = next;
    await _writeV2(all);
    return true;
  }

  /// Removes persisted type definitions when a class is deleted ([ClassMeta.id]).
  Future<void> removeAllForClass(String classId) async {
    final cid = classId.trim();
    if (cid.isEmpty) return;
    var all = await _loadAll();
    if (!all.containsKey(cid)) return;
    all = Map<String, List<ClassExamTypeDef>>.from(all)..remove(cid);
    await _writeV2(all);
  }

  Future<ClassExamTypeDef> addCustomType({
    required String classId,
    required String displayNameForDefs,
    required String displayName,
    required ExamFormType formType,
  }) async {
    final trimmed = displayName.trim();
    final name = trimmed.length > 10 ? trimmed.substring(0, 10) : trimmed;
    final id = const Uuid().v4();
    final def = ClassExamTypeDef(
      id: id,
      className: displayNameForDefs,
      displayName: name,
      formType: formType,
    );
    await upsertType(classId: classId, def: def);
    return def;
  }
}
