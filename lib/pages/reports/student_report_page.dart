import 'package:flutter/material.dart';

import '../../data/models/report_model.dart';
import '../../theme/app_colors.dart';
import '../../services/report_service.dart';

class StudentReportPage extends StatefulWidget {
  final String? selectedClass;

  const StudentReportPage({super.key, this.selectedClass});

  @override
  State<StudentReportPage> createState() => _StudentReportPageState();
}

class _StudentReportPageState extends State<StudentReportPage> {
  bool _isLoading = true;
  String? _selectedClass;
  List<StudentReportDetail> _students = const [];
  List<StudentRiskItem> _riskStudents = const [];

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.selectedClass;
    _load();
  }

  Future<void> _load() async {
    final service = await ReportService.create();
    final details = await service.getStudentDetails(className: _selectedClass);
    final risks = await service.getRiskStudents(className: _selectedClass);
    if (!mounted) return;
    setState(() {
      _students = details;
      _riskStudents = risks;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학생 상세 리포트')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_selectedClass != null)
                  Text(
                    '대상 반: $_selectedClass',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '주의 학생 ${_riskStudents.length}명',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_students.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('표시할 학생 데이터가 없습니다.'),
                    ),
                  )
                else
                  ..._students.map(
                    (student) => Card(
                      child: ListTile(
                        title: Text(student.studentName),
                        subtitle: Text(
                          '${student.className} · 출석 ${student.attendancePresent}/${student.attendancePresent + student.attendanceAbsent} · 숙제 ${student.latestHomeworkCompletion}%',
                        ),
                        trailing: student.needsAttention
                            ? const Icon(
                                Icons.error_outline,
                                color: AppColors.red,
                              )
                            : const Icon(
                                Icons.check_circle_outline,
                                color: AppColors.green,
                              ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
