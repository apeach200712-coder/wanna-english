import 'package:flutter/material.dart';

/// One-off calendar adjustments vs recurring class settings.
enum CalendarScheduleExceptionType {
  /// One-time added lesson.
  extra,

  /// Makeup / 보충 lesson.
  makeup,

  /// Skip a regular slot on this date only.
  cancelled,
}

extension CalendarScheduleExceptionTypeJson on CalendarScheduleExceptionType {
  static CalendarScheduleExceptionType parse(String raw) {
    switch (raw) {
      case 'makeup':
        return CalendarScheduleExceptionType.makeup;
      case 'cancelled':
        return CalendarScheduleExceptionType.cancelled;
      case 'extra':
      default:
        return CalendarScheduleExceptionType.extra;
    }
  }

  String get wireName {
    switch (this) {
      case CalendarScheduleExceptionType.extra:
        return 'extra';
      case CalendarScheduleExceptionType.makeup:
        return 'makeup';
      case CalendarScheduleExceptionType.cancelled:
        return 'cancelled';
    }
  }
}

/// Stored in [SharedPreferences] — does not modify recurring [ClassMeta] schedules.
class CalendarScheduleException {
  final String id;

  /// `yyyy-MM-dd` (local calendar day, same convention as todo keys).
  final String dateKey;

  final String classId;

  /// `HH:mm` (24h)
  final String startTime;

  /// `HH:mm` (24h)
  final String endTime;

  final CalendarScheduleExceptionType type;

  /// When [type] is [cancelled], links to the recurring row id built in calendar merge.
  final String? sourceScheduleId;

  final int createdAt;
  final int updatedAt;

  const CalendarScheduleException({
    required this.id,
    required this.dateKey,
    required this.classId,
    required this.startTime,
    required this.endTime,
    required this.type,
    this.sourceScheduleId,
    required this.createdAt,
    required this.updatedAt,
  });

  static final RegExp _dateKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _timePattern = RegExp(r'^\d{2}:\d{2}$');

  /// `H:mm` / `HH:mm` → `HH:mm`. 파싱 불가면 `null`.
  static String? tryNormalizeHm(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.isEmpty) return null;
    final h = int.tryParse(parts[0].trim());
    final m = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    if (h == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// 저장·표시용 시간 문자열 (가능하면 `HH:mm`로 통일).
  static String coerceStoredTime(String raw) =>
      tryNormalizeHm(raw) ?? raw.trim();

  bool get hasValidDateKey => _dateKeyPattern.hasMatch(dateKey);
  bool get hasValidTimeRange {
    final s = tryNormalizeHm(startTime);
    final e = tryNormalizeHm(endTime);
    if (s != null && e != null) return true;
    return _timePattern.hasMatch(startTime.trim()) &&
        _timePattern.hasMatch(endTime.trim());
  }

  bool get isValidForStorage {
    if (id.trim().isEmpty || classId.trim().isEmpty) return false;
    if (!hasValidDateKey || !hasValidTimeRange) return false;
    if (type == CalendarScheduleExceptionType.cancelled) {
      final src = sourceScheduleId?.trim();
      if (src == null || src.isEmpty) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'dateKey': dateKey,
    'classId': classId,
    'startTime': startTime,
    'endTime': endTime,
    'type': type.wireName,
    if (sourceScheduleId != null && sourceScheduleId!.isNotEmpty)
      'sourceScheduleId': sourceScheduleId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory CalendarScheduleException.fromJson(Map<String, dynamic> json) {
    final rawSrc = json['sourceScheduleId']?.toString().trim();
    final src = (rawSrc == null || rawSrc.isEmpty) ? null : rawSrc;
    final rawSt = json['startTime']?.toString() ?? '';
    final rawEn = json['endTime']?.toString() ?? '';
    return CalendarScheduleException(
      id: json['id']?.toString() ?? '',
      dateKey: json['dateKey']?.toString().trim() ?? '',
      classId: json['classId']?.toString().trim() ?? '',
      startTime: coerceStoredTime(rawSt),
      endTime: coerceStoredTime(rawEn),
      type: CalendarScheduleExceptionTypeJson.parse(
        json['type']?.toString() ?? 'extra',
      ),
      sourceScheduleId: src == null
          ? null
          : (canonicalizeScheduleSlotId(src) ?? src),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// `classId_weekday_start_end` 형태의 [sourceScheduleId]를 시간만 `HH:mm`로 통일.
  /// `classId`에 `_`가 있어도 뒤에서부터 `요일·시작·끝`만 분리한다.
  static String? canonicalizeScheduleSlotId(String sid) {
    final trimmed = sid.trim();
    final parts = trimmed.split('_');
    if (parts.length < 4) return null;
    final endRaw = parts.removeLast();
    final startRaw = parts.removeLast();
    final wdRaw = parts.removeLast();
    final wd = int.tryParse(wdRaw);
    if (wd == null) return null;
    final classId = parts.join('_');
    final st = coerceStoredTime(startRaw);
    final en = endRaw.isEmpty ? '' : coerceStoredTime(endRaw);
    return '${classId}_${wd}_${st}_$en';
  }
}

/// Single merged row for calendar UI (regular / extra / cancelled).
class CalendarDaySchedule {
  /// Recurring slot id, or [exceptionId] for extra/makeup rows.
  final String scheduleId;

  final String classId;

  final String name;

  final Color color;

  /// One line, e.g. `18:00` or `18:00–19:00`
  final String timeLabel;

  /// `HH:mm` — 휴강 예외 저장·정렬용
  final String startTime;

  /// `HH:mm`
  final String endTime;

  final bool isCancelled;

  final bool isExtra;

  final bool isMakeup;

  /// When [isCancelled], id of the `cancelled` exception to remove on undo.
  final String? cancelledByExceptionId;

  /// When extra/makeup, id of that exception (remove on supplemental "휴강").
  final String? supplementalExceptionId;

  const CalendarDaySchedule({
    required this.scheduleId,
    required this.classId,
    required this.name,
    required this.color,
    required this.timeLabel,
    required this.startTime,
    required this.endTime,
    this.isCancelled = false,
    this.isExtra = false,
    this.isMakeup = false,
    this.cancelledByExceptionId,
    this.supplementalExceptionId,
  });
}
