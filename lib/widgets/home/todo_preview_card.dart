import 'package:flutter/material.dart';

import '../../core/routes.dart';
import '../../core/time_utils.dart';
import '../../data/models/todo_model.dart';
import '../../services/todo_service.dart';
import '../../theme/app_colors.dart';

class TodoPreviewCard extends StatefulWidget {
  /// When true (inside [Expanded]), list fills remaining card height.
  final bool fillRemaining;

  /// When outer layout scrolls, caps list height so alerts stay on screen.
  final double? maxListHeight;

  final double titleFontSize;
  final double rowTitleFontSize;
  final double emptyMessageFontSize;
  final EdgeInsetsGeometry padding;

  const TodoPreviewCard({
    super.key,
    this.fillRemaining = false,
    this.maxListHeight,
    this.titleFontSize = 22,
    this.rowTitleFontSize = 17,
    this.emptyMessageFontSize = 15,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 15),
  });

  @override
  State<TodoPreviewCard> createState() => _TodoPreviewCardState();
}

class _TodoPreviewCardState extends State<TodoPreviewCard> {
  final TodoService _todoService = TodoService.instance;
  late final Future<void> _loadFuture;

  DateTime _todayKst() {
    return todayKst();
  }

  Future<void> _openTodayTodo() {
    final today = TodoService.calendarDayOnly(_todayKst());
    return Navigator.pushNamed(context, AppRoutes.todo, arguments: today);
  }

  @override
  void initState() {
    super.initState();
    // Only hydrate storage. Do NOT call [selectDate] here: this async can finish
    // after the user opens To-Do from the calendar for another day and would
    // overwrite [TodoService]'s active date with today.
    _loadFuture = _todoService.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            _todoService.sections.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return AnimatedBuilder(
          animation: _todoService,
          builder: (context, _) {
            final previewItems = _todoService.previewItems;

            final addSize = (widget.titleFontSize * 1.35).clamp(30.0, 34.0);
            final addIcon = (widget.titleFontSize * 0.95).clamp(20.0, 22.0);
            final gapAfterTitle = (widget.titleFontSize * 0.65).clamp(
              12.0,
              16.0,
            );

            Widget listSection() {
              if (previewItems.isEmpty) {
                final empty = Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '즐겨찾기한 To-Do가 없습니다.',
                    style: TextStyle(
                      fontSize: widget.emptyMessageFontSize,
                      fontWeight: FontWeight.w600,
                      color: AppColors.subText,
                    ),
                  ),
                );
                if (widget.fillRemaining) {
                  return Expanded(child: Center(child: empty));
                }
                return empty;
              }
              final rowWidgets = previewItems
                  .map(
                    (item) => TodoPreviewRow(
                      item: item,
                      titleFontSize: widget.rowTitleFontSize,
                      onChangeProgress: (progress) async {
                        await _todoService.selectDate(
                          TodoService.calendarDayOnly(_todayKst()),
                          notify: false,
                        );
                        await _todoService.updateTaskProgress(
                          sectionId: item.sectionId,
                          taskId: item.task.id,
                          progress: progress,
                        );
                      },
                    ),
                  )
                  .toList();
              final col = Column(
                mainAxisSize: MainAxisSize.min,
                children: rowWidgets,
              );
              if (widget.fillRemaining) {
                return Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: rowWidgets,
                  ),
                );
              }
              final cap = widget.maxListHeight;
              if (cap != null && cap.isFinite) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: cap),
                  child: SingleChildScrollView(child: col),
                );
              }
              return col;
            }

            return Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: widget.fillRemaining
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '오늘 즐겨찾기 To-Do',
                        style: TextStyle(
                          fontSize: widget.titleFontSize,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _openTodayTodo,
                        child: Container(
                          width: addSize,
                          height: addSize,
                          decoration: BoxDecoration(
                            color: AppColors.graySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            size: addIcon,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: gapAfterTitle),
                  listSection(),
                  const SizedBox(height: 4),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class TodoPreviewRow extends StatelessWidget {
  final TodoPreviewItem item;
  final ValueChanged<TodoTaskProgress> onChangeProgress;
  final double titleFontSize;

  const TodoPreviewRow({
    super.key,
    required this.item,
    required this.onChangeProgress,
    this.titleFontSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    final todo = item.task;
    final statusColor = _previewProgressColor(todo.progress, item.sectionColor);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PopupMenuButton<TodoTaskProgress>(
            initialValue: todo.progress,
            tooltip: '상태',
            onSelected: onChangeProgress,
            itemBuilder: (context) {
              return TodoTaskProgress.values
                  .map(
                    (progress) => PopupMenuItem<TodoTaskProgress>(
                      value: progress,
                      child: Row(
                        children: [
                          _PreviewProgressBadge(
                            progress: progress,
                            color: _previewProgressColor(
                              progress,
                              item.sectionColor,
                            ),
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
              padding: const EdgeInsets.only(top: 2),
              child: _PreviewProgressBadge(
                progress: todo.progress,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.sectionTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: item.sectionColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  todo.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    color: todo.isDone ? AppColors.subText : AppColors.navy,
                    fontWeight: FontWeight.w500,
                    decoration: todo.isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewProgressBadge extends StatelessWidget {
  final TodoTaskProgress progress;
  final Color color;

  const _PreviewProgressBadge({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Center(child: progress.progressGlyph(color, 18)),
    );
  }
}

Color _previewProgressColor(TodoTaskProgress progress, Color accentColor) {
  switch (progress) {
    case TodoTaskProgress.done:
      return accentColor;
    case TodoTaskProgress.inProgress:
      return const Color(0xFFF59E0B);
    case TodoTaskProgress.notDone:
      return const Color(0xFFEF4444);
  }
}
