import '../data/korean_school_search.dart';
import '../data/models/class_model.dart';

/// 내신 클래스의 표시용 [ClassMeta.name]·[ClassMeta.grade]를 짧은 학교명 + `N학년` 형식으로 맞춘다.
ClassMeta applyInternalClassDisplayMigration(ClassMeta m) {
  if (m.programType != ClassProgramType.internalExam) return m;
  final sn = m.schoolName?.trim();
  if (sn == null || sn.isEmpty) return m;

  final tier = resolveTierForInput(
    sn,
    lockedTier: null,
    lockedStorageKey: null,
    currentText: sn,
  );

  final oldGrade = m.grade?.trim();
  if (oldGrade == null || oldGrade.isEmpty) return m;

  final newGrade = canonicalGradeForTier(oldGrade, tier);
  final resolvedGrade = newGrade ?? oldGrade;

  final short = shortSchoolDisplayName(sn);
  final newBase = '$short $resolvedGrade'.trim();

  final nameTrim = m.name.trim();
  final numbered = RegExp(r'^(.+?)\s+\((\d+)\)\s*$');
  final nmatch = numbered.firstMatch(nameTrim);
  final newName = nmatch != null ? '$newBase (${nmatch.group(2)})' : newBase;

  final gradeToStore = newGrade ?? resolvedGrade;
  final gradeChanged = gradeToStore != oldGrade;
  final nameChanged = newName != nameTrim;
  if (!gradeChanged && !nameChanged) return m;

  return m.copyWith(name: newName, grade: gradeToStore);
}
