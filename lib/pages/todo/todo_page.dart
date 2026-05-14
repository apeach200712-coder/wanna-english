import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../core/time_utils.dart';
import '../../data/models/todo_model.dart';
import '../../services/todo_service.dart';
import '../../theme/app_colors.dart';

const _todoPaletteOptions = [
  _TodoPaletteOption('Ocean', [
    Color(0xFFEAF3FF),
    Color(0xFFCFE0FF),
    Color(0xFF9ABFFF),
    Color(0xFF5B8CFF),
    Color(0xFF2D63E8),
  ]),
  _TodoPaletteOption('Sky', [
    Color(0xFFE8F7FF),
    Color(0xFFC6EAFF),
    Color(0xFF8FD6FF),
    Color(0xFF42B8FF),
    Color(0xFF1887D9),
  ]),
  _TodoPaletteOption('Mint', [
    Color(0xFFE9FBF7),
    Color(0xFFC8F4E9),
    Color(0xFF93E7D1),
    Color(0xFF52CFAE),
    Color(0xFF27A37F),
  ]),
  _TodoPaletteOption('Leaf', [
    Color(0xFFF0FBEF),
    Color(0xFFD9F4D2),
    Color(0xFFB2E89F),
    Color(0xFF79CF60),
    Color(0xFF4A9B35),
  ]),
  _TodoPaletteOption('Sun', [
    Color(0xFFFFFAE7),
    Color(0xFFFFF0B8),
    Color(0xFFFFE07A),
    Color(0xFFFFC94B),
    Color(0xFFE49D17),
  ]),
  _TodoPaletteOption('Orange', [
    Color(0xFFFFF2E8),
    Color(0xFFFFDEC7),
    Color(0xFFFFBB8B),
    Color(0xFFFF8A5B),
    Color(0xFFD45A26),
  ]),
  _TodoPaletteOption('Coral', [
    Color(0xFFFFEEEC),
    Color(0xFFFFD2CC),
    Color(0xFFFFA79B),
    Color(0xFFFF7261),
    Color(0xFFD94B3A),
  ]),
  _TodoPaletteOption('Rose', [
    Color(0xFFFFEFF5),
    Color(0xFFFFD3E3),
    Color(0xFFFFA4C2),
    Color(0xFFFF6F9F),
    Color(0xFFD54879),
  ]),
  _TodoPaletteOption('Lavender', [
    Color(0xFFF3EEFF),
    Color(0xFFE0D3FF),
    Color(0xFFC0A7FF),
    Color(0xFF9A74FF),
    Color(0xFF6D49D8),
  ]),
  _TodoPaletteOption('Slate', [
    Color(0xFFF2F4F8),
    Color(0xFFDCE2EB),
    Color(0xFFBBC7D8),
    Color(0xFF8796AD),
    Color(0xFF55657D),
  ]),
];

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final TodoService _todoService = TodoService.instance;
  late Future<void> _loadFuture;
  bool _routeDateApplied = false;

  static const _weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _loadFuture = _todoService.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeDateApplied) return;
    _routeDateApplied = true;

    DateTime? fromRoute;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is DateTime) {
      fromRoute = TodoService.calendarDayOnly(args);
    }

    // Run after [load] completes so we never race a second [_hydrateSections]
    // with [selectDate]'s persisted active-day restore.
    _loadFuture = _loadFuture.then((_) async {
      if (!mounted) return;
      if (fromRoute != null) {
        await _todoService.selectDate(fromRoute);
        return;
      }
      final now = nowKst();
      await _todoService.selectDate(
        DateTime(now.year, now.month, now.day),
      );
    });
  }

  String _dateLabel(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final w = _weekday[d.weekday - 1];
    return '${d.year}.${d.month}.${d.day} ($w)';
  }

  Future<void> _pickDate() async {
    final activeDate = _todoService.activeDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: activeDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      currentDate: todayKst(),
    );
    if (picked == null) return;
    await _todoService.selectDate(picked);
  }

  Future<void> _showAddSectionSheet() async {
    final draft = await showModalBottomSheet<_NewSectionDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddSectionSheet(),
    );

    if (draft == null) return;

    await _todoService.addSection(
      title: draft.sectionTitle,
      color: draft.color,
      isPinned: draft.isPinned,
    );
  }

  Future<void> _showAddTaskSheet(TodoSectionModel section) async {
    final draft = await showModalBottomSheet<_NewTaskDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddTaskSheet(section: section),
    );

    if (draft == null) return;

    await _todoService.addTask(
      sectionId: section.id,
      title: draft.title,
      time: draft.time,
      memo: draft.memo,
      progress: draft.progress,
    );
  }

  Future<void> _showEditTaskSheet({
    required TodoSectionModel section,
    required TodoTaskModel task,
  }) async {
    final draft = await showModalBottomSheet<_EditTaskDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditTaskSheet(section: section, task: task),
    );

    if (draft == null) return;

    await _todoService.updateTask(
      sectionId: section.id,
      taskId: task.id,
      title: draft.title,
      time: draft.time,
      memo: draft.memo,
    );
  }

  Future<void> _confirmDeleteSection(TodoSectionModel section) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('목록 삭제'),
          content: Text('"${section.title}" 목록과 모든 할 일을 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) return;
    await _todoService.deleteSection(sectionId: section.id);
  }

  Future<void> _confirmDeleteTask({
    required TodoSectionModel section,
    required TodoTaskModel task,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('할 일 삭제'),
          content: Text('"${task.title}"을(를) 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    await _todoService.deleteTask(sectionId: section.id, taskId: task.id);
  }

  Widget _buildSectionCard(TodoSectionModel section, double gap) {
    return TodoSectionCard(
      section: section,
      bottomGap: gap,
      onAddTask: () => _showAddTaskSheet(section),
      onEditColor: () async {
        final color = await _showColorPickerSheet(context, section.color);
        if (color == null) return;
        await _todoService.updateSectionColor(
          sectionId: section.id,
          color: color,
        );
      },
      onDeleteSection: () => _confirmDeleteSection(section),
      onChangeProgress: (taskId, progress) {
        _todoService.updateTaskProgress(
          sectionId: section.id,
          taskId: taskId,
          progress: progress,
        );
      },
      onTogglePinned: (taskId) {
        _todoService.toggleTaskPinned(sectionId: section.id, taskId: taskId);
      },
      onEditTask: (task) {
        _showEditTaskSheet(section: section, task: task);
      },
      onDeleteTask: (task) {
        _confirmDeleteTask(section: section, task: task);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              _todoService.sections.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return AnimatedBuilder(
            animation: _todoService,
            builder: (context, _) {
              final sections = _todoService.sections;
              final activeDate = _todoService.activeDate;
              final hPad = Responsive.hPadding(context);
              final vTop = Responsive.vPaddingTop(context);
              final vBot = Responsive.vPaddingBottom(context);
              final sectionGap = Responsive.todoSectionGap(context);
              final maxW = Responsive.maxContentWidth(context);
              final isWide = Responsive.todoTwoColumns(context);

              // On tablet-landscape: show two equal columns of sections
              Widget sectionContent;
              if (isWide && sections.isNotEmpty) {
                final mid = (sections.length / 2).ceil();
                final left = sections.sublist(0, mid);
                final right = sections.sublist(mid);
                sectionContent = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: left
                            .map((s) => _buildSectionCard(s, sectionGap))
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: right
                            .map((s) => _buildSectionCard(s, sectionGap))
                            .toList(),
                      ),
                    ),
                  ],
                );
              } else if (sections.isEmpty) {
                sectionContent = _EmptyTodoState(onAdd: _showAddSectionSheet);
              } else {
                sectionContent = Column(
                  children: sections
                      .map((s) => _buildSectionCard(s, sectionGap))
                      .toList(),
                );
              }

              return SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(hPad, vTop, hPad, vBot),
                      children: [
                        TodoDetailHeader(
                          title: 'Feed',
                          subtitle: _dateLabel(activeDate),
                          onSubtitleTap: _pickDate,
                          onBack: () => Navigator.pop(context),
                          onAdd: _showAddSectionSheet,
                          showAddAction: sections.isNotEmpty,
                        ),
                        const SizedBox(height: 16),
                        sectionContent,
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class TodoDetailHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSubtitleTap;
  final VoidCallback onBack;
  final Future<void> Function() onAdd;
  final bool showAddAction;

  const TodoDetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSubtitleTap,
    required this.onBack,
    required this.onAdd,
    this.showAddAction = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                  height: 1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onSubtitleTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.subText,
                        ),
                      ),
                      if (onSubtitleTap != null) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 15,
                          color: AppColors.subText,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showAddAction) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 22,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class TodoSectionCard extends StatelessWidget {
  final TodoSectionModel section;
  final double bottomGap;
  final VoidCallback onAddTask;
  final VoidCallback onEditColor;
  final VoidCallback onDeleteSection;
  final void Function(String taskId, TodoTaskProgress progress)
  onChangeProgress;
  final ValueChanged<String> onTogglePinned;
  final ValueChanged<TodoTaskModel> onEditTask;
  final ValueChanged<TodoTaskModel> onDeleteTask;

  const TodoSectionCard({
    super.key,
    required this.section,
    this.bottomGap = 22,
    required this.onAddTask,
    required this.onEditColor,
    required this.onDeleteSection,
    required this.onChangeProgress,
    required this.onTogglePinned,
    required this.onEditTask,
    required this.onDeleteTask,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(section.icon, size: 16, color: AppColors.navy),
                    const SizedBox(width: 8),
                    Text(
                      section.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: section.color,
                        height: 1,
                      ),
                    ),
                    if (section.isPinned) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: section.color,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _MiniHeaderAction(icon: Icons.add_rounded, onTap: onAddTask),
              const SizedBox(width: 6),
              _MiniHeaderAction(
                icon: Icons.palette_outlined,
                onTap: onEditColor,
              ),
              const SizedBox(width: 6),
              _MiniHeaderAction(
                icon: Icons.delete_outline_rounded,
                onTap: onDeleteSection,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...section.tasks.map(
            (task) => TodoTaskRow(
              sectionColor: section.color,
              task: task,
              onChangeProgress: (progress) {
                onChangeProgress(task.id, progress);
              },
              onTogglePinned: () => onTogglePinned(task.id),
              onEditTask: () => onEditTask(task),
              onDeleteTask: () => onDeleteTask(task),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniHeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MiniHeaderAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, size: 16, color: AppColors.subText),
      ),
    );
  }
}

class TodoTaskRow extends StatelessWidget {
  final TodoTaskModel task;
  final Color sectionColor;
  final ValueChanged<TodoTaskProgress> onChangeProgress;
  final VoidCallback onTogglePinned;
  final VoidCallback onEditTask;
  final VoidCallback onDeleteTask;

  const TodoTaskRow({
    super.key,
    required this.task,
    required this.sectionColor,
    required this.onChangeProgress,
    required this.onTogglePinned,
    required this.onEditTask,
    required this.onDeleteTask,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _progressColor(task.progress, sectionColor);
    final trailingIcon = task.isPinned
        ? Icons.star_rounded
        : Icons.star_border_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PopupMenuButton<TodoTaskProgress>(
            initialValue: task.progress,
            tooltip: '상태',
            onSelected: onChangeProgress,
            itemBuilder: (context) {
              return TodoTaskProgress.values
                  .map(
                    (progress) => PopupMenuItem<TodoTaskProgress>(
                      value: progress,
                      child: Row(
                        children: [
                          _ProgressBadge(
                            progress: progress,
                            color: _progressColor(progress, sectionColor),
                          ),
                          const SizedBox(width: 10),
                          Text(progress.label),
                        ],
                      ),
                    ),
                  )
                  .toList();
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: _ProgressBadge(
                progress: task.progress,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: task.isDone ? AppColors.subText : AppColors.navy,
                    height: 1,
                    decoration: task.isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                if (task.time != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    task.time!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.subText,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
                if (task.memo != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      task.memo!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.subText,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: onTogglePinned,
            child: Icon(
              trailingIcon,
              color: task.isPinned
                  ? const Color(0xFFF59E0B)
                  : AppColors.subText,
              size: 21,
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '메뉴',
            onSelected: (value) {
              if (value == 'edit') {
                onEditTask();
                return;
              }
              if (value == 'delete') {
                onDeleteTask();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(value: 'edit', child: Text('수정')),
              PopupMenuItem<String>(value: 'delete', child: Text('삭제')),
            ],
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppColors.subText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditTaskDraft {
  final String title;
  final String? time;
  final String? memo;

  const _EditTaskDraft({required this.title, this.time, this.memo});
}

class _EditTaskSheet extends StatefulWidget {
  final TodoSectionModel section;
  final TodoTaskModel task;

  const _EditTaskSheet({required this.section, required this.task});

  @override
  State<_EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<_EditTaskSheet> {
  late final TextEditingController _taskController;
  late final TextEditingController _timeController;
  late final TextEditingController _memoController;

  @override
  void initState() {
    super.initState();
    _taskController = TextEditingController(text: widget.task.title);
    _timeController = TextEditingController(text: widget.task.time ?? '');
    _memoController = TextEditingController(text: widget.task.memo ?? '');
  }

  @override
  void dispose() {
    _taskController.dispose();
    _timeController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return _BottomSheetFrame(
      bottomInset: bottomInset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '할 일 수정',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.section.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(widget.section.icon, color: widget.section.color),
                const SizedBox(width: 10),
                Text(
                  widget.section.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: widget.section.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SheetTextField(
            controller: _taskController,
            label: '할 일',
            hint: '예: 단어 재시험 문항 출력',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SheetTextField(
                  controller: _timeController,
                  label: '시간',
                  hint: '선택 입력',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetTextField(
                  controller: _memoController,
                  label: '메모',
                  hint: '선택 입력',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PrimarySheetButton(
            label: '저장',
            onPressed: () {
              final title = _taskController.text.trim();
              if (title.isEmpty) return;

              Navigator.pop(
                context,
                _EditTaskDraft(
                  title: title,
                  time: _emptyToNull(_timeController.text),
                  memo: _emptyToNull(_memoController.text),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProgressBadge extends StatelessWidget {
  final TodoTaskProgress progress;
  final Color color;

  const _ProgressBadge({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(child: progress.progressGlyph(color, 15)),
    );
  }
}

class _EmptyTodoState extends StatelessWidget {
  final Future<void> Function() onAdd;

  const _EmptyTodoState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '아직 비어있어요',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '첫 리스트를 추가해보세요',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.subText,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '새 목록',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewSectionDraft {
  final String sectionTitle;
  final Color color;
  final bool isPinned;

  const _NewSectionDraft({
    required this.sectionTitle,
    required this.color,
    required this.isPinned,
  });
}

class _NewTaskDraft {
  final String title;
  final String? time;
  final String? memo;
  final TodoTaskProgress progress;

  const _NewTaskDraft({
    required this.title,
    required this.time,
    required this.memo,
    required this.progress,
  });
}

class _AddSectionSheet extends StatefulWidget {
  const _AddSectionSheet();

  @override
  State<_AddSectionSheet> createState() => _AddSectionSheetState();
}

class _AddSectionSheetState extends State<_AddSectionSheet> {
  late final TextEditingController _sectionController;

  Color _selectedColor = _todoPaletteOptions.first.shades[3];
  bool _isPinned = false;

  @override
  void initState() {
    super.initState();
    _sectionController = TextEditingController();
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return _BottomSheetFrame(
      bottomInset: bottomInset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '새 목록',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          _SheetTextField(
            controller: _sectionController,
            label: '이름',
            hint: '예: 이화여고2',
          ),
          const SizedBox(height: 12),
          _CompactColorField(
            color: _selectedColor,
            onTap: () async {
              final picked = await _showColorPickerSheet(
                context,
                _selectedColor,
              );
              if (picked == null) return;
              setState(() => _selectedColor = picked);
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _isPinned,
            onChanged: (value) => setState(() => _isPinned = value),
            title: const Text(
              '고정',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PrimarySheetButton(
            label: '저장',
            onPressed: () {
              final sectionTitle = _sectionController.text.trim();
              if (sectionTitle.isEmpty) return;

              Navigator.pop(
                context,
                _NewSectionDraft(
                  sectionTitle: sectionTitle,
                  color: _selectedColor,
                  isPinned: _isPinned,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CompactColorField extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _CompactColorField({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.graySoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '색상',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: softShadow(),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.subText,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTaskSheet extends StatefulWidget {
  final TodoSectionModel section;

  const _AddTaskSheet({required this.section});

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  late final TextEditingController _taskController;
  late final TextEditingController _timeController;
  late final TextEditingController _memoController;

  @override
  void initState() {
    super.initState();
    _taskController = TextEditingController();
    _timeController = TextEditingController();
    _memoController = TextEditingController();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _timeController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return _BottomSheetFrame(
      bottomInset: bottomInset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '할 일 추가',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.section.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(widget.section.icon, color: widget.section.color),
                const SizedBox(width: 10),
                Text(
                  widget.section.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: widget.section.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SheetTextField(
            controller: _taskController,
            label: '할 일',
            hint: '예: 단어 재시험 문항 출력',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SheetTextField(
                  controller: _timeController,
                  label: '시간',
                  hint: '선택 입력',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetTextField(
                  controller: _memoController,
                  label: '메모',
                  hint: '선택 입력',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PrimarySheetButton(
            label: '저장',
            onPressed: () {
              final taskTitle = _taskController.text.trim();
              if (taskTitle.isEmpty) return;

              Navigator.pop(
                context,
                _NewTaskDraft(
                  title: taskTitle,
                  time: _emptyToNull(_timeController.text),
                  memo: _emptyToNull(_memoController.text),
                  progress: TodoTaskProgress.notDone,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BottomSheetFrame extends StatelessWidget {
  final Widget child;
  final double bottomInset;

  const _BottomSheetFrame({required this.child, required this.bottomInset});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(22, 22, 22, bottomInset + 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.graySoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class _PrimarySheetButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimarySheetButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _TodoPaletteOption {
  final String name;
  final List<Color> shades;

  const _TodoPaletteOption(this.name, this.shades);
}

Color _progressColor(TodoTaskProgress progress, Color accentColor) {
  switch (progress) {
    case TodoTaskProgress.done:
      return accentColor;
    case TodoTaskProgress.inProgress:
      return const Color(0xFFF59E0B);
    case TodoTaskProgress.notDone:
      return const Color(0xFFEF4444);
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<Color?> _showColorPickerSheet(BuildContext context, Color currentColor) {
  return showModalBottomSheet<Color>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => _ColorPickerSheet(currentColor: currentColor),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color currentColor;

  const _ColorPickerSheet({required this.currentColor});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.currentColor;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '색상 변경',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          ..._todoPaletteOptions.map(
            (palette) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: palette.shades.map((shade) {
                  final isSelected =
                      shade.toARGB32() == _selectedColor.toARGB32();
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = shade),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: shade,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.navy : Colors.white,
                          width: isSelected ? 2.2 : 1.1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _PrimarySheetButton(
            label: '적용',
            onPressed: () => Navigator.pop(context, _selectedColor),
          ),
        ],
      ),
    );
  }
}
