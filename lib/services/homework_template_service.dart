import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Model for a global homework section entry.
class HomeworkSectionTemplate {
  final String sectionId;
  final String sectionName;
  final bool isDefault;

  const HomeworkSectionTemplate({
    required this.sectionId,
    required this.sectionName,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
    'sectionId': sectionId,
    'sectionName': sectionName,
    'isDefault': isDefault,
  };

  factory HomeworkSectionTemplate.fromJson(Map<String, dynamic> json) =>
      HomeworkSectionTemplate(
        sectionId: json['sectionId'] as String,
        sectionName: json['sectionName'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

/// Manages global homework section templates and per-section sub-section lists.
class HomeworkTemplateService {
  static const String _sectionsKey = 'hw_sections_v2';
  static const String _subSectionsKey = 'hw_sub_sections_v2';

  static const List<HomeworkSectionTemplate> _defaults = [
    HomeworkSectionTemplate(
      sectionId: 'textbook',
      sectionName: '교과서',
      isDefault: true,
    ),
    HomeworkSectionTemplate(
      sectionId: 'workbook',
      sectionName: '부교재',
      isDefault: true,
    ),
  ];

  /// Preset sub-section options per section (shown before user adds custom ones).
  static const Map<String, List<String>> _presetSubSections = {
    'textbook': [
      '본문 읽기',
      '본문 해석',
      '본문 암기',
      'p.32~35 문제 풀이',
      '서술형 예상문제',
      '단원 복습',
    ],
    'workbook': ['워크북 4단원', '기본 문제', '유형 문제', '심화 문제', '서술형 문제', '실전 테스트'],
    'vocabulary': ['Day 7', 'Day 1~7 누적', '뜻 암기', '스펠링 테스트 준비', '틀린 단어 3번씩 쓰기'],
    'wrong_answers': ['오답노트 작성', '오답 재풀이', '유사문제 풀이', '개념 재정리', '해설 분석'],
    'print': ['수업 프린트 풀이', '추가 문제 풀이', '개념 프린트 정리', '서술형 프린트'],
  };

  final SharedPreferences _prefs;

  HomeworkTemplateService({required SharedPreferences prefs}) : _prefs = prefs;

  // ── Section templates ──────────────────────────────────────────────────────

  List<HomeworkSectionTemplate> getAllSections() {
    final raw = _prefs.getString(_sectionsKey);
    List<HomeworkSectionTemplate> extras = [];
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        extras = list
            .map(
              (e) =>
                  HomeworkSectionTemplate.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {}
    }
    // Apply name overrides for default sections
    const overrideKey = 'hw_section_name_override_v2';
    final overrideRaw = _prefs.getString(overrideKey);
    final overrides = <String, String>{};
    if (overrideRaw != null) {
      try {
        (jsonDecode(overrideRaw) as Map<String, dynamic>).forEach(
          (k, v) => overrides[k] = v as String,
        );
      } catch (_) {}
    }
    final defaultsWithOverrides = _defaults
        .map(
          (d) => overrides.containsKey(d.sectionId)
              ? HomeworkSectionTemplate(
                  sectionId: d.sectionId,
                  sectionName: overrides[d.sectionId]!,
                  isDefault: true,
                )
              : d,
        )
        .toList();

    // Merge: defaults first, then extras (without duplicating defaults)
    final defaultIds = _defaults.map((d) => d.sectionId).toSet();
    final merged = [
      ...defaultsWithOverrides,
      ...extras.where((e) => !defaultIds.contains(e.sectionId)),
    ];
    return merged;
  }

  Future<void> addSection(String sectionId, String sectionName) async {
    final current = getAllSections();
    final defaultIds = _defaults.map((d) => d.sectionId).toSet();
    if (current.any((s) => s.sectionId == sectionId)) return;
    final extras =
        current.where((s) => !defaultIds.contains(s.sectionId)).toList()..add(
          HomeworkSectionTemplate(
            sectionId: sectionId,
            sectionName: sectionName,
          ),
        );
    await _prefs.setString(
      _sectionsKey,
      jsonEncode(extras.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> removeSection(String sectionId) async {
    final defaultIds = _defaults.map((d) => d.sectionId).toSet();
    if (defaultIds.contains(sectionId)) return; // cannot remove defaults
    final current = getAllSections();
    final extras = current
        .where(
          (s) => !defaultIds.contains(s.sectionId) && s.sectionId != sectionId,
        )
        .toList();
    await _prefs.setString(
      _sectionsKey,
      jsonEncode(extras.map((e) => e.toJson()).toList()),
    );
  }

  /// Renames a section. For default sections, stores a name override.
  Future<void> renameSection(String sectionId, String newName) async {
    final defaultIds = _defaults.map((d) => d.sectionId).toSet();
    if (defaultIds.contains(sectionId)) {
      // Store override separately
      const overrideKey = 'hw_section_name_override_v2';
      final raw = _prefs.getString(overrideKey);
      final map = <String, String>{};
      if (raw != null) {
        try {
          (jsonDecode(raw) as Map<String, dynamic>).forEach(
            (k, v) => map[k] = v as String,
          );
        } catch (_) {}
      }
      map[sectionId] = newName;
      await _prefs.setString(overrideKey, jsonEncode(map));
    } else {
      final current = getAllSections();
      final defaultIds2 = _defaults.map((d) => d.sectionId).toSet();
      final extras = current
          .where((s) => !defaultIds2.contains(s.sectionId))
          .map((s) {
            if (s.sectionId == sectionId) {
              return HomeworkSectionTemplate(
                sectionId: s.sectionId,
                sectionName: newName,
              );
            }
            return s;
          })
          .toList();
      await _prefs.setString(
        _sectionsKey,
        jsonEncode(extras.map((e) => e.toJson()).toList()),
      );
    }
  }

  // ── Sub-sections ──────────────────────────────────────────────────────────

  /// Returns the sub-section option list for [sectionId].
  /// Presets are shown first, then user-added entries (de-duplicated).
  List<String> getSubSections(String sectionId) {
    final presets = _presetSubSections[sectionId] ?? [];
    final stored = _loadSubSectionMap();
    // Apply hidden filter
    const hiddenKey = 'hw_hidden_sub_v2';
    final hiddenRaw = _prefs.getString(hiddenKey);
    final hiddenSet = <String>{};
    if (hiddenRaw != null) {
      try {
        final hiddenMap = jsonDecode(hiddenRaw) as Map<String, dynamic>;
        hiddenSet.addAll(
          List<String>.from(hiddenMap[sectionId] as List? ?? []),
        );
      } catch (_) {}
    }
    final visiblePresets = presets
        .where((p) => !hiddenSet.contains(p))
        .toList();
    final custom = (stored[sectionId] ?? [])
        .where((s) => !presets.contains(s) && !hiddenSet.contains(s))
        .toList();
    return [...visiblePresets, ...custom];
  }

  /// Saves a new sub-section string under [sectionId] for future use.
  Future<void> saveSubSection(String sectionId, String value) async {
    final map = _loadSubSectionMap();
    final list = List<String>.from(map[sectionId] ?? []);
    if (!list.contains(value)) {
      list.add(value);
      map[sectionId] = list;
      await _prefs.setString(_subSectionsKey, jsonEncode(map));
    }
  }

  /// Removes a sub-section option. For presets, adds to a hidden set.
  Future<void> removeSubSection(String sectionId, String value) async {
    final presets = _presetSubSections[sectionId] ?? [];
    if (presets.contains(value)) {
      // Add to hidden presets
      const hiddenKey = 'hw_hidden_sub_v2';
      final raw = _prefs.getString(hiddenKey);
      final hiddenMap = <String, List<String>>{};
      if (raw != null) {
        try {
          (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
            hiddenMap[k] = List<String>.from(v as List);
          });
        } catch (_) {}
      }
      final hiddenList = List<String>.from(hiddenMap[sectionId] ?? []);
      if (!hiddenList.contains(value)) {
        hiddenList.add(value);
        hiddenMap[sectionId] = hiddenList;
        await _prefs.setString(hiddenKey, jsonEncode(hiddenMap));
      }
    } else {
      // Remove from custom list
      final map = _loadSubSectionMap();
      final list = List<String>.from(map[sectionId] ?? []);
      list.remove(value);
      map[sectionId] = list;
      await _prefs.setString(_subSectionsKey, jsonEncode(map));
    }
  }

  /// Renames a sub-section option (saves new name, hides old name).
  Future<void> renameSubSection(
    String sectionId,
    String oldValue,
    String newValue,
  ) async {
    await removeSubSection(sectionId, oldValue);
    await saveSubSection(sectionId, newValue);
  }

  Map<String, List<String>> _loadSubSectionMap() {
    final raw = _prefs.getString(_subSectionsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {
      return {};
    }
  }
}
