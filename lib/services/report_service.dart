import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/grade_record_model.dart';
import '../data/models/report_model.dart';
import '../data/models/student_grade_model.dart';
import '../data/models/student_model.dart';
import 'grade_service.dart';
import 'grade_record_service.dart';
import 'homework_page_service.dart';
import 'student_service.dart';

class ReportService {
  final GradeRecordService _gradeRecordService;
  final GradeService _gradeService;
  final HomeworkPageService _homeworkPageService;
  final StudentService _studentService;

  const ReportService({
    required GradeRecordService gradeRecordService,
    required GradeService gradeService,
    required HomeworkPageService homeworkPageService,
    required StudentService studentService,
  }) : _gradeRecordService = gradeRecordService,
       _gradeService = gradeService,
       _homeworkPageService = homeworkPageService,
       _studentService = studentService;

  static Future<ReportService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    final gradeRecordService = GradeRecordService(prefs: prefs);
    final gradeService = GradeService(prefs: prefs);
    final homeworkPageService = HomeworkPageService(prefs: prefs);
    await studentService.initializeMockStudents();
    return ReportService(
      gradeRecordService: gradeRecordService,
      gradeService: gradeService,
      homeworkPageService: homeworkPageService,
      studentService: studentService,
    );
  }

  Future<List<ClassReportSummary>> getClassSummaries() async {
    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final students = await _studentService.getAllStudents();
    final snapshot = await _gradeRecordService.getSnapshot();
    final homeworkItems = _collectHomeworkItems(snapshot);
    final vocabItems = await _collectVocabularyItems(snapshot);
    final classNames =
        students
            .map((s) => s.className?.trim())
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final summaries = <ClassReportSummary>[];

    for (final className in classNames) {
      final classStudents = students
          .where((s) => s.className == className)
          .toList();
      final studentIds = classStudents.map((s) => s.id).toSet();

      final attendance = snapshot.attendance
          .where(
            (r) =>
                studentIds.contains(r.studentId) &&
                _isWithinWeek(r.date, weekStart),
          )
          .toList();
      final homework = homeworkItems
          .where(
            (r) =>
                studentIds.contains(r.studentId) &&
                _isWithinWeek(r.anchorDate, weekStart),
          )
          .toList();
      final wordExams = vocabItems
          .where(
            (r) =>
                studentIds.contains(r.studentId) &&
                _isWithinWeek(r.anchorDate, weekStart),
          )
          .toList();

      final attendanceRate = attendance.isEmpty
          ? 0.0
          : attendance.where((a) => a.isPresent).length / attendance.length;

      final homeworkRate = homework.isEmpty
          ? 0.0
          : homework
                    .map((h) => h.completionRate)
                    .fold<int>(0, (a, b) => a + b) /
                (homework.length * 100);

      final wordAvg = wordExams.isEmpty
          ? 0.0
          : wordExams
                    .map((w) => w.scorePercent)
                    .fold<double>(0, (a, b) => a + b) /
                wordExams.length;

      final warningCount = (await _buildRiskItems(
        classStudents,
        snapshot,
      )).length;

      summaries.add(
        ClassReportSummary(
          className: className,
          studentCount: classStudents.length,
          attendanceRate: attendanceRate,
          homeworkCompletionRate: homeworkRate,
          wordExamAverage: wordAvg,
          warningStudentCount: warningCount,
        ),
      );
    }

    return summaries;
  }

  Future<WeeklyOverview> getWeeklyOverview() async {
    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final students = await _studentService.getAllStudents();
    final snapshot = await _gradeRecordService.getSnapshot();
    final homeworkItems = _collectHomeworkItems(
      snapshot,
    ).where((item) => _isWithinWeek(item.anchorDate, weekStart)).toList();
    final vocabItems = (await _collectVocabularyItems(
      snapshot,
    )).where((item) => _isWithinWeek(item.anchorDate, weekStart)).toList();
    final attendanceItems = snapshot.attendance
        .where((item) => _isWithinWeek(item.date, weekStart))
        .toList();

    final attendanceRate = attendanceItems.isEmpty
        ? 0.0
        : attendanceItems.where((a) => a.isPresent).length /
              attendanceItems.length;

    final homeworkRate = homeworkItems.isEmpty
        ? 0.0
        : homeworkItems
                  .map((h) => h.completionRate)
                  .fold<int>(0, (a, b) => a + b) /
              (homeworkItems.length * 100);

    final wordAvg = vocabItems.isEmpty
        ? 0.0
        : vocabItems
                  .map((w) => w.scorePercent)
                  .fold<double>(0, (a, b) => a + b) /
              vocabItems.length;

    return WeeklyOverview(
      generatedAt: DateTime.now(),
      totalStudents: students.length,
      attendanceRate: attendanceRate,
      homeworkCompletionRate: homeworkRate,
      wordExamAverage: wordAvg,
    );
  }

  Future<List<StudentRiskItem>> getRiskStudents({String? className}) async {
    final students = await _studentService.getAllStudents();
    final filtered = className == null
        ? students
        : students.where((s) => s.className == className).toList();
    final snapshot = await _gradeRecordService.getSnapshot();
    return _buildRiskItems(filtered, snapshot);
  }

  Future<List<StudentReportDetail>> getStudentDetails({
    String? className,
  }) async {
    final students = await _studentService.getAllStudents();
    final filtered = className == null
        ? students
        : students.where((s) => s.className == className).toList();
    final snapshot = await _gradeRecordService.getSnapshot();
    final homeworkItems = _collectHomeworkItems(snapshot);
    final vocabItems = await _collectVocabularyItems(snapshot);

    final riskIds = (await _buildRiskItems(
      filtered,
      snapshot,
    )).map((r) => r.studentId).toSet();
    return filtered.map((student) {
      final attendance =
          snapshot.attendance.where((r) => r.studentId == student.id).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      final homework =
          homeworkItems.where((r) => r.studentId == student.id).toList()
            ..sort((a, b) => b.anchorDate.compareTo(a.anchorDate));
      final wordExams =
          vocabItems.where((r) => r.studentId == student.id).toList()
            ..sort((a, b) => b.anchorDate.compareTo(a.anchorDate));
      final reviewExams =
          snapshot.reviewExams.where((r) => r.studentId == student.id).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final present = attendance.where((a) => a.isPresent).length;
      final absent = attendance.where((a) => !a.isPresent).length;

      return StudentReportDetail(
        studentId: student.id,
        studentName: student.name,
        className: student.className ?? '-',
        attendancePresent: present,
        attendanceAbsent: absent,
        latestHomeworkCompletion: homework.isEmpty
            ? 0
            : homework.first.completionRate,
        latestWordExamScore: wordExams.isEmpty
            ? null
            : wordExams.first.rawScore,
        latestWordExamTotalScore: wordExams.isEmpty
            ? null
            : wordExams.first.totalScore,
        latestReviewGrade: reviewExams.isEmpty
            ? null
            : reviewExams.first.grade.label,
        needsAttention: riskIds.contains(student.id),
      );
    }).toList();
  }

  Future<List<StudentRiskItem>> _buildRiskItems(
    List<Student> students,
    GradeRecordSnapshot snapshot,
  ) async {
    final homeworkByStudent = <String, List<_HomeworkMetric>>{};
    for (final item in _collectHomeworkItems(snapshot)) {
      homeworkByStudent.putIfAbsent(item.studentId, () => []).add(item);
    }

    final vocabByStudent = <String, List<_VocabularyMetric>>{};
    for (final item in await _collectVocabularyItems(snapshot)) {
      vocabByStudent.putIfAbsent(item.studentId, () => []).add(item);
    }

    final items = <StudentRiskItem>[];
    for (final student in students) {
      final reasons = <String>[];

      final attendance =
          snapshot.attendance.where((r) => r.studentId == student.id).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (attendance.isNotEmpty && !attendance.first.isPresent) {
        reasons.add('최근 출결이 결석입니다');
      }

      final homework =
          (homeworkByStudent[student.id] ?? const <_HomeworkMetric>[]).toList()
            ..sort((a, b) => b.anchorDate.compareTo(a.anchorDate));
      if (homework.isNotEmpty && homework.first.completionRate < 60) {
        reasons.add('숙제 완성도가 60% 미만입니다');
      }

      final wordExam =
          (vocabByStudent[student.id] ?? const <_VocabularyMetric>[]).toList()
            ..sort((a, b) => b.anchorDate.compareTo(a.anchorDate));
      if (wordExam.isNotEmpty) {
        if (wordExam.first.scorePercent < 60) {
          reasons.add('단어 시험 점수가 60점 미만입니다');
        }
      }

      if (reasons.isNotEmpty) {
        items.add(
          StudentRiskItem(
            studentId: student.id,
            studentName: student.name,
            className: student.className ?? '-',
            reasons: reasons,
          ),
        );
      }
    }

    items.sort((a, b) {
      final byCount = b.reasons.length.compareTo(a.reasons.length);
      if (byCount != 0) return byCount;
      return a.studentName.compareTo(b.studentName);
    });
    return items;
  }

  List<_HomeworkMetric> _collectHomeworkItems(GradeRecordSnapshot snapshot) {
    final items = <String, _HomeworkMetric>{};

    for (final result in _homeworkPageService.getAllStudentResults()) {
      final date = DateTime.tryParse(result.weekStartDate);
      if (date == null) continue;
      final key =
          '${result.classId}:${result.studentId}:${_day(date).toIso8601String()}';
      items[key] = _HomeworkMetric(
        studentId: result.studentId,
        className: result.classId,
        completionRate: result.finalCompletionRate,
        anchorDate: _day(date),
      );
    }

    for (final entry in _homeworkPageService.getAllHistoryEntries()) {
      final date = DateTime.tryParse(entry.date);
      if (date == null) continue;
      for (final result in entry.studentResults) {
        final key =
            '${entry.classId}:${result.studentId}:${_day(date).toIso8601String()}';
        items.putIfAbsent(
          key,
          () => _HomeworkMetric(
            studentId: result.studentId,
            className: entry.classId,
            completionRate: result.finalCompletionRate ?? 0,
            anchorDate: _day(date),
          ),
        );
      }
    }

    for (final record in snapshot.homework) {
      final date = _day(record.dueDate);
      final key =
          '${record.className}:${record.studentId}:${date.toIso8601String()}';
      items.putIfAbsent(
        key,
        () => _HomeworkMetric(
          studentId: record.studentId,
          className: record.className,
          completionRate: record.completionPercent,
          anchorDate: date,
        ),
      );
    }

    return items.values.toList();
  }

  Future<List<_VocabularyMetric>> _collectVocabularyItems(
    GradeRecordSnapshot snapshot,
  ) async {
    final items = <String, _VocabularyMetric>{};

    for (final record in snapshot.wordExams) {
      final date = _day(record.createdAt);
      final key =
          '${record.className}:${record.studentId}:${date.toIso8601String()}';
      final scorePercent = record.totalScore == 0
          ? 0.0
          : record.score / record.totalScore * 100;
      items[key] = _VocabularyMetric(
        studentId: record.studentId,
        className: record.className,
        scorePercent: scorePercent,
        rawScore: record.score,
        totalScore: record.totalScore,
        anchorDate: date,
      );
    }

    final modernRecords = await _gradeService.getAllGradeRecords();
    for (final record in modernRecords.where(
      (entry) => entry.examType == ExamType.vocabulary,
    )) {
      final date = _day(record.examDate);
      for (final grade in record.grades) {
        final key =
            '${record.className}:${grade.studentId}:${date.toIso8601String()}';
        items[key] = _VocabularyMetric(
          studentId: grade.studentId,
          className: record.className,
          scorePercent: grade.score.clamp(0, 100),
          rawScore: grade.score.round(),
          totalScore: 100,
          anchorDate: date,
        );
      }
    }

    return items.values.toList();
  }

  DateTime _startOfWeek(DateTime now) {
    final day = _day(now);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  bool _isWithinWeek(DateTime date, DateTime weekStart) {
    final day = _day(date);
    final end = weekStart.add(const Duration(days: 7));
    return !day.isBefore(weekStart) && day.isBefore(end);
  }
}

class _HomeworkMetric {
  final String studentId;
  final String className;
  final int completionRate;
  final DateTime anchorDate;

  const _HomeworkMetric({
    required this.studentId,
    required this.className,
    required this.completionRate,
    required this.anchorDate,
  });
}

class _VocabularyMetric {
  final String studentId;
  final String className;
  final double scorePercent;
  final int? rawScore;
  final int? totalScore;
  final DateTime anchorDate;

  const _VocabularyMetric({
    required this.studentId,
    required this.className,
    required this.scorePercent,
    required this.rawScore,
    required this.totalScore,
    required this.anchorDate,
  });
}
