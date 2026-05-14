import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/exam_score_model.dart';
import '../../data/models/student_model.dart';
import '../../services/class_exam_type_service.dart';
import '../../services/class_service.dart';
import '../../services/exam_session_service.dart';
import '../../services/student_service.dart';
import '../../theme/app_colors.dart';
import 'exam_type_ui.dart';

// ─── Entry point ──────────────────────────────────────────────────────────────

class GradeInputPage extends StatefulWidget {
  const GradeInputPage({super.key});

  @override
  State<GradeInputPage> createState() => _GradeInputPageState();
}

class _GradeInputPageState extends State<GradeInputPage> {
  // ── Services & loading ─────────────────────────────────────────────────────
  late StudentService _studentService;
  late ExamSessionService _examSessionService;
  late ClassExamTypeService _classExamTypeService;
  late ClassService _classService;
  List<ClassExamTypeDef> _examTypes = [];
  bool _isLoading = true;
  bool _didInit = false;

  // ── Class selection (types are stored per [ClassMeta.id]) ──────────────────
  List<ClassDisplayItem> _classItems = const [];
  String _selectedClassId = '';
  String _selectedClassDisplay = '';
  String _pendingRouteClassArg = '';
  String? _pendingExamTypeId;
  String? _pendingExamTypeDisplayName;
  DateTime? _pendingFocusDate;
  bool _didApplyGradeRouteHints = false;

  // ── Date ──────────────────────────────────────────────────────────────────
  DateTime _examDate = DateTime.now();

  // ── Students & scores ─────────────────────────────────────────────────────
  List<Student> _students = [];
  final List<_ExamDraftForm> _examForms = [];
  static const int _scheme5 = 5;
  static const int _scheme9 = 9;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty) {
      _pendingRouteClassArg = args.trim();
    } else if (args is Map) {
      final cid = args['classId'];
      if (cid is String && cid.trim().isNotEmpty) {
        _pendingRouteClassArg = cid.trim();
      } else {
        final cn = args['className'];
        if (cn is String && cn.trim().isNotEmpty) {
          _pendingRouteClassArg = cn.trim();
        }
      }
      final eid = args['examTypeId'];
      if (eid is String && eid.trim().isNotEmpty) {
        _pendingExamTypeId = eid.trim();
      }
      final etn = args['examTypeDisplayName'];
      if (etn is String && etn.trim().isNotEmpty) {
        _pendingExamTypeDisplayName = etn.trim();
      }
      final focusRaw = args['focusDate'];
      if (focusRaw is DateTime) {
        _pendingFocusDate = DateTime(
          focusRaw.year,
          focusRaw.month,
          focusRaw.day,
        );
      } else if (focusRaw is String) {
        final p = DateTime.tryParse(focusRaw);
        if (p != null) {
          _pendingFocusDate = DateTime(p.year, p.month, p.day);
        }
      }
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _studentService = StudentService(prefs: prefs);
    _examSessionService = ExamSessionService(prefs: prefs);
    _classExamTypeService = ClassExamTypeService(prefs: prefs);
    _classService = ClassService(prefs: prefs);
    await _studentService.initializeMockStudents();
    await _classService.initializeFromMockIfNeeded();
    final items = await _classService.getDisplayItems();
    ClassDisplayItem? pick;
    if (_pendingRouteClassArg.isNotEmpty) {
      final a = _pendingRouteClassArg;
      for (final i in items) {
        if (i.id == a || i.displayName == a || i.name.trim() == a) {
          pick = i;
          break;
        }
      }
    }
    pick ??= items.isNotEmpty ? items.first : null;
    setState(() {
      _classItems = items;
      _selectedClassId = pick?.id ?? '';
      _selectedClassDisplay = pick?.displayName ?? '';
      _isLoading = false;
    });
    await _loadStudents();
  }

  Future<void> _loadStudents() async {
    if (_selectedClassId.isEmpty) return;
    final students = await _studentService.getStudentsByClassId(_selectedClassId);
    final types = await _classExamTypeService.getTypesForClass(
      classId: _selectedClassId,
      displayNameForDefs: _selectedClassDisplay,
    );
    setState(() {
      _examTypes = types;
      _students = students;
      for (final form in _examForms) {
        form.dispose();
      }
      _examForms
        ..clear()
        ..add(_createExamForm());
    });
    _recomputeAll();
    _applyGradeRouteHintsIfNeeded();
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  ExamSession? _findSessionForForm(_ExamDraftForm form) {
    if (_selectedClassDisplay.isEmpty) return null;
    final all = _examSessionService.getAllSessions();
    for (final s in all) {
      if (s.className != _selectedClassDisplay) continue;
      if (!_isSameCalendarDay(s.examDate, _examDate)) continue;
      if (s.examTypeId != form.examTypeId) continue;
      return s;
    }
    return null;
  }

  void _hydrateFormFromSession(_ExamDraftForm form, ExamSession session) {
    form.examNameUserOverridden = true;
    form.examNameCtrl.text = session.examName;
    if (session.maxScore != null) {
      final m = session.maxScore!;
      form.maxScoreCtrl.text =
          m == m.roundToDouble() ? m.toStringAsFixed(0) : '$m';
    }
    if (session.retakeThreshold != null) {
      final t = session.retakeThreshold!;
      form.retakeCtrl.text =
          t == t.roundToDouble() ? t.toStringAsFixed(0) : '$t';
    }
    for (var i = 0; i < session.retakeScheduledDates.length; i++) {
      form.setRetakeScheduledDateForRound(i, session.retakeScheduledDates[i]);
    }
    for (final s in session.scores) {
      final st = form.scoreStates[s.studentId];
      if (st == null) continue;
      if (s.score != null) {
        final v = s.score!;
        st.scoreCtrl.text =
            v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
      }
      if (s.retakeScore != null) {
        final v = s.retakeScore!;
        st.ctrlForRound(0).text =
            v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
      }
    }
    _recomputeForm(form);
  }

  void _applyGradeRouteHintsIfNeeded() {
    if (_didApplyGradeRouteHints) return;
    final hasHint =
        _pendingFocusDate != null ||
        (_pendingExamTypeId != null && _pendingExamTypeId!.isNotEmpty) ||
        (_pendingExamTypeDisplayName != null &&
            _pendingExamTypeDisplayName!.isNotEmpty);
    if (!hasHint) return;
    _didApplyGradeRouteHints = true;
    if (_examForms.isEmpty) return;

    final form = _examForms.first;

    if (_pendingFocusDate != null) {
      _examDate = _pendingFocusDate!;
    }

    ClassExamTypeDef? resolvedType;
    if (_pendingExamTypeId != null && _pendingExamTypeId!.isNotEmpty) {
      for (final t in _examTypes) {
        if (t.id == _pendingExamTypeId) {
          resolvedType = t;
          break;
        }
      }
    }
    if (resolvedType == null &&
        _pendingExamTypeDisplayName != null &&
        _pendingExamTypeDisplayName!.isNotEmpty) {
      final name = _pendingExamTypeDisplayName!;
      for (final t in _examTypes) {
        if (t.displayName == name) {
          resolvedType = t;
          break;
        }
      }
    }
    if (resolvedType != null) {
      form.examTypeId = resolvedType.id;
      form.formType = resolvedType.formType;
      if (!form.examNameUserOverridden) {
        form.examNameCtrl.text = resolvedType.displayName;
      }
    }

    final session = _findSessionForForm(form);
    if (session != null) {
      _hydrateFormFromSession(form, session);
    } else {
      _recomputeForm(form);
    }

    _pendingExamTypeId = null;
    _pendingExamTypeDisplayName = null;
    _pendingFocusDate = null;

    if (mounted) setState(() {});
  }

  ClassExamTypeDef? _typeDefForForm(_ExamDraftForm form) {
    for (final t in _examTypes) {
      if (t.id == form.examTypeId) return t;
    }
    return null;
  }

  double _examTypeSelectorWidth() {
    if (_examTypes.isEmpty) return 140;
    const style = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    var maxW = 0.0;
    for (final t in _examTypes) {
      final tp = TextPainter(
        text: TextSpan(text: t.displayName, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      maxW = math.max(maxW, tp.width);
    }
    return (maxW + 44).clamp(120.0, 260.0);
  }

  Future<void> _openExamTypeSheet(_ExamDraftForm form) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(context).height * 0.55;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in _examTypes)
                      ListTile(
                        title: Text(
                          t.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: form.examTypeId == t.id
                                ? AppColors.primary
                                : AppColors.navy,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: (action) {
                            if (action == 'edit') {
                              unawaited(_renameExamType(t));
                            } else if (action == 'delete') {
                              unawaited(_deleteExamType(t));
                            }
                          },
                          itemBuilder: (c) => const [
                            PopupMenuItem(value: 'edit', child: Text('유형명 수정')),
                            PopupMenuItem(value: 'delete', child: Text('삭제')),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            form.examTypeId = t.id;
                            form.formType = t.formType;
                            if (!form.examNameUserOverridden) {
                              form.examNameCtrl.text = t.displayName;
                            }
                            _recomputeForm(form);
                          });
                        },
                      ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.add_rounded, color: AppColors.primary),
                      title: Text(
                        '유형 추가',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_addExamTypeFlow());
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameExamType(ClassExamTypeDef def) async {
    final ctrl = TextEditingController(text: def.displayName);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('유형명 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(
            labelText: '유형명',
            counterText: '',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(ctx, t.length > 10 ? t.substring(0, 10) : t);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null || !mounted) return;
    await _classExamTypeService.updateDisplayName(
      classId: _selectedClassId,
      typeId: def.id,
      displayName: r,
    );
    final list = await _classExamTypeService.getTypesForClass(
      classId: _selectedClassId,
      displayNameForDefs: _selectedClassDisplay,
    );
    setState(() {
      _examTypes = list;
      for (final f in _examForms) {
        if (f.examTypeId == def.id && !f.examNameUserOverridden) {
          f.examNameCtrl.text = r;
        }
      }
    });
  }

  Future<void> _deleteExamType(ClassExamTypeDef def) async {
    final n = _examSessionService.countSessionsForExamType(
      _selectedClassDisplay,
      def.id,
    );
    if (!mounted) return;
    if (n > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('유형 삭제'),
          content: Text(
            '이 유형으로 저장된 시험 기록이 $n건 있습니다. 유형을 삭제하면 새 성적 입력에서는 선택할 수 없지만, 기존 기록은 유지됩니다. 삭제할까요?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('유형 삭제'),
          content: Text('"${def.displayName}" 유형을 삭제할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _classExamTypeService.removeType(
      classId: _selectedClassId,
      typeId: def.id,
    );
    final list = await _classExamTypeService.getTypesForClass(
      classId: _selectedClassId,
      displayNameForDefs: _selectedClassDisplay,
    );
    final fallback = list.isNotEmpty ? list.first : null;
    setState(() {
      _examTypes = list;
      for (final f in _examForms) {
        if (f.examTypeId == def.id && fallback != null) {
          f.examTypeId = fallback.id;
          f.formType = fallback.formType;
          if (!f.examNameUserOverridden) {
            f.examNameCtrl.text = fallback.displayName;
          }
        }
      }
    });
    _recomputeAll();
  }

  Future<void> _addExamTypeFlow() async {
    final name = await showNewExamTypeNameDialog(context);
    if (name == null || !mounted) return;
    final kind = await showExamFormatPickerDialog(context, name);
    if (kind == null || !mounted) return;
    await _classExamTypeService.addCustomType(
      classId: _selectedClassId,
      displayNameForDefs: _selectedClassDisplay,
      displayName: name,
      formType: kind,
    );
    final list = await _classExamTypeService.getTypesForClass(
      classId: _selectedClassId,
      displayNameForDefs: _selectedClassDisplay,
    );
    setState(() => _examTypes = list);
  }

  Future<void> _addExamItem() async {
    setState(() {
      _examForms.add(_createExamForm());
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('시험 입력 폼이 추가되었습니다.')));
  }

  _ExamDraftForm _createExamForm() {
    final first = _examTypes.isNotEmpty
        ? _examTypes.first
        : ClassExamTypeDef(
            id: ClassExamTypeIds.vocabulary,
            className: _selectedClassDisplay,
            displayName: ExamCategory.vocabulary.label,
            formType: ExamFormType.thresholdBased,
          );
    final maxInit = first.formType == ExamFormType.thresholdBased
        ? '50'
        : '100';
    final retInit = first.formType == ExamFormType.thresholdBased
        ? '45'
        : '45';
    final form = _ExamDraftForm(
      examTypeId: first.id,
      formType: first.formType,
      examNameCtrl: TextEditingController(text: first.displayName),
      maxScoreCtrl: TextEditingController(text: maxInit),
      retakeCtrl: TextEditingController(text: retInit),
      useFiveGrade: false,
      useNineGrade: true,
      scoreStates: {
        for (final s in _students) s.id: _StudentScoreState(student: s),
      },
    );
    _recomputeForm(form);
    return form;
  }

  void _recomputeAll() {
    for (final form in _examForms) {
      _recomputeForm(form);
    }
  }

  void _recomputeForm(_ExamDraftForm form) {
    final scores = _buildScoreList(form);
    if (form.isThresholdBased) {
      final threshold = double.tryParse(form.retakeCtrl.text.trim());
      form.simpleAnalysis = SimpleExamAnalysis.compute(scores, threshold);
      form.complexAnalysis = null;
    } else {
      form.complexAnalysis = ComplexExamAnalysis.compute(scores);
      form.simpleAnalysis = null;
    }
  }

  List<ExamStudentScore> _buildRawScoreList(_ExamDraftForm form) =>
      _students.map((s) {
        final st = form.scoreStates[s.id]!;
        return ExamStudentScore(
          studentId: s.id,
          studentName: s.name,
          score: st.score,
          retakeScore: st.scoreForRound(0),
        );
      }).toList();

  List<ExamStudentScore> _buildScoreList(_ExamDraftForm form) {
    final raw = _buildRawScoreList(form);
    if (form.isThresholdBased) return raw;
    return _deriveComplexScores(raw, scheme: _primaryScheme(form));
  }

  int _primaryScheme(_ExamDraftForm form) {
    if (form.useNineGrade) return _scheme9;
    if (form.useFiveGrade) return _scheme5;
    return _scheme9;
  }

  List<ExamStudentScore> _deriveComplexScores(
    List<ExamStudentScore> scores, {
    required int scheme,
  }) {
    final entered = scores.where((s) => s.score != null).toList();
    if (entered.isEmpty) return scores;

    final values = entered.map((s) => s.score!).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length;
    final stddev = variance <= 0 ? 0.0 : math.sqrt(variance);

    return scores.map((s) {
      if (s.score == null) return s;
      final higherCount = entered.where((e) => e.score! > s.score!).length;
      final rank = higherCount + 1;
      final percentile = ((entered.length - rank + 1) / entered.length * 100)
          .clamp(0, 100)
          .toDouble();
      final z = stddev == 0 ? 0.0 : (s.score! - mean) / stddev;
      final grade = _gradeFromZ(z, scheme);
      return s.copyWith(grade: grade, percentile: percentile);
    }).toList();
  }

  int _gradeFromZ(double z, int scheme) {
    if (scheme == _scheme5) {
      if (z >= 1.2816) return 1;
      if (z >= 0.5244) return 2;
      if (z >= -0.5244) return 3;
      if (z >= -1.2816) return 4;
      return 5;
    }
    if (z >= 1.7507) return 1;
    if (z >= 1.2265) return 2;
    if (z >= 0.7388) return 3;
    if (z >= 0.2533) return 4;
    if (z >= -0.2533) return 5;
    if (z >= -0.7388) return 6;
    if (z >= -1.2265) return 7;
    if (z >= -1.7507) return 8;
    return 9;
  }

  ExamSession _buildSession(_ExamDraftForm form, int index) {
    final now = DateTime.now();
    final def = _typeDefForForm(form) ??
        ClassExamTypeDef(
          id: form.examTypeId,
          className: _selectedClassDisplay,
          displayName: '시험',
          formType: form.formType,
        );
    return ExamSession(
      id: const Uuid().v4(),
      className: _selectedClassDisplay,
      examDate: _examDate,
      examTypeId: form.examTypeId,
      examTypeDisplayName: def.displayName,
      formType: form.formType,
      examName: form.examNameCtrl.text.trim().isEmpty
          ? def.displayName
          : form.examNameCtrl.text.trim(),
      maxScore: double.tryParse(form.maxScoreCtrl.text.trim()),
      retakeThreshold: double.tryParse(form.retakeCtrl.text.trim()),
      retakeScheduledDates: form.retakeScheduledDates,
      schoolAverage: null,
      standardDeviation: form.complexAnalysis?.standardDeviation,
      hasGrade: form.isGradeBased,
      hasPercentile: form.isGradeBased,
      scores: _buildScoreList(form),
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── Date helpers ───────────────────────────────────────────────────────────
  String _fmtDate(DateTime d) {
    const wd = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${d.month}.${d.day.toString().padLeft(2, '0')} (${wd[d.weekday]})';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _examDate = picked);
    }
  }

  Future<void> _editExamName(_ExamDraftForm form) async {
    final ctrl = TextEditingController(text: form.examNameCtrl.text);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('시험명 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '시험명을 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      form.examNameUserOverridden = true;
      form.examNameCtrl.text = result.isEmpty
          ? (_typeDefForForm(form)?.displayName ?? '')
          : result;
    });
  }

  @override
  void dispose() {
    for (final form in _examForms) {
      form.dispose();
    }
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.overlay,
        foregroundColor: AppColors.navy,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '성적관리',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            if (_selectedClassDisplay.isNotEmpty)
              Text(
                _selectedClassDisplay,
                style: const TextStyle(fontSize: 12, color: AppColors.subText),
              ),
          ],
        ),
        actions: [
          if (_classItems.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedClassId.isNotEmpty ? _selectedClassId : null,
                  dropdownColor: AppColors.card,
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.primary,
                  ),
                  items: _classItems
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            c.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    for (final e in _classItems) {
                      if (e.id == v) {
                        setState(() {
                          _selectedClassId = e.id;
                          _selectedClassDisplay = e.displayName;
                        });
                        _loadStudents();
                        return;
                      }
                    }
                  },
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedClassId.isEmpty
          ? const Center(child: Text('등록된 반이 없습니다'))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRow(),
          const SizedBox(height: 12),
          ...List.generate(_examForms.length, (index) {
            final form = _examForms[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTypeRow(form),
                const SizedBox(height: 8),
                _buildSettingsCard(form),
                const SizedBox(height: 12),
                _buildStudentListCard(form),
                const SizedBox(height: 12),
                _buildAnalysisCard(form),
                if (form.isThresholdBased) ...[
                  const SizedBox(height: 12),
                  _buildRetakeCard(form),
                ],
                if (index != _examForms.length - 1) const SizedBox(height: 16),
              ],
            );
          }),
          if (_examForms.isNotEmpty) ...[
            const SizedBox(height: 12),
          ] else ...[
            const Center(child: Text('시험 입력 폼이 없습니다')),
          ],
          const SizedBox(height: 16),
          _buildBottomActionButtons(),
        ],
      ),
    );
  }

  // ── Date row ────────────────────────────────────────────────────────────────

  Widget _buildDateRow() {
    return Row(
      children: [
        _SectionLabel(icon: Icons.calendar_today_outlined, label: '날짜'),
        const SizedBox(width: 10),
        _ChipButton(
          label: _fmtDate(_examDate),
          onTap: _pickDate,
          icon: Icons.expand_more,
        ),
      ],
    );
  }

  // ── Settings card ────────────────────────────────────────────────────────────

  Widget _buildTypeRow(_ExamDraftForm form) {
    final label = _typeDefForForm(form)?.displayName ?? '유형 선택';
    final w = _examTypeSelectorWidth();
    return _FieldRow(
      label: '유형',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => unawaited(_openExamTypeSheet(form)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.expand_more,
                    size: 18,
                    color: AppColors.subText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(_ExamDraftForm form) {
    final displayName = form.examNameCtrl.text.trim().isEmpty
        ? (_typeDefForForm(form)?.displayName ?? '')
        : form.examNameCtrl.text.trim();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(label: '시험명'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editExamName(form),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('수정'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (form.isThresholdBased) ...[
            _FieldRow(
              label: '만점',
              child: _NumField(
                ctrl: form.maxScoreCtrl,
                hint: '50',
                suffix: '점',
                onChanged: (_) => setState(() => _recomputeForm(form)),
              ),
            ),
            const SizedBox(height: 10),
            _FieldRow(
              label: '재시험 기준',
              child: _NumField(
                ctrl: form.retakeCtrl,
                hint: '45',
                suffix: '점 미만',
                onChanged: (_) => setState(() => _recomputeForm(form)),
              ),
            ),
          ] else ...[
            _FieldRow(
              label: '만점',
              child: _NumField(
                ctrl: form.maxScoreCtrl,
                hint: '100',
                suffix: '점',
                onChanged: (_) => setState(() => _recomputeForm(form)),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '등급 계산 방식',
              style: TextStyle(fontSize: 12, color: AppColors.subText),
            ),
            const SizedBox(height: 8),
            _buildGradeSchemeSelector(form),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeSchemeSelector(_ExamDraftForm form) {
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.graySoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.line,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primary : AppColors.subText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          label: '5등급제',
          selected: form.useFiveGrade,
          onTap: () => setState(() {
            form.useFiveGrade = !form.useFiveGrade;
            _recomputeForm(form);
          }),
        ),
        const SizedBox(width: 8),
        chip(
          label: '9등급제',
          selected: form.useNineGrade,
          onTap: () => setState(() {
            form.useNineGrade = !form.useNineGrade;
            _recomputeForm(form);
          }),
        ),
      ],
    );
  }

  // ── Student list card ────────────────────────────────────────────────────────

  Widget _buildStudentListCard(_ExamDraftForm form) {
    final maxScore = double.tryParse(form.maxScoreCtrl.text.trim());
    final threshold = double.tryParse(form.retakeCtrl.text.trim());
    final complexScores5 = (!form.isThresholdBased && form.useFiveGrade)
        ? {
            for (final score in _deriveComplexScores(
              _buildRawScoreList(form),
              scheme: _scheme5,
            ))
              score.studentId: score,
          }
        : const <String, ExamStudentScore>{};
    final complexScores9 = (!form.isThresholdBased && form.useNineGrade)
        ? {
            for (final score in _deriveComplexScores(
              _buildRawScoreList(form),
              scheme: _scheme9,
            ))
              score.studentId: score,
          }
        : const <String, ExamStudentScore>{};

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardTitle(label: '성적 입력'),
              const Spacer(),
              Text(
                '${_students.length}명',
                style: const TextStyle(fontSize: 12, color: AppColors.subText),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_students.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '이 반에 학생이 없습니다',
                  style: TextStyle(color: AppColors.subText),
                ),
              ),
            )
          else
            ...List.generate(_students.length, (i) {
              final student = _students[i];
              final state = form.scoreStates[student.id]!;
              return Column(
                children: [
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: AppColors.line,
                      indent: 0,
                      endIndent: 0,
                    ),
                  if (form.isThresholdBased)
                    _SimpleStudentRow(
                      student: student,
                      state: state,
                      maxScore: maxScore,
                      threshold: threshold,
                      onChanged: () => setState(() => _recomputeForm(form)),
                    )
                  else
                    _ComplexStudentRow(
                      student: student,
                      state: state,
                      maxScore: maxScore,
                      derivedScore5: complexScores5[student.id],
                      derivedScore9: complexScores9[student.id],
                      showFiveGrade: form.useFiveGrade,
                      showNineGrade: form.useNineGrade,
                      onChanged: () => setState(() => _recomputeForm(form)),
                    ),
                ],
              );
            }),
        ],
      ),
    );
  }

  // ── Analysis card ────────────────────────────────────────────────────────────

  Widget _buildAnalysisCard(_ExamDraftForm form) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(label: '분석'),
          const SizedBox(height: 12),
          if (form.isThresholdBased)
            _buildSimpleAnalysis(form)
          else
            _buildComplexAnalysis(form),
        ],
      ),
    );
  }

  Widget _buildSimpleAnalysis(_ExamDraftForm form) {
    final a = form.simpleAnalysis;
    if (a == null) return _AnalysisEmpty();
    return Column(
      children: [
        _AnalysisRow(
          label: '평균',
          value: a.average != null ? '${a.average!.toStringAsFixed(1)}점' : '–',
        ),
        _AnalysisRow(
          label: '최고점',
          value: a.highest != null ? '${a.highest!.toStringAsFixed(0)}점' : '–',
        ),
        _AnalysisRow(
          label: '최저점',
          value: a.lowest != null ? '${a.lowest!.toStringAsFixed(0)}점' : '–',
        ),
        _AnalysisRow(
          label: '재시험자',
          value: '${a.retakeCount}명',
          valueColor: a.retakeCount > 0 ? AppColors.orange : AppColors.green,
        ),
        _AnalysisRow(
          label: '미입력',
          value: '${a.unentered}명',
          valueColor: a.unentered > 0 ? AppColors.subText : null,
        ),
      ],
    );
  }

  Widget _buildComplexAnalysis(_ExamDraftForm form) {
    final a = form.complexAnalysis;
    if (a == null) return _AnalysisEmpty();
    final enteredCount = _students.length - a.unentered;
    final showFive = form.useFiveGrade;
    final showNine = form.useNineGrade;
    final fiveBands = showFive
        ? _buildComplexGradeBands(form, scheme: _scheme5)
        : const <_GradeBand>[];
    final nineBands = showNine
        ? _buildComplexGradeBands(form, scheme: _scheme9)
        : const <_GradeBand>[];
    final fiveAvg = showFive ? _averageGradeByScheme(form, _scheme5) : null;
    final nineAvg = showNine ? _averageGradeByScheme(form, _scheme9) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnalysisRow(
          label: '반 평균',
          value: a.classAverage != null
              ? '${a.classAverage!.toStringAsFixed(1)}점'
              : '–',
        ),
        _AnalysisRow(
          label: '표준편차',
          value: a.standardDeviation != null
              ? a.standardDeviation!.toStringAsFixed(1)
              : '–',
        ),
        if (showFive)
          _AnalysisRow(
            label: '평균 등급(5등급제)',
            value: fiveAvg != null ? '${fiveAvg.toStringAsFixed(1)}등급' : '–',
          ),
        if (showNine)
          _AnalysisRow(
            label: '평균 등급(9등급제)',
            value: nineAvg != null ? '${nineAvg.toStringAsFixed(1)}등급' : '–',
          ),
        _AnalysisRow(
          label: '최고점',
          value: a.highest != null ? '${a.highest!.toStringAsFixed(0)}점' : '–',
        ),
        _AnalysisRow(
          label: '최저점',
          value: a.lowest != null ? '${a.lowest!.toStringAsFixed(0)}점' : '–',
        ),
        _AnalysisRow(
          label: '미입력',
          value: '${a.unentered}명',
          valueColor: a.unentered > 0 ? AppColors.subText : null,
        ),
        if (showFive || showNine) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
        ],
        if (showFive) _buildGradeBandSection('5등급제', fiveBands, enteredCount),
        if (showNine) _buildGradeBandSection('9등급제', nineBands, enteredCount),
        if (!showFive && !showNine)
          const Text(
            '오늘 시험에서 등급 계산 방식을 선택하면 등급 분석이 표시됩니다.',
            style: TextStyle(fontSize: 12, color: AppColors.subText),
          ),
      ],
    );
  }

  Widget _buildGradeBandSection(
    String label,
    List<_GradeBand> bands,
    int enteredCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label 등급컷',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 8),
        if (enteredCount == 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              '점수를 입력하면 등급컷이 표시됩니다.',
              style: TextStyle(fontSize: 12, color: AppColors.subText),
            ),
          )
        else
          ...bands.map(
            (band) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      '${band.grade}등급 ${band.cutoff.toStringAsFixed(1)}점↑',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      band.names.join(', '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.subText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  double? _averageGradeByScheme(_ExamDraftForm form, int scheme) {
    final scored = _deriveComplexScores(
      _buildRawScoreList(form),
      scheme: scheme,
    ).where((e) => e.grade != null);
    if (scored.isEmpty) return null;
    final values = scored.map((e) => e.grade!.toDouble()).toList();
    return values.reduce((a, b) => a + b) / values.length;
  }

  List<_GradeBand> _buildComplexGradeBands(
    _ExamDraftForm form, {
    required int scheme,
  }) {
    if (form.isThresholdBased) return const [];
    final scores = _deriveComplexScores(
      _buildRawScoreList(form),
      scheme: scheme,
    );
    final grouped = <int, List<ExamStudentScore>>{};

    for (final s in scores) {
      final grade = s.grade;
      if (s.score == null || grade == null) continue;
      grouped.putIfAbsent(grade, () => []).add(s);
    }

    final bands = <_GradeBand>[];
    final gradeKeys = grouped.keys.toList()..sort();
    for (final grade in gradeKeys) {
      final members = grouped[grade]!;
      members.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
      final cutoff = members.last.score ?? 0;
      final names = members.map((e) => e.studentName).toList();
      bands.add(_GradeBand(grade: grade, cutoff: cutoff, names: names));
    }
    return bands;
  }

  // ── Retake card ───────────────────────────────────────────────────────────────

  Widget _buildRetakeCard(_ExamDraftForm form) {
    final retakes = form.simpleAnalysis?.retakeStudents ?? [];
    final enteredCount = _students.where((s) {
      final score = form.scoreStates[s.id]?.score;
      return score != null;
    }).length;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardTitle(label: '재시험자'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orangeSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${retakes.length}명',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${form.maxForRetakeRound(0)?.toStringAsFixed(0) ?? '?'}점 / ${form.thresholdForRetakeRound(0)?.toStringAsFixed(0) ?? '?'}점 미만',
                style: const TextStyle(fontSize: 11, color: AppColors.subText),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (enteredCount == 0)
            const Text(
              '점수를 입력하면 재시험자가 자동으로 표시됩니다',
              style: TextStyle(color: AppColors.subText, fontSize: 13),
            )
          else if (retakes.isEmpty)
            const Text(
              '재시험자가 없습니다 🎉',
              style: TextStyle(color: AppColors.subText, fontSize: 13),
            )
          else
            ..._buildRetakeRounds(form, retakes),
        ],
      ),
    );
  }

  List<Widget> _buildRetakeRounds(
    _ExamDraftForm form,
    List<ExamStudentScore> initialRetakes,
  ) {
    final widgets = <Widget>[];
    var candidates = initialRetakes;
    var round = 0;

    while (candidates.isNotEmpty) {
      if (round > 0) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(const Divider(height: 1, color: AppColors.line));
        widgets.add(const SizedBox(height: 10));
      }

      widgets.add(
        Text(
          '${round + 1}차 재시험',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
      );
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        Row(
          children: [
            const Text(
              '만점',
              style: TextStyle(fontSize: 11, color: AppColors.subText),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 64,
              child: _NumField(
                ctrl: form.maxCtrlForRetakeRound(round),
                hint: '50',
                onChanged: (_) => setState(() => _recomputeForm(form)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              '기준',
              style: TextStyle(fontSize: 11, color: AppColors.subText),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 82,
              child: _NumField(
                ctrl: form.thresholdCtrlForRetakeRound(round),
                hint: '45',
                onChanged: (_) => setState(() => _recomputeForm(form)),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '점 미만',
              style: TextStyle(fontSize: 11, color: AppColors.subText),
            ),
            const Spacer(),
            _ChipButton(
              label: form.retakeScheduledDateForRound(round) != null
                  ? _fmtDate(form.retakeScheduledDateForRound(round)!)
                  : '재시험 날짜',
              onTap: () => _pickRetakeDate(form, round),
              icon: Icons.calendar_today_outlined,
            ),
          ],
        ),
      );
      widgets.add(const SizedBox(height: 8));

      final threshold = form.thresholdForRetakeRound(round);
      final maxScore = form.maxForRetakeRound(round);

      for (final student in candidates) {
        final state = form.scoreStates[student.studentId]!;
        final prevScore = round == 0
            ? student.score
            : state.scoreForRound(round - 1);
        final currentScore = state.scoreForRound(round);
        final status = currentScore == null
            ? _ScoreStatus.unentered
            : (threshold != null && currentScore < threshold
                  ? _ScoreStatus.retake
                  : _ScoreStatus.pass);

        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 16,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 62,
                  child: Text(
                    student.studentName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  prevScore != null
                      ? '${prevScore.toStringAsFixed(0)}/${maxScore?.toStringAsFixed(0) ?? '?'}'
                      : '미입력',
                  style: const TextStyle(fontSize: 12, color: AppColors.orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumField(
                    ctrl: state.ctrlForRound(round),
                    hint: '${round + 1}차 점수',
                    onChanged: (_) => setState(() => _recomputeForm(form)),
                  ),
                ),
                const SizedBox(width: 6),
                _StatusBadge(status: status),
              ],
            ),
          ),
        );
      }

      widgets.add(const SizedBox(height: 8));
      widgets.addAll(_buildRetakeAnalysisRows(form, candidates, round));

      candidates = candidates.where((student) {
        final score = form.scoreStates[student.studentId]?.scoreForRound(round);
        return threshold != null && score != null && score < threshold;
      }).toList();
      round += 1;
    }

    return widgets;
  }

  List<Widget> _buildRetakeAnalysisRows(
    _ExamDraftForm form,
    List<ExamStudentScore> retakes,
    int round,
  ) {
    final retakeScores = <double>[];
    var unentered = 0;
    for (final item in retakes) {
      final score = form.scoreStates[item.studentId]?.scoreForRound(round);
      if (score == null) {
        unentered += 1;
      } else {
        retakeScores.add(score);
      }
    }
    final avg = retakeScores.isEmpty
        ? null
        : retakeScores.reduce((a, b) => a + b) / retakeScores.length;
    final highest = retakeScores.isEmpty
        ? null
        : retakeScores.reduce((a, b) => a > b ? a : b);
    final lowest = retakeScores.isEmpty
        ? null
        : retakeScores.reduce((a, b) => a < b ? a : b);

    return [
      _AnalysisRow(
        label: '${round + 1}차 평균',
        value: avg != null ? '${avg.toStringAsFixed(1)}점' : '–',
      ),
      _AnalysisRow(
        label: '${round + 1}차 최고',
        value: highest != null ? '${highest.toStringAsFixed(0)}점' : '–',
      ),
      _AnalysisRow(
        label: '${round + 1}차 최저',
        value: lowest != null ? '${lowest.toStringAsFixed(0)}점' : '–',
      ),
      _AnalysisRow(
        label: '${round + 1}차 미입력',
        value: '$unentered명',
        valueColor: unentered > 0 ? AppColors.subText : null,
      ),
    ];
  }

  // ── Bottom actions ───────────────────────────────────────────────────────────

  Future<void> _saveScores() async {
    try {
      for (var i = 0; i < _examForms.length; i++) {
        final session = _buildSession(_examForms[i], i);
        await _examSessionService.saveSession(session);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 오류: $e'), backgroundColor: AppColors.red),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_examForms.length}개 시험 폼이 저장되었습니다'),
        backgroundColor: AppColors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickRetakeDate(_ExamDraftForm form, int round) async {
    final initialDate =
        form.retakeScheduledDateForRound(round) ??
        _examDate.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      form.setRetakeScheduledDateForRound(round, picked);
    });
  }

  Widget _buildBottomActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _addExamItem,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              '시험 추가',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: _saveScores,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              '성적 저장',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Per-form editing state ───────────────────────────────────────────────────

class _ExamDraftForm {
  String examTypeId;
  ExamFormType formType;
  /// 시험명을 수정 다이얼로그로 바꾼 뒤에는 유형 변경 시 자동 이름을 덮어쓰지 않습니다.
  bool examNameUserOverridden = false;
  final TextEditingController examNameCtrl;
  final TextEditingController maxScoreCtrl;
  final TextEditingController retakeCtrl;
  final List<TextEditingController> _retakeRoundMaxCtrls = [];
  final List<TextEditingController> _retakeRoundThresholdCtrls = [];
  final List<DateTime?> retakeScheduledDates = [];
  bool useFiveGrade;
  bool useNineGrade;
  final Map<String, _StudentScoreState> scoreStates;
  SimpleExamAnalysis? simpleAnalysis;
  ComplexExamAnalysis? complexAnalysis;

  bool get isThresholdBased => formType == ExamFormType.thresholdBased;
  bool get isGradeBased => formType == ExamFormType.gradeBased;

  _ExamDraftForm({
    required this.examTypeId,
    required this.formType,
    required this.examNameCtrl,
    required this.maxScoreCtrl,
    required this.retakeCtrl,
    required this.useFiveGrade,
    required this.useNineGrade,
    required this.scoreStates,
  }) {
    _retakeRoundMaxCtrls.add(TextEditingController(text: maxScoreCtrl.text));
    _retakeRoundThresholdCtrls.add(
      TextEditingController(text: retakeCtrl.text),
    );
    retakeScheduledDates.add(null);
  }

  TextEditingController maxCtrlForRetakeRound(int round) {
    while (_retakeRoundMaxCtrls.length <= round) {
      _retakeRoundMaxCtrls.add(TextEditingController(text: maxScoreCtrl.text));
    }
    return _retakeRoundMaxCtrls[round];
  }

  TextEditingController thresholdCtrlForRetakeRound(int round) {
    while (_retakeRoundThresholdCtrls.length <= round) {
      _retakeRoundThresholdCtrls.add(
        TextEditingController(text: retakeCtrl.text),
      );
    }
    return _retakeRoundThresholdCtrls[round];
  }

  DateTime? retakeScheduledDateForRound(int round) {
    while (retakeScheduledDates.length <= round) {
      retakeScheduledDates.add(null);
    }
    return retakeScheduledDates[round];
  }

  void setRetakeScheduledDateForRound(int round, DateTime? date) {
    while (retakeScheduledDates.length <= round) {
      retakeScheduledDates.add(null);
    }
    retakeScheduledDates[round] = date;
  }

  double? maxForRetakeRound(int round) =>
      double.tryParse(maxCtrlForRetakeRound(round).text.trim());

  double? thresholdForRetakeRound(int round) =>
      double.tryParse(thresholdCtrlForRetakeRound(round).text.trim());

  void dispose() {
    examNameCtrl.dispose();
    maxScoreCtrl.dispose();
    retakeCtrl.dispose();
    for (final ctrl in _retakeRoundMaxCtrls) {
      ctrl.dispose();
    }
    for (final ctrl in _retakeRoundThresholdCtrls) {
      ctrl.dispose();
    }
    for (final state in scoreStates.values) {
      state.dispose();
    }
  }
}

// ─── Per-student editing state ────────────────────────────────────────────────

class _StudentScoreState {
  final Student student;
  final TextEditingController scoreCtrl;
  final List<TextEditingController> _retakeCtrls = [];

  _StudentScoreState({required this.student})
    : scoreCtrl = TextEditingController();

  double? get score => double.tryParse(scoreCtrl.text.trim());
  double? scoreForRound(int round) {
    if (round < 0 || round >= _retakeCtrls.length) return null;
    return double.tryParse(_retakeCtrls[round].text.trim());
  }

  TextEditingController ctrlForRound(int round) {
    while (_retakeCtrls.length <= round) {
      _retakeCtrls.add(TextEditingController());
    }
    return _retakeCtrls[round];
  }

  void dispose() {
    scoreCtrl.dispose();
    for (final ctrl in _retakeCtrls) {
      ctrl.dispose();
    }
  }
}

// ─── Student rows ─────────────────────────────────────────────────────────────

class _SimpleStudentRow extends StatelessWidget {
  final Student student;
  final _StudentScoreState state;
  final double? maxScore;
  final double? threshold;
  final VoidCallback onChanged;

  const _SimpleStudentRow({
    required this.student,
    required this.state,
    required this.maxScore,
    required this.threshold,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final score = state.score;
    final status = _status(score);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              student.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: TextField(
              controller: state.scoreCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '–',
                hintStyle: const TextStyle(color: AppColors.subText),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                filled: true,
                fillColor: AppColors.graySoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '/ ${maxScore?.toStringAsFixed(0) ?? '?'}',
            style: const TextStyle(fontSize: 13, color: AppColors.subText),
          ),
          const Spacer(),
          _StatusBadge(status: status),
        ],
      ),
    );
  }

  _ScoreStatus _status(double? score) {
    if (score == null) return _ScoreStatus.unentered;
    if (threshold != null && score < threshold!) return _ScoreStatus.retake;
    return _ScoreStatus.pass;
  }
}

class _ComplexStudentRow extends StatelessWidget {
  final Student student;
  final _StudentScoreState state;
  final double? maxScore;
  final ExamStudentScore? derivedScore5;
  final ExamStudentScore? derivedScore9;
  final bool showFiveGrade;
  final bool showNineGrade;
  final VoidCallback onChanged;

  const _ComplexStudentRow({
    required this.student,
    required this.state,
    required this.maxScore,
    required this.derivedScore5,
    required this.derivedScore9,
    required this.showFiveGrade,
    required this.showNineGrade,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              student.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumField(
              ctrl: state.scoreCtrl,
              hint: '점수',
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '/ ${maxScore?.toStringAsFixed(0) ?? '?'}',
            style: const TextStyle(fontSize: 13, color: AppColors.subText),
          ),
          const SizedBox(width: 8),
          if (showFiveGrade)
            _AutoCalcBadge(
              label: '5등급',
              value: derivedScore5?.grade != null
                  ? '${derivedScore5!.grade}'
                  : '–',
            ),
          if (showFiveGrade && showNineGrade) const SizedBox(width: 6),
          if (showNineGrade)
            _AutoCalcBadge(
              label: '9등급',
              value: derivedScore9?.grade != null
                  ? '${derivedScore9!.grade}'
                  : '–',
            ),
          if (showFiveGrade || showNineGrade) const SizedBox(width: 6),
          _AutoCalcBadge(
            label: '백분위',
            value: derivedScore9?.percentile != null
                ? derivedScore9!.percentile!.toStringAsFixed(0)
                : '–',
          ),
        ],
      ),
    );
  }
}

// ─── Score status ─────────────────────────────────────────────────────────────

enum _ScoreStatus { pass, retake, unentered }

class _StatusBadge extends StatelessWidget {
  final _ScoreStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      _ScoreStatus.pass => ('통과', const Color(0xFFE6F9F0), AppColors.green),
      _ScoreStatus.retake => ('재시험', AppColors.orangeSoft, AppColors.orange),
      _ScoreStatus.unentered => ('미입력', AppColors.graySoft, AppColors.subText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ─── Reusable small widgets ───────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String label;
  const _CardTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.navy,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const _ChipButton({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: AppColors.subText),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.subText),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final String? suffix;
  final ValueChanged<String> onChanged;

  const _NumField({
    required this.ctrl,
    required this.hint,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, color: AppColors.navy),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.subText, fontSize: 13),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 12, color: AppColors.subText),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        filled: true,
        fillColor: AppColors.graySoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _AutoCalcBadge extends StatelessWidget {
  final String label;
  final String value;

  const _AutoCalcBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.graySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
    );
  }
}

class _GradeBand {
  final int grade;
  final double cutoff;
  final List<String> names;

  const _GradeBand({
    required this.grade,
    required this.cutoff,
    required this.names,
  });
}

class _AnalysisRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _AnalysisRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.subText),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '점수를 입력하면 분석이 표시됩니다',
        style: TextStyle(fontSize: 13, color: AppColors.subText),
      ),
    );
  }
}
