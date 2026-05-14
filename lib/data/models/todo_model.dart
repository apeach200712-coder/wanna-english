import 'package:flutter/material.dart';

enum TodoTaskProgress { done, inProgress, notDone }

extension TodoTaskProgressX on TodoTaskProgress {
  String get storageValue {
    switch (this) {
      case TodoTaskProgress.done:
        return 'done';
      case TodoTaskProgress.inProgress:
        return 'in_progress';
      case TodoTaskProgress.notDone:
        return 'not_done';
    }
  }

  String get label {
    switch (this) {
      case TodoTaskProgress.done:
        return '○';
      case TodoTaskProgress.inProgress:
        return '△';
      case TodoTaskProgress.notDone:
        return 'X';
    }
  }

  IconData get icon {
    switch (this) {
      case TodoTaskProgress.done:
        return Icons.circle_outlined;
      case TodoTaskProgress.inProgress:
        return Icons.change_history_rounded;
      case TodoTaskProgress.notDone:
        return Icons.close_rounded;
    }
  }

  /// Circle / triangle use outline icons; a drawn "X" matches their visual weight better.
  Widget progressGlyph(Color color, double iconSize) {
    switch (this) {
      case TodoTaskProgress.done:
      case TodoTaskProgress.inProgress:
        return Icon(icon, color: color, size: iconSize);
      case TodoTaskProgress.notDone:
        return Text(
          'X',
          style: TextStyle(
            fontSize: iconSize * 1.12,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        );
    }
  }

  static TodoTaskProgress fromStorageValue(String? value) {
    switch (value) {
      case 'done':
        return TodoTaskProgress.done;
      case 'in_progress':
        return TodoTaskProgress.inProgress;
      case 'not_done':
        return TodoTaskProgress.notDone;
      default:
        return TodoTaskProgress.notDone;
    }
  }
}

class TodoTaskModel {
  final String id;
  final String title;
  final TodoTaskProgress progress;
  final bool isPinned;
  final String? time;
  final String? memo;

  const TodoTaskModel({
    required this.id,
    required this.title,
    this.progress = TodoTaskProgress.notDone,
    this.isPinned = false,
    this.time,
    this.memo,
  });

  bool get isDone => progress == TodoTaskProgress.done;

  TodoTaskModel copyWith({
    String? id,
    String? title,
    TodoTaskProgress? progress,
    bool? isPinned,
    String? time,
    String? memo,
  }) {
    return TodoTaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      progress: progress ?? this.progress,
      isPinned: isPinned ?? this.isPinned,
      time: time ?? this.time,
      memo: memo ?? this.memo,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'progress': progress.storageValue,
      'isPinned': isPinned,
      'time': time,
      'memo': memo,
    };
  }

  factory TodoTaskModel.fromJson(Map<String, dynamic> json) {
    final pinned =
        json['isPinned'] as bool? ??
        json['isImportant'] as bool? ??
        json['important'] as bool? ??
        json['starred'] as bool? ??
        json['favorite'] as bool? ??
        false;
    return TodoTaskModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      progress: json['progress'] != null
          ? TodoTaskProgressX.fromStorageValue(json['progress']?.toString())
          : ((json['isDone'] as bool? ?? false)
                ? TodoTaskProgress.done
                : TodoTaskProgress.notDone),
      isPinned: pinned,
      time: json['time']?.toString(),
      memo: json['memo']?.toString(),
    );
  }
}

class TodoSectionModel {
  final String id;
  final String title;
  final Color color;
  final IconData icon;
  final List<TodoTaskModel> tasks;
  final bool isPinned;

  const TodoSectionModel({
    required this.id,
    required this.title,
    required this.color,
    required this.icon,
    required this.tasks,
    this.isPinned = false,
  });

  TodoSectionModel copyWith({
    String? id,
    String? title,
    Color? color,
    IconData? icon,
    List<TodoTaskModel>? tasks,
    bool? isPinned,
  }) {
    return TodoSectionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      tasks: tasks ?? this.tasks,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'color': color.toARGB32(),
      'icon': icon.codePoint,
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'isPinned': isPinned,
    };
  }

  factory TodoSectionModel.fromJson(Map<String, dynamic> json) {
    final tasksJson = json['tasks'] as List<dynamic>? ?? const [];

    return TodoSectionModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      color: Color(
        (json['color'] as num?)?.toInt() ?? const Color(0xFF5B8CFF).toARGB32(),
      ),
      icon: Icons.folder_open_rounded,
      isPinned: json['isPinned'] as bool? ?? false,
      tasks: tasksJson
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(TodoTaskModel.fromJson)
          .toList(),
    );
  }
}
