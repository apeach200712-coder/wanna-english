import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/grade_record_model.dart';
import '../../data/models/homework_models.dart';
import '../../data/models/student_model.dart';
import '../../services/grade_record_service.dart';
import '../../services/homework_page_service.dart';
import '../../theme/app_colors.dart';

const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];

/// 학생 상세 > 숙제 기록: 4주 단위 표 + 주차 네비게이션
class StudentHomeworkHistoryView extends StatefulWidget {
  final Student student;
  final String classDisplayName;

  const StudentHomeworkHistoryView({
    super.key,
    required this.student,
    required this.classDisplayName,
  });

  @override
  State<StudentHomeworkHistoryView> createState() =>
      _StudentHomeworkHistoryViewState();
}

class _StudentHomeworkHistoryViewState extends State<StudentHomeworkHistoryView> {
  final Map<String, _MergedWeekRecord> _byWeekKey = {};
  DateTime _windowEndMonday = _mondayOf(DateTime.now());
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final hw = HomeworkPageService(prefs: prefs);
    final grade = GradeRecordService(prefs: prefs);

    final map = <String, _MergedWeekRecord>{};
    final sid = widget.student.id;

    for (final r in hw.getAllStudentResults()) {
      if (r.studentId != sid) continue;
      final d = DateTime.tryParse(r.weekStartDate);
      if (d == null) continue;
      final m = _mondayOf(d);
      final key = _dateKey(m);
      map[key] = _MergedWeekRecord(weekMonday: m, modern: r);
    }

    final legacy = await grade.getStudentHomework(sid);
    for (final record in legacy) {
      final m = _mondayOf(record.dueDate);
      final key = _dateKey(m);
      if (!map.containsKey(key)) {
        map[key] = _MergedWeekRecord(weekMonday: m, legacy: record);
      }
    }

    for (final entry in hw.getAllHistoryEntries()) {
      final parsed = DateTime.tryParse(entry.date);
      if (parsed == null) continue;
      final m = _mondayOf(parsed);
      final key = _dateKey(m);
      if (map.containsKey(key)) continue;
      HomeworkHistoryStudentResult? hit;
      for (final sr in entry.studentResults) {
        if (sr.studentId == sid) {
          hit = sr;
          break;
        }
      }
      if (hit == null) continue;
      map[key] = _MergedWeekRecord(
        weekMonday: m,
        historyEntry: entry,
        historyStudent: hit,
      );
    }

    if (!mounted) return;
    setState(() {
      _byWeekKey
        ..clear()
        ..addAll(map);
      _loading = false;
    });
  }

  DateTime get _rangeStart => _windowEndMonday.subtract(const Duration(days: 21));
  DateTime get _rangeEnd =>
      _windowEndMonday.add(const Duration(days: 6)); // 일요일

  bool get _canGoNext {
    final thisMonday = _mondayOf(DateTime.now());
    return _windowEndMonday.isBefore(thisMonday);
  }

  void _shiftWindow(int weeksDelta) {
    setState(() {
      _windowEndMonday = _windowEndMonday.add(Duration(days: 7 * weeksDelta));
      final cap = _mondayOf(DateTime.now());
      if (_windowEndMonday.isAfter(cap)) {
        _windowEndMonday = cap;
      }
    });
  }

  List<DateTime> get _fourWeeksNewestFirst {
    return List.generate(
      4,
      (i) => _windowEndMonday.subtract(Duration(days: 7 * i)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final student = widget.student;
    final rangeLabel =
        '${_rangeStart.year}.${_rangeStart.month.toString().padLeft(2, '0')}.${_rangeStart.day.toString().padLeft(2, '0')} ~ ${_rangeEnd.year}.${_rangeEnd.month.toString().padLeft(2, '0')}.${_rangeEnd.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${student.name} · ${widget.classDisplayName}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _shiftWindow(-4),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: '이전 4주',
            ),
            Expanded(
              child: Text(
                '< $rangeLabel >',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            IconButton(
              onPressed: _canGoNext ? () => _shiftWindow(4) : null,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: '다음 4주',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              _TableHeaderRow(),
              const Divider(height: 1, thickness: 1),
              ..._fourWeeksNewestFirst.map(
                (weekMon) => _DataRow(
                  weekMonday: weekMon,
                  record: _byWeekKey[_dateKey(weekMon)],
                  onTapCompletion: (rec) => _openDetail(context, weekMon, rec),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openDetail(
    BuildContext context,
    DateTime weekMonday,
    _MergedWeekRecord? record,
  ) {
    if (record == null || !record.hasRenderableData) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HomeworkWeekDetailSheet(
        weekMonday: weekMonday,
        record: record,
      ),
    );
  }
}

class _MergedWeekRecord {
  final DateTime weekMonday;
  final StudentHomeworkResult? modern;
  final HomeworkRecord? legacy;
  final HomeworkHistoryEntry? historyEntry;
  final HomeworkHistoryStudentResult? historyStudent;

  const _MergedWeekRecord({
    required this.weekMonday,
    this.modern,
    this.legacy,
    this.historyEntry,
    this.historyStudent,
  });

  bool get hasRenderableData {
    if (completionPercent != null) return true;
    final m = modern;
    if (m != null && m.sections.isNotEmpty) return true;
    final leg = legacy;
    if (leg != null && leg.sections.isNotEmpty) return true;
    final he = historyEntry;
    if (he != null && he.sections.isNotEmpty) return true;
    return false;
  }

  int? get completionPercent {
    final m = modern;
    if (m != null && m.isEvaluated) return m.finalCompletionRate;
    if (m != null && m.finalCompletionRate > 0) return m.finalCompletionRate;
    final leg = legacy;
    if (leg != null) return leg.finalCompletionRate;
    final hs = historyStudent;
    if (hs?.finalCompletionRate != null) return hs!.finalCompletionRate;
    return null;
  }

  ResubmissionInfo get resubmission {
    final m = modern;
    if (m != null) return m.resubmission;
    final hs = historyStudent;
    if (hs != null) return hs.resubmission;
    return const ResubmissionInfo();
  }

  List<HomeworkSection> get detailSections {
    final m = modern;
    if (m != null && m.sections.isNotEmpty) return m.sections;
    final leg = legacy;
    if (leg != null && leg.sections.isNotEmpty) return leg.sections;
    final he = historyEntry;
    if (he != null) return he.sections;
    return const [];
  }
}

class _TableHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const cellStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: AppColors.navy,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 26, child: Text('날짜', style: cellStyle)),
          Expanded(flex: 18, child: Text('완성도', style: cellStyle)),
          Expanded(flex: 14, child: Center(child: Text('재제출', style: cellStyle))),
          Expanded(flex: 28, child: Text('확인', style: cellStyle)),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final DateTime weekMonday;
  final _MergedWeekRecord? record;
  final void Function(_MergedWeekRecord) onTapCompletion;

  const _DataRow({
    required this.weekMonday,
    required this.record,
    required this.onTapCompletion,
  });

  @override
  Widget build(BuildContext context) {
    final displayDay = weekMonday.add(const Duration(days: 1)); // 화요일 기준 표시
    final dateStr =
        '${displayDay.month}.${displayDay.day.toString().padLeft(2, '0')} (${_weekdaysKo[displayDay.weekday - 1]})';

    final rec = record;
    final pct = rec?.completionPercent;
    final pctWidget = pct != null && rec != null
        ? GestureDetector(
            onTap: () => onTapCompletion(rec),
            child: Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.blue,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.blue,
              ),
            ),
          )
        : const Text(
            '-',
            style: TextStyle(fontSize: 14, color: AppColors.subText),
          );

    final hasData = rec?.hasRenderableData ?? false;
    final rs = rec?.resubmission ?? const ResubmissionInfo();
    final needsRed = _needsResubmitCircle(rs);
    final resubmitCell = !hasData
        ? const Text('-', style: TextStyle(color: AppColors.subText))
        : Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: needsRed
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
          );

    final confirmText = !hasData ? '-' : _confirmCellText(rs);

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 26,
            child: Text(
              dateStr,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
          Expanded(flex: 18, child: pctWidget),
          Expanded(flex: 14, child: resubmitCell),
          Expanded(
            flex: 28,
            child: Text(
              confirmText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _needsResubmitCircle(ResubmissionInfo rs) {
  switch (rs.status) {
    case ResubmissionStatus.none:
    case ResubmissionStatus.submittedAfterResubmission:
      return false;
    case ResubmissionStatus.resubmissionRequired:
      if (rs.submittedAt != null && rs.submittedAt!.trim().isNotEmpty) {
        return false;
      }
      return true;
  }
}

String _confirmCellText(ResubmissionInfo rs) {
  final now = DateTime.now();
  switch (rs.status) {
    case ResubmissionStatus.none:
      return '-';
    case ResubmissionStatus.submittedAfterResubmission:
      return '○';
    case ResubmissionStatus.resubmissionRequired:
      if (rs.submittedAt != null && rs.submittedAt!.trim().isNotEmpty) {
        return '○';
      }
      final due = _parseDueDateTime(rs.dueDate);
      if (due != null && now.isBefore(due)) {
        return _deadlinePhrase(due, now);
      }
      if (due != null && !now.isBefore(due)) {
        return '기한 지남';
      }
      return '미확인';
  }
}

DateTime? _parseDueDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

String _deadlinePhrase(DateTime due, DateTime now) {
  final sameDay = due.year == now.year &&
      due.month == now.month &&
      due.day == now.day;
  final hasTime = due.hour != 0 || due.minute != 0 || due.second != 0;
  if (sameDay && hasTime) {
    return '제출기한 오늘 ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
  }
  if (sameDay) return '제출기한 오늘';
  if (hasTime) {
    return '제출기한 ${due.month}.${due.day.toString().padLeft(2, '0')} ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
  }
  return '제출기한 ${due.month}.${due.day.toString().padLeft(2, '0')}';
}

class _HomeworkWeekDetailSheet extends StatelessWidget {
  final DateTime weekMonday;
  final _MergedWeekRecord record;

  const _HomeworkWeekDetailSheet({
    required this.weekMonday,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final displayDay = weekMonday.add(const Duration(days: 1));
    final title =
        '${displayDay.month}.${displayDay.day.toString().padLeft(2, '0')} (${_weekdaysKo[displayDay.weekday - 1]}) 숙제 상세';

    final sections = record.detailSections;
    final homeworkLines = <String>[];
    for (final s in sections) {
      final line = _sectionTitleLine(s);
      if (line.isNotEmpty) homeworkLines.add(line);
    }

    final incomplete = <String>[];
    final itemRates = <String>[];
    final hasDotData = record.modern != null || record.legacy != null;

    if (hasDotData) {
      for (final s in record.modern?.sections ?? record.legacy?.sections ?? []) {
        final pct = (s.checkCount / 5 * 100).round();
        final name = s.sectionName.trim();
        if (name.isNotEmpty) {
          itemRates.add('$name $pct%');
        }
        if (s.checkCount < 5) {
          final label = _incompleteLabel(s);
          if (label.isNotEmpty) incomplete.add(label);
        }
      }
    }

    final totalPct = record.completionPercent;
    final rs = record.resubmission;
    final needsRed = _needsResubmitCircle(rs);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.overlay,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 20),
              _detailBlock('이번주 숙제', homeworkLines.isEmpty ? ['-'] : homeworkLines),
              _detailBlock(
                '미완성 부분',
                incomplete.isEmpty ? ['-'] : incomplete,
              ),
              _detailBlock(
                '항목별 완성도',
                itemRates.isEmpty ? ['-'] : itemRates,
              ),
              const SizedBox(height: 8),
              Text(
                '전체 완성도: ${totalPct != null ? '$totalPct%' : '-'}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '재제출 ',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: needsRed
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '재제출 기한: ${_detailDeadline(rs)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
              Text(
                '재제출 확인: ${_detailConfirm(rs)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailBlock(String heading, List<String> lines) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line == '-' ? '-' : '- $line',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: line == '-' ? AppColors.subText : AppColors.navy,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _sectionTitleLine(HomeworkSection s) {
  final name = s.sectionName.trim();
  final sub = s.subSection?.trim();
  final memo = s.detailMemo?.trim();
  final parts = <String>[];
  if (name.isNotEmpty) parts.add(name);
  if (sub != null && sub.isNotEmpty) parts.add(sub);
  if (memo != null && memo.isNotEmpty) parts.add(memo);
  return parts.join(' ');
}

String _incompleteLabel(HomeworkSection section) {
  final subSection = section.subSection?.trim() ?? '';
  final detailMemo = section.detailMemo?.trim() ?? '';
  final value =
      [subSection, detailMemo].where((item) => item.isNotEmpty).join(' ').trim();
  if (value.isNotEmpty) return value;
  return section.sectionName.trim();
}

String _detailDeadline(ResubmissionInfo rs) {
  if (rs.status != ResubmissionStatus.resubmissionRequired) return '-';
  final due = _parseDueDateTime(rs.dueDate);
  if (due == null) return '-';
  return _deadlinePhrase(due, DateTime.now());
}

String _detailConfirm(ResubmissionInfo rs) {
  final t = _confirmCellText(rs);
  if (t == '-') return '-';
  if (t == '○') return '○';
  return t;
}

DateTime _mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String _dateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
