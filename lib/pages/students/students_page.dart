import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/responsive.dart';
import '../../core/routes.dart';
import '../../data/models/announcement_model.dart';
import '../../data/models/student_model.dart';
import '../../services/announcement_service.dart';
import '../../services/class_service.dart';
import '../../services/lesson_content_service.dart';
import '../../services/report_message_builder.dart';
import '../../services/sms_service.dart';
import '../../services/student_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/adaptive_scaffold.dart';
import '../../widgets/common/app_top_bar.dart';
import '../../widgets/common/lesson_content_editor_sheet.dart';
import '../../widgets/dial_pad_phone_field.dart';
import 'student_detail_page.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key});

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  static const String _unassignedClassId = '__unassigned__';
  static const String _unassignedClassLabel = '기타';

  late StudentService _studentService;
  late ClassService _classService;
  late AnnouncementService _announcementService;

  String? _selectedClassId;
  List<ClassDisplayItem> _classItems = const [];
  List<Student> _students = const [];
  bool _hasUnassignedStudents = false;
  bool _isLoading = true;
  bool _isDeleteSelectionMode = false;
  bool _isReportSendMode = false;
  Set<String> _selectedStudentIds = <String>{};

  ClassDisplayItem? get _selectedClassItem {
    final selectedClassId = _selectedClassId;
    if (selectedClassId == null) return null;
    if (selectedClassId == _unassignedClassId) return null;
    for (final item in _classItems) {
      if (item.id == selectedClassId) return item;
    }
    return null;
  }

  bool _isUnassignedStudent(Student student) {
    final classId = student.classId.trim();
    if (classId.isEmpty) return true;
    return !_classItems.any((item) => item.id == classId);
  }

  List<DropdownMenuItem<String>> get _classSelectorItems {
    final items = <DropdownMenuItem<String>>[
      ..._classItems.map(
        (item) => DropdownMenuItem(
          value: item.id,
          child: Text(item.displayName),
        ),
      ),
    ];
    if (_hasUnassignedStudents) {
      items.add(
        const DropdownMenuItem(
          value: _unassignedClassId,
          child: Text(_unassignedClassLabel),
        ),
      );
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final prefs = await SharedPreferences.getInstance();
    _studentService = StudentService(prefs: prefs);
    _classService = ClassService(prefs: prefs);
    _announcementService = AnnouncementService(prefs: prefs);
    await _studentService.initializeMockStudents();
    await _classService.initializeFromMockIfNeeded();
    await _reloadClassItems();
    await _loadStudents();
  }

  Future<void> _reloadClassItems() async {
    final classes = await _classService.getDisplayItems();
    final allStudents = await _studentService.getAllStudents();
    final classIds = classes.map((item) => item.id).toSet();
    final hasUnassigned = allStudents.any((student) {
      final classId = student.classId.trim();
      return classId.isEmpty || !classIds.contains(classId);
    });
    if (!mounted) return;

    setState(() {
      _classItems = classes;
      _hasUnassignedStudents = hasUnassigned;
      final selectableIds = <String>{
        ...classes.map((item) => item.id),
        if (hasUnassigned) _unassignedClassId,
      };
      if (selectableIds.isEmpty) {
        _selectedClassId = null;
      } else if (_selectedClassId == null ||
          !selectableIds.contains(_selectedClassId)) {
        _selectedClassId = classes.isNotEmpty
            ? classes.first.id
            : _unassignedClassId;
      }
    });
  }

  Future<void> _loadStudents() async {
    final selectedClassId = _selectedClassId;
    if (selectedClassId == null) {
      if (!mounted) return;
      setState(() {
        _students = const [];
        _isLoading = false;
      });
      return;
    }

    final students = selectedClassId == _unassignedClassId
        ? (await _studentService.getAllStudents())
              .where(_isUnassignedStudent)
              .toList()
        : await _studentService.getStudentsByClassId(selectedClassId);
    students.sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;
    setState(() {
      _students = students;
      _isLoading = false;
      _selectedStudentIds = _selectedStudentIds
          .where((id) => students.any((student) => student.id == id))
          .toSet();
      if (students.isEmpty) {
        _isDeleteSelectionMode = false;
        _isReportSendMode = false;
      }
    });
  }

  void _onClassChanged(String classId) {
    setState(() {
      _selectedClassId = classId;
      _isLoading = true;
      _isDeleteSelectionMode = false;
      _isReportSendMode = false;
      _selectedStudentIds = <String>{};
    });
    _loadStudents();
  }

  void _exitReportSendMode() {
    setState(() {
      _isReportSendMode = false;
      _selectedStudentIds = <String>{};
    });
  }

  void _handleReportSendSelectTap() {
    if (_isDeleteSelectionMode) {
      setState(() {
        _isDeleteSelectionMode = false;
        _isReportSendMode = true;
        _selectedStudentIds = <String>{};
      });
      return;
    }
    if (_isReportSendMode) return;
    setState(() {
      _isReportSendMode = true;
      _selectedStudentIds = <String>{};
    });
  }

  Future<void> _handleDeleteButtonTap() async {
    if (_isReportSendMode) {
      setState(() {
        _isReportSendMode = false;
        _selectedStudentIds = <String>{};
        _isDeleteSelectionMode = true;
      });
      return;
    }

    if (!_isDeleteSelectionMode) {
      setState(() {
        _isDeleteSelectionMode = true;
        _isReportSendMode = false;
        _selectedStudentIds = <String>{};
      });
      return;
    }

    if (_selectedStudentIds.isEmpty) {
      setState(() {
        _isDeleteSelectionMode = false;
        _selectedStudentIds = <String>{};
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('학생 삭제'),
        content: const Text('선택한 학생을 정말 삭제하시겠습니까? 삭제 후에는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final selectedIds = _selectedStudentIds.toList(growable: false);
    for (final studentId in selectedIds) {
      await _studentService.deleteStudent(studentId);
    }

    if (!mounted) return;
    setState(() {
      _selectedStudentIds = <String>{};
      _isDeleteSelectionMode = false;
      _isLoading = true;
    });
    await _reloadClassItems();
    await _loadStudents();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedIds.length}명의 학생을 삭제했습니다.')),
    );
  }

  void _toggleStudentSelection(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
    });
  }

  String _normalizePhoneInput(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String? _validateStudentInput({
    required String name,
    required String studentPhone,
    required String parentPhone,
    required ClassDisplayItem? selectedClass,
  }) {
    if (name.trim().isEmpty) {
      return '학생 이름을 입력해 주세요.';
    }
    if (studentPhone.trim().isEmpty) {
      return '학생 전화번호를 입력해 주세요.';
    }
    if (parentPhone.trim().isEmpty) {
      return '학부모 전화번호를 입력해 주세요.';
    }
    if (selectedClass == null) {
      return '소속 클래스를 선택해 주세요.';
    }
    return null;
  }

  Future<void> _showAddStudentDialog() async {
    final selectedClass = _selectedClassItem;
    if (selectedClass == null) return;

    final nameCtrl = TextEditingController();
    final studentPhoneCtrl = TextEditingController();
    final parentPhoneCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('학생 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '홍길동',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            DialPadPhoneField(
              controller: studentPhoneCtrl,
              sheetTitle: '학생 전화번호',
              decoration: const InputDecoration(
                labelText: '학생 전화번호',
                hintText: '01012345678',
                prefixIcon: Icon(Icons.smartphone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DialPadPhoneField(
              controller: parentPhoneCtrl,
              sheetTitle: '학부모 전화번호',
              decoration: const InputDecoration(
                labelText: '학부모 전화번호',
                hintText: '01012345678',
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '소속 클래스: ${selectedClass.displayName}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.subText,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final validationMessage = _validateStudentInput(
                name: name,
                studentPhone: studentPhoneCtrl.text,
                parentPhone: parentPhoneCtrl.text,
                selectedClass: selectedClass,
              );
              if (validationMessage != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(validationMessage)));
                return;
              }

              final now = DateTime.now().millisecondsSinceEpoch;
              final student = Student(
                id: const Uuid().v4(),
                name: name,
                classId: selectedClass.id,
                className: selectedClass.name,
                phone: studentPhoneCtrl.text.trim().isEmpty
                    ? null
                    : _normalizePhoneInput(studentPhoneCtrl.text),
                parentPhone: parentPhoneCtrl.text.trim().isEmpty
                    ? null
                    : _normalizePhoneInput(parentPhoneCtrl.text),
                createdAt: now,
                updatedAt: now,
              );
              await _studentService.saveStudent(student);
              if (!context.mounted) return;
              Navigator.pop(ctx);
              await _reloadClassItems();
              await _loadStudents();
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSmsComposer(
    Student student, {
    SharedPreferences? prefs,
  }) async {
    final phone = student.parentPhone ?? student.phone;
    final normalized = _normalizePhoneInput(phone ?? '');
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('보낼 전화번호가 없습니다.')));
      return;
    }

    final p = prefs ?? await SharedPreferences.getInstance();
    final body =
        (await ReportMessageBuilder.buildReportMessage(student: student, prefs: p))
            .trim();
    final encodedBody = Uri.encodeComponent(body);
    final uri = Uri.parse('sms:$normalized?body=$encodedBody');
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('문자 앱을 열 수 없습니다.')));
    }
  }

  Future<void> _sendSelectedReports() async {
    if (!_isReportSendMode || !mounted) return;
    final selected = _students
        .where((s) => _selectedStudentIds.contains(s.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전송할 학생을 선택해주세요.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final classItem = _selectedClassItem;

    if (selected.length == 1) {
      await _openSmsComposer(selected.first, prefs: prefs);
      if (mounted) _exitReportSendMode();
      return;
    }

    if (!await SMSService.isConfigured(prefs)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SMSService.buildConfigurationErrorMessage())),
      );
      return;
    }

    final className = classItem?.name;
    if (className == null || className.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('클래스 정보를 찾을 수 없습니다.')),
      );
      return;
    }

    final delayed = await _announcementService.isDelayedSending(className);
    if (delayed && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('전송 시간 확인'),
          content: Text(
            SMSService.buildDelayNotification(
              className: className,
              delayMinutes: 10,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('전송'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final batchId = 'report_${DateTime.now().millisecondsSinceEpoch}';
    var ok = 0;
    var fail = 0;

    for (final student in selected) {
      final phone = student.parentPhone?.trim();
      if (phone == null || phone.isEmpty) {
        fail++;
        continue;
      }
      final message = await ReportMessageBuilder.buildReportMessage(
        student: student,
        prefs: prefs,
      );
      final success = await SMSService.sendSMS(
        phoneNumber: phone,
        message: message,
        prefs: prefs,
      );
      if (success) {
        ok++;
      } else {
        fail++;
      }
      await _announcementService.saveSMSLog(
        SMSLog(
          id: const Uuid().v4(),
          studentId: student.id,
          parentPhone: student.parentPhone,
          announcementId: batchId,
          sentTime: DateTime.now(),
          isSuccess: success,
          errorMessage: success ? null : 'SMS 전송 실패',
        ),
      );
    }

    await _announcementService.recordSendingTime(className, DateTime.now());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('리포트 전송: 성공 $ok명 · 실패·번호없음 $fail명')),
    );
    _exitReportSendMode();
  }

  Future<void> _openStudentDetail(Student student) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailPage(studentId: student.id),
      ),
    );
    await _reloadClassItems();
    await _loadStudents();
  }

  Future<void> _openLessonContentEditor() async {
    final selectedClass = _selectedClassItem;
    if (selectedClass == null) return;

    final prefs = await SharedPreferences.getInstance();
    final service = LessonContentService(prefs: prefs);
    final existing = await service.getLessonContent(selectedClass.name);
    if (!mounted) return;

    final lines = await showLessonContentEditorSheet(
      context: context,
      className: selectedClass.displayName,
      initialLines: existing,
    );
    if (lines == null) return;

    await service.saveLessonContent(selectedClass.name, lines);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('오늘 수업 내용을 저장했습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.hPadding(context);
    final maxW = Responsive.maxContentWidth(context);

    return AdaptiveScaffold(
      currentIndex: 1,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTopBar(
                    onSettingsTap: () =>
                        Navigator.pushNamed(context, AppRoutes.settings),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '학생 관리',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildClassSelector(),
                  const SizedBox(height: 16),
                  _buildClassActionCard(),
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    _buildStudentsList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassSelector() {
    final selectorItems = _classSelectorItems;
    if (selectorItems.isEmpty || _selectedClassId == null) {
      return const SizedBox.shrink();
    }
    final canAddStudentToSelection = _selectedClassId != _unassignedClassId;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _selectedClassId,
            decoration: InputDecoration(
              labelText: '클래스',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            items: selectorItems,
            onChanged: (value) {
              if (value != null) {
                _onClassChanged(value);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: canAddStudentToSelection ? _showAddStudentDialog : null,
          icon: const Icon(Icons.person_add),
          label: const Text('학생 추가'),
        ),
      ],
    );
  }

  Widget _buildStudentsList() {
    if (_selectedClassId == null) {
      return const _EmptyState(
        icon: Icons.class_outlined,
        title: '등록된 클래스가 없습니다.',
        subtitle: '설정에서 클래스를 먼저 추가해주세요.',
      );
    }

    if (_students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const Icon(
                Icons.people_outline,
                size: 48,
                color: AppColors.subText,
              ),
              const SizedBox(height: 8),
              const Text(
                '학생이 없습니다.',
                style: TextStyle(color: AppColors.subText),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _showAddStudentDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('학생 추가'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '학생 목록 (${_students.length}명)',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.subText,
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_isReportSendMode) ...[
                  TextButton(
                    onPressed: _exitReportSendMode,
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: _sendSelectedReports,
                    child: const Text('전송'),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: _handleReportSendSelectTap,
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('리포트 전송 선택'),
                  ),
                OutlinedButton.icon(
                  onPressed: _handleDeleteButtonTap,
                  icon: Icon(
                    !_isDeleteSelectionMode
                        ? Icons.delete_outline
                        : _selectedStudentIds.isEmpty
                        ? Icons.close_rounded
                        : Icons.delete_forever_outlined,
                  ),
                  label: Text(
                    !_isDeleteSelectionMode
                        ? '학생 삭제'
                        : _selectedStudentIds.isEmpty
                        ? '삭제 취소'
                        : '선택 학생 삭제',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isDeleteSelectionMode &&
                            _selectedStudentIds.isNotEmpty
                        ? Colors.red
                        : AppColors.subText,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (_isReportSendMode) ...[
          const SizedBox(height: 8),
          Text(
            _selectedStudentIds.isEmpty
                ? '리포트를 보낼 학생을 선택하세요.'
                : '${_selectedStudentIds.length}명 선택됨',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.subText,
            ),
          ),
        ],
        if (_isDeleteSelectionMode && !_isReportSendMode) ...[
          const SizedBox(height: 8),
          Text(
            _selectedStudentIds.isEmpty
                ? '삭제할 학생을 선택하세요.'
                : '${_selectedStudentIds.length}명 선택됨',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.subText,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _students.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.line),
            itemBuilder: (context, index) => _StudentListTile(
              student: _students[index],
              showSelectionCheckbox:
                  _isDeleteSelectionMode || _isReportSendMode,
              isSelected: _selectedStudentIds.contains(_students[index].id),
              onSelectionToggle: () =>
                  _toggleStudentSelection(_students[index].id),
              onSmsTap: () => _openSmsComposer(_students[index]),
              onTap: () {
                if (_isDeleteSelectionMode || _isReportSendMode) {
                  _toggleStudentSelection(_students[index].id);
                  return;
                }
                _openStudentDetail(_students[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassActionCard() {
    final selectedClass = _selectedClassItem;
    if (selectedClass == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '수업 리포트 관리',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _openLessonContentEditor,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('오늘 수업 내용'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.homework,
                    arguments: {
                      'classId': selectedClass.id,
                      'className': selectedClass.name,
                      'classDisplayName': selectedClass.displayName,
                      'tab': 'nextWeek',
                    },
                  ),
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('다음 숙제'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.announcements,
                    arguments: {
                      'className': selectedClass.name,
                      'reportMode': true,
                    },
                  ),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('리포트 편집'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentListTile extends StatelessWidget {
  final Student student;
  final bool showSelectionCheckbox;
  final bool isSelected;
  final VoidCallback onSelectionToggle;
  final VoidCallback onSmsTap;
  final VoidCallback onTap;

  const _StudentListTile({
    required this.student,
    required this.showSelectionCheckbox,
    required this.isSelected,
    required this.onSelectionToggle,
    required this.onSmsTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: showSelectionCheckbox
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onSelectionToggle(),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            )
          : null,
      title: Text(
        student.name,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: onSmsTap,
            icon: const Icon(Icons.sms_outlined),
            label: const Text('문자'),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.subText),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.subText),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: AppColors.subText)),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: AppColors.subText)),
          ],
        ),
      ),
    );
  }
}
