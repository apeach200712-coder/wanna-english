import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/time_utils.dart';
import '../data/models/class_model.dart';
import '../data/models/exam_score_model.dart';
import '../data/models/grade_record_model.dart';
import '../data/models/homework_models.dart';
import '../data/models/student_model.dart';
import 'class_service.dart';
import 'exam_session_service.dart';
import 'grade_record_service.dart';
import 'homework_page_service.dart';
import 'student_service.dart';

enum HomeAlertType { homework, testRetake }

enum HomeAlertStatus { overdue, pending, completed }

extension HomeAlertStatusView on HomeAlertStatus {
  int get priority {
    switch (this) {
      case HomeAlertStatus.overdue:
        return 0;
      case HomeAlertStatus.pending:
        return 1;
      case HomeAlertStatus.completed:
        return 2;
    }
  }

  String get label {
    switch (this) {
      case HomeAlertStatus.overdue:
        return '기한 지남';
      case HomeAlertStatus.pending:
        return '확인 필요';
      case HomeAlertStatus.completed:
        return '완료';
    }
  }

  Color get color {
    switch (this) {
      case HomeAlertStatus.overdue:
        return const Color(0xFFD73A49);
      case HomeAlertStatus.pending:
        return const Color(0xFFCC8500);
      case HomeAlertStatus.completed:
        return const Color(0xFF2D8A5D);
    }
  }
}

class HomeAlertItem {
  final String className;
  /// Class meta id for navigation (homework / grade management).
  final String? classId;
  final String studentId;
  final String studentName;
  final HomeAlertStatus status;
  final String detail;
  final String? secondaryDetail;
  final DateTime anchorDate;
  final DateTime? dueAt;
  /// Set for threshold-based test retake rows (성적 관리 deep link).
  final String? examTypeId;
  final String? examTypeDisplayName;

  const HomeAlertItem({
    required this.className,
    this.classId,
    required this.studentId,
    required this.studentName,
    required this.status,
    required this.detail,
    required this.secondaryDetail,
    required this.anchorDate,
    this.dueAt,
    this.examTypeId,
    this.examTypeDisplayName,
  });
}

class HomeAlertGroup {
  final String className;
  final String? classId;
  final List<HomeAlertItem> items;

  const HomeAlertGroup({
    required this.className,
    this.classId,
    required this.items,
  });
}

class HomeAlertSnapshot {
  final List<HomeAlertGroup> homeworkGroups;
  final List<HomeAlertGroup> testRetakeGroups;

  const HomeAlertSnapshot({
    required this.homeworkGroups,
    required this.testRetakeGroups,
  });

  int countFor(HomeAlertType type) {
    return groupsFor(type).fold<int>(0, (sum, group) => sum + group.items.length);
  }

  List<HomeAlertGroup> groupsFor(HomeAlertType type) {
    switch (type) {
      case HomeAlertType.homework:
        return homeworkGroups;
      case HomeAlertType.testRetake:
        return testRetakeGroups;
    }
  }
}

class HomeAlertService {
  final ClassService _classService;
  final StudentService _studentService;
  final HomeworkPageService _homeworkService;
  final GradeRecordService _gradeRecordService;
  final ExamSessionService _examSessionService;

  HomeAlertService._({
    required ClassService classService,
    required StudentService studentService,
    required HomeworkPageService homeworkService,
    required GradeRecordService gradeRecordService,
    required ExamSessionService examSessionService,
  }) : _classService = classService,
       _studentService = studentService,
       _homeworkService = homeworkService,
       _gradeRecordService = gradeRecordService,
       _examSessionService = examSessionService;

  static Future<HomeAlertService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return HomeAlertService._(
      classService: ClassService(prefs: prefs),
      studentService: StudentService(prefs: prefs),
      homeworkService: HomeworkPageService(prefs: prefs),
      gradeRecordService: GradeRecordService(prefs: prefs),
      examSessionService: ExamSessionService(prefs: prefs),
    );
  }

  Future<HomeAlertSnapshot> build({String? className}) async {
    await _studentService.initializeMockStudents();
    await _classService.initializeFromMockIfNeeded();

    final allClasses = await _classService.getAllClasses();
    final displayItems = await _classService.getDisplayItems();
    final idToDisplayName = {
      for (final i in displayItems) i.id: i.displayName,
    };
    final targetClasses = className == null
        ? allClasses
        : _resolveTargetClasses(className, allClasses, displayItems);

    final allStudents = await _studentService.getAllStudents();
    final currentHomework = _homeworkService.getAllStudentResults();
    final historyHomework = _homeworkService.getAllHistoryEntries();
    final sessions = _examSessionService.getAllSessions();
    final wordExams = await _gradeRecordService.getAllWordExams();
    final now = nowKst();

    return HomeAlertSnapshot(
      homeworkGroups: _buildHomeworkGroups(
        targetClasses,
        allStudents,
        currentHomework,
        historyHomework,
        now,
        idToDisplayName,
      ),
      testRetakeGroups: _buildTestRetakeGroups(
        targetClasses,
        allStudents,
        sessions,
        wordExams,
        now,
        idToDisplayName,
      ),
    );
  }

  List<ClassMeta> _resolveTargetClasses(
    String key,
    List<ClassMeta> allClasses,
    List<ClassDisplayItem> displayItems,
  ) {
    final trimmed = key.trim();
    for (final item in displayItems) {
      if (item.displayName == trimmed || item.id == trimmed) {
        return [item.meta];
      }
    }
    return allClasses.where((c) => c.name == trimmed).toList();
  }

  List<HomeAlertGroup> _buildHomeworkGroups(
    List<ClassMeta> classes,
    List<Student> allStudents,
    List<StudentHomeworkResult> currentHomework,
    List<HomeworkHistoryEntry> historyHomework,
    DateTime now,
    Map<String, String> idToDisplayName,
  ) {
    final groups = <HomeAlertGroup>[];
    for (final classMeta in classes) {
      final students =
          allStudents.where((s) => s.classId == classMeta.id).toList();
      final window = _lessonWindowFor(classMeta, now);
      final current = currentHomework
          .where((item) => item.classId == classMeta.id)
          .toList();
      final history = historyHomework
          .where((item) => item.classId == classMeta.id)
          .toList();
      final items = <HomeAlertItem>[];

      final groupLabel =
          idToDisplayName[classMeta.id] ?? classMeta.name;
      for (final student in students) {
        final selected = _selectHomeworkAlert(
          student,
          groupLabel,
          current,
          history,
          window,
          now,
        );
        if (selected != null) {
          items.add(selected);
        }
      }

      items.sort(_compareAlertItems);
      if (items.isNotEmpty) {
        groups.add(
          HomeAlertGroup(
            className: groupLabel,
            classId: classMeta.id,
            items: items,
          ),
        );
      }
    }
    return groups;
  }

  HomeAlertItem? _selectHomeworkAlert(
    Student student,
    String className,
    List<StudentHomeworkResult> current,
    List<HomeworkHistoryEntry> history,
    _LessonWindow window,
    DateTime now,
  ) {
    final candidates = <HomeAlertItem>[];

    for (final result in current.where(
      (item) => item.studentId == student.id,
    )) {
      final anchorDate = DateTime.tryParse(result.weekStartDate);
      if (anchorDate == null) continue;
      final status = _homeworkStatusFromCurrent(
        result,
        window,
        now,
        anchorDate,
      );
      if (!_includeByWindow(anchorDate, status, window)) continue;

      candidates.add(
        HomeAlertItem(
          className: className,
          classId: student.classId,
          studentId: student.id,
          studentName: student.name,
          status: status,
          detail: _buildHomeworkDetail(result),
          secondaryDetail: _buildHomeworkSecondary(result),
          anchorDate: anchorDate,
          dueAt: _homeworkDueAt(result, window),
        ),
      );
    }

    for (final entry in history) {
      final record = entry.studentResults
          .where((item) => item.studentId == student.id)
          .cast<HomeworkHistoryStudentResult?>()
          .firstWhere((item) => item != null, orElse: () => null);
      if (record == null) continue;
      final anchorDate = DateTime.tryParse(entry.date);
      if (anchorDate == null) continue;
      final status = _homeworkStatusFromHistory(
        record,
        window,
        now,
        anchorDate,
      );
      if (!_includeByWindow(anchorDate, status, window)) continue;

      candidates.add(
        HomeAlertItem(
          className: className,
          classId: student.classId,
          studentId: student.id,
          studentName: student.name,
          status: status,
          detail: _buildHomeworkHistoryDetail(record),
          secondaryDetail: _buildHomeworkHistorySecondary(record),
          anchorDate: anchorDate,
          dueAt: _historyHomeworkDueAt(record, window),
        ),
      );
    }

    if (candidates.isEmpty) return null;
    candidates.sort(_compareAlertItems);
    return candidates.first;
  }

  /// All [ExamSession] threshold-based retakes + legacy 단어시험 (numeric threshold).
  /// 등급형·리뷰 레거시(등급 기준)는 제외.
  List<HomeAlertGroup> _buildTestRetakeGroups(
    List<ClassMeta> classes,
    List<Student> allStudents,
    List<ExamSession> sessions,
    List<WordExamRecord> wordExams,
    DateTime now,
    Map<String, String> idToDisplayName,
  ) {
    final groups = <HomeAlertGroup>[];
    for (final classMeta in classes) {
      final students =
          allStudents.where((s) => s.classId == classMeta.id).toList();
      final window = _lessonWindowFor(classMeta, now);
      final classSessions = sessions.where((item) {
        if (item.className != classMeta.name) return false;
        return item.isThresholdBased && item.retakeThreshold != null;
      }).toList();
      final classWordLegacy = wordExams
          .where((item) => item.className == classMeta.name)
          .toList();
      final items = <HomeAlertItem>[];

      final groupLabel =
          idToDisplayName[classMeta.id] ?? classMeta.name;
      for (final student in students) {
        final item = _selectTestRetakeAlert(
          student,
          classMeta,
          groupLabel,
          classSessions,
          classWordLegacy,
          window,
          now,
        );
        if (item != null) {
          items.add(item);
        }
      }

      items.sort(_compareAlertItems);
      if (items.isNotEmpty) {
        groups.add(
          HomeAlertGroup(
            className: groupLabel,
            classId: classMeta.id,
            items: items,
          ),
        );
      }
    }
    return groups;
  }

  /// 두 번째 줄: 유형명 + 점수 (메인 스타일). `examTypeDisplayName` 우선.
  String _buildTestRetakeScoreLine(ExamSession session, ExamStudentScore score) {
    final label = session.examTypeDisplayName.trim().isNotEmpty
        ? session.examTypeDisplayName.trim()
        : session.examName.trim();
    final max = session.maxScore == null
        ? '점'
        : '/${_formatScore(session.maxScore!)}점';
    return '$label ${_formatScore(score.score!)}$max';
  }

  /// 세 번째 줄 이하: 작은 회색용. 줄바꿈으로만 구분(가운데점 없음).
  String? _buildTestRetakeGrayLines(
    ExamSession session,
    ExamStudentScore score,
    HomeAlertStatus status,
  ) {
    final lines = <String>[];
    final belowThreshold = session.retakeThreshold != null &&
        score.score != null &&
        score.score! < session.retakeThreshold!;
    if (belowThreshold && score.retakeScore == null) {
      lines.add('기준 ${_formatScore(session.retakeThreshold!)}점 미만');
    }
    if (score.retakeScore != null) {
      lines.add('재시험 ${_formatScore(score.retakeScore!)}점');
    } else if (status != HomeAlertStatus.completed &&
        session.retakeScheduledDates.isNotEmpty) {
      final first = session.retakeScheduledDates
          .whereType<DateTime?>()
          .firstWhere((value) => value != null, orElse: () => null);
      if (first != null) {
        lines.add('재시험 예정 ${_formatDateTime(first)}');
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  HomeAlertItem? _selectTestRetakeAlert(
    Student student,
    ClassMeta classMeta,
    String groupLabel,
    List<ExamSession> sessions,
    List<WordExamRecord> wordLegacy,
    _LessonWindow window,
    DateTime now,
  ) {
    final candidates = <HomeAlertItem>[];
    final cid = classMeta.id;

    for (final session in sessions) {
      final score = session.scores
          .where((item) => item.studentId == student.id)
          .cast<ExamStudentScore?>()
          .firstWhere((item) => item != null, orElse: () => null);
      if (score == null || score.score == null) continue;
      final requiresRetake =
          session.retakeThreshold != null &&
          score.score! < session.retakeThreshold!;
      final completed = !requiresRetake || score.retakeScore != null;
      final dueAt = _sessionDueAt(session, window);
      final status = completed
          ? HomeAlertStatus.completed
          : (session.examDate.isBefore(window.start) || now.isAfter(dueAt)
                ? HomeAlertStatus.overdue
                : HomeAlertStatus.pending);
      if (!_includeByWindow(session.examDate, status, window)) continue;

      final gray = _buildTestRetakeGrayLines(session, score, status);
      candidates.add(
        HomeAlertItem(
          className: groupLabel,
          classId: cid,
          studentId: student.id,
          studentName: student.name,
          status: status,
          detail: _buildTestRetakeScoreLine(session, score),
          secondaryDetail: gray,
          examTypeId: session.examTypeId,
          examTypeDisplayName: session.examTypeDisplayName,
          anchorDate: session.examDate,
          dueAt: dueAt,
        ),
      );
    }

    for (final record in wordLegacy.where(
      (item) => item.studentId == student.id,
    )) {
      final status = !record.needsRetake || record.retakeScore != null
          ? HomeAlertStatus.completed
          : (record.createdAt.isBefore(window.start) || now.isAfter(window.end)
                ? HomeAlertStatus.overdue
                : HomeAlertStatus.pending);
      if (!_includeByWindow(record.createdAt, status, window)) continue;

      final line =
          '${ExamCategory.vocabulary.label} ${record.score}/${record.totalScore}점';
      final sec = record.retakeScore != null
          ? '재시험 완료 ${record.retakeScore}점'
          : '기준 ${record.retakePassingScore}점 미만';
      candidates.add(
        HomeAlertItem(
          className: groupLabel,
          classId: cid,
          studentId: student.id,
          studentName: student.name,
          status: status,
          detail: line,
          secondaryDetail: sec,
          examTypeId: ClassExamTypeIds.vocabulary,
          examTypeDisplayName: ExamCategory.vocabulary.label,
          anchorDate: record.createdAt,
          dueAt: window.end,
        ),
      );
    }

    if (candidates.isEmpty) return null;
    candidates.sort(_compareAlertItems);
    return candidates.first;
  }

  bool _includeByWindow(
    DateTime anchorDate,
    HomeAlertStatus status,
    _LessonWindow window,
  ) {
    if (status != HomeAlertStatus.completed) return true;
    return !anchorDate.isBefore(window.start) &&
        anchorDate.isBefore(window.end);
  }

  HomeAlertStatus _homeworkStatusFromCurrent(
    StudentHomeworkResult result,
    _LessonWindow window,
    DateTime now,
    DateTime anchorDate,
  ) {
    if (_isHomeworkCompleted(result)) {
      return HomeAlertStatus.completed;
    }
    final dueAt = _homeworkDueAt(result, window);
    if (anchorDate.isBefore(window.start) || now.isAfter(dueAt)) {
      return HomeAlertStatus.overdue;
    }
    return HomeAlertStatus.pending;
  }

  HomeAlertStatus _homeworkStatusFromHistory(
    HomeworkHistoryStudentResult result,
    _LessonWindow window,
    DateTime now,
    DateTime anchorDate,
  ) {
    if (_isHistoryHomeworkCompleted(result)) {
      return HomeAlertStatus.completed;
    }
    final dueAt = _historyHomeworkDueAt(result, window);
    if (anchorDate.isBefore(window.start) || now.isAfter(dueAt)) {
      return HomeAlertStatus.overdue;
    }
    return HomeAlertStatus.pending;
  }

  bool _isHomeworkCompleted(StudentHomeworkResult result) {
    return result.resubmission.status ==
            ResubmissionStatus.submittedAfterResubmission ||
        (result.resubmission.status == ResubmissionStatus.none &&
            result.finalCompletionRate >= 100);
  }

  bool _isHistoryHomeworkCompleted(HomeworkHistoryStudentResult result) {
    return result.resubmission.status ==
            ResubmissionStatus.submittedAfterResubmission ||
        (result.resubmission.status == ResubmissionStatus.none &&
            (result.finalCompletionRate ?? 0) >= 100);
  }

  DateTime _homeworkDueAt(StudentHomeworkResult result, _LessonWindow window) {
    final dueDate = result.resubmission.dueDate;
    if (dueDate == null) return window.end;
    final parsed = DateTime.tryParse(dueDate);
    if (parsed == null) return window.end;
    return DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
  }

  DateTime _historyHomeworkDueAt(
    HomeworkHistoryStudentResult result,
    _LessonWindow window,
  ) {
    final dueDate = result.resubmission.dueDate;
    if (dueDate == null) return window.end;
    final parsed = DateTime.tryParse(dueDate);
    if (parsed == null) return window.end;
    return DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
  }

  DateTime _sessionDueAt(ExamSession session, _LessonWindow window) {
    for (final scheduled in session.retakeScheduledDates) {
      if (scheduled != null) {
        return DateTime(
          scheduled.year,
          scheduled.month,
          scheduled.day,
          23,
          59,
          59,
        );
      }
    }
    return window.end;
  }

  String _buildHomeworkDetail(StudentHomeworkResult result) {
    final missing = result.sections
        .where((section) => section.checkCount < 5)
        .map(_formatHomeworkSection)
        .take(3)
        .toList();
    if (missing.isNotEmpty) {
      return '미완료: ${missing.join(' · ')}';
    }
    return '미완료 항목 없음';
  }

  String? _buildHomeworkSecondary(StudentHomeworkResult result) {
    final lines = <String>['완성도 ${result.finalCompletionRate}%'];
    if (result.resubmission.dueDate != null) {
      lines.add('기한 ${_formatDate(result.resubmission.dueDate!)}');
    }
    return lines.join('\n');
  }

  String _buildHomeworkHistoryDetail(HomeworkHistoryStudentResult result) {
    if (result.finalCompletionRate == null) {
      return '숙제 확인 필요';
    }
    return '미완료';
  }

  String? _buildHomeworkHistorySecondary(HomeworkHistoryStudentResult result) {
    final lines = <String>[];
    final rate = result.finalCompletionRate;
    if (rate != null) {
      lines.add('완성도 $rate%');
    }
    if (result.resubmission.dueDate != null) {
      lines.add('재제출 기한 ${_formatDate(result.resubmission.dueDate!)}');
    } else if (result.resubmission.status ==
        ResubmissionStatus.submittedAfterResubmission) {
      lines.add('재제출 완료');
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  String _formatHomeworkSection(HomeworkSection section) {
    final parts = <String>[section.sectionName];
    if ((section.subSection ?? '').trim().isNotEmpty) {
      parts.add(section.subSection!.trim());
    }
    return parts.join(' ');
  }

  int _compareAlertItems(HomeAlertItem a, HomeAlertItem b) {
    final statusCompare = a.status.priority.compareTo(b.status.priority);
    if (statusCompare != 0) return statusCompare;

    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue != null && bDue != null) {
      final dueCompare = aDue.compareTo(bDue);
      if (dueCompare != 0) return dueCompare;
    } else if (aDue != null) {
      return -1;
    } else if (bDue != null) {
      return 1;
    }

    final anchorCompare = b.anchorDate.compareTo(a.anchorDate);
    if (anchorCompare != 0) return anchorCompare;
    return a.studentName.compareTo(b.studentName);
  }

  _LessonWindow _lessonWindowFor(ClassMeta classMeta, DateTime now) {
    final schedules = classMeta.effectiveSchedules;
    if (schedules.isEmpty) {
      return _LessonWindow(
        start: now.subtract(const Duration(days: 7)),
        end: now.add(const Duration(days: 7)),
      );
    }

    final today = DateTime(now.year, now.month, now.day);
    DateTime? lastLesson;
    DateTime? nextLesson;

    for (int offset = -14; offset <= 14; offset++) {
      final date = today.add(Duration(days: offset));
      for (final schedule in schedules) {
        if (schedule.weekday != date.weekday) continue;
        final time = _parseMeetingTime(schedule.time);
        final candidate = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        if (!candidate.isAfter(now)) {
          if (lastLesson == null || candidate.isAfter(lastLesson)) {
            lastLesson = candidate;
          }
        }
        if (candidate.isAfter(now)) {
          if (nextLesson == null || candidate.isBefore(nextLesson)) {
            nextLesson = candidate;
          }
        }
      }
    }

    lastLesson ??= now.subtract(const Duration(days: 7));
    nextLesson ??= now.add(const Duration(days: 7));
    return _LessonWindow(start: lastLesson, end: nextLesson);
  }

  TimeOfDay _parseMeetingTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
    final parts = raw.split(':');
    if (parts.length != 2) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.month}.${parsed.day}';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}.${value.day} $hour:$minute';
  }

  String _formatScore(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _LessonWindow {
  final DateTime start;
  final DateTime end;

  const _LessonWindow({required this.start, required this.end});
}
