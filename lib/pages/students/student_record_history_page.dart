import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/student_model.dart';
import '../../services/announcement_service.dart';
import '../../services/class_service.dart';
import '../../services/grade_record_service.dart';
import '../../services/student_service.dart';
import '../../theme/app_colors.dart';
import 'student_exam_history_view.dart';
import 'student_homework_history_view.dart';

enum StudentRecordHistoryType {
  lessonReport('수업 리포트 기록'),
  homework('숙제 기록'),
  exam('시험 기록'),
  attendance('출결 기록');

  final String title;
  const StudentRecordHistoryType(this.title);
}

class StudentRecordHistoryPage extends StatefulWidget {
  final String studentId;
  final StudentRecordHistoryType type;

  const StudentRecordHistoryPage({
    super.key,
    required this.studentId,
    required this.type,
  });

  @override
  State<StudentRecordHistoryPage> createState() =>
      _StudentRecordHistoryPageState();
}

class _StudentRecordHistoryPageState extends State<StudentRecordHistoryPage> {
  Student? _student;
  String _classDisplayName = '-';
  List<_RecordEntry> _entries = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    final classService = ClassService(prefs: prefs);
    final gradeRecordService = GradeRecordService(prefs: prefs);
    final announcementService = AnnouncementService(prefs: prefs);
    final student = await studentService.getStudentById(widget.studentId);
    if (student == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final classDisplayName =
        await classService.getDisplayNameById(student.classId) ??
        student.className ??
        '-';

    late final List<_RecordEntry> entries;
    switch (widget.type) {
      case StudentRecordHistoryType.lessonReport:
        final byClassId = await announcementService.getAnnouncementsByClassId(
          student.classId,
        );
        final reports = byClassId.isNotEmpty
            ? byClassId
            : (student.className == null
                  ? const []
                  : await announcementService.getAnnouncementsByClass(
                      student.className!,
                    ));
        entries =
            reports
                .map(
                  (item) => _RecordEntry(
                    date: item.createdAt,
                    title: item.title,
                    subtitle: classDisplayName,
                    body: item.content,
                  ),
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        break;
      case StudentRecordHistoryType.homework:
        entries = const [];
        break;
      case StudentRecordHistoryType.exam:
        entries = const [];
        break;
      case StudentRecordHistoryType.attendance:
        final attendance = await gradeRecordService.getStudentAttendance(
          student.id,
        );
        entries =
            attendance
                .map(
                  (record) => _RecordEntry(
                    date: record.date,
                    title: record.isPresent ? '출석' : '결석',
                    subtitle: classDisplayName,
                    body: (record.note?.trim().isNotEmpty ?? false)
                        ? record.note!.trim()
                        : null,
                  ),
                )
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        break;
    }

    if (!mounted) return;
    setState(() {
      _student = student;
      _classDisplayName = classDisplayName;
      _entries = entries;
      _isLoading = false;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final student = _student;
    return Scaffold(
      appBar: AppBar(title: Text(widget.type.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : student == null
          ? const Center(child: Text('학생 정보를 찾을 수 없습니다.'))
          : widget.type == StudentRecordHistoryType.homework
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StudentHomeworkHistoryView(
                  student: student,
                  classDisplayName: _classDisplayName,
                ),
              ],
            )
          : widget.type == StudentRecordHistoryType.exam
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StudentExamHistoryView(
                  student: student,
                  classDisplayName: _classDisplayName,
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${student.name} · $_classDisplayName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                if (_entries.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('저장된 기록이 없습니다.'),
                    ),
                  )
                else
                  ..._entries.map(
                    (entry) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatDate(entry.date),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.subText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              entry.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (entry.subtitle?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(
                                entry.subtitle!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.blue,
                                ),
                              ),
                            ],
                            if (entry.body?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              Text(
                                entry.body!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.subText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RecordEntry {
  final DateTime date;
  final String title;
  final String? subtitle;
  final String? body;

  const _RecordEntry({
    required this.date,
    required this.title,
    this.subtitle,
    this.body,
  });
}
