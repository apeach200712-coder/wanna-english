import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/exam_score_model.dart';
import '../data/models/grade_record_model.dart';
import '../data/models/student_grade_model.dart';
import '../data/models/student_model.dart';
import 'exam_session_service.dart';
import 'grade_service.dart';
import 'grade_record_service.dart';
import 'homework_page_service.dart';
import 'student_service.dart';

enum StudentAnalyticsRange {
  thisWeek('이번주'),
  lastThreeWeeks('지난 3주'),
  thisSemester('이번 학기'),
  thisYear('이번 1년');

  final String label;
  const StudentAnalyticsRange(this.label);
}

enum StudentExamFocus {
  vocabulary('단어시험'),
  reviewTest('리뷰테스트'),
  regularExam('모의고사'),
  internalExam('내신직보시험');

  final String label;
  const StudentExamFocus(this.label);
}

class StudentTrendPoint {
  final String label;
  final double value;
  final DateTime date;

  const StudentTrendPoint({
    required this.label,
    required this.value,
    required this.date,
  });
}

class StudentHomeworkTrendData {
  final StudentAnalyticsRange range;
  final List<StudentTrendPoint> points;

  const StudentHomeworkTrendData({required this.range, required this.points});

  double? get average {
    if (points.isEmpty) return null;
    return points.map((point) => point.value).reduce((a, b) => a + b) /
        points.length;
  }
}

class StudentExamTrendData {
  final StudentExamFocus focus;
  final Map<StudentAnalyticsRange, List<StudentTrendPoint>> series;
  final List<StudentExamRecordItem> records;

  const StudentExamTrendData({
    required this.focus,
    required this.series,
    required this.records,
  });

  bool get hasData => series.values.any((items) => items.isNotEmpty);
}

class StudentExamRecordItem {
  final DateTime date;
  final String examName;
  final String rawScoreText;
  final double normalizedScore;

  const StudentExamRecordItem({
    required this.date,
    required this.examName,
    required this.rawScoreText,
    required this.normalizedScore,
  });
}

class StudentDetailData {
  final Student student;
  final Map<StudentAnalyticsRange, StudentHomeworkTrendData> homeworkByRange;
  final Map<StudentExamFocus, StudentExamTrendData> examByFocus;

  const StudentDetailData({
    required this.student,
    required this.homeworkByRange,
    required this.examByFocus,
  });
}

class StudentDetailService {
  final StudentService _studentService;
  final GradeRecordService _gradeRecordService;
  final ExamSessionService _examSessionService;
  final GradeService _gradeService;
  final HomeworkPageService _homeworkPageService;

  const StudentDetailService({
    required StudentService studentService,
    required GradeRecordService gradeRecordService,
    required ExamSessionService examSessionService,
    required GradeService gradeService,
    required HomeworkPageService homeworkPageService,
  }) : _studentService = studentService,
       _gradeRecordService = gradeRecordService,
       _examSessionService = examSessionService,
       _gradeService = gradeService,
       _homeworkPageService = homeworkPageService;

  static Future<StudentDetailService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    await studentService.initializeMockStudents();
    return StudentDetailService(
      studentService: studentService,
      gradeRecordService: GradeRecordService(prefs: prefs),
      examSessionService: ExamSessionService(prefs: prefs),
      gradeService: GradeService(prefs: prefs),
      homeworkPageService: HomeworkPageService(prefs: prefs),
    );
  }

  Future<StudentDetailData?> getStudentDetail(String studentId) async {
    final student = await _studentService.getStudentById(studentId);
    if (student == null) return null;

    final snapshot = await _gradeRecordService.getSnapshot();
    final homeworkPoints = _collectHomeworkPoints(student, snapshot)
      ..sort((a, b) => a.date.compareTo(b.date));

    final homeworkByRange = {
      for (final range in StudentAnalyticsRange.values)
        range: StudentHomeworkTrendData(
          range: range,
          points: _buildSeries(homeworkPoints, range),
        ),
    };

    final examPoints = await _collectExamPoints(studentId, snapshot);
    final examByFocus = <StudentExamFocus, StudentExamTrendData>{};
    for (final focus in StudentExamFocus.values) {
      final source = examPoints[focus] ?? const <_DatedValue>[];
      final data = StudentExamTrendData(
        focus: focus,
        series: {
          for (final range in StudentAnalyticsRange.values)
            range: _buildSeries(source, range),
        },
        records: _buildExamRecords(source),
      );
      if (data.hasData) {
        examByFocus[focus] = data;
      }
    }

    return StudentDetailData(
      student: student,
      homeworkByRange: homeworkByRange,
      examByFocus: examByFocus,
    );
  }

  List<_DatedValue> _collectHomeworkPoints(
    Student student,
    GradeRecordSnapshot snapshot,
  ) {
    final items = <String, _DatedValue>{};

    for (final result in _homeworkPageService.getAllStudentResults()) {
      if (result.studentId != student.id) continue;
      final date = DateTime.tryParse(result.weekStartDate);
      if (date == null) continue;
      final key = _day(date).toIso8601String();
      items[key] = _DatedValue(
        date: _day(date),
        value: result.finalCompletionRate.toDouble(),
        label: _shortDate(date),
        rawScoreText: '${result.finalCompletionRate}%',
      );
    }

    for (final entry in _homeworkPageService.getAllHistoryEntries()) {
      final date = DateTime.tryParse(entry.date);
      if (date == null) continue;
      final result = entry.studentResults.cast<dynamic>().firstWhere(
        (item) => item.studentId == student.id,
        orElse: () => null,
      );
      if (result == null) continue;
      final key = _day(date).toIso8601String();
      items.putIfAbsent(
        key,
        () => _DatedValue(
          date: _day(date),
          value: (result.finalCompletionRate ?? 0).toDouble(),
          label: _shortDate(date),
          rawScoreText: '${result.finalCompletionRate ?? 0}%',
        ),
      );
    }

    for (final record in snapshot.homework.where(
      (record) => record.studentId == student.id,
    )) {
      final key = _day(record.dueDate).toIso8601String();
      items.putIfAbsent(
        key,
        () => _DatedValue(
          date: record.dueDate,
          value: record.finalCompletionRate.toDouble(),
          label: _homeworkLabel(record),
          rawScoreText: '${record.finalCompletionRate}%',
        ),
      );
    }

    return items.values.toList();
  }

  Future<Map<StudentExamFocus, List<_DatedValue>>> _collectExamPoints(
    String studentId,
    GradeRecordSnapshot snapshot,
  ) async {
    final modern = <StudentExamFocus, List<_DatedValue>>{};
    final sessions = _examSessionService.getAllSessions().toList()
      ..sort((a, b) => a.examDate.compareTo(b.examDate));
    for (final session in sessions) {
      final studentScore = session.scores.cast<ExamStudentScore?>().firstWhere(
        (item) => item?.studentId == studentId,
        orElse: () => null,
      );
      final rawScore = studentScore?.score;
      if (rawScore == null) continue;
      final focus = _mapCategory(session.legacyCategory);
      if (focus == null) continue;
      modern.putIfAbsent(focus, () => []);
      modern[focus]!.add(
        _DatedValue(
          date: session.examDate,
          value: _normalizeExamScore(rawScore, session.maxScore),
          label: session.examName.isEmpty ? focus.label : session.examName,
          rawScoreText: _rawScoreTextForModernSession(session, studentScore!),
        ),
      );
    }

    if ((modern[StudentExamFocus.vocabulary] ?? const []).isEmpty) {
      final gradeRecords = await _gradeService.getAllGradeRecords();
      final vocabularyFromGrades =
          gradeRecords
              .where((record) => record.examType == ExamType.vocabulary)
              .map((record) {
                final grade = record.grades.cast<StudentGrade?>().firstWhere(
                  (item) => item?.studentId == studentId,
                  orElse: () => null,
                );
                if (grade == null) return null;
                return _DatedValue(
                  date: record.examDate,
                  value: grade.score.clamp(0, 100),
                  label: record.examType.label,
                  rawScoreText: '${grade.score.toStringAsFixed(0)} / 100',
                );
              })
              .whereType<_DatedValue>()
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      modern[StudentExamFocus.vocabulary] =
          vocabularyFromGrades.isNotEmpty
                ? vocabularyFromGrades
                : snapshot.wordExams
                      .where((record) => record.studentId == studentId)
                      .map(
                        (record) => _DatedValue(
                          date: record.createdAt,
                          value: record.totalScore == 0
                              ? 0
                              : record.score / record.totalScore * 100,
                          label: '단어시험',
                          rawScoreText:
                              '${record.score} / ${record.totalScore}',
                        ),
                      )
                      .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
    }

    if ((modern[StudentExamFocus.reviewTest] ?? const []).isEmpty) {
      modern[StudentExamFocus.reviewTest] =
          snapshot.reviewExams
              .where((record) => record.studentId == studentId)
              .map(
                (record) => _DatedValue(
                  date: record.createdAt,
                  value: _gradeToPercent(record.grade),
                  label: '리뷰테스트 ${record.grade.label}',
                  rawScoreText: record.grade.label,
                ),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
    }

    return modern;
  }

  List<StudentTrendPoint> _buildSeries(
    List<_DatedValue> source,
    StudentAnalyticsRange range,
  ) {
    final now = DateTime.now();
    final filtered = source.where((item) {
      switch (range) {
        case StudentAnalyticsRange.thisWeek:
          return !_isBefore(item.date, _startOfWeek(now));
        case StudentAnalyticsRange.lastThreeWeeks:
          return !_isBefore(item.date, now.subtract(const Duration(days: 21)));
        case StudentAnalyticsRange.thisSemester:
          return !_isBefore(item.date, _semesterStart(now));
        case StudentAnalyticsRange.thisYear:
          return !_isBefore(item.date, now.subtract(const Duration(days: 365)));
      }
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    switch (range) {
      case StudentAnalyticsRange.thisWeek:
        return filtered
            .map(
              (item) => StudentTrendPoint(
                label: _shortDate(item.date),
                value: item.value,
                date: item.date,
              ),
            )
            .toList();
      case StudentAnalyticsRange.lastThreeWeeks:
        return _groupByWeek(filtered);
      case StudentAnalyticsRange.thisSemester:
        return _groupByFixedWindow(filtered, daysPerBucket: 21, prefix: '3주');
      case StudentAnalyticsRange.thisYear:
        return _groupByMonth(filtered);
    }
  }

  List<StudentTrendPoint> _groupByWeek(List<_DatedValue> items) {
    final grouped = <String, List<_DatedValue>>{};
    for (final item in items) {
      final anchor = _startOfWeek(item.date);
      final key = anchor.toIso8601String();
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final values = grouped[key]!;
      final avg =
          values.map((item) => item.value).reduce((a, b) => a + b) /
          values.length;
      final date = DateTime.parse(key);
      return StudentTrendPoint(
        label: '${date.month}.${date.day.toString().padLeft(2, '0')}',
        value: avg,
        date: date,
      );
    }).toList();
  }

  List<StudentTrendPoint> _groupByFixedWindow(
    List<_DatedValue> items, {
    required int daysPerBucket,
    required String prefix,
  }) {
    if (items.isEmpty) return const [];
    final firstDate = items.first.date;
    final grouped = <int, List<_DatedValue>>{};
    for (final item in items) {
      final diff = item.date.difference(firstDate).inDays;
      final bucket = diff ~/ daysPerBucket;
      grouped.putIfAbsent(bucket, () => []).add(item);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((bucket) {
      final values = grouped[bucket]!;
      final avg =
          values.map((item) => item.value).reduce((a, b) => a + b) /
          values.length;
      return StudentTrendPoint(
        label: '$prefix ${bucket + 1}',
        value: avg,
        date: values.last.date,
      );
    }).toList();
  }

  List<StudentTrendPoint> _groupByMonth(List<_DatedValue> items) {
    final grouped = <String, List<_DatedValue>>{};
    for (final item in items) {
      final key =
          '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final keys = grouped.keys.toList()..sort();
    return keys.map((key) {
      final values = grouped[key]!;
      final avg =
          values.map((item) => item.value).reduce((a, b) => a + b) /
          values.length;
      final date = DateTime(values.first.date.year, values.first.date.month);
      return StudentTrendPoint(label: '${date.month}월', value: avg, date: date);
    }).toList();
  }

  StudentExamFocus? _mapCategory(ExamCategory category) {
    switch (category) {
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

  double _normalizeExamScore(double rawScore, double? maxScore) {
    if (maxScore == null || maxScore <= 0) return rawScore.clamp(0, 100);
    return (rawScore / maxScore * 100).clamp(0, 100);
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

  List<StudentExamRecordItem> _buildExamRecords(List<_DatedValue> source) {
    final items =
        source
            .map(
              (item) => StudentExamRecordItem(
                date: item.date,
                examName: item.label,
                rawScoreText: item.rawScoreText,
                normalizedScore: item.value,
              ),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  String _rawScoreTextForModernSession(
    ExamSession session,
    ExamStudentScore score,
  ) {
    if (session.isThresholdBased) {
      final max = session.maxScore?.toStringAsFixed(0) ?? '?';
      return '${score.score?.toStringAsFixed(0) ?? '-'} / $max';
    }
    return '${score.score?.toStringAsFixed(0) ?? '-'}점';
  }

  String _homeworkLabel(HomeworkRecord record) {
    final title = record.title.trim();
    if (title.isNotEmpty) return title;
    return _shortDate(record.dueDate);
  }

  DateTime _startOfWeek(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
  }

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime _semesterStart(DateTime now) {
    final month = now.month;
    if (month >= 3 && month <= 8) {
      return DateTime(now.year, 3, 1);
    }
    if (month >= 9) {
      return DateTime(now.year, 9, 1);
    }
    return DateTime(now.year - 1, 9, 1);
  }

  bool _isBefore(DateTime left, DateTime right) {
    return left.isBefore(DateTime(right.year, right.month, right.day));
  }

  String _shortDate(DateTime date) {
    return '${date.month}.${date.day.toString().padLeft(2, '0')}';
  }
}

class _DatedValue {
  final DateTime date;
  final double value;
  final String label;
  final String rawScoreText;

  const _DatedValue({
    required this.date,
    required this.value,
    required this.label,
    required this.rawScoreText,
  });
}
