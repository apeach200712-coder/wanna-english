import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/grade_record_model.dart';
import '../../services/attendance_service.dart';
import '../../services/class_selection_service.dart';
import '../../theme/app_colors.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  AttendanceService? _service;
  Future<void>? _initFuture;
  bool _didInit = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    final routeClass = (args is String && args.trim().isNotEmpty)
        ? args.trim()
        : null;

    _initFuture = _initService(routeClass: routeClass);
  }

  Future<void> _initService({String? routeClass}) async {
    final preferredClass = context.read<ClassSelectionService>().selectedClass;
    final service = await AttendanceService.create(
      routeClass: routeClass,
      preferredClass: preferredClass,
    );

    if (!mounted) {
      service.dispose();
      return;
    }

    setState(() {
      _service = service;
    });
    final selected = service.selectedClass;
    if (selected != null) {
      context.read<ClassSelectionService>().selectClass(selected);
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final future = _initFuture;
    if (future == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        final service = _service;
        if (service == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final selectedClass = service.selectedClass;
            final selectedDate = service.selectedDate;
            final classNames = service.classNames;
            final classStudents = service.classStudents;
            final records = service.records;

            return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                title: const Text('출결관리'),
                backgroundColor: AppColors.overlay,
                foregroundColor: AppColors.navy,
                elevation: 0,
              ),
              body: service.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : selectedClass == null
                  ? const Center(
                      child: Text(
                        '등록된 반이 없습니다. 학생을 먼저 추가해주세요.',
                        style: TextStyle(color: AppColors.subText),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 반 선택
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedClass,
                                isExpanded: true,
                                dropdownColor: AppColors.card,
                                items: classNames
                                    .map(
                                      (className) => DropdownMenuItem(
                                        value: className,
                                        child: Text(
                                          className,
                                          style: const TextStyle(
                                            color: AppColors.navy,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) async {
                                  if (value != null) {
                                    await service.setSelectedClass(value);
                                    if (!context.mounted) return;
                                    context
                                        .read<ClassSelectionService>()
                                        .selectClass(value);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 날짜 선택
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 365),
                                ),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                await service.setSelectedDate(picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                border: Border.all(color: AppColors.line),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: AppColors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${selectedDate.month}월 ${selectedDate.day}일',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 출결 현황
                          Text(
                            '${selectedDate.month}월 ${selectedDate.day}일 출결현황',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 12),

                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: classStudents.length,
                            itemBuilder: (context, index) {
                              final student = classStudents[index];
                              final record = records.firstWhere(
                                (r) => r.studentId == student.id,
                                orElse: () => AttendanceRecord(
                                  id: 'temp_${student.id}',
                                  studentId: student.id,
                                  className: selectedClass,
                                  date: selectedDate,
                                  isPresent: true,
                                  createdAt: 0,
                                ),
                              );

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(
                                    student.name,
                                    style: const TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          service.toggleAttendance(
                                            student.id,
                                            true,
                                          );
                                        },
                                        icon: const Icon(Icons.check),
                                        label: const Text('출석'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: record.isPresent
                                              ? AppColors.blue
                                              : AppColors.cardAlt,
                                          foregroundColor: record.isPresent
                                              ? Colors.white
                                              : AppColors.subText,
                                          elevation: 0,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          service.toggleAttendance(
                                            student.id,
                                            false,
                                          );
                                        },
                                        icon: const Icon(Icons.close),
                                        label: const Text('결석'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: !record.isPresent
                                              ? AppColors.red
                                              : AppColors.cardAlt,
                                          foregroundColor: !record.isPresent
                                              ? Colors.white
                                              : AppColors.subText,
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
            );
          },
        );
      },
    );
  }
}
