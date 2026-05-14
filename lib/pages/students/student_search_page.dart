import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/student_model.dart';
import '../../services/student_service.dart';
import '../../theme/app_colors.dart';
import 'student_detail_page.dart';

class StudentSearchPage extends StatefulWidget {
  final String selectedMode;

  const StudentSearchPage({super.key, required this.selectedMode});

  @override
  State<StudentSearchPage> createState() => _StudentSearchPageState();
}

class _StudentSearchPageState extends State<StudentSearchPage> {
  String query = '';
  bool _isLoading = true;
  Map<String, List<Student>> _groupedStudents = const {};

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    await studentService.initializeMockStudents();
    final grouped = await studentService.getStudentsGroupedByClass();
    if (!mounted) return;
    setState(() {
      _groupedStudents = grouped;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _groupedStudents.entries.where((entry) {
      if (widget.selectedMode == 'HOME') return true;
      return entry.key == widget.selectedMode;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: softShadow(),
                      ),
                      child: TextField(
                        autofocus: true,
                        onChanged: (value) => setState(() => query = value),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '학생 이름 직접 입력',
                          hintStyle: TextStyle(color: AppColors.subText),
                          icon: Icon(
                            Icons.search_rounded,
                            color: AppColors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: entries.map((entry) {
                          final students = entry.value
                              .where((student) => student.name.contains(query))
                              .toList();

                          if (students.isEmpty) return const SizedBox.shrink();

                          return StudentGroupSection(
                            className: entry.key,
                            students: students,
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentGroupSection extends StatelessWidget {
  final String className;
  final List<Student> students;

  const StudentGroupSection({
    super.key,
    required this.className,
    required this.students,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$className (${students.length})',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 6),
          ...students.map(
            (student) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                student.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentDetailPage(studentId: student.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
