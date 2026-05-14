import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/announcement_model.dart';
import '../../data/models/exam_score_model.dart';
import '../../data/models/parent_report_models.dart';
import '../../data/models/student_model.dart';
import '../../services/announcement_service.dart';
import '../../services/announcement_message_generator.dart';
import '../../services/class_report_draft_service.dart';
import '../../services/class_report_settings_service.dart';
import '../../services/exam_session_service.dart';
import '../../services/grade_record_service.dart';
import '../../services/grade_service.dart';
import '../../services/homework_page_service.dart';
import '../../services/lesson_content_service.dart';
import '../../services/parent_report_message_builder.dart';
import '../../services/sms_service.dart';
import '../../services/student_service.dart';
import '../../core/constants.dart';
import '../../theme/app_colors.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({super.key});

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  late AnnouncementService _announcementService;
  late StudentService _studentService;
  late GradeRecordService _gradeRecordService;
  late AnnouncementMessageGenerator _messageGenerator;
  late ExamSessionService _examSessionService;
  late ClassReportSettingsService _classReportSettingsService;
  late ClassReportDraftService _classReportDraftService;
  late String _academyLabel;
  late SharedPreferences _prefs;
  String? _selectedClass;
  bool _reportMode = false;
  List<String> _classNames = const [];
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _greetingController = TextEditingController();
  final TextEditingController _closingController = TextEditingController();
  final TextEditingController _reportExtraController = TextEditingController();
  List<Announcement> _announcements = [];
  List<Student> _classStudents = [];
  Map<String, bool> _selectedStudents = {};
  bool _isLoading = true;
  bool _didApplyRouteArguments = false;
  bool _servicesReady = false;

  bool _includeTodayLesson = true;
  bool _includeNextHomework = true;
  bool _homeworkIncludeCompletion = true;
  bool _homeworkIncludeWeak = true;
  bool _homeworkIncludeResubmit = true;
  final Set<String> _selectedExamSessionIds = {};
  List<ExamSession> _todaysExamSessions = [];
  String? _previewStudentId;
  int _reportPreviewEpoch = 0;
  Timer? _classReportPersistDebounce;
  Timer? _reportDraftPersistDebounce;
  Timer? _previewBumpDebounce;

  @override
  void initState() {
    super.initState();
    _greetingController.addListener(_schedulePersistClassReportSettings);
    _closingController.addListener(_schedulePersistClassReportSettings);
    _reportExtraController.addListener(_onReportExtraChanged);
    _initServices();
  }

  void _onReportExtraChanged() {
    _schedulePreviewBump();
    _schedulePersistReportDraft();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final parsed = _parseRouteArguments(routeArgs);
    final routeClass = parsed.className;
    final routeReportMode = parsed.reportMode;
    if (routeClass == null) {
      _reportMode = routeReportMode;
      _didApplyRouteArguments = true;
      return;
    }

    final classChanged = _selectedClass != routeClass;
    final modeChanged = _reportMode != routeReportMode;
    if (!_didApplyRouteArguments || classChanged || modeChanged) {
      _selectedClass = routeClass;
      _reportMode = routeReportMode;
      if (_servicesReady) {
        _loadClassData();
      }
    }
    _didApplyRouteArguments = true;
  }

  Future<void> _initServices() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _academyLabel = _resolveAcademyLabel(prefs);
    _announcementService = AnnouncementService(prefs: prefs);
    _studentService = StudentService(prefs: prefs);
    _gradeRecordService = GradeRecordService(prefs: prefs);
    final homeworkPageService = HomeworkPageService(prefs: prefs);
    _examSessionService = ExamSessionService(prefs: prefs);
    _classReportSettingsService = ClassReportSettingsService(prefs: prefs);
    _classReportDraftService = ClassReportDraftService(prefs: prefs);
    final examSessionService = _examSessionService;
    final lessonContentService = LessonContentService(prefs: prefs);
    _messageGenerator = AnnouncementMessageGenerator(
      academyLabel: _academyLabel,
      gradeRecordService: _gradeRecordService,
      gradeService: GradeService(prefs: prefs),
      homeworkPageService: homeworkPageService,
      examSessionService: examSessionService,
      lessonContentService: lessonContentService,
    );
    await _studentService.initializeMockStudents();
    _classNames = await _studentService.getClassNames();
    if (_classNames.isEmpty) {
      _selectedClass = null;
    } else if (_selectedClass == null ||
        !_classNames.contains(_selectedClass)) {
      _selectedClass = _classNames.first;
    }
    _servicesReady = true;

    if (_selectedClass == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    await _loadStudents();
    await _loadAnnouncements();
    if (_reportMode) {
      await _applyReportModeState();
    }
  }

  Future<void> _loadStudents() async {
    final selectedClass = _selectedClass;
    if (selectedClass == null) {
      setState(() {
        _classStudents = const [];
        _selectedStudents = const {};
      });
      return;
    }

    final students = await _studentService.getStudentsByClass(selectedClass);
    if (!mounted) return;
    setState(() {
      _classStudents = students;
      _selectedStudents = {for (var s in students) s.id: true};
    });
  }

  Future<void> _loadAnnouncements() async {
    final selectedClass = _selectedClass;
    if (selectedClass == null) {
      setState(() {
        _announcements = const [];
        _isLoading = false;
      });
      return;
    }

    final announcements = await _announcementService.getAnnouncementsByClass(
      selectedClass,
    );
    if (!mounted) return;

    setState(() {
      _announcements = announcements;
      _isLoading = false;
    });
  }

  Future<void> _sendAnnouncement(
    Announcement announcement,
    String className,
  ) async {
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

    if (!await SMSService.isConfigured(_prefs)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(SMSService.buildConfigurationErrorMessage())),
        );
      }
      return;
    }

    final students = await _studentService.getStudentsByClass(className);

    // 선택된 학생들만 필터링
    final selectedStudents = students
        .where((s) => _selectedStudents[s.id] ?? false)
        .toList();

    final studentsWithPhone = selectedStudents
        .where((s) => s.parentPhone != null && s.parentPhone!.isNotEmpty)
        .toList();

    if (studentsWithPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택된 학생 중 학부모 전화번호가 없습니다.')),
        );
      }
      return;
    }

    // 각 학생별로 자동 생성된 메시지로 발송 및 로그 저장
    final messages = await _messageGenerator.generateMessagesForClass(
      className,
      studentsWithPhone,
    );
    int successCount = 0;
    int failureCount = 0;

    for (final student in studentsWithPhone) {
      final personalized = messages[student.id]?.trim() ?? '';
      final commonNotice = _buildAnnouncementNotice(announcement);
      final message = personalized.isEmpty
          ? commonNotice
          : commonNotice.isEmpty
          ? personalized
          : '$personalized\n\n$commonNotice';
      final success = await SMSService.sendSMS(
        phoneNumber: student.parentPhone!,
        message: message,
        prefs: _prefs,
      );

      if (success) {
        successCount++;
      } else {
        failureCount++;
      }

      await _announcementService.saveSMSLog(
        SMSLog(
          id: const Uuid().v4(),
          studentId: student.id,
          parentPhone: student.parentPhone,
          announcementId: announcement.id,
          sentTime: DateTime.now(),
          isSuccess: success,
          errorMessage: success ? null : 'SMS 전송 실패',
        ),
      );
    }

    // Record sending time
    await _announcementService.recordSendingTime(className, DateTime.now());

    // Update announcement
    final updated = announcement.copyWith(
      sentCount: successCount,
      lastSentTime: DateTime.now(),
    );
    await _announcementService.saveAnnouncement(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount명에게 전송 완료 (실패: $failureCount명)')),
      );
      _loadAnnouncements();
    }
  }

  Future<void> _createAnnouncement() async {
    if (_selectedClass == null) return;
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제목과 내용을 입력해주세요.')));
      return;
    }

    final announcement = Announcement(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      className: _selectedClass!,
      title: _titleController.text,
      content: _contentController.text,
      createdAt: DateTime.now(),
    );

    await _announcementService.saveAnnouncement(announcement);

    _titleController.clear();
    _contentController.clear();

    _loadAnnouncements();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공지가 저장되었습니다.')));
    }
  }

  void _onClassChanged(String newClass) {
    setState(() {
      _selectedClass = newClass;
      _isLoading = true;
    });
    _loadClassData();
  }

  Future<void> _loadClassData() async {
    await _loadStudents();
    await _loadAnnouncements();
    await _applyReportModeState();
  }

  void _schedulePersistClassReportSettings() {
    if (!_reportMode) return;
    _classReportPersistDebounce?.cancel();
    _classReportPersistDebounce = Timer(
      const Duration(milliseconds: 450),
      _persistClassReportSettingsNow,
    );
  }

  void _schedulePreviewBump() {
    _previewBumpDebounce?.cancel();
    _previewBumpDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _reportPreviewEpoch++);
      }
    });
  }

  Future<void> _persistClassReportSettingsNow() async {
    final cn = _selectedClass;
    if (cn == null || !_reportMode) return;
    await _classReportSettingsService.save(
      ClassReportSettings(
        classKey: cn,
        greetingTemplate: _greetingController.text,
        closingText: _closingController.text,
        includeHomeworkCompletion: _homeworkIncludeCompletion,
        includeHomeworkWeakParts: _homeworkIncludeWeak,
        includeHomeworkResubmissionDeadline: _homeworkIncludeResubmit,
      ),
    );
  }

  void _schedulePersistReportDraft() {
    if (!_reportMode) return;
    _reportDraftPersistDebounce?.cancel();
    _reportDraftPersistDebounce = Timer(
      const Duration(milliseconds: 450),
      _persistReportDraftNow,
    );
  }

  Future<void> _persistReportDraftNow() async {
    final cn = _selectedClass;
    if (cn == null || !_reportMode) return;
    await _classReportDraftService.save(
      cn,
      ClassReportDraft(
        includeTodayLesson: _includeTodayLesson,
        includeNextHomework: _includeNextHomework,
        selectedExamSessionIds: _selectedExamSessionIds.toList(),
        extraNotice: _reportExtraController.text,
      ),
    );
  }

  Future<void> _applyReportModeState() async {
    if (!_reportMode) return;
    final cn = _selectedClass;
    if (cn == null) return;

    final settings = await _classReportSettingsService.load(cn);
    final draft = await _classReportDraftService.load(cn);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final exams = _examSessionService.getSessions(className: cn, examDate: day);

    _greetingController.removeListener(_schedulePersistClassReportSettings);
    _closingController.removeListener(_schedulePersistClassReportSettings);
    _greetingController.text = settings.greetingTemplate;
    _closingController.text = settings.closingText;
    _greetingController.addListener(_schedulePersistClassReportSettings);
    _closingController.addListener(_schedulePersistClassReportSettings);

    _reportExtraController.removeListener(_onReportExtraChanged);
    _reportExtraController.text = draft.extraNotice;
    _reportExtraController.addListener(_onReportExtraChanged);

    final todayExamIds = exams.map((e) => e.id).toSet();
    final persistedExam = draft.selectedExamSessionIds.toSet();
    final examSelection = persistedExam.isEmpty
        ? todayExamIds
        : persistedExam.intersection(todayExamIds).isEmpty &&
              todayExamIds.isNotEmpty
        ? todayExamIds
        : persistedExam.intersection(todayExamIds);

    if (!mounted) return;
    setState(() {
      _homeworkIncludeCompletion = settings.includeHomeworkCompletion;
      _homeworkIncludeWeak = settings.includeHomeworkWeakParts;
      _homeworkIncludeResubmit = settings.includeHomeworkResubmissionDeadline;
      _includeTodayLesson = draft.includeTodayLesson;
      _includeNextHomework = draft.includeNextHomework;
      _todaysExamSessions = exams;
      _selectedExamSessionIds
        ..clear()
        ..addAll(examSelection);
      _previewStudentId = _pickPreviewStudentId();
      _reportPreviewEpoch++;
    });
  }

  String? _pickPreviewStudentId() {
    if (_classStudents.isEmpty) return null;
    final current = _previewStudentId;
    if (current != null) {
      for (final s in _classStudents) {
        if (s.id == current) return current;
      }
    }
    return _classStudents.first.id;
  }

  ClassReportSettings _classReportSettingsFromUi() {
    return ClassReportSettings(
      classKey: _selectedClass ?? '',
      greetingTemplate: _greetingController.text,
      closingText: _closingController.text,
      includeHomeworkCompletion: _homeworkIncludeCompletion,
      includeHomeworkWeakParts: _homeworkIncludeWeak,
      includeHomeworkResubmissionDeadline: _homeworkIncludeResubmit,
    );
  }

  Future<String> _buildPreviewMessage() async {
    final cn = _selectedClass;
    if (cn == null) return '클래스를 선택해주세요.';
    final sid = _previewStudentId;
    Student? student;
    if (sid != null) {
      for (final s in _classStudents) {
        if (s.id == sid) {
          student = s;
          break;
        }
      }
    }
    student ??= _classStudents.isEmpty ? null : _classStudents.first;
    if (student == null) return '학생이 없습니다.';

    return ParentReportMessageBuilder.build(
      student: student,
      className: cn,
      classSettings: _classReportSettingsFromUi(),
      sendOptions: ReportSendOptions(
        includeTodayLesson: _includeTodayLesson,
        includeNextHomework: _includeNextHomework,
        selectedExamSessionIds: Set<String>.from(_selectedExamSessionIds),
      ),
      extraNoticeRaw: _reportExtraController.text,
      prefs: _prefs,
    );
  }

  String _buildAnnouncementNotice(Announcement announcement) {
    final title = announcement.title.trim();
    final content = announcement.content.trim();
    final lines = <String>[];
    if (title.isNotEmpty) {
      lines.add(title);
    }
    if (content.isNotEmpty) {
      lines.addAll(
        content
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
      );
    }
    if (lines.isEmpty) return '';
    final body = lines.map((line) => '* $line').join('\n');
    return '추가 안내\n\n$body';
  }

  String _resolveAcademyLabel(SharedPreferences prefs) {
    const academyNameKey = 'academy_info_name_v1';
    const branchNameKey = 'academy_info_branch_v1';
    final academy =
        (prefs.getString(academyNameKey) ?? AppConstants.academyName).trim();
    final branch =
        (prefs.getString(branchNameKey) ?? AppConstants.academyBranch).trim();
    if (academy.isEmpty && branch.isEmpty) return AppConstants.academyName;
    if (academy.isEmpty) return branch;
    if (branch.isEmpty) return academy;
    return '$academy $branch';
  }

  @override
  void dispose() {
    if (_reportMode) {
      unawaited(_persistClassReportSettingsNow());
      unawaited(_persistReportDraftNow());
    }
    _classReportPersistDebounce?.cancel();
    _reportDraftPersistDebounce?.cancel();
    _previewBumpDebounce?.cancel();
    _greetingController.removeListener(_schedulePersistClassReportSettings);
    _closingController.removeListener(_schedulePersistClassReportSettings);
    _reportExtraController.removeListener(_onReportExtraChanged);
    _titleController.dispose();
    _contentController.dispose();
    _greetingController.dispose();
    _closingController.dispose();
    _reportExtraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedClass = _selectedClass;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _reportMode
              ? (selectedClass == null ? '리포트 편집' : '$selectedClass · 리포트 편집')
              : (selectedClass == null ? '공지' : '$selectedClass 공지'),
        ),
        backgroundColor: AppColors.overlay,
        foregroundColor: AppColors.navy,
        elevation: 0,
      ),
      body: selectedClass == null
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
                  _buildClassSelector(),
                  const SizedBox(height: 24),
                  if (!_reportMode) _buildStudentSelector(),
                  if (!_reportMode) const SizedBox(height: 24),
                  if (_reportMode) ...[
                    const SizedBox(height: 24),
                    _buildReportSendPanel(),
                  ] else ...[
                    const SizedBox(height: 24),
                    _buildAnnouncementForm(),
                    const SizedBox(height: 32),
                    _buildAnnouncementsList(),
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
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedClass,
              isExpanded: true,
              dropdownColor: AppColors.card,
              items: _classNames
                  .map(
                    (className) => DropdownMenuItem(
                      value: className,
                      child: Text(
                        className,
                        style: const TextStyle(color: AppColors.navy),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  _onClassChanged(value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentSelector() {
    if (_classStudents.isEmpty) {
      return const SizedBox.shrink();
    }

    final allSelected =
        _classStudents.isNotEmpty &&
        _classStudents.every(
          (student) => _selectedStudents[student.id] ?? false,
        );
    final selectedCount = _classStudents
        .where((student) => _selectedStudents[student.id] ?? false)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '학생 선택',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.subText,
              ),
            ),
            TextButton(
              onPressed: () {
                final nextValue = !allSelected;
                setState(() {
                  for (final student in _classStudents) {
                    _selectedStudents[student.id] = nextValue;
                  }
                });
              },
              child: Text(
                allSelected ? '전체 해제' : '전체 선택',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        Text(
          '$selectedCount명 선택됨',
          style: const TextStyle(fontSize: 12, color: AppColors.subText),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: _classStudents.map((student) {
              return CheckboxListTile(
                value: _selectedStudents[student.id] ?? false,
                activeColor: AppColors.blue,
                checkColor: Colors.white,
                onChanged: (value) {
                  setState(() {
                    _selectedStudents[student.id] = value ?? false;
                    if (_previewStudentId != null &&
                        (_selectedStudents[_previewStudentId!] != true)) {
                      _previewStudentId = _pickPreviewStudentId();
                    }
                    if (_reportMode) _reportPreviewEpoch++;
                  });
                },
                title: Text(
                  student.name,
                  style: const TextStyle(color: AppColors.navy),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '새 공지사항',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: '내용',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _createAnnouncement,
                    child: const Text('공지 저장'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportSendPanel() {
    final classLabel = _selectedClass ?? '-';
    final previewStudents = _classStudents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '리포트 편집',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          classLabel,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const Text(
          '내용은 저장되며, 학생 탭에서 문자·일괄 전송 시 반영됩니다.',
          style: TextStyle(fontSize: 13, color: AppColors.subText),
        ),
        const SizedBox(height: 16),
        _reportSectionTitle('인사말'),
        const SizedBox(height: 8),
        TextField(
          controller: _greetingController,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: '{학생이름}은 발송 시 학생 이름으로 바뀝니다.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        _reportSectionTitle('전송 내용 선택'),
        const SizedBox(height: 8),
        const Text(
          '숙제',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: AppColors.navy,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('이행률'),
                value: _homeworkIncludeCompletion,
                onChanged: (v) {
                  setState(() {
                    _homeworkIncludeCompletion = v ?? true;
                    _reportPreviewEpoch++;
                  });
                  unawaited(_persistClassReportSettingsNow());
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('부족한 점'),
                value: _homeworkIncludeWeak,
                onChanged: (v) {
                  setState(() {
                    _homeworkIncludeWeak = v ?? true;
                    _reportPreviewEpoch++;
                  });
                  unawaited(_persistClassReportSettingsNow());
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('재제출 기한'),
                value: _homeworkIncludeResubmit,
                onChanged: (v) {
                  setState(() {
                    _homeworkIncludeResubmit = v ?? true;
                    _reportPreviewEpoch++;
                  });
                  unawaited(_persistClassReportSettingsNow());
                },
              ),
            ],
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('오늘 수업 내용'),
          value: _includeTodayLesson,
          onChanged: (v) {
            setState(() {
              _includeTodayLesson = v ?? true;
              _reportPreviewEpoch++;
            });
            unawaited(_persistReportDraftNow());
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('다음주 숙제'),
          value: _includeNextHomework,
          onChanged: (v) {
            setState(() {
              _includeNextHomework = v ?? true;
              _reportPreviewEpoch++;
            });
            unawaited(_persistReportDraftNow());
          },
        ),
        const SizedBox(height: 6),
        const Text(
          '오늘 시험',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: AppColors.navy,
          ),
        ),
        if (_todaysExamSessions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(left: 12, top: 4),
            child: Text(
              '오늘 등록된 시험이 없습니다.',
              style: TextStyle(fontSize: 12, color: AppColors.subText),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: _todaysExamSessions.map((session) {
                final title = session.examName.trim().isNotEmpty
                    ? session.examName.trim()
                    : session.examTypeDisplayName;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(title, style: const TextStyle(fontSize: 13)),
                  value: _selectedExamSessionIds.contains(session.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedExamSessionIds.add(session.id);
                      } else {
                        _selectedExamSessionIds.remove(session.id);
                      }
                      _reportPreviewEpoch++;
                    });
                    unawaited(_persistReportDraftNow());
                  },
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 20),
        _reportSectionTitle('마무리'),
        const SizedBox(height: 8),
        TextField(
          controller: _closingController,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        _reportSectionTitle('추가안내'),
        const SizedBox(height: 8),
        TextField(
          controller: _reportExtraController,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '저장되며 문자 발송 시 포함됩니다. 비우면 생략됩니다.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        _reportSectionTitle('미리보기'),
        const SizedBox(height: 8),
        if (previewStudents.length > 1) ...[
          Row(
            children: [
              const Text('미리보기 기준: ', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value:
                          _previewStudentId != null &&
                              previewStudents.any(
                                (e) => e.id == _previewStudentId,
                              )
                          ? _previewStudentId
                          : previewStudents.first.id,
                      items: previewStudents
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.name),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          _previewStudentId = id;
                          _reportPreviewEpoch++;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Card(
          color: AppColors.graySoft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<String>(
              key: ValueKey(_reportPreviewEpoch),
              future: _buildPreviewMessage(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return SelectableText(
                  snap.data ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.navy,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.subText,
      ),
    );
  }

  Widget _buildAnnouncementsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_announcements.isEmpty) {
      return const Center(
        child: Text(
          '작성된 공지가 없습니다.',
          style: TextStyle(color: AppColors.subText),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '공지사항 (${_announcements.length}개)',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.subText,
          ),
        ),
        const SizedBox(height: 12),
        ...(_announcements.map(
          (announcement) => _buildAnnouncementCard(announcement),
        )),
      ],
    );
  }

  Widget _buildAnnouncementCard(Announcement announcement) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        announcement.createdAt.toString().split('.')[0],
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.subText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (announcement.sentCount != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.graySoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      '${announcement.sentCount}명',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              announcement.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.subText),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    _sendAnnouncement(announcement, announcement.className),
                child: const Text('학부모에게 전송'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementRouteArgs {
  final String? className;
  final bool reportMode;

  const _AnnouncementRouteArgs({this.className, this.reportMode = false});
}

_AnnouncementRouteArgs _parseRouteArguments(dynamic args) {
  if (args is String) {
    final trimmed = args.trim();
    return _AnnouncementRouteArgs(className: trimmed.isEmpty ? null : trimmed);
  }
  if (args is Map) {
    final className = args['className'];
    final reportMode = args['reportMode'] == true;
    return _AnnouncementRouteArgs(
      className: className is String && className.trim().isNotEmpty
          ? className.trim()
          : null,
      reportMode: reportMode,
    );
  }
  return const _AnnouncementRouteArgs();
}
