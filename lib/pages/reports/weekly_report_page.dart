import 'package:flutter/material.dart';

import '../../data/models/report_model.dart';
import '../../services/report_service.dart';
import '../../theme/app_colors.dart';

class WeeklyReportPage extends StatefulWidget {
  final String? selectedClass;

  const WeeklyReportPage({super.key, this.selectedClass});

  @override
  State<WeeklyReportPage> createState() => _WeeklyReportPageState();
}

class _WeeklyReportPageState extends State<WeeklyReportPage> {
  bool _isLoading = true;
  WeeklyOverview? _overview;
  List<ClassReportSummary> _summaries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await ReportService.create();
    final overview = await service.getWeeklyOverview();
    final summaries = await service.getClassSummaries();

    if (!mounted) return;
    setState(() {
      _overview = overview;
      _summaries = summaries;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('주간 상세 리포트')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '전체 요약',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _line('학생 수', '${_overview?.totalStudents ?? 0}명'),
                        _line(
                          '출석률',
                          '${((_overview?.attendanceRate ?? 0) * 100).toStringAsFixed(1)}%',
                        ),
                        _line(
                          '숙제 완성도',
                          '${((_overview?.homeworkCompletionRate ?? 0) * 100).toStringAsFixed(1)}%',
                        ),
                        _line(
                          '단어 평균',
                          '${(_overview?.wordExamAverage ?? 0).toStringAsFixed(1)}점',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '반별 요약',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ..._summaries.map(
                  (summary) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.className,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _line('학생 수', '${summary.studentCount}명'),
                          _line(
                            '출석률',
                            '${(summary.attendanceRate * 100).toStringAsFixed(1)}%',
                          ),
                          _line(
                            '숙제 완성도',
                            '${(summary.homeworkCompletionRate * 100).toStringAsFixed(1)}%',
                          ),
                          _line(
                            '단어 평균',
                            '${summary.wordExamAverage.toStringAsFixed(1)}점',
                          ),
                          _line('주의 학생', '${summary.warningStudentCount}명'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.subText),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
