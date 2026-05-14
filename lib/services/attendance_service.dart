import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/grade_record_model.dart';
import '../data/models/student_model.dart';
import 'grade_record_service.dart';
import 'student_service.dart';

class AttendanceService extends ChangeNotifier {
  final GradeRecordService _gradeRecordService;
  final StudentService _studentService;

  String? _selectedClass;
  List<String> _classNames = const [];
  DateTime _selectedDate = DateTime.now();
  List<AttendanceRecord> _records = const [];
  List<Student> _classStudents = const [];
  bool _isLoading = true;

  AttendanceService({
    required GradeRecordService gradeRecordService,
    required StudentService studentService,
  }) : _gradeRecordService = gradeRecordService,
       _studentService = studentService;

  static Future<AttendanceService> create({
    String? routeClass,
    String? preferredClass,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final service = AttendanceService(
      gradeRecordService: GradeRecordService(prefs: prefs),
      studentService: StudentService(prefs: prefs),
    );
    await service.initialize(
      routeClass: routeClass,
      preferredClass: preferredClass,
    );
    return service;
  }

  String? get selectedClass => _selectedClass;
  List<String> get classNames => _classNames;
  DateTime get selectedDate => _selectedDate;
  List<AttendanceRecord> get records => _records;
  List<Student> get classStudents => _classStudents;
  bool get isLoading => _isLoading;

  Future<void> initialize({String? routeClass, String? preferredClass}) async {
    _isLoading = true;
    notifyListeners();

    await _studentService.initializeMockStudents();
    _classNames = await _studentService.getClassNames();

    if (_classNames.isNotEmpty) {
      final candidate = routeClass ?? preferredClass;
      if (candidate != null && _classNames.contains(candidate)) {
        _selectedClass = candidate;
      } else {
        _selectedClass = _classNames.first;
      }
      await _loadStudents();
      await _loadRecords();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setSelectedClass(String className) async {
    if (_selectedClass == className) return;
    _selectedClass = className;
    _isLoading = true;
    notifyListeners();

    await _loadStudents();
    await _loadRecords();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setSelectedDate(DateTime date) async {
    _selectedDate = date;
    _isLoading = true;
    notifyListeners();

    await _loadRecords();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggleAttendance(String studentId, bool isPresent) async {
    final className = _selectedClass;
    if (className == null) return;

    final dayKey =
        '${_selectedDate.year}${_selectedDate.month.toString().padLeft(2, '0')}${_selectedDate.day.toString().padLeft(2, '0')}';
    final record = AttendanceRecord(
      id: '${className}_${studentId}_$dayKey',
      studentId: studentId,
      className: className,
      date: _selectedDate,
      isPresent: isPresent,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _gradeRecordService.saveAttendance(record);
    await _loadRecords();
    notifyListeners();
  }

  Future<void> _loadStudents() async {
    final className = _selectedClass;
    if (className == null) {
      _classStudents = const [];
      return;
    }
    _classStudents = await _studentService.getStudentsByClass(className);
  }

  Future<void> _loadRecords() async {
    final className = _selectedClass;
    if (className == null) {
      _records = const [];
      return;
    }
    _records = await _gradeRecordService.getClassAttendance(
      className,
      _selectedDate,
    );
  }
}
