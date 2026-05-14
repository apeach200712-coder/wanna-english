import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/student_model.dart';
import '../../services/class_service.dart';
import '../../services/student_service.dart';
import '../../theme/app_colors.dart';
import 'student_counsel_memo_page.dart';
import 'student_edit_page.dart';
import 'student_record_history_page.dart';

class StudentDetailPage extends StatefulWidget {
  final String studentId;

  const StudentDetailPage({super.key, required this.studentId});

  @override
  State<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends State<StudentDetailPage> {
  Student? _student;
  String _classDisplayName = '-';
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

    final student = await studentService.getStudentById(widget.studentId);
    final classDisplayName = student == null
        ? '-'
        : await classService.getDisplayNameById(student.classId) ??
              student.className ??
              StudentService.unassignedGroupLabel;

    if (!mounted) return;
    setState(() {
      _student = student;
      _classDisplayName = classDisplayName;
      _isLoading = false;
    });
  }

  Future<void> _openEditPage() async {
    final student = _student;
    if (student == null) return;

    final didSave = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StudentEditPage(studentId: student.id)),
    );
    if (didSave == true) {
      await _load();
    }
  }

  Future<void> _openRecordPage(StudentRecordHistoryType type) async {
    final student = _student;
    if (student == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StudentRecordHistoryPage(studentId: student.id, type: type),
      ),
    );
  }

  Future<void> _openCounselMemoPage() async {
    final student = _student;
    if (student == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentCounselMemoPage(studentId: student.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final student = _student;
    if (student == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('학생 상세')),
        body: const Center(child: Text('학생 정보를 찾을 수 없습니다.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('학생 상세'),
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: '기본 정보',
            child: Column(
              children: [
                _InfoRow(label: '학생 이름', value: student.name),
                _InfoRow(label: '학생 전화번호', value: student.phone ?? '-'),
                _InfoRow(label: '학부모 전화번호', value: student.parentPhone ?? '-'),
                _InfoRow(label: '소속 클래스', value: _classDisplayName),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '기록',
            child: Column(
              children: [
                _RecordTile(
                  title: '숙제 기록',
                  onTap: () =>
                      _openRecordPage(StudentRecordHistoryType.homework),
                ),
                _RecordTile(
                  title: '시험 기록',
                  onTap: () => _openRecordPage(StudentRecordHistoryType.exam),
                ),
                _RecordTile(
                  title: '출결 기록',
                  onTap: () =>
                      _openRecordPage(StudentRecordHistoryType.attendance),
                ),
                _RecordTile(
                  title: '상담 메모',
                  onTap: _openCounselMemoPage,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '관리',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _openEditPage,
                child: const Text('정보 수정'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.subText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final bool isLast;

  const _RecordTile({
    required this.title,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.blue,
          ),
        ),
        if (!isLast) const Divider(height: 1, color: AppColors.line),
      ],
    );
  }
}
