part of 'homework_page.dart';

// ─── Tab enum ─────────────────────────────────────────────────────────────────

enum _Tab { thisWeek, lastWeeks, nextWeek }

extension _TabLabel on _Tab {
  String get label {
    switch (this) {
      case _Tab.thisWeek:
        return 'THIS WEEK';
      case _Tab.lastWeeks:
        return 'LAST WEEKS';
      case _Tab.nextWeek:
        return 'NEXT WEEK';
    }
  }
}

// ─── Per-section editing state ────────────────────────────────────────────────

class _SectionRow {
  final String sectionId;
  String? categoryId;
  String sectionName;
  String? subSection;
  int checkCount = 0;
  bool detailExpanded = false;
  final TextEditingController detailCtrl;

  _SectionRow({
    required this.sectionId,
    this.categoryId,
    required this.sectionName,
    this.subSection,
    int? checkCount,
    String detailMemo = '',
  }) : checkCount = checkCount ?? 0,
       detailCtrl = TextEditingController(text: detailMemo);

  HomeworkSection toSection() => HomeworkSection(
    sectionId: sectionId,
    categoryId: categoryId,
    sectionName: sectionName,
    subSection: (subSection?.trim().isNotEmpty == true) ? subSection : null,
    detailMemo: detailCtrl.text.trim().isEmpty ? null : detailCtrl.text.trim(),
    checkCount: checkCount,
  );

  void dispose() => detailCtrl.dispose();
}

// ─── Per-student editing state ────────────────────────────────────────────────

class _StudentState {
  final Student student;
  List<_SectionRow> rows;
  HomeworkCompletionMode mode;
  int? manualRate;
  final TextEditingController manualCtrl;
  ResubmissionInfo resubmission;

  _StudentState({
    required this.student,
    required this.rows,
    this.mode = HomeworkCompletionMode.auto,
    this.manualRate,
    ResubmissionInfo? resubmission,
  }) : manualCtrl = TextEditingController(
         text: manualRate != null ? manualRate.toString() : '',
       ),
       resubmission = resubmission ?? const ResubmissionInfo();

  int get autoRate => StudentHomeworkResult.computeAutoRate(
    rows.map((r) => r.toSection()).toList(),
  );

  int get finalRate {
    if (mode == HomeworkCompletionMode.direct && manualRate != null) {
      return manualRate!;
    }
    return autoRate;
  }

  bool get isEvaluated =>
      rows.any((r) => r.checkCount > 0) ||
      (mode == HomeworkCompletionMode.direct && manualRate != null);

  StudentHomeworkResult toResult(String classId, String weekStartDate) {
    final sections = rows.map((r) => r.toSection()).toList();
    final ar = StudentHomeworkResult.computeAutoRate(sections);
    final fr = mode == HomeworkCompletionMode.direct && manualRate != null
        ? manualRate!
        : ar;
    return StudentHomeworkResult(
      id: const Uuid().v4(),
      classId: classId,
      studentId: student.id,
      studentName: student.name,
      weekStartDate: weekStartDate,
      sections: sections,
      calculationMode: mode,
      manualCompletionRate: mode == HomeworkCompletionMode.direct
          ? manualRate
          : null,
      autoCompletionRate: ar,
      finalCompletionRate: fr,
      isEvaluated: isEvaluated,
      resubmission: resubmission,
    );
  }

  void dispose() {
    manualCtrl.dispose();
    for (final r in rows) {
      r.dispose();
    }
  }
}
