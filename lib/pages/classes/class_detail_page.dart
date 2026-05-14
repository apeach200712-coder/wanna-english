import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/korean_school_search.dart';
import '../../data/models/class_model.dart';
import '../../services/class_management_service.dart';
import '../../services/class_service.dart';
import '../../services/korean_school_search_service.dart';
import '../../theme/app_colors.dart';

enum _DuplicateResolution {
  addAnyway,
  renameExisting,
}

class _RenameExistingClassDraft {
  final ClassProgramType programType;
  final String schoolName;
  final String? grade;
  final String customClassName;

  const _RenameExistingClassDraft({
    required this.programType,
    required this.schoolName,
    required this.grade,
    required this.customClassName,
  });
}

class ClassDetailPage extends StatefulWidget {
  final String? classId;

  const ClassDetailPage({super.key, this.classId});

  @override
  State<ClassDetailPage> createState() => _ClassDetailPageState();
}

class _ClassDetailPageState extends State<ClassDetailPage> {
  static const _uuid = Uuid();
  static const _minuteOptions = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
  static final List<int> _hour12Values = List<int>.generate(12, (i) => i + 1);
  static const _weekdayLabels = {
    1: '월',
    2: '화',
    3: '수',
    4: '목',
    5: '금',
    6: '토',
    7: '일',
  };
  static const _palette = [
    Color(0xFF4DA3FF),
    Color(0xFF4FCB8D),
    Color(0xFFFF9F5A),
    Color(0xFF9B8CFF),
    Color(0xFFFF8FAB),
    Color(0xFF6FE7D8),
  ];

  final _schoolCtrl = TextEditingController();
  final _customLessonCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final FocusNode _schoolFocus = FocusNode();
  final KoreanSchoolSearchService _schoolSearch = KoreanSchoolSearchService();

  ClassProgramType _programType = ClassProgramType.internalExam;
  String? _grade;

  Timer? _schoolQueryDebounce;
  List<KoreanSchoolHit> _schoolHits = [];
  bool _schoolSearchBusy = false;
  String? _schoolPickStorageKey;
  SchoolSearchTier? _schoolPickTier;
  /// false면 학교는 목록에서 고른 확정 상태(필드 잠금, 다시 검색으로만 변경).
  bool _schoolSearchOpen = true;

  bool _isLoading = true;
  ClassMeta? _classMeta;
  List<_EditableMeetingSlot> _scheduleDrafts = const [];
  int _colorValue = Colors.white.toARGB32();

  @override
  void initState() {
    super.initState();
    _schoolCtrl.addListener(_onSchoolTextChanged);
    _schoolFocus.addListener(_onSchoolFocusChanged);
    unawaited(_schoolSearch.ensureOfflineLoaded());
    _load();
  }

  @override
  void dispose() {
    _schoolQueryDebounce?.cancel();
    _schoolCtrl.removeListener(_onSchoolTextChanged);
    _schoolFocus.removeListener(_onSchoolFocusChanged);
    _schoolSearch.dispose();
    _schoolCtrl.dispose();
    _customLessonCtrl.dispose();
    _noteCtrl.dispose();
    _schoolFocus.dispose();
    super.dispose();
  }

  bool get _isCreateMode => widget.classId == null;

  /// 현재 학교 입력에 맞는 학년 목록(학교 비어 있으면 빈 목록).
  List<String> _gradeChoicesForSchoolInput() {
    final n = _schoolCtrl.text.trim();
    if (n.isEmpty) return const [];
    final tier = resolveTierForInput(
      n,
      lockedTier: _schoolPickTier,
      lockedStorageKey: _schoolPickStorageKey,
      currentText: _schoolCtrl.text,
    );
    return gradesForTier(tier);
  }

  void _onSchoolFocusChanged() {
    if (_schoolFocus.hasFocus) return;
    if (_schoolHits.isNotEmpty || _schoolSearchBusy) {
      setState(() {
        _schoolHits = [];
        _schoolSearchBusy = false;
      });
    }
  }

  void _onSchoolTextChanged() {
    if (_programType != ClassProgramType.internalExam) return;
    if (!_schoolSearchOpen) return;
    var needRebuild = false;
    final trimmed = _schoolCtrl.text.trim();
    if (_schoolPickStorageKey != null && trimmed != _schoolPickStorageKey) {
      _schoolPickStorageKey = null;
      _schoolPickTier = null;
      needRebuild = true;
    }
    final opts = _gradeChoicesForSchoolInput();
    if (_grade != null && !opts.contains(_grade)) {
      final tier = resolveTierForInput(
        trimmed,
        lockedTier: _schoolPickTier,
        lockedStorageKey: _schoolPickStorageKey,
        currentText: _schoolCtrl.text,
      );
      final canon = canonicalGradeForTier(_grade, tier);
      if (canon != null && opts.contains(canon)) {
        setState(() => _grade = canon);
      } else {
        setState(() => _grade = null);
      }
      _scheduleSchoolSearchQuery();
      return;
    }
    if (needRebuild) setState(() {});
    _scheduleSchoolSearchQuery();
  }

  void _scheduleSchoolSearchQuery() {
    _schoolQueryDebounce?.cancel();
    if (_programType != ClassProgramType.internalExam) return;
    if (!_schoolSearchOpen) return;
    _schoolQueryDebounce = Timer(const Duration(milliseconds: 380), () {
      final q = _schoolCtrl.text.trim();
      if (q.length < 2) {
        if (mounted) {
          setState(() {
            _schoolHits = [];
            _schoolSearchBusy = false;
          });
        }
        return;
      }
      _runSchoolSearch(q);
    });
  }

  Future<void> _runSchoolSearch(String query) async {
    if (!mounted) return;
    setState(() => _schoolSearchBusy = true);
    final hits = await _schoolSearch.search(query);
    if (!mounted) return;
    setState(() {
      _schoolSearchBusy = false;
      _schoolHits = hits;
    });
  }

  void _selectSchoolHit(KoreanSchoolHit hit) {
    setState(() {
      _schoolSearchOpen = false;
      _schoolCtrl.text = hit.storageLabel;
      _schoolPickStorageKey = hit.storageLabel;
      _schoolPickTier = hit.tier;
      _schoolHits = [];
      final opts = _gradeChoicesForSchoolInput();
      if (_grade != null && !opts.contains(_grade)) {
        final canon = canonicalGradeForTier(_grade!, hit.tier);
        _grade = (canon != null && opts.contains(canon)) ? canon : null;
      }
    });
    _schoolFocus.unfocus();
  }

  void _beginSchoolReselect() {
    setState(() {
      _schoolSearchOpen = true;
      _schoolPickStorageKey = null;
      _schoolPickTier = null;
      _schoolCtrl.clear();
      _grade = null;
      _schoolHits = [];
      _schoolSearchBusy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _schoolFocus.requestFocus();
    });
  }

  Future<void> _load() async {
    if (_isCreateMode) {
      final draft = _createDraftClassMeta();
      _schoolCtrl.clear();
      _customLessonCtrl.clear();
      _noteCtrl.clear();
      setState(() {
        _classMeta = draft;
        _programType = ClassProgramType.internalExam;
        _grade = null;
        _schoolSearchOpen = true;
        _scheduleDrafts = _draftSchedulesFromMeta(draft);
        _colorValue = draft.colorValue;
        _isLoading = false;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final service = ClassService(prefs: prefs);
    await service.initializeFromMockIfNeeded();
    final item = await service.getClassById(widget.classId!);
    if (!mounted) return;

    if (item == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    _programType = item.programType;
    _schoolCtrl.text = item.schoolName ?? '';
    _grade = item.grade;
    if (item.programType == ClassProgramType.internalExam) {
      final n = _schoolCtrl.text.trim();
      if (n.isNotEmpty) {
        _schoolPickStorageKey = n;
        _schoolPickTier = resolveTierForInput(n);
        if (_grade != null && _schoolPickTier != null) {
          final canon = canonicalGradeForTier(_grade!, _schoolPickTier!);
          if (canon != null) {
            _grade = canon;
          }
          final opts = gradesForTier(_schoolPickTier!);
          if (!opts.contains(_grade)) {
            _grade = null;
          }
        }
      }
    }
    _customLessonCtrl.text = item.customClassName ??
        (item.programType == ClassProgramType.custom ? item.name : '');
    _noteCtrl.text = item.note ?? '';

    final hasSchool =
        item.schoolName != null && item.schoolName!.trim().isNotEmpty;
    setState(() {
      _classMeta = item;
      _schoolSearchOpen = !hasSchool;
      _scheduleDrafts = _draftSchedulesFromMeta(item);
      _colorValue = item.colorValue;
      _isLoading = false;
    });
  }

  ClassMeta _createDraftClassMeta() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ClassMeta(
      id: _uuid.v4(),
      name: '',
      programType: ClassProgramType.internalExam,
      schoolName: null,
      grade: null,
      customClassName: null,
      meetingTime: null,
      weekdays: const [],
      schedules: const [],
      colorValue: Colors.white.toARGB32(),
      note: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<_EditableMeetingSlot> _draftSchedulesFromMeta(ClassMeta meta) {
    final schedules = meta.effectiveSchedules;
    if (schedules.isEmpty) return const [];
    return schedules
        .map(
          (slot) => _EditableMeetingSlot(
            weekday: slot.weekday,
            time: slot.time,
            endTime: slot.endTime,
          ),
        )
        .toList();
  }

  static const int _defaultLessonMinutes = 60;
  static const int _pickerCycles = 500;

  int _todMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _snapMinuteToStep(TimeOfDay t) {
    final best = _minuteOptions.reduce(
      (a, b) =>
          (b - t.minute).abs() < (a - t.minute).abs() ? b : a,
    );
    return TimeOfDay(hour: t.hour, minute: best);
  }

  TimeOfDay _todFrom12({
    required bool isPm,
    required int hour12,
    required int minute,
  }) {
    assert(hour12 >= 1 && hour12 <= 12);
    final h24 = hour12 == 12
        ? (isPm ? 12 : 0)
        : (isPm ? hour12 + 12 : hour12);
    return TimeOfDay(hour: h24, minute: minute);
  }

  ({bool isPm, int hour12}) _to12h(TimeOfDay t) {
    final isPm = t.hour >= 12;
    var h12 = t.hour % 12;
    if (h12 == 0) h12 = 12;
    return (isPm: isPm, hour12: h12);
  }

  String _format24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _addMinutesClampedSameDay(TimeOfDay start, int deltaMinutes) {
    var total = _todMinutes(start) + deltaMinutes;
    total = total.clamp(0, 23 * 60 + 55);
    final snapped = (total ~/ 5) * 5;
    return TimeOfDay(hour: snapped ~/ 60, minute: snapped % 60);
  }

  String _defaultEndFromStartLabel(String startHHmm) {
    final st = _parseMeetingTime(startHHmm);
    if (st == null) return '19:00';
    return _format24(
      _addMinutesClampedSameDay(
        _snapMinuteToStep(st),
        _defaultLessonMinutes,
      ),
    );
  }

  void _bumpSlotEndAfterStartChange(_EditableMeetingSlot slot, String newStart) {
    final st = _parseMeetingTime(newStart);
    if (st == null) return;
    final en = _parseMeetingTime(slot.endTime);
    if (en == null || _todMinutes(en) <= _todMinutes(st)) {
      slot.endTime = _defaultEndFromStartLabel(newStart);
    }
  }

  void _ensureEndsForDrafts() {
    for (final slot in _scheduleDrafts) {
      final s = slot.time?.trim() ?? '';
      if (s.isEmpty) continue;
      final e = slot.endTime?.trim() ?? '';
      if (e.isEmpty) {
        slot.endTime = _defaultEndFromStartLabel(s);
      }
    }
  }

  int _initialInfiniteScrollIndex(int logicalIndex, int cycleLength) {
    final n = cycleLength;
    final total = _pickerCycles * n;
    final mid = total ~/ 2;
    return mid - (mid % n) + logicalIndex;
  }

  /// 다른 슬롯에서 이미 쓰는 요일은 `excludedWeekdays`에 넣습니다. (현재 편집 중인 슬롯의 요일은 제외하지 않음)
  Future<({int weekday, String time, String endTime})?> _pickWeekdayAndTime({
    required Set<int> excludedWeekdays,
    int? initialWeekday,
    String? initialTime,
    String? initialEndTime,
    bool isEditing = false,
  }) async {
    final availableWeekdays = _weekdayLabels.keys
        .where((d) => !excludedWeekdays.contains(d))
        .toList()
      ..sort();
    if (availableWeekdays.isEmpty) return null;

    var selectedWeekday =
        initialWeekday != null && availableWeekdays.contains(initialWeekday)
        ? initialWeekday
        : availableWeekdays.first;

    final startBase = _snapMinuteToStep(
      _parseMeetingTime(initialTime) ?? const TimeOfDay(hour: 18, minute: 0),
    );
    final start12 = _to12h(startBase);
    var startPm = start12.isPm;
    var startH12 = start12.hour12;
    var startMin = startBase.minute;

    final parsedEnd = initialEndTime != null
        ? _parseMeetingTime(initialEndTime)
        : null;
    final endBase = parsedEnd != null
        ? _snapMinuteToStep(parsedEnd)
        : _addMinutesClampedSameDay(startBase, _defaultLessonMinutes);
    final end12 = _to12h(endBase);
    var endPm = end12.isPm;
    var endH12 = end12.hour12;
    var endMin = endBase.minute;

    if (_todMinutes(endBase) <= _todMinutes(startBase)) {
      final bumped = _addMinutesClampedSameDay(startBase, _defaultLessonMinutes);
      final r = _to12h(bumped);
      endPm = r.isPm;
      endH12 = r.hour12;
      endMin = bumped.minute;
    }

    final ampmStartCtrl = FixedExtentScrollController(
      initialItem: startPm ? 1 : 0,
    );
    final hourStartCtrl = FixedExtentScrollController(
      initialItem: _initialInfiniteScrollIndex(startH12 - 1, 12),
    );
    final minStartCtrl = FixedExtentScrollController(
      initialItem: _initialInfiniteScrollIndex(
        _minuteOptions.indexOf(startMin),
        _minuteOptions.length,
      ),
    );
    final ampmEndCtrl = FixedExtentScrollController(
      initialItem: endPm ? 1 : 0,
    );
    final hourEndCtrl = FixedExtentScrollController(
      initialItem: _initialInfiniteScrollIndex(endH12 - 1, 12),
    );
    final minEndCtrl = FixedExtentScrollController(
      initialItem: _initialInfiniteScrollIndex(
        _minuteOptions.indexOf(endMin),
        _minuteOptions.length,
      ),
    );

    var lastStartH12 = startH12;
    var lastEndH12 = endH12;

    void clampEndAfterStart() {
      final st = _todFrom12(
        isPm: startPm,
        hour12: startH12,
        minute: startMin,
      );
      var en = _todFrom12(isPm: endPm, hour12: endH12, minute: endMin);
      if (_todMinutes(en) <= _todMinutes(st)) {
        en = _addMinutesClampedSameDay(st, _defaultLessonMinutes);
        final r = _to12h(en);
        endPm = r.isPm;
        endH12 = r.hour12;
        endMin = en.minute;
        ampmEndCtrl.jumpToItem(endPm ? 1 : 0);
        lastEndH12 = endH12;
        hourEndCtrl.jumpToItem(
          _initialInfiniteScrollIndex(endH12 - 1, 12),
        );
        minEndCtrl.jumpToItem(
          _initialInfiniteScrollIndex(
            _minuteOptions.indexOf(endMin),
            _minuteOptions.length,
          ),
        );
      }
    }

    final picked =
        await showModalBottomSheet<({int weekday, String time, String endTime})>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (sheetContext) {
            return StatefulBuilder(
              builder: (context, setSheetState) {
                Widget timeRow({
                  required String label,
                  required String preview,
                  required FixedExtentScrollController ampmC,
                  required FixedExtentScrollController hourC,
                  required FixedExtentScrollController minC,
                  required void Function(bool isPm) onPm,
                  required void Function(int h12) onH,
                  required void Function(int m) onM,
                  required VoidCallback onAnyChange,
                }) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          Text(
                            preview,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFAFC6FF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 196,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E222B),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: _FiniteAmPmColumn(
                                controller: ampmC,
                                onSelected: (pm) {
                                  setSheetState(() {
                                    onPm(pm);
                                    onAnyChange();
                                  });
                                },
                              ),
                            ),
                            _wheelDivider(),
                            Expanded(
                              flex: 10,
                              child: _InfiniteWheelColumn<int>(
                                controller: hourC,
                                items: _hour12Values,
                                labelOf: (h) => '$h',
                                onSelected: (h) {
                                  setSheetState(() {
                                    onH(h);
                                    onAnyChange();
                                  });
                                },
                              ),
                            ),
                            _wheelDivider(),
                            Expanded(
                              flex: 10,
                              child: _InfiniteWheelColumn<int>(
                                controller: minC,
                                items: _minuteOptions,
                                labelOf: (m) =>
                                    m.toString().padLeft(2, '0'),
                                onSelected: (m) {
                                  setSheetState(() {
                                    onM(m);
                                    onAnyChange();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                final startPreview = _format24(
                  _todFrom12(
                    isPm: startPm,
                    hour12: startH12,
                    minute: startMin,
                  ),
                );
                final endPreview = _format24(
                  _todFrom12(
                    isPm: endPm,
                    hour12: endH12,
                    minute: endMin,
                  ),
                );

                return SafeArea(
                  top: false,
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF171A20),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            isEditing ? '수업 시간 수정' : '수업 시간 추가',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '요일·시작·종료 시간을 선택하세요.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '수업 요일',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableWeekdays.map((wd) {
                              final selected = selectedWeekday == wd;
                              return ChoiceChip(
                                label: Text(
                                  _weekdayLabels[wd]!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? const Color(0xFF10295A)
                                        : Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                selected: selected,
                                selectedColor: const Color(0xFF81A8FF),
                                backgroundColor: const Color(0xFF1E222B),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                                showCheckmark: false,
                                onSelected: (_) {
                                  setSheetState(() => selectedWeekday = wd);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                          timeRow(
                            label: '시작 시간',
                            preview: startPreview,
                            ampmC: ampmStartCtrl,
                            hourC: hourStartCtrl,
                            minC: minStartCtrl,
                            onPm: (b) => startPm = b,
                            onH: (h) {
                              final prev = lastStartH12;
                              if (prev == 12 && h == 1) startPm = !startPm;
                              if (prev == 1 && h == 12) startPm = !startPm;
                              startH12 = h;
                              lastStartH12 = h;
                              ampmStartCtrl.jumpToItem(startPm ? 1 : 0);
                            },
                            onM: (m) => startMin = m,
                            onAnyChange: () {
                              clampEndAfterStart();
                            },
                          ),
                          const SizedBox(height: 18),
                          timeRow(
                            label: '종료 시간',
                            preview: endPreview,
                            ampmC: ampmEndCtrl,
                            hourC: hourEndCtrl,
                            minC: minEndCtrl,
                            onPm: (b) => endPm = b,
                            onH: (h) {
                              final prev = lastEndH12;
                              if (prev == 12 && h == 1) endPm = !endPm;
                              if (prev == 1 && h == 12) endPm = !endPm;
                              endH12 = h;
                              lastEndH12 = h;
                              ampmEndCtrl.jumpToItem(endPm ? 1 : 0);
                            },
                            onM: (m) => endMin = m,
                            onAnyChange: () {},
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetContext),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                    foregroundColor: Colors.white70,
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text('취소'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    final st = _todFrom12(
                                      isPm: startPm,
                                      hour12: startH12,
                                      minute: startMin,
                                    );
                                    final en = _todFrom12(
                                      isPm: endPm,
                                      hour12: endH12,
                                      minute: endMin,
                                    );
                                    if (_todMinutes(en) <= _todMinutes(st)) {
                                      ScaffoldMessenger.of(
                                        sheetContext,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            '종료시간은 시작시간보다 늦어야 합니다.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.pop(
                                      sheetContext,
                                      (
                                        weekday: selectedWeekday,
                                        time: _format24(st),
                                        endTime: _format24(en),
                                      ),
                                    );
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF81A8FF),
                                    foregroundColor: const Color(0xFF10295A),
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text('선택 완료'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );

    ampmStartCtrl.dispose();
    hourStartCtrl.dispose();
    minStartCtrl.dispose();
    ampmEndCtrl.dispose();
    hourEndCtrl.dispose();
    minEndCtrl.dispose();
    return picked;
  }

  Widget _wheelDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 22),
      color: Colors.white.withValues(alpha: 0.06),
    );
  }

  Future<int?> _pickWeekdayOnly({
    required Set<int> excludedWeekdays,
    int? initialWeekday,
  }) async {
    final availableWeekdays = _weekdayLabels.keys
        .where((d) => !excludedWeekdays.contains(d))
        .toList()
      ..sort();
    if (availableWeekdays.isEmpty) return null;
    var selectedWeekday =
        initialWeekday != null && availableWeekdays.contains(initialWeekday)
        ? initialWeekday
        : availableWeekdays.first;

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF171A20),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '수업 요일',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableWeekdays.map((wd) {
                        final selected = selectedWeekday == wd;
                        return ChoiceChip(
                          label: Text(
                            _weekdayLabels[wd]!,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? const Color(0xFF10295A)
                                  : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          selected: selected,
                          selectedColor: const Color(0xFF81A8FF),
                          backgroundColor: const Color(0xFF1E222B),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          showCheckmark: false,
                          onSelected: (_) {
                            setSheetState(() => selectedWeekday = wd);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              foregroundColor: Colors.white70,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.pop(sheetContext, selectedWeekday),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF81A8FF),
                              foregroundColor: const Color(0xFF10295A),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('저장'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return picked;
  }

  /// 공통 iOS 스타일 시간 휠 (오전/오후·12시·5분 단위 분, 시·분만 무한 스크롤).
  Future<String?> _showIosTimePickerBottomSheet({
    required String title,
    TimeOfDay? initial,
    TimeOfDay? mustBeAfter,
  }) async {
    final base = _snapMinuteToStep(
      initial ?? const TimeOfDay(hour: 18, minute: 0),
    );
    final c12 = _to12h(base);
    var isPm = c12.isPm;
    var h12 = c12.hour12;
    var minute = base.minute;
    var lastH12 = h12;

    final ampmCtrl = FixedExtentScrollController(
      initialItem: isPm ? 1 : 0,
    );
    final hourCtrl = FixedExtentScrollController(
      initialItem: _initialInfiniteScrollIndex(h12 - 1, 12),
    );
    final minCtrl = FixedExtentScrollController(
      initialItem: _initialInfiniteScrollIndex(
        _minuteOptions.indexOf(minute),
        _minuteOptions.length,
      ),
    );

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final preview = _format24(
              _todFrom12(isPm: isPm, hour12: h12, minute: minute),
            );
            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF171A20),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        preview,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFAFC6FF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 210,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E222B),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: _FiniteAmPmColumn(
                              controller: ampmCtrl,
                              onSelected: (pm) =>
                                  setSheetState(() => isPm = pm),
                            ),
                          ),
                          _wheelDivider(),
                          Expanded(
                            flex: 10,
                            child: _InfiniteWheelColumn<int>(
                              controller: hourCtrl,
                              items: _hour12Values,
                              labelOf: (h) => '$h',
                              onSelected: (h) => setSheetState(() {
                                final prev = lastH12;
                                if (prev == 12 && h == 1) isPm = !isPm;
                                if (prev == 1 && h == 12) isPm = !isPm;
                                h12 = h;
                                lastH12 = h;
                                ampmCtrl.jumpToItem(isPm ? 1 : 0);
                              }),
                            ),
                          ),
                          _wheelDivider(),
                          Expanded(
                            flex: 10,
                            child: _InfiniteWheelColumn<int>(
                              controller: minCtrl,
                              items: _minuteOptions,
                              labelOf: (m) => m.toString().padLeft(2, '0'),
                              onSelected: (m) =>
                                  setSheetState(() => minute = m),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              foregroundColor: Colors.white70,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final picked = _todFrom12(
                                isPm: isPm,
                                hour12: h12,
                                minute: minute,
                              );
                              if (mustBeAfter != null &&
                                  _todMinutes(picked) <=
                                      _todMinutes(mustBeAfter)) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '종료시간은 시작시간보다 늦어야 합니다.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(sheetContext, _format24(picked));
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF81A8FF),
                              foregroundColor: const Color(0xFF10295A),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('저장'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    ampmCtrl.dispose();
    hourCtrl.dispose();
    minCtrl.dispose();
    return result;
  }

  Future<void> _editScheduleWeekday(int index) async {
    final usedByOthers = _scheduleDrafts
        .asMap()
        .entries
        .where((e) => e.key != index)
        .map((e) => e.value.weekday)
        .whereType<int>()
        .toSet();
    final slot = _scheduleDrafts[index];
    final picked = await _pickWeekdayOnly(
      excludedWeekdays: usedByOthers,
      initialWeekday: slot.weekday,
    );
    if (!mounted || picked == null) return;
    setState(() => slot.weekday = picked);
  }

  static List<Color> get _representativeColorSwatches =>
      [Colors.white, ..._palette];

  Future<void> _pickRepresentativeColor() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ClassRepresentativeColorSheet(
        initialArgb: _colorValue,
        swatches: _representativeColorSwatches,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _colorValue = picked);
  }

  Future<void> _pickSlotStartTime(int index) async {
    final slot = _scheduleDrafts[index];
    if (slot.weekday == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요일을 먼저 선택해 주세요.')),
      );
      return;
    }
    final initial = _parseMeetingTime(slot.time) ??
        const TimeOfDay(hour: 18, minute: 0);
    final t = await _showIosTimePickerBottomSheet(
      title: '시작 시간',
      initial: initial,
    );
    if (!mounted || t == null) return;
    setState(() {
      slot.time = t;
      _bumpSlotEndAfterStartChange(slot, t);
    });
  }

  Future<void> _pickSlotEndTime(int index) async {
    final slot = _scheduleDrafts[index];
    if (slot.weekday == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('요일을 먼저 선택해 주세요.')),
      );
      return;
    }
    final start = _parseMeetingTime(slot.time);
    if (start == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시작 시간을 먼저 선택해 주세요.')),
      );
      return;
    }
    final initialEnd =
        _parseMeetingTime(slot.endTime) ??
        _addMinutesClampedSameDay(start, _defaultLessonMinutes);
    final t = await _showIosTimePickerBottomSheet(
      title: '종료 시간',
      initial: initialEnd,
      mustBeAfter: start,
    );
    if (!mounted || t == null) return;
    setState(() => slot.endTime = t);
  }

  TimeOfDay? _parseMeetingTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String? _validateClassIdentity() {
    if (_programType == ClassProgramType.internalExam) {
      final school = _schoolCtrl.text.trim();
      if (school.isEmpty || _grade == null || _grade!.trim().isEmpty) {
        return '내신 수업은 학교와 학년을 선택해주세요.';
      }
    } else {
      if (_customLessonCtrl.text.trim().isEmpty) {
        return '기타 수업은 수업명을 입력해주세요.';
      }
    }
    return null;
  }

  String? _validateInput() {
    final identityError = _validateClassIdentity();
    if (identityError != null) return identityError;
    if (_scheduleDrafts.isEmpty) {
      return '수업 스케줄을 하나 이상 추가해 주세요.';
    }

    final selectedWeekdays = <int>{};
    _ensureEndsForDrafts();
    for (final slot in _scheduleDrafts) {
      if (slot.weekday == null) {
        return '각 수업 스케줄의 요일을 선택해 주세요.';
      }
      if (selectedWeekdays.contains(slot.weekday)) {
        return '같은 요일은 한 번만 추가해 주세요.';
      }
      if (slot.time == null || slot.time!.trim().isEmpty) {
        return '각 수업 스케줄의 시작 시간을 선택해 주세요.';
      }
      final st = _parseMeetingTime(slot.time);
      final en = _parseMeetingTime(slot.endTime);
      if (st == null || en == null) {
        return '시작·종료 시간 형식을 확인해 주세요.';
      }
      if (_todMinutes(en) <= _todMinutes(st)) {
        return '종료시간은 시작시간보다 늦어야 합니다.';
      }
      selectedWeekdays.add(slot.weekday!);
    }

    return null;
  }

  List<ClassMeetingSlot> _normalizedSchedules() {
    final schedules =
        _scheduleDrafts
            .where((slot) => slot.weekday != null)
            .map(
              (slot) {
                final start = (slot.time ?? '').trim();
                final endRaw = slot.endTime?.trim() ?? '';
                final end = endRaw.isEmpty
                    ? _defaultEndFromStartLabel(start)
                    : endRaw;
                return ClassMeetingSlot(
                  weekday: slot.weekday!,
                  time: start,
                  endTime: end,
                );
              },
            )
            .where((slot) => slot.time.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final weekdayCompare = a.weekday.compareTo(b.weekday);
            if (weekdayCompare != 0) return weekdayCompare;
            return a.time.compareTo(b.time);
          });
    return schedules;
  }

  Future<void> _addScheduleSlot() async {
    if (_scheduleDrafts.length >= _weekdayLabels.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('더 이상 추가할 수 있는 수업 시간이 없습니다.')),
      );
      return;
    }

    final used = _scheduleDrafts
        .map((slot) => slot.weekday)
        .whereType<int>()
        .toSet();
    final picked = await _pickWeekdayAndTime(excludedWeekdays: used);
    if (!mounted || picked == null) return;
    setState(() {
      _scheduleDrafts = [
        ..._scheduleDrafts,
        _EditableMeetingSlot(
          weekday: picked.weekday,
          time: picked.time,
          endTime: picked.endTime,
        ),
      ];
    });
  }

  Future<void> _editScheduleSlot(int index) async {
    final usedByOthers = _scheduleDrafts
        .asMap()
        .entries
        .where((e) => e.key != index)
        .map((e) => e.value.weekday)
        .whereType<int>()
        .toSet();
    final slot = _scheduleDrafts[index];
    final picked = await _pickWeekdayAndTime(
      excludedWeekdays: usedByOthers,
      initialWeekday: slot.weekday,
      initialTime: slot.time,
      initialEndTime: slot.endTime,
      isEditing: true,
    );
    if (!mounted || picked == null) return;
    setState(() {
      slot.weekday = picked.weekday;
      slot.time = picked.time;
      slot.endTime = picked.endTime;
    });
  }

  void _removeScheduleSlot(int index) {
    setState(() {
      _scheduleDrafts = [
        ..._scheduleDrafts.take(index),
        ..._scheduleDrafts.skip(index + 1),
      ];
    });
  }

  Future<void> _save() async {
    final item = _classMeta;
    if (item == null) return;

    final validationMessage = _validateInput();
    if (validationMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }

    final schedules = _normalizedSchedules();
    final weekdays = schedules.map((slot) => slot.weekday).toSet().toList()
      ..sort();
    final primaryMeetingTime = schedules.isEmpty ? null : schedules.first.time;

    final prefs = await SharedPreferences.getInstance();
    final classService = ClassService(prefs: prefs);
    await classService.initializeFromMockIfNeeded();
    final allClasses = await classService.getAllClasses();

    String? schoolName;
    String? grade;
    String? customClassName;
    String baseDisplayName;

    if (_programType == ClassProgramType.internalExam) {
      schoolName = _schoolCtrl.text.trim();
      grade = _grade!.trim();
      customClassName = null;
      baseDisplayName =
          '${shortSchoolDisplayName(schoolName)} $grade'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    } else {
      schoolName = null;
      grade = null;
      customClassName = _customLessonCtrl.text.trim();
      baseDisplayName = customClassName;
    }

    final excludeId = _isCreateMode ? null : item.id;

    var identityUnchanged = false;
    if (!_isCreateMode) {
      if (_programType == ClassProgramType.internalExam &&
          item.programType == ClassProgramType.internalExam) {
        identityUnchanged = item.schoolName?.trim() == schoolName &&
            item.grade?.trim() == grade;
      } else if (_programType == ClassProgramType.custom &&
          item.programType == ClassProgramType.custom) {
        final prevBase = item.customClassName != null &&
                item.customClassName!.trim().isNotEmpty
            ? item.customClassName!.trim()
            : item.name.trim();
        identityUnchanged = prevBase == customClassName;
      }
    }

    var resolvedName =
        (!_isCreateMode && identityUnchanged) ? item.name : baseDisplayName;

    List<ClassMeta> dupes = const [];
    if (_isCreateMode || !identityUnchanged) {
      if (_programType == ClassProgramType.internalExam) {
        dupes = ClassIdentityUtils.findInternalDuplicates(
          all: allClasses,
          schoolName: schoolName!,
          grade: grade!,
          excludeId: excludeId,
        );
      } else {
        dupes = ClassIdentityUtils.findCustomDuplicates(
          all: allClasses,
          baseLessonName: customClassName!,
          excludeId: excludeId,
        );
      }
    }

    if (dupes.isNotEmpty) {
      if (!mounted) return;
      final choice = await _showDuplicateDialog(dupes.first);
      if (!mounted) return;
      if (choice == null) {
        return;
      }
      switch (choice) {
        case _DuplicateResolution.addAnyway:
          final occupied = allClasses.map((e) => e.name.trim()).toSet();
          resolvedName = ClassIdentityUtils.allocateNumberedDisplayName(
            baseDisplayName,
            occupied,
          );
          break;
        case _DuplicateResolution.renameExisting:
          await _renameExistingClass(dupes.first);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('기존 클래스 이름을 변경했습니다.'),
              ),
            );
          }
          return;
      }
    }

    if (_isCreateMode || !identityUnchanged) {
      final nameClash = allClasses.any(
        (entry) => entry.id != item.id && entry.name.trim() == resolvedName,
      );
      if (nameClash && dupes.isEmpty) {
        final occupied = allClasses.map((e) => e.name.trim()).toSet();
        resolvedName = ClassIdentityUtils.allocateNumberedDisplayName(
          resolvedName,
          occupied,
        );
      }
    }

    final updated = item.copyWith(
      name: resolvedName,
      programType: _programType,
      schoolName: schoolName,
      grade: grade,
      customClassName: customClassName,
      meetingTime: primaryMeetingTime,
      weekdays: weekdays,
      schedules: schedules,
      colorValue: _colorValue,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final service = ClassManagementService(prefs: prefs);
    await service.saveClass(
      updated: updated,
      previousName: _isCreateMode ? null : item.name,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isCreateMode ? '반이 추가되었습니다.' : '클래스 정보가 저장되었습니다.'),
      ),
    );
    Navigator.pop(context);
  }

  Future<_DuplicateResolution?> _showDuplicateDialog(ClassMeta existing) {
    return showDialog<_DuplicateResolution>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 36, 0),
          title: Stack(
            clipBehavior: Clip.none,
            children: [
              const Text('클래스 중복'),
              Positioned(
                right: -8,
                top: -8,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(ctx, null),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('동일 클래스가 이미 존재합니다.'),
                const SizedBox(height: 12),
                Text(
                  '기존 클래스:\n${existing.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text('어떻게 처리할까요?'),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.start,
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, _DuplicateResolution.addAnyway),
              child: const Text('새 클래스로 추가'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _DuplicateResolution.renameExisting),
              child: const Text('기존 클래스 이름 변경'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameExistingClass(ClassMeta target) async {
    final schoolCtrl = TextEditingController(text: target.schoolName ?? '');
    final customCtrl = TextEditingController(
      text: target.customClassName?.trim().isNotEmpty == true
          ? target.customClassName!
          : (target.programType == ClassProgramType.custom ? target.name : ''),
    );
    final schoolFocus = FocusNode();
    Timer? schoolQueryDebounce;
    List<KoreanSchoolHit> localSchoolHits = [];
    var localSchoolSearchBusy = false;
    var localSchoolSearchOpen = (target.schoolName?.trim().isEmpty ?? true);
    String? localSchoolPickStorageKey =
        target.schoolName?.trim().isNotEmpty == true
        ? target.schoolName!.trim()
        : null;
    SchoolSearchTier? localSchoolPickTier = target.schoolName == null
        ? null
        : resolveTierForInput(
            target.schoolName!,
            lockedTier: null,
            lockedStorageKey: null,
            currentText: target.schoolName!,
          );
    var localProgramType = target.programType;
    var localGrade = target.grade;
    final initialTier = localSchoolPickTier;
    if (localGrade != null && initialTier != null) {
      localGrade =
          canonicalGradeForTier(localGrade, initialTier) ?? localGrade;
    }

    final draft = await showDialog<_RenameExistingClassDraft>(
      context: context,
      builder: (ctx) {
        final mq = MediaQuery.sizeOf(ctx);
        final dialogWidth = (mq.width * 0.56).clamp(420.0, 860.0);
        return StatefulBuilder(
          builder: (context, setLocalState) {
            void scheduleLocalSchoolSearch() {
              schoolQueryDebounce?.cancel();
              if (localProgramType != ClassProgramType.internalExam) return;
              if (!localSchoolSearchOpen) return;
              schoolQueryDebounce = Timer(const Duration(milliseconds: 380), () async {
                final query = schoolCtrl.text.trim();
                if (query.length < 2) {
                  if (!context.mounted) return;
                  setLocalState(() {
                    localSchoolHits = [];
                    localSchoolSearchBusy = false;
                  });
                  return;
                }
                if (!context.mounted) return;
                setLocalState(() => localSchoolSearchBusy = true);
                final hits = await _schoolSearch.search(query);
                if (!context.mounted) return;
                setLocalState(() {
                  localSchoolSearchBusy = false;
                  localSchoolHits = hits;
                });
              });
            }

            final schoolText = schoolCtrl.text.trim();
            final gradeOptions = schoolText.isEmpty
                ? const <String>[]
                : gradesForTier(
                    resolveTierForInput(
                      schoolText,
                      lockedTier: localSchoolPickTier,
                      lockedStorageKey: localSchoolPickStorageKey,
                      currentText: schoolCtrl.text,
                    ),
                  );
            if (localGrade != null && !gradeOptions.contains(localGrade)) {
              final t = resolveTierForInput(
                schoolText,
                lockedTier: localSchoolPickTier,
                lockedStorageKey: localSchoolPickStorageKey,
                currentText: schoolCtrl.text,
              );
              final canon = canonicalGradeForTier(localGrade, t);
              localGrade =
                  (canon != null && gradeOptions.contains(canon)) ? canon : null;
            }

            return AlertDialog(
              title: const Text('클래스 이름 변경'),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: dialogWidth),
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '수업 유형',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<ClassProgramType>(
                              value: localProgramType,
                              isExpanded: true,
                              isDense: true,
                              items: ClassProgramType.values
                                  .map(
                                    (type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(type.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (next) {
                                if (next == null) return;
                                setLocalState(() {
                                  localProgramType = next;
                                  if (next == ClassProgramType.custom) {
                                    localGrade = null;
                                    localSchoolHits = [];
                                    localSchoolSearchBusy = false;
                                  } else {
                                    localSchoolSearchOpen =
                                        schoolCtrl.text.trim().isEmpty;
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (localProgramType == ClassProgramType.internalExam) ...[
                        Expanded(
                          flex: 58,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (localSchoolSearchOpen) ...[
                                TextField(
                                  controller: schoolCtrl,
                                  focusNode: schoolFocus,
                                  autofocus: true,
                                  onChanged: (_) {
                                    final trimmed = schoolCtrl.text.trim();
                                    if (localSchoolPickStorageKey != null &&
                                        trimmed != localSchoolPickStorageKey) {
                                      localSchoolPickStorageKey = null;
                                      localSchoolPickTier = null;
                                    }
                                    final opts = schoolCtrl.text.trim().isEmpty
                                        ? const <String>[]
                                        : gradesForTier(
                                            resolveTierForInput(
                                              schoolCtrl.text.trim(),
                                              lockedTier: localSchoolPickTier,
                                              lockedStorageKey:
                                                  localSchoolPickStorageKey,
                                              currentText: schoolCtrl.text,
                                            ),
                                          );
                                    if (localGrade != null &&
                                        !opts.contains(localGrade)) {
                                      localGrade = null;
                                    }
                                    setLocalState(() {});
                                    scheduleLocalSchoolSearch();
                                  },
                                  decoration: InputDecoration(
                                    hintText: '학교 검색 (전국)',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    suffixIcon: localSchoolSearchBusy
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  textInputAction: TextInputAction.search,
                                ),
                                if (localSchoolHits.isNotEmpty &&
                                    schoolFocus.hasFocus) ...[
                                  const SizedBox(height: 6),
                                  Material(
                                    elevation: 6,
                                    borderRadius: BorderRadius.circular(8),
                                    clipBehavior: Clip.antiAlias,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 220,
                                      ),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: localSchoolHits.length,
                                        itemBuilder: (ctx2, i) {
                                          final hit = localSchoolHits[i];
                                          return ListTile(
                                            dense: true,
                                            title: Text(
                                              hit.storageLabel,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              hit.subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(
                                                  context,
                                                ).hintColor,
                                              ),
                                            ),
                                            onTap: () {
                                              schoolCtrl.text = hit.storageLabel;
                                              localSchoolPickStorageKey =
                                                  hit.storageLabel;
                                              localSchoolPickTier = hit.tier;
                                              final opts = gradesForTier(hit.tier);
                                              if (localGrade != null &&
                                                  !opts.contains(localGrade)) {
                                                final canon =
                                                    canonicalGradeForTier(
                                                  localGrade,
                                                  hit.tier,
                                                );
                                                localGrade =
                                                    (canon != null &&
                                                            opts.contains(
                                                              canon,
                                                            ))
                                                        ? canon
                                                        : null;
                                              }
                                              setLocalState(() {
                                                localSchoolSearchOpen = false;
                                                localSchoolHits = [];
                                                localSchoolSearchBusy = false;
                                              });
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ] else
                                InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: '학교',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      tooltip: '다시 검색',
                                      icon: const Icon(
                                        Icons.manage_search_rounded,
                                      ),
                                      onPressed: () {
                                        schoolCtrl.clear();
                                        setLocalState(() {
                                          localSchoolPickStorageKey = null;
                                          localSchoolPickTier = null;
                                          localSchoolHits = [];
                                          localSchoolSearchBusy = false;
                                          localSchoolSearchOpen = true;
                                          localGrade = null;
                                        });
                                      },
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        shortSchoolDisplayName(
                                          schoolCtrl.text,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 98,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: '학년',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 12,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: localGrade != null &&
                                        gradeOptions.contains(localGrade)
                                    ? localGrade
                                    : null,
                                isExpanded: true,
                                isDense: true,
                                hint: const Text('선택'),
                                items: gradeOptions
                                    .map(
                                      (grade) => DropdownMenuItem(
                                        value: grade,
                                        child: Text(grade),
                                      ),
                                    )
                                    .toList(),
                                onChanged: gradeOptions.isEmpty
                                    ? null
                                    : (next) =>
                                          setLocalState(() => localGrade = next),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: TextField(
                            controller: customCtrl,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: '수업명',
                              hintText: '수업명 입력',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    if (localProgramType == ClassProgramType.internalExam) {
                      final schoolName = schoolCtrl.text.trim();
                      if (schoolName.isEmpty ||
                          localGrade == null ||
                          localGrade!.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('학교와 학년을 입력해 주세요.')),
                        );
                        return;
                      }
                    } else {
                      if (customCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('수업명을 입력해 주세요.')),
                        );
                        return;
                      }
                    }
                    Navigator.pop(
                      ctx,
                      _RenameExistingClassDraft(
                        programType: localProgramType,
                        schoolName: schoolCtrl.text.trim(),
                        grade: localGrade?.trim(),
                        customClassName: customCtrl.text.trim(),
                      ),
                    );
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
    schoolQueryDebounce?.cancel();
    schoolFocus.dispose();
    schoolCtrl.dispose();
    customCtrl.dispose();
    if (draft == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final classService = ClassService(prefs: prefs);
    await classService.initializeFromMockIfNeeded();
    final allClasses = await classService.getAllClasses();

    String? schoolName;
    String? grade;
    String? customClassName;
    late final String baseDisplayName;
    if (draft.programType == ClassProgramType.internalExam) {
      schoolName = draft.schoolName;
      grade = draft.grade;
      customClassName = null;
      final gr = grade ?? '';
      baseDisplayName =
          '${shortSchoolDisplayName(schoolName)} $gr'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    } else {
      schoolName = null;
      grade = null;
      customClassName = draft.customClassName;
      baseDisplayName = customClassName;
    }

    final occupiedNames = allClasses
        .where((entry) => entry.id != target.id)
        .map((entry) => entry.name.trim())
        .toSet();
    final resolvedName = occupiedNames.contains(baseDisplayName)
        ? ClassIdentityUtils.allocateNumberedDisplayName(
            baseDisplayName,
            occupiedNames,
          )
        : baseDisplayName;

    final service = ClassManagementService(prefs: prefs);
    await service.saveClass(
      updated: target.copyWith(
        name: resolvedName,
        programType: draft.programType,
        schoolName: schoolName,
        grade: grade,
        customClassName: customClassName,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      previousName: target.name,
    );
  }

  Widget _buildClassIdentitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '클래스 이름',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: _programType == ClassProgramType.internalExam ? 22 : 32,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '수업 유형',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ClassProgramType>(
                    value: _programType,
                    isExpanded: true,
                    isDense: true,
                    items: ClassProgramType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _programType = v;
                        if (v == ClassProgramType.custom) {
                          _grade = null;
                          _schoolHits = [];
                          _schoolSearchBusy = false;
                          _schoolPickStorageKey = null;
                          _schoolPickTier = null;
                          _schoolSearchOpen = true;
                        } else {
                          _schoolSearchOpen =
                              _schoolCtrl.text.trim().isEmpty;
                        }
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_programType == ClassProgramType.internalExam) ...[
              Expanded(
                flex: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_schoolSearchOpen) ...[
                      TextField(
                        controller: _schoolCtrl,
                        focusNode: _schoolFocus,
                        decoration: InputDecoration(
                          hintText: '학교 검색 (전국)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _schoolSearchBusy
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        textInputAction: TextInputAction.search,
                      ),
                      if (!KoreanSchoolSearchService.hasConfiguredNeisKey)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '전국 검색: 빌드 시 NEIS_API_KEY(나이스)를 넣거나, assets/data/korean_schools.json 목록을 채워 주세요.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      if (_schoolHits.isNotEmpty && _schoolFocus.hasFocus) ...[
                        const SizedBox(height: 6),
                        Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _schoolHits.length,
                              itemBuilder: (ctx, i) {
                                final hit = _schoolHits[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    hit.storageLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    hit.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                  onTap: () => _selectSchoolHit(hit),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ] else
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: '학교',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: '다시 검색',
                            icon: const Icon(Icons.manage_search_rounded),
                            onPressed: _beginSchoolReselect,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              shortSchoolDisplayName(_schoolCtrl.text),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 22,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '학년',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 12,
                    ),
                  ),
                  child: Builder(
                    builder: (context) {
                      final gradeOpts = _gradeChoicesForSchoolInput();
                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _grade != null &&
                                  gradeOpts.contains(_grade)
                              ? _grade
                              : null,
                          hint: Text(
                            '선택',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                          isExpanded: true,
                          isDense: true,
                          items: gradeOpts
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(g),
                                ),
                              )
                              .toList(),
                          onChanged: gradeOpts.isEmpty
                              ? null
                              : (g) => setState(() => _grade = g),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ] else
              Expanded(
                flex: 68,
                child: TextField(
                  controller: _customLessonCtrl,
                  decoration: const InputDecoration(
                    hintText: '수업명 입력',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_classMeta == null) {
      body = const Center(child: Text('클래스를 찾을 수 없습니다.'));
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildClassIdentitySection(),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '수업 스케줄',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _addScheduleSlot,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('수업시간 추가'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_scheduleDrafts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                '수업시간 추가 버튼을 눌러 요일과 시간을 등록하세요.',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            )
          else
            Column(
              children: List.generate(_scheduleDrafts.length, (index) {
                final slot = _scheduleDrafts[index];
                final hasCore = slot.weekday != null && slot.time != null;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == _scheduleDrafts.length - 1 ? 0 : 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '요일 · 시작 · 종료',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.fromLTRB(12, 10, 8, 10),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ActionChip(
                                label: Text(
                                  slot.weekday == null
                                      ? '요일'
                                      : _weekdayLabels[slot.weekday!]!,
                                ),
                                onPressed: () => _editScheduleWeekday(index),
                              ),
                              ActionChip(
                                label: Text(slot.time ?? '시작'),
                                onPressed: () => _pickSlotStartTime(index),
                              ),
                              ActionChip(
                                label: Text(
                                  (slot.endTime != null &&
                                          slot.endTime!.trim().isNotEmpty)
                                      ? slot.endTime!
                                      : '종료',
                                ),
                                onPressed: () => _pickSlotEndTime(index),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: hasCore
                            ? () => _editScheduleSlot(index)
                            : null,
                        icon: const Icon(Icons.edit_calendar_outlined),
                        tooltip: '요일·시간 한 번에 편집',
                      ),
                      IconButton(
                        onPressed: () => _removeScheduleSlot(index),
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: '스케줄 삭제',
                      ),
                    ],
                  ),
                );
              }),
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '색상 선택',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _pickRepresentativeColor,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(_colorValue),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line, width: 1.2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '메모',
              hintText: '예: 재시 대비반, 숙제 점검 필요',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _save,
            child: Text(_isCreateMode ? '추가' : '저장'),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isCreateMode ? '클래스 추가' : '클래스 수정')),
      body: body,
    );
  }
}

class _ClassRepresentativeColorSheet extends StatefulWidget {
  final int initialArgb;
  final List<Color> swatches;

  const _ClassRepresentativeColorSheet({
    required this.initialArgb,
    required this.swatches,
  });

  @override
  State<_ClassRepresentativeColorSheet> createState() =>
      _ClassRepresentativeColorSheetState();
}

class _ClassRepresentativeColorSheetState
    extends State<_ClassRepresentativeColorSheet> {
  late int _selectedArgb;

  @override
  void initState() {
    super.initState();
    _selectedArgb = widget.initialArgb;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(22, 18, 22, 24 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '색상 선택',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.swatches.map((shade) {
              final isSelected = shade.toARGB32() == _selectedArgb;
              return GestureDetector(
                onTap: () => setState(() => _selectedArgb = shade.toARGB32()),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: shade,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.navy : Colors.white,
                      width: isSelected ? 2.2 : 1.1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selectedArgb),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                '적용',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _kIosWheelSurface = Color(0xFF1E222B);

/// 오전/오후만 고정 2칸 (무한 스크롤 없음).
class _FiniteAmPmColumn extends StatelessWidget {
  final FixedExtentScrollController controller;
  final ValueChanged<bool> onSelected;

  const _FiniteAmPmColumn({
    required this.controller,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CupertinoPicker.builder(
          scrollController: controller,
          itemExtent: 40,
          diameterRatio: 1.35,
          useMagnifier: false,
          selectionOverlay: const SizedBox.shrink(),
          onSelectedItemChanged: (i) => onSelected(i == 1),
          childCount: 2,
          itemBuilder: (context, i) {
            return Center(
              child: Text(
                i == 0 ? '오전' : '오후',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
        IgnorePointer(
          child: Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// iOS 스타일 무한 스크롤 휠 (값은 `index % items.length`).
class _InfiniteWheelColumn<T> extends StatelessWidget {
  static const int _cycles = 500;

  final FixedExtentScrollController controller;
  final List<T> items;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  const _InfiniteWheelColumn({
    required this.controller,
    required this.items,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    final childCount = n * _cycles;
    return Stack(
      alignment: Alignment.center,
      children: [
        CupertinoPicker.builder(
          scrollController: controller,
          itemExtent: 40,
          diameterRatio: 1.18,
          useMagnifier: true,
          magnification: 1.08,
          selectionOverlay: const SizedBox.shrink(),
          onSelectedItemChanged: (i) => onSelected(items[i % n]),
          childCount: childCount,
          itemBuilder: (context, i) {
            final value = items[i % n];
            return Center(
              child: Text(
                labelOf(value),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _kIosWheelSurface.withValues(alpha: 0.92),
                    _kIosWheelSurface.withValues(alpha: 0.0),
                    _kIosWheelSurface.withValues(alpha: 0.0),
                    _kIosWheelSurface.withValues(alpha: 0.92),
                  ],
                  stops: const [0.0, 0.30, 0.70, 1.0],
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableMeetingSlot {
  int? weekday;
  String? time;
  String? endTime;

  _EditableMeetingSlot({this.weekday, this.time, this.endTime});
}
