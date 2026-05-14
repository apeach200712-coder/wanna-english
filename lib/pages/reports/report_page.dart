import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/report_model.dart';
import '../../services/student_service.dart';
import '../../services/report_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/adaptive_scaffold.dart';
import 'student_report_page.dart';
import 'weekly_report_page.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  bool _isLoading = true;
  String? _selectedClass;
  List<String> _classNames = const [];
  WeeklyOverview? _weeklyOverview;
  List<ClassReportSummary> _classSummaries = const [];
  List<StudentRiskItem> _riskItems = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    await studentService.initializeMockStudents();
    final reportService = await ReportService.create();
    final classNames = await studentService.getClassNames();

    final selectedClass = classNames.isEmpty
        ? null
        : (_selectedClass != null && classNames.contains(_selectedClass)
              ? _selectedClass
              : classNames.first);

    final classSummaries = await reportService.getClassSummaries();
    final weekly = await reportService.getWeeklyOverview();
    final risks = await reportService.getRiskStudents(className: selectedClass);

    if (!mounted) return;
    setState(() {
      _classNames = classNames;
      _selectedClass = selectedClass;
      _classSummaries = classSummaries;
      _weeklyOverview = weekly;
      _riskItems = risks;
      _isLoading = false;
    });
  }

  Future<void> _onClassChanged(String? className) async {
    if (className == _selectedClass) return;
    setState(() {
      _selectedClass = className;
      _isLoading = true;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      currentIndex: 2,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '리포트',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                      const Spacer(),
                      if (_classNames.isNotEmpty)
                        DropdownButton<String>(
                          value: _selectedClass,
                          hint: const Text('반 선택'),
                          items: _classNames
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: _onClassChanged,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildWeeklySummaryCard(),
                  const SizedBox(height: 12),
                  _buildClassSummaryCard(),
                  const SizedBox(height: 12),
                  _buildRiskCard(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WeeklyReportPage(
                                  selectedClass: _selectedClass,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.bar_chart_rounded),
                          label: const Text('주간 상세 리포트'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentReportPage(
                                  selectedClass: _selectedClass,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_search_rounded),
                          label: const Text('학생 상세 리포트'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWeeklySummaryCard() {
    final weekly = _weeklyOverview;
    if (weekly == null) {
      return const _SimpleCard(title: '주간 요약', child: Text('데이터가 없습니다.'));
    }

    return _SimpleCard(
      title: '주간 요약',
      child: Column(
        children: [
          _MetricRow(label: '학생 수', value: '${weekly.totalStudents}명'),
          _MetricRow(
            label: '출석률',
            value: '${(weekly.attendanceRate * 100).toStringAsFixed(1)}%',
          ),
          _MetricRow(
            label: '숙제 완성도',
            value:
                '${(weekly.homeworkCompletionRate * 100).toStringAsFixed(1)}%',
          ),
          _MetricRow(
            label: '단어 평균',
            value: '${weekly.wordExamAverage.toStringAsFixed(1)}점',
          ),
        ],
      ),
    );
  }

  Widget _buildClassSummaryCard() {
    if (_classSummaries.isEmpty) {
      return const _SimpleCard(title: '반별 요약', child: Text('반 데이터가 없습니다.'));
    }

    final target = _selectedClass == null
        ? _classSummaries.first
        : _classSummaries.firstWhere(
            (s) => s.className == _selectedClass,
            orElse: () => _classSummaries.first,
          );

    return _SimpleCard(
      title: '${target.className} 요약',
      child: Column(
        children: [
          _MetricRow(label: '학생 수', value: '${target.studentCount}명'),
          _MetricRow(
            label: '출석률',
            value: '${(target.attendanceRate * 100).toStringAsFixed(1)}%',
          ),
          _MetricRow(
            label: '숙제 완성도',
            value:
                '${(target.homeworkCompletionRate * 100).toStringAsFixed(1)}%',
          ),
          _MetricRow(
            label: '단어 평균',
            value: '${target.wordExamAverage.toStringAsFixed(1)}점',
          ),
          _MetricRow(
            label: '주의 학생',
            value: '${target.warningStudentCount}명',
            emphasize: target.warningStudentCount > 0,
          ),
        ],
      ),
    );
  }

  Widget _buildRiskCard() {
    if (_riskItems.isEmpty) {
      return const _SimpleCard(title: '주의 학생', child: Text('현재 주의 학생이 없습니다.'));
    }

    return _SimpleCard(
      title: '주의 학생',
      child: Column(
        children: _riskItems.take(5).map((risk) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${risk.studentName} (${risk.className})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        risk.reasons.join(' · '),
                        style: const TextStyle(color: AppColors.subText),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SimpleCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SimpleCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _MetricRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.subText),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: emphasize ? AppColors.red : AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}
