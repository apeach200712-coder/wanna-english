import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models/todo_model.dart';
import 'local_storage_service.dart';

class TodoPreviewItem {
  final String sectionId;
  final String sectionTitle;
  final Color sectionColor;
  final TodoTaskModel task;

  const TodoPreviewItem({
    required this.sectionId,
    required this.sectionTitle,
    required this.sectionColor,
    required this.task,
  });
}

class TodoService extends ChangeNotifier {
  TodoService._();

  static final TodoService instance = TodoService._();

  static const _storageKey = 'todo_sections_v3';
  static const _pinnedSectionsKey = 'todo_pinned_sections_v1';
  static const _legacyStorageKeyV2 = 'todo_sections_v2';
  static const _legacyStorageKeyV1 = 'todo_sections_v1';
  static const _kst = Duration(hours: 9);
  static const List<_LegacySeedSection> _legacySeedSections = [
    _LegacySeedSection(
      title: '이화여고 2학년',
      tasks: ['숙제 미완료 학생 확인', '단어시험 채점 및 오답 정리', '리뷰테스트 재시험 대상자 확인'],
    ),
    _LegacySeedSection(
      title: '개포고 1학년',
      tasks: ['숙제 재제출 학생 다시 확인', '단어 재시험 문항 인쇄'],
    ),
    _LegacySeedSection(
      title: '고3 내신반',
      tasks: ['고3 내신반 성적 입력', '리뷰 재시험 학생 피드백 작성'],
    ),
  ];

  final LocalStorageService _storage = const LocalStorageService();

  Map<String, List<TodoSectionModel>> _sectionsByDate = const {};
  List<TodoSectionModel> _pinnedSections = const [];
  String _activeDateKey = '';
  bool _isLoaded = false;

  /// Single-flight so [initState] `load()` and [selectDate] `load()` never run
  /// [_hydrateSections] concurrently (the second completion could restore
  /// persisted `activeDate` and wipe a calendar-selected day).
  Future<void>? _hydrateInFlight;

  List<TodoSectionModel> get sections =>
      _sectionsByDate[_activeDateKey] ?? const [];

  DateTime get activeDate => _dateFromKey(_activeDateKey);

  List<TodoSectionModel> sectionsForDate(DateTime date) {
    final key = _dateKeyFromDate(_toKstDate(date));
    return _sectionsByDate[key] ?? const [];
  }

  List<TodoPreviewItem> favoritePreviewItemsForDate(DateTime date) {
    final sections = sectionsForDate(date);
    final out = <TodoPreviewItem>[];
    for (final section in sections) {
      for (final task in section.tasks) {
        if (!task.isPinned) continue;
        out.add(
          TodoPreviewItem(
            sectionId: section.id,
            sectionTitle: section.title,
            sectionColor: section.color,
            task: task,
          ),
        );
      }
    }
    return out;
  }

  List<TodoPreviewItem> get previewItems =>
      favoritePreviewItemsForDate(_kstToday()).take(5).toList();

  Future<void> load() async {
    if (_isLoaded) return;
    _hydrateInFlight ??= _hydrateSections();
    try {
      await _hydrateInFlight!;
    } finally {
      _hydrateInFlight = null;
    }
  }

  /// Calendar / route: strip time so keys match grid days (no TZ drift).
  static DateTime calendarDayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> selectDate(DateTime date, {bool notify = true}) async {
    final key = _dateKeyFromDate(_toKstDate(date));

    // Apply the calendar day immediately so addTask / UI never run on a stale
    // activeDate while await load() is still hydrating from disk.
    _activeDateKey = key;
    if (!_sectionsByDate.containsKey(key)) {
      _sectionsByDate = {
        ..._sectionsByDate,
        key: _initialSectionsForDateKey(key),
      };
    }

    await load();

    // Hydration restores persisted activeDate — re-assert the requested day.
    _activeDateKey = key;
    if (!_sectionsByDate.containsKey(key)) {
      _sectionsByDate = {
        ..._sectionsByDate,
        key: _initialSectionsForDateKey(key),
      };
    }

    await _persistSections();
    if (notify) notifyListeners();
  }

  Future<void> addSection({
    required String title,
    required Color color,
    bool isPinned = false,
  }) async {
    await load();

    final trimmedSectionTitle = title.trim();
    if (trimmedSectionTitle.isEmpty) return;

    final sectionId = 'section_${DateTime.now().microsecondsSinceEpoch}';
    final section = TodoSectionModel(
      id: sectionId,
      title: trimmedSectionTitle,
      color: color,
      icon: Icons.folder_open_rounded,
      tasks: const [],
      isPinned: isPinned,
    );

    _setActiveSections([...sections, section]);
    if (isPinned) {
      _upsertPinnedSection(section);
    }

    await _persistSections();
    notifyListeners();
  }

  Future<void> addTask({
    required String sectionId,
    required String title,
    String? time,
    String? memo,
    TodoTaskProgress progress = TodoTaskProgress.notDone,
  }) async {
    await load();

    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;

    final newTask = _buildTask(
      sectionId: sectionId,
      title: trimmedTitle,
      time: time,
      memo: memo,
      progress: progress,
    );

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;
        return section.copyWith(tasks: [...section.tasks, newTask]);
      }).toList(),
    );

    await _persistSections();
    notifyListeners();
  }

  Future<void> updateSectionColor({
    required String sectionId,
    required Color color,
  }) async {
    await load();

    final pinnedSection = _pinnedSections.where(
      (section) => section.id == sectionId,
    );
    if (pinnedSection.isNotEmpty) {
      _pinnedSections = _pinnedSections
          .map(
            (section) => section.id == sectionId
                ? section.copyWith(color: color)
                : section,
          )
          .toList();
      _sectionsByDate = _sectionsByDate.map(
        (key, value) => MapEntry(
          key,
          value
              .map(
                (section) => section.id == sectionId
                    ? section.copyWith(color: color)
                    : section,
              )
              .toList(),
        ),
      );
      _mergePinnedSectionsIntoDate(_activeDateKey);
      await _persistSections();
      notifyListeners();
      return;
    }

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;
        return section.copyWith(color: color);
      }).toList(),
    );

    await _persistSections();
    notifyListeners();
  }

  Future<void> updateTaskProgress({
    required String sectionId,
    required String taskId,
    required TodoTaskProgress progress,
  }) async {
    await load();

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;

        final updatedTasks = section.tasks.map((task) {
          if (task.id != taskId) return task;
          return task.copyWith(progress: progress);
        }).toList();

        return section.copyWith(tasks: updatedTasks);
      }).toList(),
    );

    await _persistSections();
    notifyListeners();
  }

  Future<void> toggleTaskPinned({
    required String sectionId,
    required String taskId,
  }) async {
    await load();

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;

        final updatedTasks = section.tasks.map((task) {
          if (task.id != taskId) return task;
          return task.copyWith(isPinned: !task.isPinned);
        }).toList();

        return section.copyWith(tasks: updatedTasks);
      }).toList(),
    );

    await _persistSections();
    notifyListeners();
  }

  Future<void> updateTask({
    required String sectionId,
    required String taskId,
    required String title,
    String? time,
    String? memo,
  }) async {
    await load();

    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;

        final updatedTasks = section.tasks.map((task) {
          if (task.id != taskId) return task;
          return task.copyWith(
            title: trimmedTitle,
            time: _normalizeField(time),
            memo: _normalizeField(memo),
          );
        }).toList();

        return section.copyWith(tasks: updatedTasks);
      }).toList(),
    );

    await _persistSections();
    notifyListeners();
  }

  Future<void> deleteSection({required String sectionId}) async {
    await load();

    final isPinnedSection = _pinnedSections.any(
      (section) => section.id == sectionId,
    );
    if (isPinnedSection) {
      _pinnedSections = _pinnedSections
          .where((section) => section.id != sectionId)
          .toList();
      _sectionsByDate = _sectionsByDate.map(
        (key, value) => MapEntry(
          key,
          value.where((section) => section.id != sectionId).toList(),
        ),
      );
    } else {
      _setActiveSections(sections.where((s) => s.id != sectionId).toList());
    }

    await _persistSections();
    notifyListeners();
  }

  Future<void> deleteTask({
    required String sectionId,
    required String taskId,
  }) async {
    await load();

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;

        final updatedTasks = section.tasks
            .where((task) => task.id != taskId)
            .toList();

        return section.copyWith(tasks: updatedTasks);
      }).toList(),
    );

    await _persistSections();
    notifyListeners();
  }

  Future<void> cycleTaskProgress({
    required String sectionId,
    required String taskId,
  }) async {
    await load();

    TodoTaskProgress? nextProgress;

    _setActiveSections(
      sections.map((section) {
        if (section.id != sectionId) return section;

        final updatedTasks = section.tasks.map((task) {
          if (task.id != taskId) return task;
          nextProgress = _nextProgress(task.progress);
          return task.copyWith(progress: nextProgress);
        }).toList();

        return section.copyWith(tasks: updatedTasks);
      }).toList(),
    );

    if (nextProgress == null) return;

    await _persistSections();
    notifyListeners();
  }

  Future<void> _hydrateSections() async {
    final todayKey = _dateKeyFromDate(_kstToday());
    _activeDateKey = todayKey;

    final storedV3 = await _storage.readString(_storageKey);
    final pinnedRaw = await _storage.readString(_pinnedSectionsKey);
    _pinnedSections = _parsePinnedSections(pinnedRaw);
    if (storedV3 != null) {
      try {
        final decodedRaw = jsonDecode(storedV3);
        if (decodedRaw is! Map)
          throw const FormatException('todo root not map');
        final decoded = Map<String, dynamic>.from(decodedRaw);
        final byDate = decoded['byDate'];
        final loadedMap = <String, List<TodoSectionModel>>{};

        if (byDate is Map) {
          for (final entry in byDate.entries) {
            final rawSections = entry.value;
            if (rawSections is! List) continue;
            final sections = <TodoSectionModel>[];
            for (final item in rawSections) {
              if (item is! Map) continue;
              try {
                sections.add(
                  _stripEmojisFromSection(
                    TodoSectionModel.fromJson(Map<String, dynamic>.from(item)),
                  ),
                );
              } catch (_) {}
            }
            loadedMap[entry.key.toString()] = sections;
          }
        }

        _sectionsByDate = loadedMap;
        if (_isOnlySeededDefault(loadedMap, todayKey)) {
          _sectionsByDate = {todayKey: const []};
        }

        final activeKey = decoded['activeDate']?.toString();
        if (activeKey != null && activeKey.isNotEmpty) {
          _activeDateKey = activeKey;
        }
      } catch (_) {
        _sectionsByDate = {};
      }

      if (_sectionsByDate.isEmpty) {
        _sectionsByDate = {todayKey: const []};
      }

      for (final key in _sectionsByDate.keys.toList()) {
        _mergePinnedSectionsIntoDate(key);
      }
      _mergePinnedSectionsIntoDate(_activeDateKey);

      _isLoaded = true;
      notifyListeners();
      return;
    }

    final legacyValue =
        await _storage.readString(_legacyStorageKeyV2) ??
        await _storage.readString(_legacyStorageKeyV1);

    if (legacyValue == null) {
      _sectionsByDate = {todayKey: const []};
      _activeDateKey = todayKey;
      _isLoaded = true;
      await _persistSections();
      notifyListeners();
      return;
    }

    _sectionsByDate = {todayKey: _parseLegacySections(legacyValue)};
    _mergePinnedSectionsIntoDate(todayKey);
    _activeDateKey = todayKey;
    _isLoaded = true;
    await _persistSections();
    notifyListeners();
  }

  List<TodoSectionModel> _parseLegacySections(String raw) {
    try {
      final decodedRaw = jsonDecode(raw);
      if (decodedRaw is! Map) return const [];
      final decoded = Map<String, dynamic>.from(decodedRaw);
      final storedSections = decoded['sections'];

      if (storedSections is List) {
        final out = <TodoSectionModel>[];
        for (final item in storedSections) {
          if (item is! Map) continue;
          try {
            out.add(TodoSectionModel.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
        return out;
      }

      if (storedSections is Map<String, dynamic>) {
        return const [];
      }

      return const [];
    } catch (_) {
      return const [];
    }
  }

  static final _emojiRegex = RegExp(
    r'[\u{1F000}-\u{1FFFF}]|[\u{2600}-\u{27BF}]|[\u{FE00}-\u{FE0F}]|\u{200D}',
    unicode: true,
  );

  TodoSectionModel _stripEmojisFromSection(TodoSectionModel section) {
    final cleaned = section.title.replaceAll(_emojiRegex, '').trim();
    if (cleaned == section.title) return section;
    return section.copyWith(title: cleaned);
  }

  Future<void> _persistSections() async {
    final byDate = _sectionsByDate.map(
      (key, value) =>
          MapEntry(key, value.map((section) => section.toJson()).toList()),
    );

    final encoded = jsonEncode({
      'version': 3,
      'activeDate': _activeDateKey,
      'byDate': byDate,
    });

    await _storage.writeString(_storageKey, encoded);
    await _storage.writeString(
      _pinnedSectionsKey,
      jsonEncode(_pinnedSections.map((section) => section.toJson()).toList()),
    );
  }

  void _setActiveSections(List<TodoSectionModel> updated) {
    _sectionsByDate = {..._sectionsByDate, _activeDateKey: updated};
  }

  List<TodoSectionModel> _initialSectionsForDateKey(String dateKey) {
    return _clonedPinnedSections();
  }

  List<TodoSectionModel> _parsePinnedSections(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <TodoSectionModel>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(
            TodoSectionModel.fromJson(
              Map<String, dynamic>.from(item),
            ).copyWith(tasks: const [], isPinned: true),
          );
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<TodoSectionModel> _clonedPinnedSections() {
    return _pinnedSections
        .map((section) => section.copyWith(tasks: const [], isPinned: true))
        .toList();
  }

  void _upsertPinnedSection(TodoSectionModel section) {
    final pinnedSection = section.copyWith(tasks: const [], isPinned: true);
    final index = _pinnedSections.indexWhere((item) => item.id == section.id);
    if (index >= 0) {
      final updated = [..._pinnedSections];
      updated[index] = pinnedSection;
      _pinnedSections = updated;
      return;
    }
    _pinnedSections = [..._pinnedSections, pinnedSection];
  }

  void _mergePinnedSectionsIntoDate(String dateKey) {
    final existing = _sectionsByDate[dateKey] ?? const [];
    final existingIds = existing.map((section) => section.id).toSet();
    final merged = [
      ...existing,
      ..._pinnedSections
          .where((section) => !existingIds.contains(section.id))
          .map((section) => section.copyWith(tasks: const [], isPinned: true)),
    ];
    _sectionsByDate = {..._sectionsByDate, dateKey: merged};
  }

  bool _isOnlySeededDefault(
    Map<String, List<TodoSectionModel>> loadedMap,
    String todayKey,
  ) {
    if (loadedMap.length != 1 || !loadedMap.containsKey(todayKey)) {
      return false;
    }
    final sections = loadedMap[todayKey] ?? const [];
    if (sections.length != _legacySeedSections.length) {
      return false;
    }

    for (int index = 0; index < sections.length; index++) {
      final loadedSection = sections[index];
      final seedSection = _legacySeedSections[index];
      if (loadedSection.title != seedSection.title) {
        return false;
      }
      if (loadedSection.tasks.length != seedSection.tasks.length) {
        return false;
      }
      for (
        int taskIndex = 0;
        taskIndex < loadedSection.tasks.length;
        taskIndex++
      ) {
        final loadedTask = loadedSection.tasks[taskIndex];
        final seedTask = seedSection.tasks[taskIndex];
        if (loadedTask.title != seedTask) {
          return false;
        }
      }
    }

    return true;
  }

  static DateTime _kstToday() {
    final now = DateTime.now().toUtc().add(_kst);
    return DateTime(now.year, now.month, now.day);
  }

  /// Calendar / UI "day" only — never shift by timezone (avoids May 12 → May 11).
  static DateTime _toKstDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static String _dateKeyFromDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime _dateFromKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      return _kstToday();
    }

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);

    if (y == null || m == null || d == null) {
      return _kstToday();
    }

    return DateTime(y, m, d);
  }

  TodoTaskModel _buildTask({
    required String sectionId,
    required String title,
    String? time,
    String? memo,
    required TodoTaskProgress progress,
  }) {
    return TodoTaskModel(
      id: '${sectionId}_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      time: _normalizeField(time),
      memo: _normalizeField(memo),
      progress: progress,
    );
  }

  TodoTaskProgress _nextProgress(TodoTaskProgress progress) {
    switch (progress) {
      case TodoTaskProgress.notDone:
        return TodoTaskProgress.inProgress;
      case TodoTaskProgress.inProgress:
        return TodoTaskProgress.done;
      case TodoTaskProgress.done:
        return TodoTaskProgress.notDone;
    }
  }

  String? _normalizeField(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class _LegacySeedSection {
  final String title;
  final List<String> tasks;

  const _LegacySeedSection({required this.title, required this.tasks});
}
