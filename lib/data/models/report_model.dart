class ClassReportSummary {
  final String className;
  final int studentCount;
  final double attendanceRate;
  final double homeworkCompletionRate;
  final double wordExamAverage;
  final int warningStudentCount;

  const ClassReportSummary({
    required this.className,
    required this.studentCount,
    required this.attendanceRate,
    required this.homeworkCompletionRate,
    required this.wordExamAverage,
    required this.warningStudentCount,
  });
}

class StudentRiskItem {
  final String studentId;
  final String studentName;
  final String className;
  final List<String> reasons;

  const StudentRiskItem({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.reasons,
  });
}

class WeeklyOverview {
  final DateTime generatedAt;
  final int totalStudents;
  final double attendanceRate;
  final double homeworkCompletionRate;
  final double wordExamAverage;

  const WeeklyOverview({
    required this.generatedAt,
    required this.totalStudents,
    required this.attendanceRate,
    required this.homeworkCompletionRate,
    required this.wordExamAverage,
  });
}

class StudentReportDetail {
  final String studentId;
  final String studentName;
  final String className;
  final int attendancePresent;
  final int attendanceAbsent;
  final int latestHomeworkCompletion;
  final int? latestWordExamScore;
  final int? latestWordExamTotalScore;
  final String? latestReviewGrade;
  final bool needsAttention;

  const StudentReportDetail({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.attendancePresent,
    required this.attendanceAbsent,
    required this.latestHomeworkCompletion,
    required this.latestWordExamScore,
    required this.latestWordExamTotalScore,
    required this.latestReviewGrade,
    required this.needsAttention,
  });
}
