import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/exam_score_model.dart';
import '../../data/models/grade_record_model.dart';
import '../../data/models/student_grade_model.dart';
import '../../data/models/student_model.dart';
import '../../services/exam_session_service.dart';
import '../../services/grade_record_service.dart';
import '../../services/grade_service.dart';
import '../../services/student_detail_service.dart';
import '../../theme/app_colors.dart';

const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];

/// 학생 상세 > 시험 기록: 상단 표 + 기간·체크박스 + 통합 선그래프
class StudentExamHistoryView extends StatefulWidget {
  final Student student;
  final String classDisplayName;

  const StudentExamHistoryView({
    super.key,
    required this.student,
    required this.classDisplayName,
  });

  @override
  State<StudentExamHistoryView> createState() => _StudentExamHistoryViewState();
}

enum _ExamGraphPeriod {
  last4Weeks('지난 4주'),
  thisSemester('이번 학기'),
  thisYear('올해');

  final String label;
  const _ExamGraphPeriod(this.label);
}

class _StudentExamHistoryViewState extends State<StudentExamHistoryView> {
  List<_ExamTableRow> _rows = const [];
  List<_ExamPlotEvent> _plotEvents = const [];
  bool _loading = true;

  _ExamGraphPeriod _period = _ExamGraphPeriod.last4Weeks;
  final Set<StudentExamFocus> _visibleFocus = {
    StudentExamFocus.vocabulary,
    StudentExamFocus.reviewTest,
    StudentExamFocus.regularExam,
    StudentExamFocus.internalExam,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final examSvc = ExamSessionService(prefs: prefs);
    final gradeRec = GradeRecordService(prefs: prefs);
    final gradeSvc = GradeService(prefs: prefs);
    final snapshot = await gradeRec.getSnapshot();
    final st = widget.student;

    final rows = <_ExamTableRow>[];
    final plotEvents = <_ExamPlotEvent>[];
    final sessionDays = <String>{};

    final sessions = examSvc.getAllSessions().where((s) {
      return _sessionMatchesClass(s, st);
    }).toList()
      ..sort((a, b) => b.examDate.compareTo(a.examDate));

    for (final session in sessions) {
      ExamStudentScore? sc;
      for (final e in session.scores) {
        if (e.studentId == st.id) {
          sc = e;
          break;
        }
      }
      if (sc?.score == null) continue;
      sessionDays.add(_dayKey(session.examDate));
      rows.add(_ExamTableRow.fromSession(session, sc!));
      plotEvents.add(_ExamPlotEvent.fromSession(session, sc));
    }

    final gradeRecords = await gradeSvc.getAllGradeRecords();
    for (final record in gradeRecords.where(
      (r) => r.examType == ExamType.vocabulary,
    )) {
      final grade = record.grades.cast<StudentGrade?>().firstWhere(
        (g) => g?.studentId == st.id,
        orElse: () => null,
      );
      if (grade == null) continue;
      final dk = _dayKey(record.examDate);
      if (sessionDays.contains(dk)) continue;
      sessionDays.add(dk);
      rows.add(_ExamTableRow.fromWordLegacy(record, grade));
      plotEvents.add(
        _ExamPlotEvent(
          date: record.examDate,
          focus: StudentExamFocus.vocabulary,
          yValue: grade.score.clamp(0, 100).toDouble(),
        ),
      );
    }

    for (final w in snapshot.wordExams.where((e) => e.studentId == st.id)) {
      final dk = _dayKey(w.createdAt);
      if (sessionDays.contains(dk)) continue;
      sessionDays.add(dk);
      rows.add(_ExamTableRow.fromWordSnapshot(w));
      final y = w.totalScore == 0 ? 0.0 : w.score / w.totalScore * 100;
      plotEvents.add(
        _ExamPlotEvent(
          date: w.createdAt,
          focus: StudentExamFocus.vocabulary,
          yValue: y.clamp(0, 100),
        ),
      );
    }

    for (final r in snapshot.reviewExams.where((e) => e.studentId == st.id)) {
      final dk = _dayKey(r.createdAt);
      if (sessionDays.contains(dk)) continue;
      sessionDays.add(dk);
      rows.add(_ExamTableRow.fromReviewLegacy(r));
      plotEvents.add(
        _ExamPlotEvent(
          date: r.createdAt,
          focus: StudentExamFocus.reviewTest,
          yValue: _gradeToPercent(r.grade),
        ),
      );
    }

    rows.sort((a, b) {
      final c = b.date.compareTo(a.date);
      if (c != 0) return c;
      return a.examName.compareTo(b.examName);
    });

    plotEvents.sort((a, b) => a.date.compareTo(b.date));

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _plotEvents = plotEvents;
      _loading = false;
    });
  }

  bool _sessionMatchesClass(ExamSession s, Student st) {
    final cn = st.className?.trim() ?? '';
    final cid = st.classId.trim();
    final sn = s.className.trim();
    if (cn.isNotEmpty && sn == cn) return true;
    if (cid.isNotEmpty && sn == cid) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final st = widget.student;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${st.name} · ${widget.classDisplayName}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 16),
        if (_rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('저장된 시험 기록이 없습니다.'),
            ),
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 720),
              child: Table(
                border: TableBorder.all(color: AppColors.line, width: 0.5),
                columnWidths: const {
                  0: FlexColumnWidth(1.1),
                  1: FlexColumnWidth(1.05),
                  2: FlexColumnWidth(1.15),
                  3: FlexColumnWidth(1.25),
                  4: FlexColumnWidth(0.55),
                  5: FlexColumnWidth(1.1),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: AppColors.cardAlt),
                    children: [
                      _th('날짜'),
                      _th('시험 종류'),
                      _th('시험 이름'),
                      _th('점수/만점'),
                      _th('재시험'),
                      _th('최종점수'),
                    ],
                  ),
                  ..._rows.map(
                    (r) => TableRow(
                      children: [
                        _td(r.dateLabel, onTap: () => _openDetail(context, r)),
                        _td(r.categoryLabel, onTap: () => _openDetail(context, r)),
                        _td(r.examName, onTap: () => _openDetail(context, r)),
                        _td(r.scoreSlashMax, onTap: () => _openDetail(context, r)),
                        _tdRetake(r, onTap: () => _openDetail(context, r)),
                        _td(r.finalScoreText, onTap: () => _openDetail(context, r)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        const Text(
          '시험 추이',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: StudentExamFocus.values.map((f) {
            final sel = _visibleFocus.contains(f);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 36,
                  width: 36,
                  child: Checkbox(
                    value: sel,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _visibleFocus.add(f);
                        } else if (_visibleFocus.length > 1) {
                          _visibleFocus.remove(f);
                        }
                      });
                    },
                  ),
                ),
                Text(
                  f.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        SegmentedButton<_ExamGraphPeriod>(
          segments: _ExamGraphPeriod.values
              .map(
                (p) => ButtonSegment<_ExamGraphPeriod>(
                  value: p,
                  label: Text(p.label, style: const TextStyle(fontSize: 12)),
                ),
              )
              .toList(),
          selected: {_period},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() => _period = s.first);
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 240,
          child: _ExamLineChart(
            period: _period,
            events: _plotEvents,
            visible: _visibleFocus,
          ),
        ),
      ],
    );
  }

  Widget _th(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.navy,
      ),
    ),
  );

  Widget _td(String t, {VoidCallback? onTap}) {
    final child = Text(
      t,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.navy,
        height: 1.25,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              child: child,
            ),
    );
  }

  Widget _tdRetake(_ExamTableRow r, {VoidCallback? onTap}) {
    final w = r.retakeCircle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: w ??
              const Text('-', style: TextStyle(color: AppColors.subText)),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, _ExamTableRow row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scroll) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.overlay,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${row.dateLabel} · ${row.categoryLabel}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  row.examName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  row.detailBody,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.subText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _examDateLabel(DateTime d) =>
    '${d.month}.${d.day} (${_weekdaysKo[d.weekday - 1]})';

// ── Table row ────────────────────────────────────────────────────────────────

class _ExamTableRow {
  final DateTime date;
  final String categoryLabel;
  final String examName;
  final String scoreSlashMax;
  final Widget? retakeCircle;
  final String finalScoreText;
  final String detailBody;

  const _ExamTableRow({
    required this.date,
    required this.categoryLabel,
    required this.examName,
    required this.scoreSlashMax,
    required this.retakeCircle,
    required this.finalScoreText,
    required this.detailBody,
  });

  String get dateLabel => _examDateLabel(date);

  factory _ExamTableRow.fromSession(ExamSession session, ExamStudentScore sc) {
    final categoryLabel = session.examTypeDisplayName;
    final name =
        session.examName.trim().isNotEmpty ? session.examName.trim() : '-';
    final score = sc.score!;
    final max = session.maxScore;

    final scoreSlash = _scoreColumnForCategory(session, sc);
    final simple = session.isThresholdBased;
    final threshold = session.retakeThreshold;
    final needsRetake = threshold != null && score < threshold;
    final hasFinal = sc.retakeScore != null;

    Widget? circle;
    String finalTxt = '-';
    if (simple) {
      final retakeGreen = !needsRetake || hasFinal;
      circle = Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: retakeGreen
              ? const Color(0xFF22C55E)
              : const Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      );
      if (!needsRetake) {
        finalTxt = '-';
      } else if (hasFinal) {
        final m = max?.round() ?? 100;
        finalTxt = '최종 ${sc.retakeScore!.round()}/$m';
      } else {
        final sched = _firstRetakeDate(session);
        if (sched != null) {
          finalTxt = '예정 ${_fmtSchedule(sched)}';
        } else {
          finalTxt = '-';
        }
      }
    } else {
      circle = null;
    }

    final buf = StringBuffer();
    buf.writeln('점수 표기: $scoreSlash');
    if (max != null) buf.writeln('만점: ${max.toStringAsFixed(0)}');
    if (simple && threshold != null) {
      buf.writeln('재시험 기준: ${threshold.toStringAsFixed(0)}점 미만');
    }
    if (hasFinal) {
      buf.writeln('재시험 점수: ${sc.retakeScore!.toStringAsFixed(0)}');
    }

    return _ExamTableRow(
      date: session.examDate,
      categoryLabel: categoryLabel,
      examName: name,
      scoreSlashMax: scoreSlash,
      retakeCircle: circle,
      finalScoreText: finalTxt,
      detailBody: buf.toString().trim(),
    );
  }

  factory _ExamTableRow.fromWordLegacy(
    GradeRecord record,
    StudentGrade grade,
  ) {
    final circle = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E),
        shape: BoxShape.circle,
      ),
    );
    return _ExamTableRow(
      date: record.examDate,
      categoryLabel: ExamCategory.vocabulary.label,
      examName: record.examType.label,
      scoreSlashMax: '${grade.score.round()}/100',
      retakeCircle: circle,
      finalScoreText: '-',
      detailBody: '레거시 성적 기록\n${grade.score.toStringAsFixed(0)} / 100',
    );
  }

  factory _ExamTableRow.fromWordSnapshot(WordExamRecord w) {
    final needs = w.needsRetake;
    final hasFinal = w.retakeScore != null;
    final circle = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: (!needs || hasFinal)
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444),
        shape: BoxShape.circle,
      ),
    );
    String finalTxt = '-';
    if (!needs) {
      finalTxt = '-';
    } else if (hasFinal) {
      finalTxt = '최종 ${w.retakeScore}/${w.totalScore}';
    } else {
      finalTxt = '-';
    }
    return _ExamTableRow(
      date: w.createdAt,
      categoryLabel: ExamCategory.vocabulary.label,
      examName: '단어시험',
      scoreSlashMax: '${w.score}/${w.totalScore}',
      retakeCircle: circle,
      finalScoreText: finalTxt,
      detailBody:
          '단어시험 (저장소)\n${w.score} / ${w.totalScore}\n반 평균: ${w.classAverage.toStringAsFixed(1)}',
    );
  }

  factory _ExamTableRow.fromReviewLegacy(ReviewExamRecord r) {
    final needs = r.needsRetake;
    final hasFinal = r.retakeGrade != null;
    final circle = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: (!needs || hasFinal)
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444),
        shape: BoxShape.circle,
      ),
    );
    String finalTxt = '-';
    if (!needs) {
      finalTxt = '-';
    } else if (hasFinal) {
      finalTxt = '최종 ${_reviewScoreSlashMax(r.retakeGrade!)}';
    } else {
      finalTxt = '-';
    }
    return _ExamTableRow(
      date: r.createdAt,
      categoryLabel: ExamCategory.reviewTest.label,
      examName: '리뷰테스트',
      scoreSlashMax: _reviewScoreSlashMax(r.grade),
      retakeCircle: circle,
      finalScoreText: finalTxt,
      detailBody:
          '리뷰테스트 (레거시)\n성적: ${r.grade.label}\n반 평균: ${r.classAverage.label}',
    );
  }
}

String _scoreColumnForCategory(ExamSession session, ExamStudentScore sc) {
  final s = sc.score!;
  if (session.isThresholdBased) {
    final max = session.maxScore?.round() ?? 100;
    return '${s.round()}/$max';
  }
  if (session.examTypeId == ClassExamTypeIds.internal) {
    final max = (session.maxScore ?? 100).round();
    final g5 = _internalExamFiveGrade(session, sc);
    return '${s.round()}/$max · $g5등급';
  }
  final max = (session.maxScore ?? 100).round();
  final g = sc.grade;
  final (int g5, int g9) = g != null && g >= 1 && g <= 9
      ? (_nineToFiveGrade(g), g)
      : _gradesFromSession(session, sc);
  return '${s.round()}/$max · $g5($g9)등급';
}

/// Maps 9등급제 등급 (1–9) to 5등급제 등급 (1–5) for 표기 보조.
int _nineToFiveGrade(int grade9) {
  final g = grade9 < 1 ? 1 : (grade9 > 9 ? 9 : grade9);
  var v = 1 + ((g - 1) * 4 / 8).round();
  if (v < 1) v = 1;
  if (v > 5) v = 5;
  return v;
}

int _internalExamFiveGrade(ExamSession session, ExamStudentScore sc) {
  final g = sc.grade;
  if (g != null && g >= 1 && g <= 5) return g;
  if (g != null && g >= 1 && g <= 9) return _nineToFiveGrade(g);
  return _gradesFromSession(session, sc).$1;
}

String _reviewScoreSlashMax(GradeLevel g) {
  final pct = _gradeToPercent(g);
  final n = (pct / 100 * 20).round().clamp(1, 20);
  return '$n/20';
}

DateTime? _firstRetakeDate(ExamSession session) {
  for (final d in session.retakeScheduledDates) {
    if (d != null) return d;
  }
  return null;
}

String _fmtSchedule(DateTime d) {
  final p = '${d.month}.${d.day}';
  if (d.hour != 0 || d.minute != 0) {
    return '$p ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return p;
}

(int, int) _gradesFromSession(ExamSession session, ExamStudentScore sc) {
  final entered = session.scores.where((e) => e.score != null).toList();
  if (entered.isEmpty) return (0, 0);
  final avg =
      entered.map((e) => e.score!).reduce((a, b) => a + b) / entered.length;
  final std = session.standardDeviation ??
      _populationStd(entered.map((e) => e.score!).toList(), avg);
  final z = (std > 0) ? (sc.score! - avg) / std : 0.0;
  return (_gradeFromZ(z, true), _gradeFromZ(z, false));
}

double _populationStd(List<double> values, double mean) {
  if (values.length < 2) return 0;
  final v = values.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
      values.length;
  return v <= 0 ? 0 : math.sqrt(v);
}

int _gradeFromZ(double z, bool five) {
  if (five) {
    if (z >= 1.2816) return 1;
    if (z >= 0.4125) return 2;
    if (z >= -0.4125) return 3;
    if (z >= -1.2816) return 4;
    return 5;
  }
  if (z >= 1.75) return 1;
  if (z >= 1.23) return 2;
  if (z >= 0.74) return 3;
  if (z >= 0.25) return 4;
  if (z >= -0.25) return 5;
  if (z >= -0.74) return 6;
  if (z >= -1.23) return 7;
  if (z >= -1.75) return 8;
  return 9;
}

double _gradeToPercent(GradeLevel level) {
  switch (level) {
    case GradeLevel.aPlus:
      return 100;
    case GradeLevel.a0:
      return 95;
    case GradeLevel.aMinus:
      return 90;
    case GradeLevel.bPlus:
      return 85;
    case GradeLevel.b0:
      return 80;
    case GradeLevel.bMinus:
      return 75;
    case GradeLevel.c:
      return 70;
  }
}

// ── Plot events ──────────────────────────────────────────────────────────────

class _ExamPlotEvent {
  final DateTime date;
  final StudentExamFocus focus;
  final double yValue;

  const _ExamPlotEvent({
    required this.date,
    required this.focus,
    required this.yValue,
  });

  factory _ExamPlotEvent.fromSession(
    ExamSession session,
    ExamStudentScore sc,
  ) {
    final s = sc.score!;
    final cat = session.legacyCategory;
    double y;
    if (session.isThresholdBased) {
      final max = session.maxScore;
      y = (max != null && max > 0) ? (s / max * 100) : s.clamp(0, 100);
    } else {
      // 모의고사·내신직보시험: 100점 만점 기준 점수 그대로(퍼센트 축에 동일 값).
      y = s.clamp(0, 100);
    }
    return _ExamPlotEvent(
      date: session.examDate,
      focus: _focusFromCategory(cat),
      yValue: y.clamp(0, 100),
    );
  }
}

StudentExamFocus _focusFromCategory(ExamCategory c) {
  switch (c) {
    case ExamCategory.vocabulary:
      return StudentExamFocus.vocabulary;
    case ExamCategory.reviewTest:
      return StudentExamFocus.reviewTest;
    case ExamCategory.regularExam:
      return StudentExamFocus.regularExam;
    case ExamCategory.internalExam:
      return StudentExamFocus.internalExam;
  }
}

// ── Chart ────────────────────────────────────────────────────────────────────

class _ExamLineChart extends StatelessWidget {
  final _ExamGraphPeriod period;
  final List<_ExamPlotEvent> events;
  final Set<StudentExamFocus> visible;

  const _ExamLineChart({
    required this.period,
    required this.events,
    required this.visible,
  });

  Color _color(StudentExamFocus f) {
    switch (f) {
      case StudentExamFocus.vocabulary:
        return AppColors.blue;
      case StudentExamFocus.reviewTest:
        return AppColors.green;
      case StudentExamFocus.regularExam:
        return AppColors.orange;
      case StudentExamFocus.internalExam:
        return AppColors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final buckets = _bucketize(period, events, now);
    if (buckets.isEmpty) {
      return const Center(
        child: Text(
          '표시할 데이터가 없습니다.',
          style: TextStyle(color: AppColors.subText),
        ),
      );
    }

    return CustomPaint(
      painter: _ExamChartPainter(
        buckets: buckets,
        visible: visible,
        colorFor: _color,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ChartBucket {
  final String label;
  final Map<StudentExamFocus, double> averages;

  const _ChartBucket({required this.label, required this.averages});
}

List<_ChartBucket> _bucketize(
  _ExamGraphPeriod period,
  List<_ExamPlotEvent> events,
  DateTime now,
) {
  final filtered = events.where((e) {
    switch (period) {
      case _ExamGraphPeriod.last4Weeks:
        final start = _mondayOf(now).subtract(const Duration(days: 21));
        return !e.date.isBefore(start);
      case _ExamGraphPeriod.thisSemester:
        return !e.date.isBefore(_semesterStart(now));
      case _ExamGraphPeriod.thisYear:
        return e.date.year == now.year;
    }
  }).toList();

  if (filtered.isEmpty) return const [];

  switch (period) {
    case _ExamGraphPeriod.last4Weeks:
      return _bucketLast4Weeks(filtered, now);
    case _ExamGraphPeriod.thisSemester:
      return _bucketSemester3Week(filtered);
    case _ExamGraphPeriod.thisYear:
      return _bucketYearMonth(filtered);
  }
}

DateTime _mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

DateTime _semesterStart(DateTime now) {
  final month = now.month;
  if (month >= 3 && month <= 8) return DateTime(now.year, 3, 1);
  if (month >= 9) return DateTime(now.year, 9, 1);
  return DateTime(now.year - 1, 9, 1);
}

List<_ChartBucket> _bucketLast4Weeks(List<_ExamPlotEvent> ev, DateTime now) {
  final endMonday = _mondayOf(now);
  final keys = List.generate(4, (i) {
    final m = endMonday.subtract(Duration(days: 7 * (3 - i)));
    return m;
  });
  return keys.map((monday) {
    final next = monday.add(const Duration(days: 7));
    final inWeek =
        ev.where((e) => !e.date.isBefore(monday) && e.date.isBefore(next)).toList();
    final label = '${monday.month}.${monday.day.toString().padLeft(2, '0')}';
    return _ChartBucket(
      label: label,
      averages: _avgByFocus(inWeek),
    );
  }).toList();
}

List<_ChartBucket> _bucketSemester3Week(List<_ExamPlotEvent> ev) {
  if (ev.isEmpty) return const [];
  ev.sort((a, b) => a.date.compareTo(b.date));
  final first = ev.first.date;
  final grouped = <int, List<_ExamPlotEvent>>{};
  for (final e in ev) {
    final diff = e.date.difference(_mondayOf(first)).inDays;
    final bucket = diff ~/ 21;
    grouped.putIfAbsent(bucket, () => []).add(e);
  }
  final keys = grouped.keys.toList()..sort();
  return keys.map((k) {
    final list = grouped[k]!;
    return _ChartBucket(
      label: '3주 ${k + 1}',
      averages: _avgByFocus(list),
    );
  }).toList();
}

List<_ChartBucket> _bucketYearMonth(List<_ExamPlotEvent> ev) {
  final byMonth = <String, List<_ExamPlotEvent>>{};
  for (final e in ev) {
    final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
    byMonth.putIfAbsent(key, () => []).add(e);
  }
  final keys = byMonth.keys.toList()..sort();
  return keys.map((k) {
    final parts = k.split('-');
    final m = int.parse(parts[1]);
    return _ChartBucket(
      label: '$m월',
      averages: _avgByFocus(byMonth[k]!),
    );
  }).toList();
}

Map<StudentExamFocus, double> _avgByFocus(List<_ExamPlotEvent> list) {
  final map = <StudentExamFocus, List<double>>{};
  for (final e in list) {
    map.putIfAbsent(e.focus, () => []).add(e.yValue);
  }
  final out = <StudentExamFocus, double>{};
  for (final e in StudentExamFocus.values) {
    final vals = map[e];
    if (vals == null || vals.isEmpty) continue;
    out[e] = vals.reduce((a, b) => a + b) / vals.length;
  }
  return out;
}

class _ExamChartPainter extends CustomPainter {
  final List<_ChartBucket> buckets;
  final Set<StudentExamFocus> visible;
  final Color Function(StudentExamFocus) colorFor;

  _ExamChartPainter({
    required this.buckets,
    required this.visible,
    required this.colorFor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 36.0;
    const padR = 12.0;
    const padT = 12.0;
    const padB = 36.0;
    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;

    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final y = padT + chartH * (i / 4);
      canvas.drawLine(Offset(padL, y), Offset(padL + chartW, y), grid);
    }

    final n = buckets.length;
    if (n == 0) return;
    final step = n > 1 ? chartW / (n - 1) : chartW / 2;

    double xAt(int i) => padL + (n > 1 ? step * i : chartW / 2);

    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (var i = 0; i < n; i++) {
      tp.text = TextSpan(
        text: buckets[i].label,
        style: const TextStyle(fontSize: 10, color: AppColors.subText),
      );
      tp.layout();
      tp.paint(canvas, Offset(xAt(i) - tp.width / 2, padT + chartH + 6));
    }

    for (var g = 0; g <= 4; g++) {
      final val = 100 - g * 25;
      tp.text = TextSpan(
        text: '$val',
        style: const TextStyle(fontSize: 9, color: AppColors.subText),
      );
      tp.layout();
      tp.paint(canvas, Offset(4, padT + chartH * (g / 4) - tp.height / 2));
    }

    for (final focus in StudentExamFocus.values) {
      if (!visible.contains(focus)) continue;
      final paint = Paint()
        ..color = colorFor(focus)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final path = Path();
      bool started = false;
      for (var i = 0; i < n; i++) {
        final v = buckets[i].averages[focus];
        if (v == null) continue;
        final x = xAt(i);
        final y = padT + chartH * (1 - v / 100);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      if (started) canvas.drawPath(path, paint);

      for (var i = 0; i < n; i++) {
        final v = buckets[i].averages[focus];
        if (v == null) continue;
        final x = xAt(i);
        final y = padT + chartH * (1 - v / 100);
        canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()..color = colorFor(focus),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExamChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets || oldDelegate.visible != visible;
  }
}
