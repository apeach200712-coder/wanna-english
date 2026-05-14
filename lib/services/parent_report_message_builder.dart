import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/exam_score_model.dart';
import '../data/models/grade_record_model.dart';
import '../data/models/homework_models.dart';
import '../data/models/parent_report_models.dart';
import '../data/models/student_model.dart';
import 'exam_session_service.dart';
import 'grade_record_service.dart';
import 'homework_page_service.dart';
import 'lesson_content_service.dart';

/// 학부모 리포트 문자 본문 생성 (UI와 분리).
class ParentReportMessageBuilder {
  ParentReportMessageBuilder._();

  static Future<String> build({
    required Student student,
    required String className,
    required ClassReportSettings classSettings,
    required ReportSendOptions sendOptions,
    required String extraNoticeRaw,
    required SharedPreferences prefs,
    DateTime? referenceDate,
  }) async {
    final day = _calendarDay(referenceDate ?? DateTime.now());

    final lessonService = LessonContentService(prefs: prefs);
    final homeworkService = HomeworkPageService(prefs: prefs);
    final examService = ExamSessionService(prefs: prefs);
    final gradeRecordService = GradeRecordService(prefs: prefs);
    final snapshot = await gradeRecordService.getSnapshot();

    final buf = StringBuffer();

    final greeting = classSettings.greetingTemplate
        .replaceAll('{학생이름}', student.name)
        .trim();
    if (greeting.isNotEmpty) {
      buf.writeln(greeting);
    }

    final homeworkBody = await _buildHomeworkSectionBody(
      student: student,
      className: className,
      classSettings: classSettings,
      homeworkService: homeworkService,
      snapshot: snapshot,
      today: day,
    );
    if (homeworkBody != null && homeworkBody.trim().isNotEmpty) {
      buf.writeln();
      buf.writeln('[숙제]');
      buf.writeln(homeworkBody.trim());
    }

    if (sendOptions.includeTodayLesson) {
      final lessonLines = await _lessonLines(lessonService, className);
      if (lessonLines.isNotEmpty) {
        buf.writeln();
        buf.writeln('[오늘 수업 내용]');
        for (final line in lessonLines) {
          buf.writeln(line);
        }
      }
    }

    if (sendOptions.includeNextHomework) {
      final nextLines = _nextWeekLines(homeworkService, student, className);
      if (nextLines.isNotEmpty) {
        buf.writeln();
        buf.writeln('[다음주 숙제]');
        for (final line in nextLines) {
          buf.writeln(line);
        }
      }
    }

    final examBlock = _buildTodayExamBlock(
      student: student,
      className: className,
      examDate: day,
      examService: examService,
      selectedIds: sendOptions.selectedExamSessionIds,
    );
    if (examBlock != null && examBlock.trim().isNotEmpty) {
      buf.writeln();
      buf.writeln('[오늘 시험]');
      buf.writeln(examBlock.trim());
    }

    final extra = extraNoticeRaw.trim();
    if (extra.isNotEmpty) {
      buf.writeln();
      buf.writeln('[추가안내]');
      buf.writeln(extra);
    }

    final closing = classSettings.closingText.trim();
    if (closing.isNotEmpty) {
      buf.writeln();
      buf.writeln(closing);
    }

    return buf.toString().trimRight();
  }

  // ── Homework (이행률 / 부족한 점 / 재제출 기한만) ───────────────────────────

  static Future<String?> _buildHomeworkSectionBody({
    required Student student,
    required String className,
    required ClassReportSettings classSettings,
    required HomeworkPageService homeworkService,
    required GradeRecordSnapshot snapshot,
    required DateTime today,
  }) async {
    final todayKey = _dateKey(today);
    final mondayKey = _mondayDateKey(today);

    final template = homeworkService.getTemplate(
      student.classId,
      fallbackKeys: [className],
    );
    final weekKeyCandidates = <String>{
      if (template != null && template.weekStartDate.isNotEmpty)
        template.weekStartDate,
      mondayKey,
      todayKey,
    };

    StudentHomeworkResult? studentWeek;
    for (final key in weekKeyCandidates) {
      final list = homeworkService.getStudentResults(
        student.classId,
        key,
        fallbackKeys: [className],
      );
      final found = list.where((r) => r.studentId == student.id).toList();
      if (found.isNotEmpty) {
        studentWeek = found.first;
        break;
      }
    }

    final snapshotHomework = snapshot.homework
        .where(
          (h) =>
              h.studentId == student.id &&
              (h.className == className || h.classId == student.classId) &&
              _isSameDay(DateTime.fromMillisecondsSinceEpoch(h.createdAt), today),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final HomeworkRecord? todayHw =
        snapshotHomework.isEmpty ? null : snapshotHomework.first;

    final rateSource =
        studentWeek?.finalCompletionRate ?? todayHw?.finalCompletionRate;

    final incompleteSource =
        studentWeek?.sections ?? todayHw?.sections ?? const <HomeworkSection>[];
    final incomplete = incompleteSource
        .where((s) => s.checkCount < 5)
        .map(_homeworkItemLabel)
        .where((s) => s.isNotEmpty)
        .toList();

    final rs = studentWeek?.resubmission ?? const ResubmissionInfo();
    String? resubmitLine;
    if (rs.status == ResubmissionStatus.resubmissionRequired) {
      if (rs.dueDate != null && rs.dueDate!.trim().isNotEmpty) {
        resubmitLine = '재제출 기한: ${_formatDueDateParent(rs.dueDate!)}';
      }
    }

    final lines = <String>[];

    if (classSettings.includeHomeworkCompletion) {
      if (studentWeek != null &&
          studentWeek.isEvaluated &&
          rateSource != null) {
        lines.add('이행률: $rateSource%');
      } else if (todayHw != null && todayHw.finalCompletionRate > 0) {
        lines.add('이행률: ${todayHw.finalCompletionRate}%');
      }
    }

    if (classSettings.includeHomeworkWeakParts && incomplete.isNotEmpty) {
      lines.add('부족한 점: ${incomplete.join(', ')}');
    }

    if (classSettings.includeHomeworkResubmissionDeadline &&
        resubmitLine != null) {
      lines.add(resubmitLine);
    }

    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  static Future<List<String>> _lessonLines(
    LessonContentService service,
    String className,
  ) async {
    final raw = await service.getLessonContent(className);
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static List<String> _nextWeekLines(
    HomeworkPageService homeworkService,
    Student student,
    String className,
  ) {
    final next = homeworkService.getNextWeek(
      student.classId,
      fallbackKeys: [className],
    );
    if (next == null) return const [];
    return next.items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  // ── Exams ─────────────────────────────────────────────────────────────────

  static String? _buildTodayExamBlock({
    required Student student,
    required String className,
    required DateTime examDate,
    required ExamSessionService examService,
    required Set<String> selectedIds,
  }) {
    if (selectedIds.isEmpty) return null;

    final sessions = examService
        .getSessions(className: className, examDate: examDate)
        .where((s) => selectedIds.contains(s.id))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final chunks = <String>[];
    for (final session in sessions) {
      final lines = _examLinesForStudent(student, session);
      if (lines.isEmpty) continue;
      chunks.add(lines.join('\n'));
    }

    if (chunks.isEmpty) return null;
    return chunks.join('\n\n');
  }

  static List<String> _examLinesForStudent(Student student, ExamSession session) {
    ExamStudentScore? score;
    for (final s in session.scores) {
      if (s.studentId == student.id) {
        score = s;
        break;
      }
    }
    if (score == null || score.score == null) return const [];

    if (session.isThresholdBased) {
      if (session.examTypeId == ClassExamTypeIds.reviewTest) {
        return _reviewReport(session, score);
      }
      return _vocabReport(session, score);
    }
    if (session.examTypeId == ClassExamTypeIds.internal) {
      return _internalReport(session, score);
    }
    return _mockReport(session, score);
  }

  static List<String> _vocabReport(ExamSession session, ExamStudentScore score) {
    final lines = <String>[];
    final examTitle = session.examName.trim().isNotEmpty
        ? session.examName.trim()
        : session.examTypeDisplayName;
    final max = session.maxScore;
    final maxStr = max?.toStringAsFixed(0) ?? '?';
    final avg = _sessionAverage(session);
    final avgStr = avg != null ? avg.toStringAsFixed(1) : '-';
    final threshold = session.retakeThreshold;

    if (score.retakeScore != null && max != null) {
      lines.add(examTitle);
      lines.add(
        '원점수 ${score.score!.toStringAsFixed(0)}점 / $maxStr점 → 최종 ${score.retakeScore!.toStringAsFixed(0)}점 / $maxStr점',
      );
      lines.add('재시험 완료');
      return lines;
    }

    lines.add(examTitle);
    lines.add(
      '${score.score!.toStringAsFixed(0)}점 / $maxStr점 · 평균 $avgStr점',
    );
    final needsRetake = threshold != null && score.score! < threshold;
    if (!needsRetake) {
      lines.add('통과');
      return lines;
    }
    lines.add('재시험 대상');
    lines.add('재시험 기준: ${threshold.toStringAsFixed(0)}점 미만');
    final scheduled = _firstRetakeDate(session);
    final schedStr = _fmtRetakeSchedule(scheduled);
    if (schedStr.isNotEmpty) {
      lines.add('재시험 예정: $schedStr');
    }
    return lines;
  }

  static List<String> _reviewReport(
    ExamSession session,
    ExamStudentScore score,
  ) {
    final lines = <String>[];
    final examTitle = session.examName.trim().isNotEmpty
        ? session.examName.trim()
        : session.examTypeDisplayName;
    final max = session.maxScore;
    final maxStr = max?.toStringAsFixed(0) ?? '?';
    final avg = _sessionAverage(session);
    final avgStr = avg != null ? avg.toStringAsFixed(1) : '-';
    final threshold = session.retakeThreshold;
    final hasFinal = score.retakeScore != null;

    if (hasFinal && max != null) {
      lines.add(examTitle);
      lines.add(
        '원점수 ${score.score!.toStringAsFixed(0)}점 / $maxStr점 → 최종 ${score.retakeScore!.toStringAsFixed(0)}점 / $maxStr점',
      );
      lines.add('재시험 완료');
      return lines;
    }

    lines.add(examTitle);
    lines.add(
      '${score.score!.toStringAsFixed(0)}점 / $maxStr점 · 평균 $avgStr점',
    );
    final needsRetake = threshold != null && score.score! < threshold;
    if (!needsRetake) {
      lines.add('통과');
      return lines;
    }
    lines.add('재시험 대상');
    final scheduled = _firstRetakeDate(session);
    final schedStr = _fmtRetakeSchedule(scheduled);
    if (schedStr.isNotEmpty) {
      lines.add('재시험 예정: $schedStr');
    }
    return lines;
  }

  static List<String> _mockReport(ExamSession session, ExamStudentScore score) {
    final lines = <String>[];
    lines.add(
      session.examName.trim().isNotEmpty
          ? session.examName.trim()
          : session.examTypeDisplayName,
    );
    final avg = _sessionAverage(session);
    final avgStr = avg != null ? avg.toStringAsFixed(1) : '-';
    final std = session.standardDeviation;
    final stdStr = std != null ? std.toStringAsFixed(0) : '-';

    lines.add(
      '${score.score!.toStringAsFixed(0)}점 · 평균 $avgStr점 · 표준편차 $stdStr',
    );
    if (score.percentile != null) {
      lines.add('백분위 ${score.percentile!.toStringAsFixed(0)}');
    }
    final classAvg = avg;
    final stddev = session.standardDeviation;
    final z = (stddev != null && stddev > 0 && classAvg != null)
        ? (score.score! - classAvg) / stddev
        : 0.0;
    final g5 = _gradeFromZ(z, isFiveScale: true);
    final g9 = _gradeFromZ(z, isFiveScale: false);
    lines.add('5등급제 $g5등급 · 9등급제 $g9등급');
    return lines;
  }

  static List<String> _internalReport(
    ExamSession session,
    ExamStudentScore score,
  ) {
    final lines = <String>[];
    lines.add(
      session.examName.trim().isNotEmpty
          ? session.examName.trim()
          : session.examTypeDisplayName,
    );
    final avg = _sessionAverage(session);
    final avgStr = avg != null ? avg.toStringAsFixed(1) : '-';
    final std = session.standardDeviation;
    final stdStr = std != null ? std.toStringAsFixed(0) : '-';

    lines.add(
      '${score.score!.toStringAsFixed(0)}점 · 평균 $avgStr점 · 표준편차 $stdStr',
    );
    if (score.percentile != null) {
      lines.add('백분위 ${score.percentile!.toStringAsFixed(0)}');
    }
    final classAvg = avg;
    final stddev = session.standardDeviation;
    final z = (stddev != null && stddev > 0 && classAvg != null)
        ? (score.score! - classAvg) / stddev
        : 0.0;
    final g5 = _gradeFromZ(z, isFiveScale: true);
    lines.add('5등급제 $g5등급');
    return lines;
  }

  static double? _sessionAverage(ExamSession session) {
    final entered = session.scores.where((s) => s.score != null).toList();
    if (entered.isEmpty) return null;
    return entered.map((e) => e.score!).reduce((a, b) => a + b) / entered.length;
  }

  static DateTime? _firstRetakeDate(ExamSession session) {
    for (final d in session.retakeScheduledDates) {
      if (d != null) return d;
    }
    return null;
  }

  static int _gradeFromZ(double z, {required bool isFiveScale}) {
    if (isFiveScale) {
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

  static DateTime _calendarDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _mondayDateKey(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - DateTime.monday));
    return _dateKey(monday);
  }

  static String _homeworkItemLabel(HomeworkSection section) {
    final subSection = section.subSection?.trim() ?? '';
    final detailMemo = section.detailMemo?.trim() ?? '';
    final value =
        [subSection, detailMemo].where((item) => item.isNotEmpty).join(' ').trim();
    if (value.isNotEmpty) return value;
    return section.sectionName.trim();
  }

  static String _formatDueDateParent(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    final now = DateTime.now();
    final isToday = parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
    if (isToday) {
      if (parsed.hour != 0 || parsed.minute != 0) {
        return '오늘 ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
      }
      return '오늘';
    }
    final hm =
        '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    if (parsed.hour != 0 || parsed.minute != 0) {
      return '${parsed.month}.${parsed.day.toString().padLeft(2, '0')} $hm';
    }
    return '${parsed.month}.${parsed.day.toString().padLeft(2, '0')}';
  }

  static String _fmtRetakeSchedule(DateTime? d) {
    if (d == null) return '';
    final datePart = '${d.month}.${d.day.toString().padLeft(2, '0')}';
    if (d.hour != 0 || d.minute != 0) {
      return '$datePart ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return datePart;
  }
}
