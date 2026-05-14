import 'package:flutter/material.dart';

/// A recurring class session (e.g. 이화여고2, Mon/Wed/Fri 18:00).
class ClassSchedule {
  final String id;

  /// [ClassMeta.id] / [ClassDisplayItem.id] — 라우트·저장소 키용.
  final String classId;

  final String name;
  final Color color;

  /// Weekdays this class meets — uses [DateTime.weekday] convention:
  /// 1 = Monday … 6 = Saturday, 7 = Sunday
  final List<int> weekdays;

  /// Display time string, e.g. '18:00'
  final String time;

  const ClassSchedule({
    required this.id,
    required this.classId,
    required this.name,
    required this.color,
    required this.weekdays,
    required this.time,
  });
}
