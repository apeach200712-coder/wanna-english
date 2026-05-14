import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/student_grade_model.dart';
import '../../services/class_selection_service.dart';
import '../../services/class_service.dart';
import '../../services/grade_service.dart';
import '../../services/student_service.dart';
import '../../data/models/student_model.dart';
import '../../theme/app_colors.dart';

enum _GradeSystem { five, nine }

class GradeCalculatorPage extends StatefulWidget {
  const GradeCalculatorPage({super.key});

  @override
  State<GradeCalculatorPage> createState() => _GradeCalculatorPageState();
}

class _GradeCalculatorPageState extends State<GradeCalculatorPage> {
  late GradeService _gradeService;
  late StudentService _studentService;
  String? _selectedClass;
  List<String> _classNames = const [];
  late DateTime _examDate;
  late ExamType _examType;
  List<Student> _students = const [];
  late Map<String, TextEditingController> _controllers;
  Timer? _saveDebounce;
  _GradeSystem _gradeSystem = _GradeSystem.nine;
  _GradeSummary? _summary;
  bool _isLoading = true;
  bool _didApplyRouteArguments = false;
  String? _routeClass;
  String? _routeClassId;
  DateTime? _routeExamDate;

  @override
  void initState() {
    super.initState();
    _examDate = DateTime.now();
    _examType = ExamType.vocabulary;
    _controllers = {};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didApplyRouteArguments) return;
    _didApplyRouteArguments = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty) {
      _routeClass = args;
    } else if (args is Map) {
      final id = args['classId'];
      if (id is String && id.trim().isNotEmpty) {
        _routeClassId = id.trim();
      }
      final c = args['className'] ?? args['displayName'];
      if (c is String && c.trim().isNotEmpty) {
        _routeClass = c.trim();
      }
      final d = args['examDate'] ?? args['selectedDate'];
      if (d is DateTime) {
        _routeExamDate = DateTime(d.year, d.month, d.day);
      }
    }

    _initService(
      preferredClass: context.read<ClassSelectionService>().selectedClass,
    );
  }

  Future<void> _initService({String? preferredClass}) async {
    final prefs = await SharedPreferences.getInstance();
    _gradeService = GradeService(prefs: prefs);
    _studentService = StudentService(prefs: prefs);
    await _studentService.initializeMockStudents();

    final classNames = await _studentService.getClassNames();
    if (!mounted) return;

    String? resolvedFromId;
    final routeId = _routeClassId;
    if (routeId != null && routeId.isNotEmpty) {
      final classService = ClassService(prefs: prefs);
      await classService.initializeFromMockIfNeeded();
      final items = await classService.getDisplayItems();
      for (final it in items) {
        if (it.id == routeId) {
          resolvedFromId = it.displayName;
          break;
        }
      }
    }

    if (classNames.isEmpty) {
      setState(() {
        _classNames = const [];
        _selectedClass = null;
        _students = const [];
        _isLoading = false;
      });
      return;
    }

    final initialClass = resolvedFromId ?? _routeClass ?? preferredClass;
    _selectedClass = (initialClass != null && classNames.contains(initialClass))
        ? initialClass
        : classNames.first;
    _classNames = classNames;
    if (_routeExamDate != null) {
      _examDate = _routeExamDate!;
    }
    if (!mounted) return;
    context.read<ClassSelectionService>().selectClass(_selectedClass);
    await _loadStudentsForClass(_selectedClass!);
    await _loadExistingData();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  void _initControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final student in _students) {
      _controllers[student.id] = TextEditingController();
    }
  }

  Future<void> _loadStudentsForClass(String className) async {
    final students = await _studentService.getStudentsByClass(className);
    if (!mounted) return;
    setState(() {
      _students = students;
      _summary = null;
    });
    _initControllers();
  }

  Future<void> _loadExistingData() async {
    final selectedClass = _selectedClass;
    if (selectedClass == null) return;

    final record = await _gradeService.getGradeRecord(
      className: selectedClass,
      examDate: _examDate,
      examType: _examType,
    );
    if (record == null) {
      _controllers.forEach((_, controller) => controller.clear());
      setState(() => _summary = null);
      return;
    }

    for (final grade in record.grades) {
      String? key;
      for (final student in _students) {
        if (student.id == grade.studentId) {
          key = student.id;
          break;
        }
      }
      if (key == null) {
        for (final student in _students) {
          if (student.name == grade.name) {
            key = student.id;
            break;
          }
        }
      }
      if (key != null && _controllers.containsKey(key)) {
        _controllers[key]!.text = grade.score.toStringAsFixed(1);
      }
    }

    _calculateStats();
  }

  void _onScoreChanged(Student student) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveScore(student);
    });
    _calculateStats();
  }

  Future<void> _saveScore(Student student) async {
    final selectedClass = _selectedClass;
    if (selectedClass == null) return;

    final scoreText = _controllers[student.id]?.text ?? '';
    final score = double.tryParse(scoreText);
    if (score == null || score < 0 || score > 100) return;

    await _gradeService.upsertStudentGrade(
      className: selectedClass,
      examDate: _examDate,
      examType: _examType,
      studentId: student.id,
      studentName: student.name,
      score: score,
    );
  }

  void _calculateStats() {
    final scores = <double>[];
    for (final controller in _controllers.values) {
      final score = double.tryParse(controller.text);
      if (score != null && score >= 0 && score <= 100) {
        scores.add(score);
      }
    }

    if (scores.isEmpty) {
      setState(() => _summary = null);
      return;
    }

    final summary = _buildSummary(scores, _gradeSystem);
    setState(() => _summary = summary);
  }

  void _onClassChanged(String newClass) {
    _selectedClass = newClass;
    context.read<ClassSelectionService>().selectClass(newClass);
    _loadStudentsForClass(newClass).then((_) => _loadExistingData());
  }

  void _onDateChanged(DateTime newDate) {
    setState(() {
      _examDate = newDate;
      _summary = null;
    });
    _initControllers();
    _loadExistingData();
  }

  void _onExamTypeChanged(ExamType newType) {
    setState(() {
      _examType = newType;
      _summary = null;
    });
    _initControllers();
    _loadExistingData();
  }

  _GradeSummary _buildSummary(List<double> scores, _GradeSystem system) {
    final sorted = [...scores]..sort((a, b) => b.compareTo(a));

    final count = sorted.length;
    final mean = sorted.reduce((a, b) => a + b) / count;

    final variance =
        sorted.map((s) => math.pow(s - mean, 2)).reduce((a, b) => a + b) /
        count;
    final stdDev = math.sqrt(variance);

    final rows = <_GradeRow>[];
    for (int i = 0; i < sorted.length; i++) {
      final score = sorted[i];
      final rank = _rankFor(sorted, i);
      final z = stdDev == 0 ? 0.0 : (score - mean) / stdDev;
      final grade = _gradeFromZ(z, system, stdDev == 0);
      rows.add(_GradeRow(rank: rank, score: score, zScore: z, grade: grade));
    }

    return _GradeSummary(count: count, mean: mean, stdDev: stdDev, rows: rows);
  }

  int _rankFor(List<double> sorted, int index) {
    final score = sorted[index];
    int rank = 1;
    for (int i = 0; i < index; i++) {
      if (sorted[i] > score) {
        rank += 1;
      }
    }
    return rank;
  }

  int _gradeFromZ(double z, _GradeSystem system, bool sameScoreGroup) {
    if (sameScoreGroup) {
      return system == _GradeSystem.five ? 3 : 5;
    }

    if (system == _GradeSystem.five) {
      if (z >= 1.2816) return 1;
      if (z >= 0.4125) return 2;
      if (z >= -0.4125) return 3;
      if (z >= -1.2816) return 4;
      return 5;
    }

    if (z >= 1.7507) return 1;
    if (z >= 1.2265) return 2;
    if (z >= 0.7388) return 3;
    if (z >= 0.2533) return 4;
    if (z >= -0.2533) return 5;
    if (z >= -0.7388) return 6;
    if (z >= -1.2265) return 7;
    if (z >= -1.7507) return 8;
    return 9;
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_classNames.isEmpty || _selectedClass == null) {
      return const Scaffold(
        body: Center(child: Text('등록된 클래스가 없습니다. 학생을 먼저 추가해주세요.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('성적 계산기'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildClassSelector(),
            const SizedBox(height: 16),
            _buildDateSelector(),
            const SizedBox(height: 16),
            _buildExamTypeSelector(),
            const SizedBox(height: 24),
            _buildGradeSystemSelector(),
            const SizedBox(height: 24),
            if (_students.isNotEmpty) _buildStudentScoresTable(),
            if (_summary != null) ...[
              const SizedBox(height: 32),
              _buildSummaryStats(),
              const SizedBox(height: 24),
              _buildGradesDataTable(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '클래스 선택',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: _selectedClass,
          isExpanded: true,
          items: _classNames
              .map(
                (className) =>
                    DropdownMenuItem(value: className, child: Text(className)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              _onClassChanged(value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '시험 날짜',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _examDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) {
              _onDateChanged(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_examDate.year}년 ${_examDate.month}월 ${_examDate.day}일',
                  style: const TextStyle(fontSize: 14),
                ),
                const Icon(Icons.calendar_today, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExamTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '시험 종류',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButton<ExamType>(
          value: _examType,
          isExpanded: true,
          items: ExamType.values
              .map(
                (type) =>
                    DropdownMenuItem(value: type, child: Text(type.label)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              _onExamTypeChanged(value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildGradeSystemSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '등급 시스템',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<_GradeSystem>(
                segments: const [
                  ButtonSegment(label: Text('9등급제'), value: _GradeSystem.nine),
                  ButtonSegment(label: Text('5등급제'), value: _GradeSystem.five),
                ],
                selected: {_gradeSystem},
                onSelectionChanged: (value) {
                  setState(() {
                    _gradeSystem = value.first;
                    _calculateStats();
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStudentScoresTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '학생 점수',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1)},
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.1),
                ),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '학생명',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '점수',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              for (final student in _students)
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey[200]!)),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(student.name),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        controller: _controllers[student.id],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          hintText: '0-100',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          isDense: true,
                        ),
                        onChanged: (_) => _onScoreChanged(student),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStats() {
    if (_summary == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '통계',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: '평균',
                value: _summary!.mean.toStringAsFixed(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: '표준편차',
                value: _summary!.stdDev.toStringAsFixed(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(label: '인원', value: '${_summary!.count}명'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGradesDataTable() {
    if (_summary == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '등급 현황',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateColor.resolveWith(
              (_) => AppColors.blue.withValues(alpha: 0.1),
            ),
            columns: const [
              DataColumn(label: Text('순위')),
              DataColumn(label: Text('점수')),
              DataColumn(label: Text('Z-Score')),
              DataColumn(label: Text('등급')),
            ],
            rows: _summary!.rows
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(Text('${row.rank}등')),
                      DataCell(Text(row.score.toStringAsFixed(1))),
                      DataCell(Text(row.zScore.toStringAsFixed(2))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${row.grade}등',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeSummary {
  final int count;
  final double mean;
  final double stdDev;
  final List<_GradeRow> rows;

  _GradeSummary({
    required this.count,
    required this.mean,
    required this.stdDev,
    required this.rows,
  });
}

class _GradeRow {
  final int rank;
  final double score;
  final double zScore;
  final int grade;

  _GradeRow({
    required this.rank,
    required this.score,
    required this.zScore,
    required this.grade,
  });
}
