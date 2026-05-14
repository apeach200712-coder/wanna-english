import '../data/models/exam_score_model.dart';
import '../data/models/grade_record_model.dart';
import '../data/models/homework_models.dart';
import '../data/models/student_grade_model.dart';
import '../data/models/student_model.dart';
import 'exam_session_service.dart';
import 'grade_service.dart';
import 'grade_record_service.dart';
import 'homework_page_service.dart';
import 'lesson_content_service.dart';

class AnnouncementMessageGenerator {
  final String academyLabel;
  final GradeRecordService _gradeRecordService;
  final GradeService _gradeService;
  final HomeworkPageService _homeworkPageService;
  final ExamSessionService _examSessionService;
  final LessonContentService _lessonContentService;

  AnnouncementMessageGenerator({
    required this.academyLabel,
    required GradeRecordService gradeRecordService,
    required GradeService gradeService,
    required HomeworkPageService homeworkPageService,
    required ExamSessionService examSessionService,
    required LessonContentService lessonContentService,
  }) : _gradeRecordService = gradeRecordService,
       _gradeService = gradeService,
       _homeworkPageService = homeworkPageService,
       _examSessionService = examSessionService,
       _lessonContentService = lessonContentService;

  Future<String> generateStudentMessage(Student student) async {
    final snapshot = await _gradeRecordService.getSnapshot();
    final gradeRecords = await _gradeService.getAllGradeRecords();
    return _generateStudentMessageFromSnapshot(student, snapshot, gradeRecords);
  }

  Future<String> _generateStudentMessageFromSnapshot(
    Student student,
    GradeRecordSnapshot snapshot,
    List<GradeRecord> gradeRecords,
  ) async {
    final sections = <_MessageSection>[];
    final today = _today();
    final className = student.className;
    if (className == null || className.isEmpty) {
      return '[$academyLabel] ${student.name} 학생 금일 수업 리포트\n\n* 소속 클래스 정보를 찾을 수 없습니다.';
    }

    final studentHomework =
        snapshot.homework
            .where(
              (record) =>
                  record.studentId == student.id &&
                  _isSameDay(
                    DateTime.fromMillisecondsSinceEpoch(record.createdAt),
                    today,
                  ),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final homework = studentHomework.isEmpty ? null : studentHomework.first;
    final todayResult = _todayHomeworkResult(
      classId: student.classId,
      className: className,
      studentId: student.id,
      today: today,
    );
    final completionRate =
        todayResult?.finalCompletionRate ?? homework?.finalCompletionRate;

    final homeworkSection = _buildHomeworkSection(
      homeworkTitle: homework?.title,
      completionRate: completionRate,
      homework: homework,
      todayResult: todayResult,
    );
    sections.add(homeworkSection);

    final todaySessions = _examSessionService.getSessions(
      className: className,
      examDate: today,
    );
    final latestSession = todaySessions.isEmpty ? null : todaySessions.first;
    sections.addAll(
      _buildExamSectionsForStudent(
        student,
        latestSession,
        snapshot,
        gradeRecords,
        today,
      ),
    );

    final lessonContent = await _lessonContentService.getLessonContent(
      className,
    );
    if (lessonContent.isNotEmpty) {
      sections.add(_MessageSection(title: '오늘 수업 내용', lines: lessonContent));
    }

    final nextWeek = _homeworkPageService.getNextWeek(
      student.classId,
      fallbackKeys: [className],
    );
    if (nextWeek != null && nextWeek.items.isNotEmpty) {
      sections.add(_MessageSection(title: '다음 숙제', lines: nextWeek.items));
    }

    final buffer = StringBuffer();
    buffer.writeln('[$academyLabel] ${student.name} 학생 금일 수업 리포트');
    for (final section in sections) {
      if (section.lines.isEmpty) continue;
      buffer.writeln();
      buffer.writeln(section.title);
      buffer.writeln();
      for (final line in section.lines) {
        buffer.writeln('* $line');
      }
    }

    return buffer.toString().trimRight();
  }

  StudentHomeworkResult? _todayHomeworkResult({
    required String classId,
    required String className,
    required String studentId,
    required DateTime today,
  }) {
    final todayKey = _dateKey(today);
    final results = _homeworkPageService.getAllStudentResults().where(
      (result) =>
          (result.classId == className || result.classId == classId) &&
          result.studentId == studentId &&
          result.weekStartDate == todayKey,
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  _MessageSection _buildHomeworkSection({
    required String? homeworkTitle,
    required int? completionRate,
    required HomeworkRecord? homework,
    required StudentHomeworkResult? todayResult,
  }) {
    if (completionRate == null && homework == null && todayResult == null) {
      return const _MessageSection(title: '오늘 숙제 확인', lines: ['금일 숙제 없습니다.']);
    }

    final lines = <String>[];
    if (homeworkTitle != null && homeworkTitle.trim().isNotEmpty) {
      lines.add(homeworkTitle.trim());
    }
    if (completionRate != null) {
      lines.add('완성도: $completionRate%');
    }

    final incompleteItems = <String>{};
    if (homework != null) {
      for (final section in homework.sections) {
        if (section.checkCount >= 5) continue;
        final label = _homeworkItemLabel(section);
        if (label.isNotEmpty) {
          incompleteItems.add(label);
        }
      }
    }

    if (completionRate == 100 && incompleteItems.isEmpty) {
      lines.add('모든 항목을 완료했습니다.');
    } else if (incompleteItems.isNotEmpty) {
      lines.add('미완성 항목: ${incompleteItems.join(', ')}');
    } else if (completionRate != null && completionRate < 100) {
      lines.add('미완성 항목이 있습니다.');
    }

    final info = todayResult?.resubmission;
    if (info != null) {
      if (info.status == ResubmissionStatus.resubmissionRequired &&
          info.dueDate?.isNotEmpty == true) {
        lines.add('재제출 기한: ${_formatDueDate(info.dueDate!)}');
      } else if (info.status == ResubmissionStatus.submittedAfterResubmission) {
        lines.add('재제출: 제출 완료');
      }
    }

    return lines.isEmpty
        ? const _MessageSection(title: '오늘 숙제 확인', lines: ['금일 숙제 없습니다.'])
        : _MessageSection(title: '오늘 숙제 확인', lines: lines);
  }

  List<_MessageSection> _buildExamSectionsForStudent(
    Student student,
    ExamSession? session,
    GradeRecordSnapshot snapshot,
    List<GradeRecord> gradeRecords,
    DateTime today,
  ) {
    if (session != null) {
      final report = _buildCurrentExamSections(student, session);
      if (report.isNotEmpty) {
        return report;
      }
    }
    return _buildLegacyExamSections(student, snapshot, gradeRecords, today);
  }

  List<_MessageSection> _buildCurrentExamSections(
    Student student,
    ExamSession session,
  ) {
    ExamStudentScore? score;
    for (final s in session.scores) {
      if (s.studentId == student.id) {
        score = s;
        break;
      }
    }
    if (score == null || score.score == null) return const [];

    final entered = session.scores.where((s) => s.score != null).toList();
    final avg = entered.isEmpty
        ? null
        : entered.map((e) => e.score!).reduce((a, b) => a + b) / entered.length;
    final examLines = <String>[];
    _MessageSection? retakeSection;
    final examName = session.examName.isNotEmpty
        ? session.examName
        : session.examTypeDisplayName;

    if (session.isThresholdBased &&
        session.examTypeId == ClassExamTypeIds.reviewTest) {
      final max = session.maxScore?.toStringAsFixed(0) ?? '?';
      final threshold = session.retakeThreshold;
      final needsRetake = threshold != null && score.score! < threshold;
      final hasFinal = score.retakeScore != null;
      final scheduledDate = session.retakeScheduledDates.isNotEmpty
          ? session.retakeScheduledDates.first
          : null;
      examLines.add(examName);
      examLines.add('1차: ${score.score!.toStringAsFixed(0)}점 / $max점');
      examLines.add('반 평균: ${avg?.toStringAsFixed(1) ?? '-'}점');
      if (threshold != null) {
        examLines.add('재시험 기준: ${threshold.toStringAsFixed(0)}점 미만');
      }
      examLines.add('결과: ${needsRetake ? '재시험 대상' : '통과'}');
      if (hasFinal) {
        examLines.add(
          '최종: ${score.retakeScore!.toStringAsFixed(0)}점 / $max점',
        );
        examLines.add('재시험 완료');
      } else if (needsRetake) {
        final retakeLines = <String>['금일 재시험 미응시'];
        if (scheduledDate != null) {
          retakeLines.add(
            '재시험 예정일: ${_fmtShortDateWithWeekday(scheduledDate)}',
          );
        }
        retakeSection = _MessageSection(title: '재시험 안내', lines: retakeLines);
      }
    } else if (session.isThresholdBased) {
      final max = session.maxScore?.toStringAsFixed(0) ?? '?';
      final threshold = session.retakeThreshold;
      final needsRetake = threshold != null && score.score! < threshold;
      final scheduledDate = session.retakeScheduledDates.isNotEmpty
          ? session.retakeScheduledDates.first
          : null;
      examLines.add(examName);
      examLines.add('${score.score!.toStringAsFixed(0)}점 / $max점');
      examLines.add('반 평균: ${avg?.toStringAsFixed(1) ?? '-'}점');
      if (threshold != null) {
        examLines.add('재시험 기준: ${threshold.toStringAsFixed(0)}점 미만');
      }
      examLines.add('결과: ${needsRetake ? '재시험 대상' : '통과'}');
      if (needsRetake) {
        final retakeLines = <String>['금일 재시험 미응시'];
        if (scheduledDate != null) {
          retakeLines.add(
            '재시험 예정일: ${_fmtShortDateWithWeekday(scheduledDate)}',
          );
        }
        retakeSection = _MessageSection(title: '재시험 안내', lines: retakeLines);
      }
    } else if (session.examTypeId == ClassExamTypeIds.internal) {
      final classAvg = avg;
      final stddev = session.standardDeviation;
      final z = (stddev != null && stddev > 0 && classAvg != null)
          ? (score.score! - classAvg) / stddev
          : 0.0;
      final g5 = _gradeFromZ(z, isFiveScale: true);
      examLines.add(examName);
      examLines.add('원점수: ${score.score!.toStringAsFixed(0)}점');
      examLines.add('반 평균: ${classAvg?.toStringAsFixed(1) ?? '-'}점');
      examLines.add('5등급제 기준: $g5등급');
    } else {
      final classAvg = avg;
      final stddev = session.standardDeviation;
      final z = (stddev != null && stddev > 0 && classAvg != null)
          ? (score.score! - classAvg) / stddev
          : 0.0;
      final g5 = _gradeFromZ(z, isFiveScale: true);
      final g9 = _gradeFromZ(z, isFiveScale: false);
      examLines.add(examName);
      examLines.add('원점수: ${score.score!.toStringAsFixed(0)}점');
      examLines.add('반 평균: ${classAvg?.toStringAsFixed(1) ?? '-'}점');
      if (score.percentile != null) {
        examLines.add('백분위: ${score.percentile!.toStringAsFixed(0)}');
      }
      examLines.add('5등급제 기준: $g5등급');
      examLines.add('9등급제 기준: $g9등급');
    }

    final sections = <_MessageSection>[];
    if (examLines.isNotEmpty) {
      sections.add(_MessageSection(title: '오늘 시험', lines: examLines));
    }
    if (retakeSection != null) {
      sections.add(retakeSection);
    }
    return sections;
  }

  int _gradeFromZ(double z, {required bool isFiveScale}) {
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

  String _fmtShortDateWithWeekday(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${date.month}.${date.day.toString().padLeft(2, '0')} (${weekdays[date.weekday - 1]})';
  }

  List<_MessageSection> _buildLegacyExamSections(
    Student student,
    GradeRecordSnapshot snapshot,
    List<GradeRecord> gradeRecords,
    DateTime today,
  ) {
    final sections = <_MessageSection>[];

    final todayVocabulary =
        gradeRecords
            .where(
              (record) =>
                  record.className == student.className &&
                  record.examType == ExamType.vocabulary &&
                  _isSameDay(record.examDate, today),
            )
            .toList()
          ..sort((a, b) => b.examDate.compareTo(a.examDate));
    final vocabularyRecord = todayVocabulary.isEmpty
        ? null
        : todayVocabulary.first;
    if (vocabularyRecord != null) {
      final grade = vocabularyRecord.grades.cast<StudentGrade?>().firstWhere(
        (item) => item?.studentId == student.id,
        orElse: () => null,
      );
      if (grade != null) {
        final classAverage = vocabularyRecord.grades.isEmpty
            ? null
            : vocabularyRecord.grades
                      .map((item) => item.score)
                      .reduce((a, b) => a + b) /
                  vocabularyRecord.grades.length;
        sections.add(
          _MessageSection(
            title: '오늘 시험',
            lines: [
              vocabularyRecord.examType.label,
              '${grade.score.toStringAsFixed(0)}점 / 100점',
              '반 평균: ${classAverage?.toStringAsFixed(1) ?? '-'}점',
            ],
          ),
        );
        return sections;
      }
    }

    final studentWordExams =
        snapshot.wordExams
            .where(
              (record) =>
                  record.studentId == student.id &&
                  _isSameDay(record.createdAt, today),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final wordExam = studentWordExams.isEmpty ? null : studentWordExams.first;
    if (wordExam != null) {
      sections.add(
        _MessageSection(
          title: '오늘 시험',
          lines: [
            '단어시험',
            '${wordExam.score}점 / ${wordExam.totalScore}점',
            '반 평균: ${wordExam.classAverage.toStringAsFixed(1)}점',
            '재시험 기준: ${wordExam.retakePassingScore}점 미만',
            '결과: ${wordExam.needsRetake ? '재시험 대상' : '통과'}',
            if (wordExam.retakeScore != null)
              '최종: ${wordExam.retakeScore}점 / ${wordExam.totalScore}점',
          ],
        ),
      );
      return sections;
    }

    final studentReviewExams =
        snapshot.reviewExams
            .where(
              (record) =>
                  record.studentId == student.id &&
                  _isSameDay(record.createdAt, today),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final reviewExam = studentReviewExams.isEmpty
        ? null
        : studentReviewExams.first;
    if (reviewExam != null) {
      sections.add(
        _MessageSection(
          title: '오늘 시험',
          lines: [
            '리뷰테스트',
            '성적: ${reviewExam.grade.label}',
            '반 평균: ${reviewExam.classAverage.label}',
            '결과: ${reviewExam.needsRetake ? '재시험 대상' : '통과'}',
            if (reviewExam.retakeGrade != null)
              '재시험 완료: ${reviewExam.retakeGrade!.label}',
          ],
        ),
      );
    }

    if (sections.isEmpty) {
      return const [
        _MessageSection(title: '오늘 시험', lines: ['금일 시험 없습니다.']),
      ];
    }

    return sections;
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _homeworkItemLabel(HomeworkSection section) {
    final subSection = section.subSection?.trim() ?? '';
    final detailMemo = section.detailMemo?.trim() ?? '';
    final value = [
      subSection,
      detailMemo,
    ].where((item) => item.isNotEmpty).join(' ').trim();
    if (value.isNotEmpty) return value;
    return section.sectionName.trim();
  }

  String _formatDueDate(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    final now = DateTime.now();
    final isToday =
        parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
    if (isToday) return '오늘';
    return '${parsed.month}.${parsed.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, String>> generateMessagesForClass(
    String className,
    List<Student> students,
  ) async {
    final snapshot = await _gradeRecordService.getSnapshot();
    final gradeRecords = await _gradeService.getAllGradeRecords();
    final messages = <String, String>{};
    for (final student in students) {
      if (student.className == className) {
        messages[student.id] = await _generateStudentMessageFromSnapshot(
          student,
          snapshot,
          gradeRecords,
        );
      }
    }
    return messages;
  }
}

class _MessageSection {
  final String title;
  final List<String> lines;

  const _MessageSection({required this.title, required this.lines});
}
