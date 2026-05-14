import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/student_model.dart';
import '../../services/class_service.dart';
import '../../services/student_service.dart';
import '../../widgets/dial_pad_phone_field.dart';
import '../../theme/app_colors.dart';

class StudentEditPage extends StatefulWidget {
  final String studentId;

  const StudentEditPage({super.key, required this.studentId});

  @override
  State<StudentEditPage> createState() => _StudentEditPageState();
}

class _StudentEditPageState extends State<StudentEditPage> {
  final _nameCtrl = TextEditingController();
  final _studentPhoneCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();

  Student? _student;
  List<ClassDisplayItem> _classItems = const [];
  String? _selectedClassId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _studentPhoneCtrl.dispose();
    _parentPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    final classService = ClassService(prefs: prefs);

    final student = await studentService.getStudentById(widget.studentId);
    final classItems = await classService.getDisplayItems();
    if (!mounted) return;

    if (student == null) {
      setState(() => _isLoading = false);
      return;
    }

    _nameCtrl.text = student.name;
    _studentPhoneCtrl.text = student.phone ?? '';
    _parentPhoneCtrl.text = student.parentPhone ?? '';

    setState(() {
      _student = student;
      _classItems = classItems;
      _selectedClassId = classItems.any((item) => item.id == student.classId)
          ? student.classId
          : (classItems.isEmpty ? null : classItems.first.id);
      _isLoading = false;
    });
  }

  String _normalizePhoneInput(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String? _validateInput() {
    if (_nameCtrl.text.trim().isEmpty) {
      return '학생 이름을 입력해 주세요.';
    }
    if (_studentPhoneCtrl.text.trim().isEmpty) {
      return '학생 전화번호를 입력해 주세요.';
    }
    if (_parentPhoneCtrl.text.trim().isEmpty) {
      return '학부모 전화번호를 입력해 주세요.';
    }
    if (_selectedClassId == null) {
      return '소속 클래스를 선택해 주세요.';
    }
    return null;
  }

  Future<void> _save() async {
    final student = _student;
    final selectedClassId = _selectedClassId;
    if (student == null || selectedClassId == null) return;

    final validationMessage = _validateInput();
    if (validationMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }
    final trimmedName = _nameCtrl.text.trim();

    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    final studentService = StudentService(prefs: prefs);
    final selectedClass = _classItems.firstWhere(
      (item) => item.id == selectedClassId,
    );

    final updated = student.copyWith(
      name: trimmedName,
      classId: selectedClassId,
      className: selectedClass.name,
      phone: _studentPhoneCtrl.text.trim().isEmpty
          ? null
          : _normalizePhoneInput(_studentPhoneCtrl.text),
      parentPhone: _parentPhoneCtrl.text.trim().isEmpty
          ? null
          : _normalizePhoneInput(_parentPhoneCtrl.text),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await studentService.saveStudent(updated);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_student == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('정보 수정')),
        body: const Center(child: Text('학생 정보를 찾을 수 없습니다.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('정보 수정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '학생 이름',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          DialPadPhoneField(
            controller: _studentPhoneCtrl,
            sheetTitle: '학생 전화번호',
            decoration: const InputDecoration(
              labelText: '학생 전화번호',
              hintText: '01012345678',
              prefixIcon: Icon(Icons.smartphone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DialPadPhoneField(
            controller: _parentPhoneCtrl,
            sheetTitle: '학부모 전화번호',
            decoration: const InputDecoration(
              labelText: '학부모 전화번호',
              hintText: '01012345678',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedClassId,
            decoration: const InputDecoration(
              labelText: '소속 클래스',
              prefixIcon: Icon(Icons.class_),
            ),
            items: _classItems
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(item.displayName),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedClassId = value);
              }
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? '저장 중...' : '저장'),
          ),
        ],
      ),
    );
  }
}
