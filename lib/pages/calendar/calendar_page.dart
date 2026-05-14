import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/routes.dart';
import '../../core/responsive.dart';
import '../../data/korean_school_search.dart';
import '../../data/models/calendar_schedule_exception.dart';
import '../../data/models/class_model.dart';
import '../classes/class_detail_page.dart';
import '../../services/calendar_schedule_exception_service.dart';
import '../../services/class_management_service.dart';
import '../../services/class_service.dart';
import '../../services/todo_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/adaptive_scaffold.dart';
import '../../widgets/common/app_top_bar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with TickerProviderStateMixin {
  static const _kst = Duration(hours: 9);

  static const _panelMaxScreenFraction = 0.62;
  static const _panelMinHeight = 172.0;
  static const _pinnedHeaderPx = 80.0;

  /// Must stay in sync with [_DayDetailPanel] + [_DayPanelHeader] layout.
  static const _kPanelBodyBottomPad = 20.0;
  static const _kSectionLabelLineH = 18.0;
  static const _kAfterSectionLabelGap = 10.0;
  static const _kBetweenScheduleAndFav = 22.0;
  static const _kBeforeOpenButtonGap = 14.0;
  static const _kOpenButtonMinH = 52.0;
  static const _kEmptyRowH = 30.0;
  static const _kScheduleSectionHeaderH = 24.0;
  static const _kScheduleRowH = 52.0;
  /// Section title + 2-line task title + paddings (see [_CalendarFavoriteTodoRow]).
  static const _kFavTodoRowH = 88.0;
  static const _kMoreHintBlockH = 22.0;
  /// Cushion for font metrics / rounding vs. real layout.
  static const _kPanelLayoutFudge = 10.0;

  DateTime get _kstNow => DateTime.now().toUtc().add(_kst);

  late final DateTime _today;
  late DateTime _focusedMonth;

  /// When null, the bottom day panel is not shown.
  DateTime? _selectedDate;
  List<ClassDisplayItem> _classItems = const [];
  List<CalendarScheduleException> _calendarExceptions = const [];

  final _todoService = TodoService.instance;
  static const _uuid = Uuid();

  /// Vertical drag offset for closing the day panel (px).
  double _panelDragDy = 0;

  AnimationController? _panelAnim;

  void _onTodoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final now = _kstNow;
    _today = DateTime(now.year, now.month, now.day);
    _focusedMonth = DateTime(_today.year, _today.month);
    _selectedDate = null;
    _todoService.load();
    _todoService.addListener(_onTodoChanged);
    _loadClasses();
  }

  @override
  void dispose() {
    _panelAnim?.dispose();
    _todoService.removeListener(_onTodoChanged);
    super.dispose();
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  double _estimateDayPanelHeight(
    double screenH,
    int scheduleCount,
    int favoriteCount,
  ) {
    const maxPreview = 3;
    final schShown = math.min(maxPreview, scheduleCount);
    final favShown = math.min(maxPreview, favoriteCount);
    final moreSched = scheduleCount > maxPreview;
    final moreFav = favoriteCount > maxPreview;

    double scheduleBlock() {
      var h = _kScheduleSectionHeaderH + _kAfterSectionLabelGap;
      if (scheduleCount == 0) {
        h += _kEmptyRowH;
      } else {
        h += schShown * _kScheduleRowH;
        if (moreSched) h += _kMoreHintBlockH;
      }
      return h;
    }

    double favBlock() {
      var h = _kSectionLabelLineH + _kAfterSectionLabelGap;
      if (favoriteCount == 0) {
        h += _kEmptyRowH;
      } else {
        h += favShown * _kFavTodoRowH;
        if (moreFav) h += _kMoreHintBlockH;
      }
      return h;
    }

    final body =
        scheduleBlock() +
        _kBetweenScheduleAndFav +
        favBlock() +
        _kBeforeOpenButtonGap +
        _kOpenButtonMinH +
        _kPanelBodyBottomPad +
        _kPanelLayoutFudge;

    final raw = _pinnedHeaderPx + body;
    return raw.clamp(_panelMinHeight, screenH * _panelMaxScreenFraction);
  }

  void _closeDaySheet() {
    _panelAnim?.dispose();
    _panelAnim = null;
    setState(() {
      _selectedDate = null;
      _panelDragDy = 0;
    });
  }

  void _snapPanelDragBack() {
    _panelAnim?.dispose();
    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    final start = _panelDragDy;
    _panelAnim!.addListener(() {
      if (!mounted) return;
      setState(() {
        _panelDragDy =
            start * (1.0 - Curves.easeOut.transform(_panelAnim!.value));
      });
    });
    _panelAnim!.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        _panelAnim?.dispose();
        _panelAnim = null;
        if (mounted) setState(() => _panelDragDy = 0);
      }
    });
    _panelAnim!.forward();
  }

  void _animatePanelClose(double panelHeight) {
    _panelAnim?.dispose();
    final start = _panelDragDy;
    final end = panelHeight + 48.0;
    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _panelAnim!.addListener(() {
      if (!mounted) return;
      setState(() {
        _panelDragDy =
            start +
            (end - start) * Curves.easeOutCubic.transform(_panelAnim!.value);
      });
    });
    _panelAnim!.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _panelAnim?.dispose();
        _panelAnim = null;
        if (mounted) {
          setState(() {
            _selectedDate = null;
            _panelDragDy = 0;
          });
        }
      }
    });
    _panelAnim!.forward();
  }

  void _onDaySelected(DateTime day) {
    final current = _selectedDate;
    if (current != null && _isSameDay(current, day)) {
      _closeDaySheet();
      return;
    }
    setState(() {
      _selectedDate = day;
      _panelDragDy = 0;
    });
  }

  Future<void> _loadClasses() async {
    final prefs = await SharedPreferences.getInstance();
    final classManagementService = ClassManagementService(prefs: prefs);
    final classService = ClassService(prefs: prefs);
    await classManagementService.ensureClassMetaForStudentNames();
    await classService.initializeFromMockIfNeeded();
    final items = await classService.getDisplayItems();
    final exceptions =
        await CalendarScheduleExceptionService(prefs).loadAll();
    if (!mounted) return;
    setState(() {
      _classItems = items;
      _calendarExceptions = exceptions;
    });
  }

  Future<void> _reloadCalendarExceptions() async {
    final prefs = await SharedPreferences.getInstance();
    final exceptions =
        await CalendarScheduleExceptionService(prefs).loadAll();
    if (!mounted) return;
    setState(() => _calendarExceptions = exceptions);
  }

  String _regularSlotId(String classId, ClassMeetingSlot slot) {
    final t = CalendarScheduleException.coerceStoredTime(slot.time);
    final rawEnd = slot.endTime?.trim();
    final end = (rawEnd != null && rawEnd.isNotEmpty)
        ? CalendarScheduleException.coerceStoredTime(rawEnd)
        : '';
    return '${classId}_${slot.weekday}_${t}_$end';
  }

  /// `yyyy-MM-dd` (로컬 달력 날짜). 예외 저장·조회 키로 사용.
  static String dateKeyForSelectedDay(DateTime day) =>
      CalendarScheduleExceptionService.dateKeyOf(day);

  String _calendarNameForClassId(String classId) {
    for (final item in _classItems) {
      if (item.id == classId) return _calendarRowDisplayName(item);
    }
    return '삭제된 클래스';
  }

  /// 이 날짜에 휴강 예외만 있고 목록에서는 숨겨진 항목 — 되돌리기 UI용.
  List<CalendarScheduleException> _hiddenCancelledExceptionsForDay(
    DateTime day,
  ) {
    final key = dateKeyForSelectedDay(day);
    final list = _calendarExceptions
        .where(
          (e) =>
              e.dateKey == key &&
              e.type == CalendarScheduleExceptionType.cancelled &&
              (e.sourceScheduleId ?? '').isNotEmpty,
        )
        .toList()
      ..sort((a, b) => _parseHm(a.startTime).compareTo(_parseHm(b.startTime)));
    return list;
  }

  /// Calendar 수업 row 전용 표시명. 다른 화면은 짧은 [ClassDisplayItem.displayName]
  /// (예: "숙명여고 2학년")을 유지하지만, 캘린더 row 는 가로폭이 넓어 빈자리가
  /// 어색하므로 풀네임 + "N학년"으로 길게 보여준다.
  ///
  /// 예: `숙명여자고등학교 (서울특별시) 2학년`, `상산고등학교 (전라북도) 2학년`.
  /// 내신이 아닌(custom) 클래스는 풀네임 개념이 없으므로 기존 displayName 으로
  /// 폴백한다.
  static String _calendarRowDisplayName(ClassDisplayItem item) {
    final meta = item.meta;
    if (meta.programType == ClassProgramType.internalExam) {
      final school = (meta.schoolName ?? '').trim();
      final grade = gradeDisplayLabel(meta.grade);
      if (school.isNotEmpty || grade.isNotEmpty) {
        return [school, grade]
            .where((s) => s.isNotEmpty)
            .join(' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
    }
    return item.displayName;
  }

  List<CalendarDaySchedule> _calendarDaySchedulesForDay(DateTime day) {
    final key = dateKeyForSelectedDay(day);
    final dayEx =
        _calendarExceptions.where((e) => e.dateKey == key).toList();

    final cancelledBySource = <String, CalendarScheduleException>{};
    for (final e in dayEx) {
      if (e.type == CalendarScheduleExceptionType.cancelled &&
          (e.sourceScheduleId ?? '').isNotEmpty) {
        final raw = e.sourceScheduleId!.trim();
        cancelledBySource[raw] = e;
        final canon =
            CalendarScheduleException.canonicalizeScheduleSlotId(raw);
        if (canon != null && canon != raw) {
          cancelledBySource[canon] = e;
        }
      }
    }

    final rows = <CalendarDaySchedule>[];

    for (final item in _classItems) {
      for (final slot in item.meta.effectiveSchedules) {
        if (slot.weekday != day.weekday) continue;
        final sid = _regularSlotId(item.id, slot);
        final start = CalendarScheduleException.coerceStoredTime(slot.time);
        final endRaw = slot.endTime?.trim();
        final end = (endRaw != null && endRaw.isNotEmpty)
            ? CalendarScheduleException.coerceStoredTime(endRaw)
            : start;
        final timeLabel = slot.timeRangeLabel;
        final cancel = cancelledBySource[sid];
        final rowName = _calendarRowDisplayName(item);
        if (cancel != null) {
          // 원본 반복 수업은 유지하고, 이 날짜에만 목록에서 제외 (저장은 cancelled 예외).
          continue;
        }
        rows.add(
          CalendarDaySchedule(
            scheduleId: sid,
            classId: item.id,
            name: rowName,
            color: item.meta.color,
            timeLabel: timeLabel,
            startTime: start,
            endTime: end,
          ),
        );
      }
    }

    for (final e in dayEx) {
      if (e.type != CalendarScheduleExceptionType.extra &&
          e.type != CalendarScheduleExceptionType.makeup) {
        continue;
      }
      ClassDisplayItem? match;
      for (final item in _classItems) {
        if (item.id == e.classId) {
          match = item;
          break;
        }
      }
      final name = match == null
          ? '삭제된 클래스'
          : _calendarRowDisplayName(match);
      final color = match?.meta.color ?? const Color(0xFF9E9E9E);
      rows.add(
        CalendarDaySchedule(
          scheduleId: e.id,
          classId: e.classId,
          name: name,
          color: color,
          timeLabel: _calendarTimeRangeLabel(e.startTime, e.endTime),
          startTime: e.startTime,
          endTime: e.endTime,
          isExtra: e.type == CalendarScheduleExceptionType.extra,
          isMakeup: e.type == CalendarScheduleExceptionType.makeup,
          supplementalExceptionId: e.id,
        ),
      );
    }

    rows.sort(
      (a, b) => _calendarStartMinutes(a).compareTo(_calendarStartMinutes(b)),
    );
    return rows;
  }

  static String _calendarTimeRangeLabel(String start, String end) {
    final s = start.trim();
    final t = end.trim();
    if (t.isEmpty || s == t) return s;
    return '$s–$t';
  }

  static int _calendarStartMinutes(CalendarDaySchedule r) {
    final parts = r.startTime.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  static int _parseHm(String t) {
    final parts = t.trim().split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  Future<void> _handleHolidayTap(
    BuildContext context,
    DateTime day,
    CalendarDaySchedule row,
  ) async {
    final isSupplemental = row.supplementalExceptionId != null;

    final bool? ok;
    if (isSupplemental) {
      final msg = row.isMakeup
          ? '이 보충 수업을 취소할까요?'
          : '이 추가 수업을 취소할까요?';
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('일회 수업'),
          content: Text(msg),
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
      );
    } else {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('휴강'),
          content: const Text('이 날짜의 수업을 휴강 처리할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('휴강'),
            ),
          ],
        ),
      );
    }
    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final svc = CalendarScheduleExceptionService(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (isSupplemental) {
      await svc.remove(row.supplementalExceptionId!);
    } else {
      final slotId =
          CalendarScheduleException.canonicalizeScheduleSlotId(row.scheduleId) ??
          row.scheduleId.trim();
      final ex = CalendarScheduleException(
        id: _uuid.v4(),
        dateKey: dateKeyForSelectedDay(day),
        classId: row.classId.trim(),
        startTime: CalendarScheduleException.coerceStoredTime(row.startTime),
        endTime: CalendarScheduleException.coerceStoredTime(row.endTime),
        type: CalendarScheduleExceptionType.cancelled,
        sourceScheduleId: slotId,
        createdAt: now,
        updatedAt: now,
      );
      if (!ex.isValidForStorage) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('휴강 정보를 저장할 수 없어요. 시간 형식을 확인해 주세요.')),
          );
        }
        return;
      }
      await svc.addCancelledDedup(ex);
    }
    if (!mounted) return;
    await _reloadCalendarExceptions();
  }

  Future<void> _handleHolidayUndo(CalendarDaySchedule row) async {
    final id = row.cancelledByExceptionId;
    if (id == null) return;
    await _undoCancelledExceptionById(id);
  }

  Future<void> _undoCancelledExceptionById(String exceptionId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await CalendarScheduleExceptionService(prefs).remove(exceptionId);
    if (!mounted) return;
    await _reloadCalendarExceptions();
  }

  Future<void> _submitOneOffLesson({
    required BuildContext sheetContext,
    required DateTime selectedDay,
    required String classId,
    required String startTime,
    required String endTime,
    required CalendarScheduleExceptionType type,
  }) async {
    if (_parseHm(endTime) <= _parseHm(startTime)) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(content: Text('종료 시간은 시작 시간보다 늦어야 해요.')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!sheetContext.mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final st = CalendarScheduleException.coerceStoredTime(startTime);
    final en = CalendarScheduleException.coerceStoredTime(endTime);
    final ex = CalendarScheduleException(
      id: _uuid.v4(),
      dateKey: dateKeyForSelectedDay(selectedDay),
      classId: classId.trim(),
      startTime: st,
      endTime: en,
      type: type,
      createdAt: now,
      updatedAt: now,
    );
    if (!ex.isValidForStorage) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(content: Text('추가 수업 정보를 저장할 수 없어요. 시간을 다시 확인해 주세요.')),
      );
      return;
    }
    await CalendarScheduleExceptionService(prefs).addOrReplace(ex);
    if (!mounted) return;
    await _reloadCalendarExceptions();
    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
    }
  }

  void _openAddLessonSheet(BuildContext context, DateTime selectedDay) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _AddOneOffLessonSheet(
          classes: _classItems,
          onSubmit: (classId, start, end, type) => _submitOneOffLesson(
            sheetContext: ctx,
            selectedDay: selectedDay,
            classId: classId,
            startTime: start,
            endTime: end,
            type: type,
          ),
        ),
      ),
    );
  }

  void _prevMonth() {
    final m = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    _panelAnim?.dispose();
    _panelAnim = null;
    setState(() {
      _focusedMonth = m;
      _selectedDate = null;
      _panelDragDy = 0;
    });
  }

  void _nextMonth() {
    final m = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    _panelAnim?.dispose();
    _panelAnim = null;
    setState(() {
      _focusedMonth = m;
      _selectedDate = null;
      _panelDragDy = 0;
    });
  }

  Widget _calendarColumn({
    required double hPad,
    required bool includeBottomSpacer,
    required void Function(DateTime day) onDayTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
          child: const AppTopBar(showActionIcons: false),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: _MonthHeader(
            month: _focusedMonth,
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: const _WeekdayLabels(),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: _CalendarGrid(
            focusedMonth: _focusedMonth,
            today: _today,
            selectedDay: _selectedDate,
            schedulesForDay: _calendarDaySchedulesForDay,
            onDayTap: onDayTap,
          ),
        ),
        if (includeBottomSpacer) const Spacer(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPadding(context);
    final maxW = Responsive.maxContentWidth(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final H = constraints.maxHeight;
              final hasSheet = _selectedDate != null;

              Widget calendarBlock({
                required bool scroll,
                required bool spacer,
              }) {
                final col = _calendarColumn(
                  hPad: hPad,
                  includeBottomSpacer: spacer,
                  onDayTap: _onDaySelected,
                );
                if (!scroll) return col;
                return ClipRect(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: col,
                  ),
                );
              }

              if (!hasSheet) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: calendarBlock(scroll: false, spacer: true),
                    ),
                  ],
                );
              }

              final day = _selectedDate!;
              final schedules = _calendarDaySchedulesForDay(day);
              final hiddenCancelled = _hiddenCancelledExceptionsForDay(day);
              final favorites = _todoService.favoritePreviewItemsForDate(day);
              final layoutScheduleCount =
                  schedules.length +
                  (hiddenCancelled.isEmpty
                      ? 0
                      : 1 + hiddenCancelled.length.clamp(0, 6));
              final panelH = _estimateDayPanelHeight(
                H,
                layoutScheduleCount,
                favorites.length,
              );
              // As the sheet moves down by `_panelDragDy`, grow the calendar so
              // rows behind the sheet are revealed (no fixed "dead" band).
              final reveal = math.min(_panelDragDy, panelH);
              final maxCalH = (H - bottomInset).clamp(120.0, H);
              final calendarH =
                  (H - panelH - bottomInset + reveal).clamp(120.0, maxCalH);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: calendarH,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _animatePanelClose(panelH),
                      child: ClipRect(
                        child: calendarBlock(scroll: true, spacer: false),
                      ),
                    ),
                  ),
                  Positioned(
                    left: hPad,
                    right: hPad,
                    bottom: bottomInset - _panelDragDy,
                    height: panelH,
                    child: GestureDetector(
                      behavior: HitTestBehavior.deferToChild,
                      onVerticalDragUpdate: (d) {
                        setState(() {
                          final maxDy = panelH + 56.0;
                          _panelDragDy =
                              (_panelDragDy + d.delta.dy).clamp(0.0, maxDy);
                        });
                      },
                      onVerticalDragEnd: (d) {
                        final v = d.velocity.pixelsPerSecond.dy;
                        // ~24–40px downward drag closes; fast downward fling too.
                        if (_panelDragDy > 34 || v > 520) {
                          _animatePanelClose(panelH);
                        } else if (_panelDragDy > 0) {
                          _snapPanelDragBack();
                        }
                      },
                      child: _DayDetailPanel(
                        day: day,
                        today: _today,
                        schedules: schedules,
                        hiddenCancelledExceptions: hiddenCancelled,
                        calendarNameForClassId: _calendarNameForClassId,
                        onUndoHiddenCancel: _undoCancelledExceptionById,
                        favoriteTodos: favorites,
                        hPad: hPad,
                        headerHeight: _pinnedHeaderPx,
                        onOpenTodo: () {
                          final targetDay = TodoService.calendarDayOnly(day);
                          Navigator.pushNamed(
                            context,
                            AppRoutes.todo,
                            arguments: targetDay,
                          );
                        },
                        onAddScheduleTap: () =>
                            _openAddLessonSheet(context, day),
                        onHolidayTap: (row) =>
                            _handleHolidayTap(context, day, row),
                        onHolidayUndoTap: (row) => _handleHolidayUndo(row),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    return AdaptiveScaffold(currentIndex: 2, body: body);
  }
}

// ── Month header ──────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '${month.year}년 ${month.month}월',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const Spacer(),
        _ArrowBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
        const SizedBox(width: 6),
        _ArrowBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
      ],
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.graySoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 22, color: AppColors.navy),
      ),
    );
  }
}

// ── Weekday labels ────────────────────────────────────────────────────────────

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  static const _labels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _labels
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Center(
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: e.key == 0
                        ? const Color(0xFFFF6B6B)
                        : e.key == 6
                        ? AppColors.blue
                        : AppColors.subText,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Calendar grid ─────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime today;
  final DateTime? selectedDay;
  final List<CalendarDaySchedule> Function(DateTime) schedulesForDay;
  final ValueChanged<DateTime> onDayTap;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.today,
    required this.selectedDay,
    required this.schedulesForDay,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    // Sunday-first offset: Sun(7)→0, Mon(1)→1 … Sat(6)→6
    final startOffset = firstDay.weekday % 7;
    final daysInMonth = DateTime(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    ).day;
    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.0,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        late final DateTime day;
        var isOtherMonth = false;

        if (index < startOffset) {
          final prevMonthEnd = DateTime(focusedMonth.year, focusedMonth.month, 0);
          final dInPrev = prevMonthEnd.day - startOffset + index + 1;
          day = DateTime(prevMonthEnd.year, prevMonthEnd.month, dInPrev);
          isOtherMonth = true;
        } else {
          final mDay = index - startOffset + 1;
          if (mDay <= daysInMonth) {
            day = DateTime(focusedMonth.year, focusedMonth.month, mDay);
          } else {
            final intoNext = mDay - daysInMonth;
            day = DateTime(focusedMonth.year, focusedMonth.month + 1, intoNext);
            isOtherMonth = true;
          }
        }

        final sel = selectedDay;
        final isSel =
            sel != null &&
            day.year == sel.year &&
            day.month == sel.month &&
            day.day == sel.day;
        final isToday =
            day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;
        final colIndex = index % 7; // 0=Sun, 6=Sat

        return GestureDetector(
          onTap: () => onDayTap(day),
          child: _DayCell(
            day: day.day,
            isSelected: isSel,
            isToday: isToday,
            isOtherMonth: isOtherMonth,
            schedules: schedulesForDay(day),
            isSunday: colIndex == 0,
            isSaturday: colIndex == 6,
          ),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isSelected;
  final bool isToday;
  final bool isOtherMonth;
  final List<CalendarDaySchedule> schedules;
  final bool isSunday;
  final bool isSaturday;

  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isOtherMonth,
    required this.schedules,
    required this.isSunday,
    required this.isSaturday,
  });

  @override
  Widget build(BuildContext context) {
    Color numColor;
    if (isSelected) {
      numColor = Colors.white;
    } else if (isSunday) {
      numColor = const Color(0xFFFF6B6B);
    } else if (isSaturday) {
      numColor = AppColors.blue;
    } else {
      numColor = AppColors.navy;
    }

    final fadeAdjacent =
        isOtherMonth && !isSelected && !isToday;

    Widget cell = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.blue
                : isToday
                ? AppColors.blueSoft
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected || isToday
                  ? FontWeight.w800
                  : FontWeight.w500,
              color: numColor,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: schedules
              .where((s) => !s.isCancelled)
              .take(3)
              .map(
                (s) => Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: s.color,
                    shape: BoxShape.circle,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );

    if (fadeAdjacent) {
      cell = Opacity(opacity: 0.48, child: cell);
    }
    return cell;
  }
}

// ── Day detail panel (content-height card, no DraggableScrollableSheet) ─────

class _DayPanelHeader extends StatelessWidget {
  final double hPad;
  final String label;
  final bool isToday;

  const _DayPanelHeader({
    required this.hPad,
    required this.label,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.subText.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.graySoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Text(
                    '오늘',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.blue,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDetailPanel extends StatelessWidget {
  final DateTime day;
  final DateTime today;
  final List<CalendarDaySchedule> schedules;
  final List<CalendarScheduleException> hiddenCancelledExceptions;
  final String Function(String classId) calendarNameForClassId;
  final Future<void> Function(String exceptionId) onUndoHiddenCancel;
  final List<TodoPreviewItem> favoriteTodos;
  final double hPad;
  final double headerHeight;
  final VoidCallback onOpenTodo;
  final VoidCallback onAddScheduleTap;
  final Future<void> Function(CalendarDaySchedule row) onHolidayTap;
  final Future<void> Function(CalendarDaySchedule row) onHolidayUndoTap;

  const _DayDetailPanel({
    required this.day,
    required this.today,
    required this.schedules,
    required this.hiddenCancelledExceptions,
    required this.calendarNameForClassId,
    required this.onUndoHiddenCancel,
    required this.favoriteTodos,
    required this.hPad,
    required this.headerHeight,
    required this.onOpenTodo,
    required this.onAddScheduleTap,
    required this.onHolidayTap,
    required this.onHolidayUndoTap,
  });

  static const _weekLabels = ['', '월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final label = '${day.month}월 ${day.day}일 (${_weekLabels[day.weekday]})';
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;

    const maxPreview = 3;
    final schShown = schedules.take(maxPreview).toList();
    final favShown = favoriteTodos.take(maxPreview).toList();
    final moreSched = math.max(0, schedules.length - maxPreview);
    final moreFav = math.max(0, favoriteTodos.length - maxPreview);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: const Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          SizedBox(
            height: headerHeight,
            child: _DayPanelHeader(hPad: hPad, label: label, isToday: isToday),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Text(
                            '수업 스케줄',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.subText,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onAddScheduleTap,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('추가'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.blue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (schedules.isEmpty)
                      const _EmptyRow(
                        text: '수업 없는 날',
                        icon: Icons.free_breakfast_outlined,
                      )
                    else
                      ...schShown.map(
                        (s) => _ScheduleRow(
                          day: day,
                          schedule: s,
                          onHolidayTap: () => onHolidayTap(s),
                          onHolidayUndoTap: () => onHolidayUndoTap(s),
                        ),
                      ),
                    if (hiddenCancelledExceptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '이 날 휴강 처리된 수업',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.subText.withValues(alpha: 0.85),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...hiddenCancelledExceptions.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  '${calendarNameForClassId(e.classId)} · ${_CalendarPageState._calendarTimeRangeLabel(e.startTime, e.endTime)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.subText,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  onUndoHiddenCancel(e.id);
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '되돌리기',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (moreSched > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '외 $moreSched개 수업이 더 있어요',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.subText.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    const _SectionLabel(text: '즐겨찾기 To-Do'),
                    const SizedBox(height: 10),
                    if (favoriteTodos.isEmpty)
                      const _EmptyRow(
                        text: '즐겨찾기한 To-Do가 없습니다',
                        icon: Icons.star_outline_rounded,
                      )
                    else
                      ...favShown.map(
                        (item) => _CalendarFavoriteTodoRow(item: item),
                      ),
                    if (moreFav > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '외 $moreFav개 더 있어요',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.subText.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: onOpenTodo,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 18,
                              color: AppColors.blue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '해당 날짜 열기',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarFavoriteTodoRow extends StatelessWidget {
  final TodoPreviewItem item;

  const _CalendarFavoriteTodoRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final t = item.task;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(Icons.star_rounded, size: 16, color: item.sectionColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.sectionTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: item.sectionColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.isDone ? AppColors.subText : AppColors.navy,
                      decoration: t.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.subText,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String text;
  final IconData icon;

  const _EmptyRow({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.subText),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.subText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final DateTime day;
  final CalendarDaySchedule schedule;
  final Future<void> Function() onHolidayTap;
  final Future<void> Function() onHolidayUndoTap;

  const _ScheduleRow({
    required this.day,
    required this.schedule,
    required this.onHolidayTap,
    required this.onHolidayUndoTap,
  });

  @override
  Widget build(BuildContext context) {
    final focusDay = TodoService.calendarDayOnly(day);
    final s = schedule;

    void openHomework() {
      Navigator.pushNamed(
        context,
        AppRoutes.homework,
        arguments: {
          'classId': s.classId,
          'classDisplayName': s.name,
          'focusDate': focusDay,
        },
      );
    }

    void openGrades() {
      Navigator.pushNamed(
        context,
        AppRoutes.gradeInput,
        arguments: {
          'classId': s.classId,
          'className': s.name,
          'focusDate': focusDay,
        },
      );
    }

    void openClass() {
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ClassDetailPage(classId: s.classId),
        ),
      );
    }

    Widget? badge;
    if (s.isCancelled) {
      badge = _MiniBadge(text: '휴강', color: AppColors.subText);
    } else if (s.isMakeup) {
      badge = _MiniBadge(text: '보충', color: AppColors.blue);
    } else if (s.isExtra) {
      badge = _MiniBadge(text: '추가', color: AppColors.blue);
    }

    final timeStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: s.isCancelled ? AppColors.subText : AppColors.navy,
    );

    final nameStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: s.isCancelled ? AppColors.subText : AppColors.blue,
    );

    final Widget classLabel = s.isCancelled
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nameStyle,
            ),
          )
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: openClass,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle,
                ),
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: s.isCancelled ? AppColors.subText : s.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 94,
              child: Text(
                s.timeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: timeStyle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: classLabel,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 4),
                    badge,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (s.isCancelled)
              _CalendarLinkPill(
                label: '휴강 취소',
                onTap: () => onHolidayUndoTap(),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CalendarLinkPill(label: '숙제 확인', onTap: openHomework),
                  const SizedBox(width: 4),
                  _CalendarLinkPill(label: '성적 확인', onTap: openGrades),
                  const SizedBox(width: 4),
                  _CalendarMutedPill(
                    label:
                        s.supplementalExceptionId != null ? '취소' : '휴강',
                    onTap: () => onHolidayTap(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _AddOneOffLessonSheet extends StatefulWidget {
  final List<ClassDisplayItem> classes;
  final Future<void> Function(
    String classId,
    String startTime,
    String endTime,
    CalendarScheduleExceptionType type,
  ) onSubmit;

  const _AddOneOffLessonSheet({
    required this.classes,
    required this.onSubmit,
  });

  @override
  State<_AddOneOffLessonSheet> createState() => _AddOneOffLessonSheetState();
}

class _AddOneOffLessonSheetState extends State<_AddOneOffLessonSheet> {
  String? _selectedClassId;
  TimeOfDay _start = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 19, minute: 0);
  CalendarScheduleExceptionType _type = CalendarScheduleExceptionType.extra;
  bool _submitting = false;

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    if (widget.classes.isNotEmpty) {
      _selectedClassId = widget.classes.first.id;
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    final id = _selectedClassId;
    if (id == null || id.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(id, _fmt(_start), _fmt(_end), _type);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.subText.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const Text(
              '일회 수업 추가',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '선택한 날짜에만 반영되며 정규 스케줄은 바뀌지 않아요.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.subText.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.classes.isEmpty)
              const Text(
                '등록된 클래스가 없습니다. 설정에서 클래스를 먼저 추가해 주세요.',
                style: TextStyle(fontSize: 14, color: AppColors.subText),
              )
            else ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '클래스',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedClassId,
                    hint: const Text('선택'),
                    items: widget.classes
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Text(
                              c.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedClassId = v),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(isStart: true),
                      child: Text('시작 ${_fmt(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(isStart: false),
                      child: Text('종료 ${_fmt(_end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<CalendarScheduleExceptionType>(
                segments: const [
                  ButtonSegment(
                    value: CalendarScheduleExceptionType.extra,
                    label: Text('추가'),
                  ),
                  ButtonSegment(
                    value: CalendarScheduleExceptionType.makeup,
                    label: Text('보충'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (next) {
                  setState(() => _type = next.first);
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalendarMutedPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CalendarMutedPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.subText,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLinkPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CalendarLinkPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.graySoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.blue,
            ),
          ),
        ),
      ),
    );
  }
}
