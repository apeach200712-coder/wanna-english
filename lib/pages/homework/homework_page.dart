// homework_page.dart — class-specific homework management
// Entry: Navigator.pushNamed(context, '/homework', arguments: className)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/time_utils.dart';
import '../../data/models/class_model.dart';
import '../../data/models/grade_record_model.dart';
import '../../data/models/homework_models.dart';
import '../../data/models/student_model.dart';
import '../../services/class_service.dart';
import '../../services/homework_page_service.dart';
import '../../services/homework_template_service.dart';
import '../../services/student_service.dart';
import '../../services/todo_service.dart';
import '../../theme/app_colors.dart';

part 'homework_page_models.dart';
part 'homework_page_sheets.dart';

/// KST·월요일 시작 주( [DateTime.weekday]: 월=1 … 일=7 ) 기준으로 캘린더에서 고른 날에 맞는 숙제 탭.
_Tab _homeworkTabForCalendarFocusDay(DateTime focusDay, DateTime todayKstDay) {
  final f = DateTime(focusDay.year, focusDay.month, focusDay.day);
  final t = DateTime(todayKstDay.year, todayKstDay.month, todayKstDay.day);
  DateTime mondayOf(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return x.subtract(Duration(days: x.weekday - 1));
  }

  final mThis = mondayOf(t);
  final mFocus = mondayOf(f);
  final mNext = mThis.add(const Duration(days: 7));

  if (mFocus.isBefore(mThis)) return _Tab.lastWeeks;
  if (mFocus == mThis) return _Tab.thisWeek;
  if (mFocus == mNext) return _Tab.nextWeek;
  return _Tab.lastWeeks;
}

// ─── HomeworkPage ─────────────────────────────────────────────────────────────

class HomeworkPage extends StatefulWidget {
  const HomeworkPage({super.key});

  @override
  State<HomeworkPage> createState() => _HomeworkPageState();
}

class _HomeworkPageState extends State<HomeworkPage> {
  static const Map<String, List<String>> _defaultCategoryItems = {
    '교과서': ['본문 읽기', '본문 해석', '본문 암기', 'p.32~35 문제 풀이', '서술형 예상문제', '단원 복습'],
    '부교재': ['Unit 1 단어', 'Unit 1 문법'],
  };

  // Services
  late HomeworkPageService _hwService;
  late HomeworkTemplateService _tmplService;
  late StudentService _studentService;
  late ClassService _classService;

  // Identity
  String _classId = '';
  String _className = '';
  String _classDisplayName = '';
  List<int> _classWeekdays = const [];
  bool _isLoading = true;
  bool _routeApplied = false;
  DateTime? _routeFocusDay;

  // Tab
  _Tab _tab = _Tab.thisWeek;
  bool _tabDropdownOpen = false;

  String get _classStorageKey => _classId.isNotEmpty ? _classId : _className;

  Iterable<String> get _legacyClassKeys sync* {
    final name = _className.trim();
    final id = _classId.trim();
    if (name.isNotEmpty && name != _classStorageKey) {
      yield name;
    }
    if (id.isNotEmpty && id != _classStorageKey) {
      yield id;
    }
  }

  String get _classTitle {
    if (_classDisplayName.trim().isNotEmpty) return _classDisplayName;
    if (_className.trim().isNotEmpty) return _className;
    return '숙제관리';
  }

  // ── THIS WEEK state ──────────────────────────────────────────────────────
  late String _weekStartDate;
  List<HomeworkSection> _classTemplateSections = [];
  List<Student> _students = [];
  final Map<String, _StudentState> _states = {};
  final Set<String> _expanded = {};

  // ── LAST WEEKS state ─────────────────────────────────────────────────────
  late DateTime _calMonth;
  List<HomeworkHistoryEntry> _history = [];
  String? _selDate;

  // ── NEXT WEEK state ──────────────────────────────────────────────────────
  List<HomeworkSection> _nwSections = [];
  String _switchDay = 'monday';
  final Map<String, TextEditingController> _nwAddLineCtrls = {};

  // ── Categories & inspection ─────────────────────────────────────────────
  List<HomeworkCategoryMeta> _categoryMetas = [];
  bool _inspectionComplete = false;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeApplied) return;
    _routeApplied = true;
    _applyRouteArguments(ModalRoute.of(context)?.settings.arguments);
    _init();
  }

  void _applyRouteArguments(dynamic arg) {
    if (arg is String && arg.trim().isNotEmpty) {
      _className = arg.trim();
      _classDisplayName = _className;
      return;
    }
    if (arg is! Map) return;

    final classId = arg['classId'];
    final className = arg['className'];
    final classDisplayName = arg['classDisplayName'];
    if (classId is String && classId.trim().isNotEmpty) {
      _classId = classId.trim();
    }
    final tab = arg['tab'];
    if (className is String && className.trim().isNotEmpty) {
      _className = className.trim();
    }
    if (classDisplayName is String && classDisplayName.trim().isNotEmpty) {
      _classDisplayName = classDisplayName.trim();
    }

    DateTime? parsedFocus;
    final focusRaw = arg['focusDate'];
    if (focusRaw is DateTime) {
      parsedFocus = TodoService.calendarDayOnly(focusRaw);
    } else if (focusRaw is String) {
      final p = DateTime.tryParse(focusRaw);
      if (p != null) parsedFocus = TodoService.calendarDayOnly(p);
    }

    // focusDate가 있으면 탭은 주차로만 정한다(맵의 tab 무시).
    if (parsedFocus == null && tab is String) {
      switch (tab) {
        case 'nextWeek':
          _tab = _Tab.nextWeek;
          break;
        case 'lastWeeks':
          _tab = _Tab.lastWeeks;
          break;
        case 'thisWeek':
          _tab = _Tab.thisWeek;
          break;
      }
    }

    if (parsedFocus != null) {
      _routeFocusDay = parsedFocus;
    }
  }

  @override
  void dispose() {
    for (final c in _nwAddLineCtrls.values) {
      c.dispose();
    }
    _nwAddLineCtrls.clear();
    for (final s in _states.values) {
      s.dispose();
    }
    super.dispose();
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _hwService = HomeworkPageService(prefs: prefs);
    _tmplService = HomeworkTemplateService(prefs: prefs);
    _studentService = StudentService(prefs: prefs);
    _classService = ClassService(prefs: prefs);
    await _studentService.initializeMockStudents();
    await _classService.initializeFromMockIfNeeded();

    final now = nowKst();
    _calMonth = DateTime(now.year, now.month);
    _weekStartDate = _computeWeekStart(now);

    final focus = _routeFocusDay;
    if (focus != null) {
      _tab = _homeworkTabForCalendarFocusDay(focus, todayKst());
      if (_tab == _Tab.lastWeeks) {
        _calMonth = DateTime(focus.year, focus.month);
        _selDate = _dateKey(focus);
      } else {
        _calMonth = DateTime(now.year, now.month);
        _selDate = null;
      }
    }

    await _resolveClassIdentity();
    if (_classStorageKey.isEmpty) {
      final items = await _classService.getDisplayItems();
      if (items.isNotEmpty) {
        _classId = items.first.id;
        _className = items.first.name;
        _classDisplayName = items.first.displayName;
      }
    }

    await _loadClassMeetingDates();

    await _loadAll();
  }

  Future<void> _loadClassMeetingDates() async {
    if (_classStorageKey.isEmpty) {
      _classWeekdays = const [];
      return;
    }

    ClassMeta? meta;
    if (_classId.isNotEmpty) {
      meta = await _classService.getClassById(_classId);
    }
    meta ??= await _classService.getFirstClassByName(_className);
    if (meta != null) {
      _classId = meta.id;
      _className = meta.name;
      _classDisplayName =
          (await _classService.getDisplayNameById(meta.id)) ?? meta.name;
    }
    if (meta == null) {
      _classWeekdays = const [];
      return;
    }

    _classWeekdays = meta.weekdays;
  }

  Future<void> _loadAll() async {
    if (_classStorageKey.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    _students = _classId.isNotEmpty
        ? await _studentService.getStudentsByClassId(_classId)
        : await _studentService.getStudentsByClass(_className);

    _categoryMetas = _hwService.getCategoryMetas(
      _classStorageKey,
      fallbackKeys: _legacyClassKeys,
    );

    // Load class template for this week (or use defaults)
    final tmpl = _hwService.getTemplate(
      _classStorageKey,
      fallbackKeys: _legacyClassKeys,
    );
    if (tmpl != null && tmpl.weekStartDate == _weekStartDate) {
      _classTemplateSections = _ensureTemplateItems(tmpl.sections);
      if (_classTemplateSections.length != tmpl.sections.length) {
        _saveTemplate(markInspectionDirty: false);
      }
    } else {
      final nw = _hwService.getNextWeek(
        _classStorageKey,
        fallbackKeys: _legacyClassKeys,
      );
      final switched = _tryAutoSwitch(nw);
      if (!switched) {
        _classTemplateSections = [];
      }
    }

    await _bootstrapCategoryMetasAndTemplate();

    // Load saved student results for this week
    final saved = _hwService.getStudentResults(
      _classStorageKey,
      _weekStartDate,
      fallbackKeys: _legacyClassKeys,
    );
    final savedMap = {for (final r in saved) r.studentId: r};

    // Init student states from saved results or class template
    for (final student in _students) {
      final existing = savedMap[student.id];
      if (existing != null) {
        _states[student.id] = _studentStateFromResult(student, existing);
      } else {
        _states[student.id] = _defaultStudentState(student);
      }
    }
    _syncSectionNamesFromCategoryMetas();

    final nwData = _hwService.getNextWeek(
      _classStorageKey,
      fallbackKeys: _legacyClassKeys,
    );
    _applyNextWeekData(nwData);

    _history = _hwService.getHistory(
      _classStorageKey,
      fallbackKeys: _legacyClassKeys,
    );

    _inspectionComplete = _hwService.getInspectionComplete(
      _classStorageKey,
      _weekStartDate,
      fallbackKeys: _legacyClassKeys,
    );

    setState(() => _isLoading = false);
  }

  Future<void> _resolveClassIdentity() async {
    if (_classId.isNotEmpty) {
      final meta = await _classService.getClassById(_classId);
      if (meta != null) {
        _className = meta.name;
        _classDisplayName =
            (await _classService.getDisplayNameById(meta.id)) ?? meta.name;
      }
      return;
    }

    if (_className.isEmpty) return;
    final meta = await _classService.getFirstClassByName(_className);
    if (meta == null) return;
    _classId = meta.id;
    _className = meta.name;
    _classDisplayName =
        (await _classService.getDisplayNameById(meta.id)) ?? meta.name;
  }

  bool _tryAutoSwitch(NextWeekHomework? nw) {
    if (nw == null) return false;
    final hasPlanned =
        (nw.sections != null && nw.sections!.isNotEmpty) || nw.items.isNotEmpty;
    if (!hasPlanned) return false;
    final saved = _hwService.getTemplate(
      _classStorageKey,
      fallbackKeys: _legacyClassKeys,
    );
    if (saved != null && saved.weekStartDate == _weekStartDate) return false;
    final now = nowKst();
    final switchWd = _dayNameToWeekday(nw.switchDay);
    if (now.weekday < switchWd) return false;
    if (nw.sections != null && nw.sections!.isNotEmpty) {
      _classTemplateSections = nw.sections!
          .map(
            (s) => HomeworkSection(
              sectionId: const Uuid().v4(),
              categoryId: s.categoryId,
              sectionName: s.sectionName,
              subSection: s.subSection,
              checkCount: 0,
            ),
          )
          .toList();
    } else {
      _classTemplateSections = _convertNextWeekItems(nw.items);
    }
    _saveTemplate(markInspectionDirty: false);
    _hwService.saveNextWeek(
      nw.copyWith(classId: _classStorageKey, items: [], sections: []),
    );
    return true;
  }

  Future<void> _bootstrapCategoryMetasAndTemplate() async {
    final uuid = const Uuid();
    var persistTemplate = false;
    var persistMetas = false;

    final nameToId = <String, String>{};
    for (var i = 0; i < _classTemplateSections.length; i++) {
      final s = _classTemplateSections[i];
      if (s.categoryId != null && s.categoryId!.isNotEmpty) continue;
      final nid = nameToId.putIfAbsent(s.sectionName, () => uuid.v4());
      _classTemplateSections[i] = s.copyWith(categoryId: nid);
      persistTemplate = true;
    }

    final known = <String>{for (final m in _categoryMetas) m.id};
    for (final s in _classTemplateSections) {
      final cid = s.categoryId;
      if (cid == null || cid.isEmpty) continue;
      if (!known.contains(cid)) {
        _categoryMetas.add(HomeworkCategoryMeta(id: cid, name: s.sectionName));
        known.add(cid);
        persistMetas = true;
      }
    }

    if (_classTemplateSections.isEmpty && _categoryMetas.isEmpty) {
      for (final name in _defaultCategoryItems.keys) {
        _categoryMetas.add(HomeworkCategoryMeta(id: uuid.v4(), name: name));
      }
      _classTemplateSections = _defaultTemplateItemsFromMetas(_categoryMetas);
      persistMetas = true;
      persistTemplate = true;
    }

    _syncSectionNamesFromCategoryMetas();

    if (persistTemplate) {
      _saveTemplate(markInspectionDirty: false);
    }
    if (persistMetas) {
      await _hwService.saveCategoryMetas(_classStorageKey, _categoryMetas);
    }
  }

  void _applyNextWeekData(NextWeekHomework? nwData) {
    if (nwData == null) {
      _nwSections = [];
      _switchDay = 'monday';
      return;
    }
    _switchDay = nwData.switchDay;
    if (nwData.sections != null && nwData.sections!.isNotEmpty) {
      _nwSections = nwData.sections!.map((s) => s.copyWith()).toList();
    } else if (nwData.items.isNotEmpty) {
      _nwSections = _legacyNwItemsToSections(nwData.items);
    } else {
      _nwSections = [];
    }
  }

  List<HomeworkSection> _legacyNwItemsToSections(List<String> items) {
    if (items.isEmpty) return [];
    if (_categoryMetas.isEmpty) {
      return _convertNextWeekItems(items);
    }
    final first = _categoryMetas.first;
    return [
      for (final text in items)
        HomeworkSection(
          sectionId: const Uuid().v4(),
          categoryId: first.id,
          sectionName: first.name,
          subSection: text,
          checkCount: 0,
        ),
    ];
  }

  void _syncSectionNamesFromCategoryMetas() {
    if (_categoryMetas.isEmpty) return;
    final byId = {for (final m in _categoryMetas) m.id: m};
    _classTemplateSections = _classTemplateSections.map((s) {
      final cid = s.categoryId;
      if (cid != null && byId.containsKey(cid)) {
        final m = byId[cid]!;
        if (s.sectionName != m.name) {
          return s.copyWith(sectionName: m.name);
        }
      }
      return s;
    }).toList();
    for (final state in _states.values) {
      for (final r in state.rows) {
        final cid = r.categoryId;
        if (cid != null && byId.containsKey(cid)) {
          r.sectionName = byId[cid]!.name;
        }
      }
    }
    for (var i = 0; i < _nwSections.length; i++) {
      final s = _nwSections[i];
      final cid = s.categoryId;
      if (cid != null && byId.containsKey(cid)) {
        final m = byId[cid]!;
        if (s.sectionName != m.name) {
          _nwSections[i] = s.copyWith(sectionName: m.name);
        }
      }
    }
  }

  List<HomeworkSection> _defaultTemplateItemsFromMetas(
    List<HomeworkCategoryMeta> metas,
  ) {
    final items = <HomeworkSection>[];
    for (final meta in metas) {
      final titles = _defaultCategoryItems[meta.name];
      if (titles == null || titles.isEmpty) continue;
      for (final title in titles) {
        items.add(
          HomeworkSection(
            sectionId: const Uuid().v4(),
            categoryId: meta.id,
            sectionName: meta.name,
            subSection: title,
            checkCount: 0,
          ),
        );
      }
    }
    return items;
  }

  bool _rowInCategory(_SectionRow row, HomeworkCategoryMeta cat) =>
      row.categoryId == cat.id ||
      (row.categoryId == null && row.sectionName == cat.name);

  bool _sectionInCategory(HomeworkSection s, HomeworkCategoryMeta cat) =>
      s.categoryId == cat.id ||
      (s.categoryId == null && s.sectionName == cat.name);

  int _templateItemCountForCategory(String categoryId) =>
      _classTemplateSections.where((s) => s.categoryId == categoryId).length;

  _StudentState _defaultStudentState(Student student) {
    final rows = _buildRowsFromTemplate(_classTemplateSections);
    return _StudentState(student: student, rows: rows);
  }

  _StudentState _studentStateFromResult(
    Student student,
    StudentHomeworkResult result,
  ) {
    final loadedRows = result.sections
        .map(
          (s) => _SectionRow(
            sectionId: s.sectionId,
            categoryId: s.categoryId,
            sectionName: s.sectionName,
            subSection: s.subSection,
            checkCount: s.checkCount,
            detailMemo: s.detailMemo ?? '',
          ),
        )
        .toList();
    final rows = loadedRows;
    return _StudentState(
      student: student,
      rows: rows,
      mode: result.calculationMode,
      manualRate: result.manualCompletionRate,
      resubmission: result.resubmission,
    );
  }

  List<_SectionRow> _buildRowsFromTemplate(List<HomeworkSection> sections) =>
      sections
          .map(
            (s) => _SectionRow(
              sectionId: s.sectionId,
              categoryId: s.categoryId,
              sectionName: s.sectionName,
              subSection: s.subSection,
              checkCount: s.checkCount,
            ),
          )
          .toList();

  List<HomeworkSection> _ensureTemplateItems(List<HomeworkSection> sections) {
    final hasLegacyCategoryOnly = sections.any(
      (s) => (s.subSection ?? '').isEmpty,
    );
    if (!hasLegacyCategoryOnly) return sections;
    if (_categoryMetas.isNotEmpty) {
      return _defaultTemplateItemsFromMetas(_categoryMetas);
    }
    final uuid = const Uuid();
    final metas = _defaultCategoryItems.keys
        .map((name) => HomeworkCategoryMeta(id: uuid.v4(), name: name))
        .toList();
    return _defaultTemplateItemsFromMetas(metas);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _computeWeekStart(DateTime kst) {
    final monday = kst.subtract(Duration(days: kst.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  int _dayNameToWeekday(String day) {
    const map = {
      'monday': 1,
      'tuesday': 2,
      'wednesday': 3,
      'thursday': 4,
      'friday': 5,
      'saturday': 6,
      'sunday': 7,
    };
    return map[day.toLowerCase()] ?? 1;
  }

  List<HomeworkSection> _convertNextWeekItems(List<String> items) {
    const keywordMap = {
      '교과서': 'textbook',
      '부교재': 'workbook',
      '단어': 'vocabulary',
      '오답': 'wrong_answers',
      '프린트': 'print',
    };
    final result = <HomeworkSection>[];
    final usedIds = <String>{};
    final categoryIdForName = <String, String>{};
    String catId(String sectionName) => categoryIdForName.putIfAbsent(
      sectionName,
      () => const Uuid().v4(),
    );
    for (final item in items) {
      String sectionId = '';
      String sectionName = '';
      String? subSection;
      for (final entry in keywordMap.entries) {
        if (item.contains(entry.key)) {
          sectionId = entry.value;
          sectionName = entry.key;
          final idx = item.indexOf(entry.key) + entry.key.length;
          subSection = item.substring(idx).trim();
          if (subSection.isEmpty) subSection = null;
          break;
        }
      }
      if (sectionId.isEmpty || usedIds.contains(sectionId)) {
        sectionId = 'custom_${result.length}';
        sectionName = item.length > 8 ? item.substring(0, 8) : item;
        subSection = item;
      }
      usedIds.add(sectionId);
      result.add(
        HomeworkSection(
          sectionId: sectionId,
          categoryId: catId(sectionName),
          sectionName: sectionName,
          subSection: subSection,
          checkCount: 0,
        ),
      );
    }
    return result;
  }

  void _saveTemplate({bool markInspectionDirty = true}) {
    _hwService.saveTemplate(
      ClassHomeworkTemplate(
        classId: _classStorageKey,
        weekStartDate: _weekStartDate,
        sections: _classTemplateSections,
      ),
    );
    if (markInspectionDirty) _bumpInspectionIncomplete();
  }

  void _bumpInspectionIncomplete() {
    if (!_inspectionComplete) return;
    setState(() => _inspectionComplete = false);
    _hwService.saveInspectionComplete(_classStorageKey, _weekStartDate, false);
  }

  void _saveStudentResult(
    String studentId, {
    bool markInspectionDirty = true,
  }) {
    final state = _states[studentId];
    if (state == null) return;
    final allResults = _states.values
        .map((s) => s.toResult(_classStorageKey, _weekStartDate))
        .toList();
    _hwService.saveStudentResults(_classStorageKey, _weekStartDate, allResults);
    if (markInspectionDirty) _bumpInspectionIncomplete();
  }

  // ── Archive / 검사 완료 ────────────────────────────────────────────────────

  bool get _inspectionArchiveToLastWeeks {
    final now = nowKst();
    return now.weekday >= _dayNameToWeekday(_switchDay);
  }

  String get _inspectionTargetLabel =>
      _inspectionArchiveToLastWeeks ? 'LAST WEEKS' : 'THIS WEEK';

  Future<void> _completeInspection() async {
    final allResults = _states.values
        .map((s) => s.toResult(_classStorageKey, _weekStartDate))
        .toList();
    await _hwService.saveStudentResults(
      _classStorageKey,
      _weekStartDate,
      allResults,
    );

    if (_inspectionArchiveToLastWeeks) {
      final studentResults = _states.values.map((s) {
        final r = s.toResult(_classStorageKey, _weekStartDate);
        return HomeworkHistoryStudentResult(
          studentId: r.studentId,
          studentName: r.studentName,
          finalCompletionRate: r.isEvaluated ? r.finalCompletionRate : null,
          isEvaluated: r.isEvaluated,
          resubmission: s.resubmission,
        );
      }).toList();

      final entry = HomeworkHistoryEntry(
        classId: _classStorageKey,
        date: _weekStartDate,
        sections: List<HomeworkSection>.from(_classTemplateSections),
        studentResults: studentResults,
      );
      await _hwService.archiveEntry(entry);
      _history = _hwService.getHistory(
        _classStorageKey,
        fallbackKeys: _legacyClassKeys,
      );
    }

    setState(() => _inspectionComplete = true);
    await _hwService.saveInspectionComplete(
      _classStorageKey,
      _weekStartDate,
      true,
    );

    if (!mounted) return;
    final msg = _inspectionArchiveToLastWeeks
        ? '검사 완료! LAST WEEKS에 저장되었습니다'
        : '검사 완료! THIS WEEK에 저장되었습니다';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Section management ────────────────────────────────────────────────────

  void _addSectionToClass(String sectionId, String sectionName) {
    if (_classTemplateSections.any((s) => s.sectionId == sectionId)) return;
    setState(() {
      _classTemplateSections = [
        ..._classTemplateSections,
        HomeworkSection(
          sectionId: sectionId,
          categoryId: null,
          sectionName: sectionName,
          checkCount: 0,
        ),
      ];
      // Add to all student states
      for (final state in _states.values) {
        if (!state.rows.any((r) => r.sectionId == sectionId)) {
          state.rows = [
            ...state.rows,
            _SectionRow(
              sectionId: sectionId,
              categoryId: null,
              sectionName: sectionName,
            ),
          ];
        }
      }
    });
    _saveTemplate();
  }

  // ignore: unused_element
  void _removeSectionFromStudent(_StudentState state, _SectionRow row) {
    row.dispose();
    setState(() {
      state.rows = state.rows
          .where((r) => r.sectionId != row.sectionId)
          .toList();
    });
    _saveStudentResult(state.student.id);
  }

  /// Rename a section across the class template and all student rows.
  void _renameClassSection(String sectionId, String newName) {
    setState(() {
      _classTemplateSections = _classTemplateSections.map((s) {
        if (s.sectionId == sectionId) {
          return HomeworkSection(
            sectionId: s.sectionId,
            categoryId: s.categoryId,
            sectionName: newName,
            subSection: s.subSection,
            detailMemo: s.detailMemo,
            checkCount: s.checkCount,
          );
        }
        return s;
      }).toList();
      for (final state in _states.values) {
        for (final row in state.rows) {
          if (row.sectionId == sectionId) row.sectionName = newName;
        }
      }
    });
    _saveTemplate();
  }

  /// Delete a section from the class template and all student rows.
  void _deleteClassSection(String sectionId) {
    setState(() {
      _classTemplateSections = _classTemplateSections
          .where((s) => s.sectionId != sectionId)
          .toList();
      for (final state in _states.values) {
        final toRemove = state.rows
            .where((r) => r.sectionId == sectionId)
            .toList();
        for (final row in toRemove) {
          row.dispose();
        }
        state.rows = state.rows.where((r) => r.sectionId != sectionId).toList();
      }
    });
    _saveTemplate();
    // Save updated student results
    final allResults = _states.values
        .map((s) => s.toResult(_classStorageKey, _weekStartDate))
        .toList();
    _hwService.saveStudentResults(_classStorageKey, _weekStartDate, allResults);
  }

  /// Show manage-sections bottom sheet.
  // ignore: unused_element
  Future<void> _showManageSections() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManageSectionsSheet(
        sections: List.from(_classTemplateSections),
        onRename: (sectionId, newName) async {
          _renameClassSection(sectionId, newName);
          await _tmplService.renameSection(sectionId, newName);
        },
        onDelete: (sectionId) {
          _deleteClassSection(sectionId);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── Sub-section picker ────────────────────────────────────────────────────

  // ignore: unused_element
  Future<void> _pickSubSection(_StudentState state, _SectionRow row) async {
    final options = _tmplService.getSubSections(row.sectionId);
    String? chosen;
    String? custom;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SubSectionSheet(
        sectionName: row.sectionName,
        options: options,
        current: row.subSection,
        onSelected: (v) {
          chosen = v;
          Navigator.pop(ctx);
        },
        onCustom: (v) {
          custom = v.trim();
          Navigator.pop(ctx);
        },
        onClear: () {
          chosen = '';
          Navigator.pop(ctx);
        },
        onRemove: (v) async {
          await _tmplService.removeSubSection(row.sectionId, v);
          // If removed option was selected, clear it
          if (row.subSection == v) {
            setState(() => row.subSection = null);
            _saveStudentResult(state.student.id);
          }
        },
        onRenameOption: (oldV, newV) async {
          await _tmplService.renameSubSection(row.sectionId, oldV, newV);
          if (row.subSection == oldV) {
            setState(() => row.subSection = newV);
            _saveStudentResult(state.student.id);
          }
        },
      ),
    );

    if (chosen != null) {
      setState(() {
        row.subSection = chosen!.isEmpty ? null : chosen;
      });
      if (chosen!.isNotEmpty) {
        await _tmplService.saveSubSection(row.sectionId, chosen!);
      }
    } else if (custom != null && custom!.isNotEmpty) {
      await _tmplService.saveSubSection(row.sectionId, custom!);
      setState(() => row.subSection = custom);
    }
    _saveStudentResult(state.student.id);
  }

  // ── Add section sheet ─────────────────────────────────────────────────────

  // ignore: unused_element
  Future<void> _showAddSection(_StudentState? forStudent) async {
    final available = _tmplService
        .getAllSections()
        .where(
          (s) => !_classTemplateSections.any((c) => c.sectionId == s.sectionId),
        )
        .toList();

    HomeworkSectionTemplate? chosen;
    String? newName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddSectionSheet(
        available: available,
        onSelected: (t) {
          chosen = t;
          Navigator.pop(ctx);
        },
        onCreateNew: (name) {
          newName = name.trim();
          Navigator.pop(ctx);
        },
      ),
    );

    if (chosen != null) {
      _addSectionToClass(chosen!.sectionId, chosen!.sectionName);
    } else if (newName != null && newName!.isNotEmpty) {
      final id = newName!.toLowerCase().replaceAll(' ', '_');
      await _tmplService.addSection(id, newName!);
      _addSectionToClass(id, newName!);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        if (_tabDropdownOpen) setState(() => _tabDropdownOpen = false);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(_classTitle),
          backgroundColor: AppColors.overlay,
          foregroundColor: AppColors.navy,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildTabDropdown(),
                  Expanded(child: _buildTabContent()),
                ],
              ),
      ),
    );
  }

  // ── Tab dropdown ──────────────────────────────────────────────────────────

  Widget _buildTabDropdown() {
    return Material(
      color: AppColors.overlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_Tab>(
                value: _tab,
                dropdownColor: AppColors.card,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: AppColors.blue,
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.navy,
                ),
                items: _Tab.values
                    .map(
                      (t) => DropdownMenuItem<_Tab>(
                        value: t,
                        child: Text(
                          t.label,
                          style: const TextStyle(color: AppColors.navy),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _tab = v;
                    _tabDropdownOpen = false;
                  });
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case _Tab.thisWeek:
        return _buildThisWeek();
      case _Tab.lastWeeks:
        return _buildLastWeeks();
      case _Tab.nextWeek:
        return _buildNextWeek();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // THIS WEEK
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildThisWeek() {
    if (_students.isEmpty) {
      return const Center(
        child: Text('이 반에 등록된 학생이 없습니다', style: TextStyle(color: Colors.grey)),
      );
    }
    final allExpanded =
        _students.isNotEmpty &&
        _students.every((s) => _expanded.contains(s.id));

    return Column(
      children: [
        // 모두 펼치기 / 접기
        Container(
          width: double.infinity,
          color: AppColors.overlay,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  if (allExpanded) {
                    _expanded.clear();
                  } else {
                    _expanded.addAll(_students.map((s) => s.id));
                  }
                }),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  allExpanded ? '모두 접기' : '모두 펼치기',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const Spacer(),
              Text(
                '숙제 체크',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _buildClassHomeworkEditor(),
              const SizedBox(height: 8),
              ..._students.map((s) => _buildStudentRow(s)),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildInspectionButton(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInspectionButton() {
    if (_inspectionComplete) {
      return ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle, size: 18),
        label: Text(
          '검사 완료 — $_inspectionTargetLabel에 저장됨',
          style: const TextStyle(fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.green,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _completeInspection,
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text(
            '검사 미완료',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '완료 시 $_inspectionTargetLabel에 저장',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.subText),
        ),
      ],
    );
  }

  Widget _buildClassHomeworkEditor() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '숙제 항목',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addTopLevelCategory,
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                label: const Text(
                  '상위 항목 추가',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._categoryMetas.map(_buildClassCategoryEditorForMeta),
        ],
      ),
    );
  }

  Widget _buildClassCategoryEditorForMeta(HomeworkCategoryMeta meta) {
    final items = _classTemplateSections
        .where((s) => _sectionInCategory(s, meta))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                meta.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.subText,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _renameTopLevelCategory(meta),
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: Colors.grey[600],
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '상위 항목 이름',
            ),
            IconButton(
              onPressed: () => _deleteTopLevelCategory(meta),
              icon: const Icon(Icons.delete_outline, size: 16),
              color: Colors.red[300],
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: '상위 항목 삭제',
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...items.map((item) {
          final title = item.subSection ?? item.sectionName;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, color: AppColors.navy),
                  ),
                ),
                IconButton(
                  onPressed: () => _renameClassHomeworkItem(item),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  color: Colors.grey[600],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '수정',
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => _deleteClassHomeworkItem(item.sectionId),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: Colors.red[300],
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '삭제',
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 2),
        TextButton.icon(
          onPressed: () => _addClassHomeworkItem(meta),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('항목 추가', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _addTopLevelCategory() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('상위 항목 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 단어장, 모의고사'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    final meta = HomeworkCategoryMeta(
      id: const Uuid().v4(),
      name: result.trim(),
    );
    setState(() => _categoryMetas = [..._categoryMetas, meta]);
    await _hwService.saveCategoryMetas(_classStorageKey, _categoryMetas);
    _bumpInspectionIncomplete();
  }

  Future<void> _renameTopLevelCategory(HomeworkCategoryMeta meta) async {
    final ctrl = TextEditingController(text: meta.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('상위 항목 이름'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '새 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    final trimmed = result.trim();
    setState(() {
      _categoryMetas = _categoryMetas
          .map((m) => m.id == meta.id ? m.copyWith(name: trimmed) : m)
          .toList();
      _classTemplateSections = _classTemplateSections.map((s) {
        if (s.categoryId != meta.id) return s;
        return s.copyWith(sectionName: trimmed);
      }).toList();
      for (final st in _states.values) {
        for (final r in st.rows) {
          if (r.categoryId == meta.id) r.sectionName = trimmed;
        }
      }
      for (var i = 0; i < _nwSections.length; i++) {
        final s = _nwSections[i];
        if (s.categoryId == meta.id) {
          _nwSections[i] = s.copyWith(sectionName: trimmed);
        }
      }
    });
    await _hwService.saveCategoryMetas(_classStorageKey, _categoryMetas);
    _saveTemplate();
    if (_students.isNotEmpty) _saveStudentResult(_students.first.id);
    await _saveNextWeek(showSnackBar: false);
  }

  Future<void> _deleteTopLevelCategory(HomeworkCategoryMeta meta) async {
    final n = _templateItemCountForCategory(meta.id);
    if (n > 0) {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('상위 항목 삭제'),
              content: Text(
                '「${meta.name}」에 등록된 숙제 $n개가 함께 삭제됩니다. 계속할까요?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('삭제'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }

    setState(() {
      _categoryMetas = _categoryMetas.where((m) => m.id != meta.id).toList();
      _classTemplateSections = _classTemplateSections
          .where((s) => s.categoryId != meta.id)
          .toList();
      for (final st in _states.values) {
        final toRemove = st.rows.where((r) => r.categoryId == meta.id).toList();
        for (final r in toRemove) {
          r.dispose();
        }
        st.rows = st.rows.where((r) => r.categoryId != meta.id).toList();
      }
      _nwSections = _nwSections.where((s) => s.categoryId != meta.id).toList();
      final nwC = _nwAddLineCtrls.remove(meta.id);
      nwC?.dispose();
    });
    await _hwService.saveCategoryMetas(_classStorageKey, _categoryMetas);
    _saveTemplate();
    if (_students.isNotEmpty) _saveStudentResult(_students.first.id);
    await _saveNextWeek(showSnackBar: false);
  }

  Future<void> _addClassHomeworkItem(HomeworkCategoryMeta meta) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${meta.name} 항목 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '숙제 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;

    final section = HomeworkSection(
      sectionId: const Uuid().v4(),
      categoryId: meta.id,
      sectionName: meta.name,
      subSection: result,
      checkCount: 0,
    );
    setState(() {
      _classTemplateSections = [..._classTemplateSections, section];
      for (final state in _states.values) {
        state.rows = [
          ...state.rows,
          _SectionRow(
            sectionId: section.sectionId,
            categoryId: meta.id,
            sectionName: meta.name,
            subSection: result,
          ),
        ];
      }
    });
    _saveTemplate();
    if (_students.isNotEmpty) _saveStudentResult(_students.first.id);
  }

  Future<void> _renameClassHomeworkItem(HomeworkSection target) async {
    final ctrl = TextEditingController(text: target.subSection ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('숙제 항목 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '숙제 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;

    setState(() {
      _classTemplateSections = _classTemplateSections.map((s) {
        if (s.sectionId != target.sectionId) return s;
        return HomeworkSection(
          sectionId: s.sectionId,
          categoryId: s.categoryId,
          sectionName: s.sectionName,
          subSection: result,
          detailMemo: s.detailMemo,
          checkCount: s.checkCount,
        );
      }).toList();
      for (final state in _states.values) {
        for (final row in state.rows) {
          if (row.sectionId == target.sectionId) {
            row.subSection = result;
          }
        }
      }
    });
    _saveTemplate();
    if (_students.isNotEmpty) _saveStudentResult(_students.first.id);
  }

  void _deleteClassHomeworkItem(String sectionId) {
    setState(() {
      _classTemplateSections = _classTemplateSections
          .where((s) => s.sectionId != sectionId)
          .toList();
      for (final state in _states.values) {
        final removed = state.rows
            .where((r) => r.sectionId == sectionId)
            .toList();
        for (final row in removed) {
          row.dispose();
        }
        state.rows = state.rows.where((r) => r.sectionId != sectionId).toList();
      }
    });
    _saveTemplate();
    if (_students.isNotEmpty) _saveStudentResult(_students.first.id);
  }

  Widget _buildStudentRow(Student student) {
    final state = _states[student.id];
    final isExp = _expanded.contains(student.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() {
              if (isExp) {
                _expanded.remove(student.id);
              } else {
                _expanded.add(student.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Text(
                    student.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (state != null) _buildStatusBadge(state),
                  const Spacer(),
                  Icon(
                    isExp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.subText,
                  ),
                ],
              ),
            ),
          ),
          if (isExp && state != null) _buildStudentExpanded(state),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(_StudentState state) {
    if (!state.isEvaluated) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '미평가',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      );
    }
    final pct = state.finalRate;
    final color = pct >= 80
        ? AppColors.green
        : pct >= 50
        ? AppColors.orange
        : AppColors.red;
    final rsLabel = state.resubmission.status.displayLabel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$pct%',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (rsLabel.isNotEmpty) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color:
                  state.resubmission.status ==
                      ResubmissionStatus.resubmissionRequired
                  ? AppColors.orange.withValues(alpha: 0.15)
                  : AppColors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              rsLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color:
                    state.resubmission.status ==
                        ResubmissionStatus.resubmissionRequired
                    ? AppColors.orange
                    : AppColors.green,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStudentExpanded(_StudentState state) {
    final isManual = state.mode == HomeworkCompletionMode.direct;
    final finalRate = state.finalRate;
    final modeLabel = isManual ? '직접 입력' : '자동 입력';

    return Container(
      decoration: BoxDecoration(
        border: const Border(top: BorderSide(color: AppColors.line)),
        color: AppColors.cardAlt,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode label
          Text(
            modeLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.subText,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          // Section rows
          for (var ci = 0; ci < _categoryMetas.length; ci++) ...[
            if (ci > 0) const SizedBox(height: 8),
            _buildCategoryBlock(state, _categoryMetas[ci]),
          ],
          const SizedBox(height: 10),

          // 직접 입력 파트
          Row(
            children: [
              Text(
                '직접 입력',
                style: const TextStyle(fontSize: 13, color: AppColors.subText),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: state.manualCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    hintText: '0',
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null) {
                      final clamped = parsed.clamp(0, 100);
                      setState(() {
                        state.mode = HomeworkCompletionMode.direct;
                        state.manualRate = clamped;
                      });
                    } else {
                      setState(() {
                        state.mode = HomeworkCompletionMode.auto;
                        state.manualRate = null;
                      });
                    }
                    _saveStudentResult(state.student.id);
                  },
                ),
              ),
              const SizedBox(width: 6),
              const Text('%', style: TextStyle(color: AppColors.subText)),
            ],
          ),
          const SizedBox(height: 12),

          // Final rate display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '최종 숙제 이행률',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Text(
                    state.isEvaluated ? '$finalRate%' : '미평가',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: state.isEvaluated
                          ? (finalRate >= 80
                                ? AppColors.green
                                : finalRate >= 50
                                ? AppColors.orange
                                : AppColors.red)
                          : AppColors.subText,
                    ),
                  ),
                  if (state.isEvaluated) ...[
                    const SizedBox(width: 8),
                    Text(
                      _dotsStr(finalRate),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          _buildResubmissionSection(state),
        ],
      ),
    );
  }

  Widget _buildCategoryBlock(_StudentState state, HomeworkCategoryMeta meta) {
    final rows = state.rows.where((r) => _rowInCategory(r, meta)).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ...rows.map((row) => _buildSectionRowUi(state, row)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showAddHomeworkItemDialog(state, meta),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('숙제 항목 추가', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddHomeworkItemDialog(
    _StudentState state,
    HomeworkCategoryMeta meta,
  ) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${meta.name} 항목 추가'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: Unit 2 본문 해석'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    setState(() {
      state.rows.add(
        _SectionRow(
          sectionId: const Uuid().v4(),
          categoryId: meta.id,
          sectionName: meta.name,
          subSection: result,
        ),
      );
    });
    _saveStudentResult(state.student.id);
  }

  Widget _buildSectionRowUi(_StudentState state, _SectionRow row) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                row.subSection ?? row.sectionName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // 5 dots
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final filled = row.checkCount > i;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      // Cumulative: tap i → set checkCount to i+1 (or 0 if already at i+1)
                      row.checkCount = row.checkCount == i + 1 ? 0 : i + 1;
                      // Tapping a dot forces auto mode
                      state.mode = HomeworkCompletionMode.auto;
                      state.manualRate = null;
                      state.manualCtrl.clear();
                    });
                    _saveStudentResult(state.student.id);
                  },
                  child: Text(
                    filled ? '●' : '○',
                    style: TextStyle(
                      fontSize: 20,
                      color: filled ? AppColors.primary : Colors.grey[300],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LAST WEEKS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildLastWeeks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildCalendarHeader(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Expanded(flex: _selDate != null ? 5 : 10, child: _buildCalendarGridExpanded()),
                if (_selDate != null) ...[
                  const SizedBox(height: 8),
                  Flexible(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSelectedDateCard(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarHeader() {
    return Row(
      children: [
        Text(
          '${_calMonth.year}년 ${_calMonth.month}월',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const Spacer(),
        _calendarArrowBtn(
          icon: Icons.chevron_left_rounded,
          onTap: () => setState(() {
            _calMonth = DateTime(_calMonth.year, _calMonth.month - 1);
            _selDate = null;
          }),
        ),
        const SizedBox(width: 6),
        _calendarArrowBtn(
          icon: Icons.chevron_right_rounded,
          onTap: () => setState(() {
            _calMonth = DateTime(_calMonth.year, _calMonth.month + 1);
            _selDate = null;
          }),
        ),
      ],
    );
  }

  Widget _calendarArrowBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.graySoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 22, color: AppColors.navy),
        ),
      ),
    );
  }

  Widget _buildCalendarGridExpanded() {
    const dayLabels = ['일', '월', '화', '수', '목', '금', '토'];
    final firstDay = DateTime(_calMonth.year, _calMonth.month, 1);
    final daysInMonth = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;
    final rowCount = ((startWeekday + daysInMonth + 6) ~/ 7);

    final historyDates = {
      for (final e in _history)
        if (_isInMonth(e.date, _calMonth)) e.date: e,
    };
    final classMeetingDates = _meetingDatesForMonth(_calMonth, _classWeekdays);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Column(
        children: [
          Row(
            children: List.generate(7, (i) {
              return Expanded(
                child: Center(
                  child: Text(
                    dayLabels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == 0
                          ? const Color(0xFFFF6B6B)
                          : i == 6
                          ? AppColors.blue
                          : AppColors.subText,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Column(
              children: List.generate(rowCount, (row) {
                return Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      if (idx < startWeekday ||
                          idx >= startWeekday + daysInMonth) {
                        return const Expanded(child: SizedBox());
                      }
                      final day = idx - startWeekday + 1;
                      return Expanded(
                        child: _historyCalendarDayCell(
                          day: day,
                          historyDates: historyDates,
                          classMeetingDates: classMeetingDates,
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCalendarDayCell({
    required int day,
    required Map<String, HomeworkHistoryEntry> historyDates,
    required Set<String> classMeetingDates,
  }) {
    final dateStr =
        '${_calMonth.year}-${_calMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final hasEntry = historyDates.containsKey(dateStr);
    final hasClassMeeting = classMeetingDates.contains(dateStr);
    final isSelected = _selDate == dateStr;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: GestureDetector(
        onTap: () {
          if (hasEntry) {
            setState(() => _selDate = isSelected ? null : dateStr);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('해당 날짜의 숙제 기록이 없습니다'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.blue : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: hasEntry || hasClassMeeting
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.navy,
                ),
              ),
              if (hasEntry || hasClassMeeting) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasClassMeeting)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.78)
                              : Colors.grey[500],
                        ),
                      ),
                    if (hasEntry && hasClassMeeting) const SizedBox(width: 3),
                    if (hasEntry)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? Colors.white : AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isInMonth(String dateStr, DateTime month) {
    try {
      final d = DateTime.parse(dateStr);
      return d.year == month.year && d.month == month.month;
    } catch (_) {
      return false;
    }
  }

  Set<String> _meetingDatesForMonth(DateTime month, List<int> weekdays) {
    if (weekdays.isEmpty) return const {};
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final dates = <String>{};
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      if (weekdays.contains(date.weekday)) {
        dates.add(_dateKey(date));
      }
    }
    return dates;
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildSelectedDateCard() {
    final entry = _history.firstWhere(
      (e) => e.date == _selDate,
      orElse: () => HomeworkHistoryEntry(
        classId: _classStorageKey,
        date: _selDate!,
        sections: [],
        studentResults: [],
      ),
    );

    final date = DateTime.tryParse(_selDate!) ?? DateTime.now();
    const weekdays = ['', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final dayLabel = weekdays[date.weekday];

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} $dayLabel',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            // Sections
            if (entry.sections.isNotEmpty) ...[
              Text(
                '숙제 내용',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ...entry.sections.map((s) {
                final parts = [s.sectionName];
                if (s.subSection?.isNotEmpty == true) parts.add(s.subSection!);
                final base = parts.join(': ');
                final line = s.detailMemo?.isNotEmpty == true
                    ? '$base — ${s.detailMemo}'
                    : base;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $line',
                    style: const TextStyle(fontSize: 13, color: AppColors.navy),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
            // Student results
            if (entry.studentResults.isNotEmpty) ...[
              Text(
                '학생별 이행률',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ...entry.studentResults.map((r) {
                final rateStr = r.isEvaluated
                    ? '${r.finalCompletionRate}%'
                    : '미평가';
                final rsLabel = r.resubmission.status.displayLabel;
                final rateDisplay = rsLabel.isNotEmpty
                    ? '$rateStr · $rsLabel'
                    : rateStr;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '• ${r.studentName}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            rateDisplay,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: r.isEvaluated
                                  ? AppColors.primary
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      if (r.resubmission.status != ResubmissionStatus.none) ...[
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (r.resubmission.requiredAt != null)
                                Text(
                                  '재제출 지정: ${_formatDateTime(r.resubmission.requiredAt!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              if (r.resubmission.dueDate != null)
                                Text(
                                  '재제출 기한: ${_formatDate(r.resubmission.dueDate!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              Text(
                                r.resubmission.submittedAt != null
                                    ? '제출 확인: ${_formatDateTime(r.resubmission.submittedAt!)}'
                                    : '제출 확인: 미제출',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NEXT WEEK
  // ══════════════════════════════════════════════════════════════════════════

  TextEditingController _nwCtrlFor(String categoryId) {
    return _nwAddLineCtrls.putIfAbsent(
      categoryId,
      TextEditingController.new,
    );
  }

  Widget _buildNextWeek() {
    const dayOptions = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    const dayKeys = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasNw = _nwSections.isNotEmpty;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(12, 12, 12, 28 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '다음 주 숙제',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '지정 요일이 되면 THIS WEEK으로 자동 전환됩니다',
            style: TextStyle(fontSize: 12, color: AppColors.subText),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '자동 전환 요일',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _switchDay,
                    dropdownColor: AppColors.card,
                    items: List.generate(
                      dayOptions.length,
                      (i) => DropdownMenuItem(
                        value: dayKeys[i],
                        child: Text(
                          dayOptions[i],
                          style: const TextStyle(color: AppColors.navy),
                        ),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _switchDay = v);
                        _saveNextWeek(showSnackBar: false);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildNextWeekHomeworkEditor(),
          if (!hasNw)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '아직 추가된 숙제가 없습니다',
                style: TextStyle(color: AppColors.subText, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNextWeekHomeworkEditor() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '숙제 항목',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          ..._categoryMetas.map(_buildNextWeekCategoryBlock),
        ],
      ),
    );
  }

  Widget _buildNextWeekCategoryBlock(HomeworkCategoryMeta meta) {
    final items = _nwSections
        .asMap()
        .entries
        .where((e) => _sectionInCategory(e.value, meta))
        .toList();

    InputDecoration nwDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.subText),
      isDense: true,
      filled: true,
      fillColor: AppColors.cardAlt,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.blue,
          width: 1.5,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta.name,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 4),
        ...items.map((e) {
          final i = e.key;
          final s = e.value;
          final title = s.subSection ?? s.sectionName;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _editNwSectionAt(i),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    color: Colors.grey[600],
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    onPressed: () => _removeNwSectionAt(i),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    color: Colors.red[300],
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nwCtrlFor(meta.id),
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 14,
                ),
                decoration: nwDeco('세부 숙제 입력'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addNwSectionItem(meta),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _addNwSectionItem(meta),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '추가',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  void _addNwSectionItem(HomeworkCategoryMeta meta) {
    final text = _nwCtrlFor(meta.id).text.trim();
    if (text.isEmpty) return;
    setState(() {
      _nwSections.add(
        HomeworkSection(
          sectionId: const Uuid().v4(),
          categoryId: meta.id,
          sectionName: meta.name,
          subSection: text,
          checkCount: 0,
        ),
      );
      _nwCtrlFor(meta.id).clear();
    });
    _saveNextWeek();
  }

  Future<void> _removeNwSectionAt(int index) async {
    if (index < 0 || index >= _nwSections.length) return;
    setState(() => _nwSections.removeAt(index));
    await _saveNextWeek();
  }

  Future<void> _editNwSectionAt(int index) async {
    if (index < 0 || index >= _nwSections.length) return;
    final cur = _nwSections[index];
    final ctrl = TextEditingController(text: cur.subSection ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('숙제 항목 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '숙제 이름'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    setState(() {
      _nwSections[index] = cur.copyWith(subSection: result);
    });
    await _saveNextWeek();
  }

  Future<void> _saveNextWeek({bool showSnackBar = true}) async {
    final nw = NextWeekHomework(
      classId: _classStorageKey,
      switchDay: _switchDay,
      items: const [],
      sections: List<HomeworkSection>.from(_nwSections),
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _hwService.saveNextWeek(nw);
    if (showSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('다음 주 숙제가 저장되었습니다')),
      );
    }
  }

  // ── Resubmission UI ────────────────────────────────────────────────────────

  Widget _buildResubmissionSection(_StudentState state) {
    final rs = state.resubmission;
    final isOn = rs.status != ResubmissionStatus.none;
    final isRequired = rs.status == ResubmissionStatus.resubmissionRequired;
    final isSubmitted =
        rs.status == ResubmissionStatus.submittedAfterResubmission;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Divider(height: 1, color: Colors.grey[300]),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text(
              '재제출',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Switch(
              value: isOn,
              onChanged: (v) {
                setState(() {
                  if (v) {
                    state.resubmission = ResubmissionInfo(
                      status: ResubmissionStatus.resubmissionRequired,
                      requiredAt: DateTime.now().toIso8601String(),
                    );
                  } else {
                    state.resubmission = const ResubmissionInfo();
                  }
                });
                _saveStudentResult(state.student.id);
              },
              activeThumbColor: AppColors.orange,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        if (isOn) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '재제출 기한',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now().toUtc().add(
                    const Duration(hours: 9),
                  );
                  final initial = rs.dueDate != null
                      ? DateTime.tryParse(rs.dueDate!) ?? now
                      : now.add(const Duration(days: 4));
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    final ds =
                        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    setState(() {
                      state.resubmission = rs.copyWith(dueDate: ds);
                    });
                    _saveStudentResult(state.student.id);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rs.dueDate != null ? _formatDate(rs.dueDate!) : '날짜 선택',
                    style: TextStyle(
                      fontSize: 13,
                      color: rs.dueDate != null
                          ? Colors.black87
                          : Colors.grey[400],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isRequired) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    state.resubmission = rs.copyWith(
                      status: ResubmissionStatus.submittedAfterResubmission,
                      submittedAt: DateTime.now().toIso8601String(),
                    );
                  });
                  _saveStudentResult(state.student.id);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('제출 확인', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
          if (isSubmitted) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '상태: 제출 완료',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (rs.dueDate != null)
                    Text(
                      '재제출 기한: ${_formatDate(rs.dueDate!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (rs.submittedAt != null)
                    Text(
                      '제출 확인: ${_formatDateTime(rs.submittedAt!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  String _formatDate(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      const wd = ['', '월', '화', '수', '목', '금', '토', '일'];
      return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ${wd[d.weekday]}';
    } catch (_) {
      return isoDate;
    }
  }

  String _formatDateTime(String isoDatetime) {
    try {
      final d = DateTime.parse(isoDatetime).toLocal();
      const wd = ['', '월', '화', '수', '목', '금', '토', '일'];
      return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ${wd[d.weekday]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDatetime;
    }
  }

  String _dotsStr(int percent) {
    final filled = (percent / 20.0).ceil().clamp(0, 5);
    return ('●' * filled) + ('○' * (5 - filled));
  }
}
