import 'package:flutter/material.dart';

const Object _classMetaUnset = Object();

/// 수업/클래스 구분 (내신 vs 기타).
enum ClassProgramType {
  /// 내신 — 학교 + 학년으로 구성
  internalExam,

  /// 기타 — 수업명 직접 입력
  custom,
}

extension ClassProgramTypeUi on ClassProgramType {
  String get label {
    switch (this) {
      case ClassProgramType.internalExam:
        return '내신';
      case ClassProgramType.custom:
        return '기타';
    }
  }
}

class ClassMeetingSlot {
  final int weekday;
  final String time;

  /// 수업 종료 시각 `HH:mm` (24시). 없으면 레거시 데이터(시작만).
  final String? endTime;

  const ClassMeetingSlot({
    required this.weekday,
    required this.time,
    this.endTime,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'weekday': weekday, 'time': time};
    final e = endTime?.trim();
    if (e != null && e.isNotEmpty) {
      m['endTime'] = e;
    }
    return m;
  }

  factory ClassMeetingSlot.fromJson(Map<String, dynamic> json) {
    final end = json['endTime']?.toString().trim();
    return ClassMeetingSlot(
      weekday: (json['weekday'] as num?)?.toInt() ?? 1,
      time: json['time']?.toString().trim() ?? '',
      endTime: (end == null || end.isEmpty) ? null : end,
    );
  }
}

extension ClassMeetingSlotDisplay on ClassMeetingSlot {
  /// 홈/캘린더 등 한 줄 표시용 (종료 없으면 시작만).
  String get timeRangeLabel {
    final e = endTime?.trim();
    if (e == null || e.isEmpty) return time;
    return '$time–$e';
  }
}

class ClassMeta {
  final String id;

  /// 반 연동용 표시 이름 (학생·성적·숙제 등과 동일 문자열).
  /// 내신: 보통 "이화여고 2학년", 번호 구분 시 "이화여고 2학년 (1)".
  final String name;
  final ClassProgramType programType;
  final String? schoolName;
  final String? grade;

  /// 기타 수업만. 사용자가 입력한 기본 수업명(번호 접미사 없음).
  final String? customClassName;
  final String? meetingTime;
  final List<int> weekdays;
  final List<ClassMeetingSlot> schedules;
  final int colorValue;
  final String? note;
  final int createdAt;
  final int updatedAt;

  const ClassMeta({
    required this.id,
    required this.name,
    this.programType = ClassProgramType.custom,
    this.schoolName,
    this.grade,
    this.customClassName,
    required this.meetingTime,
    required this.weekdays,
    this.schedules = const [],
    required this.colorValue,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  Color get color => Color(colorValue);

  List<ClassMeetingSlot> get effectiveSchedules {
    if (schedules.isNotEmpty) {
      final normalized = [...schedules]
        ..sort((a, b) {
          final weekdayCompare = a.weekday.compareTo(b.weekday);
          if (weekdayCompare != 0) return weekdayCompare;
          return a.time.compareTo(b.time);
        });
      return normalized;
    }

    final time = meetingTime?.trim();
    if (time == null || time.isEmpty || weekdays.isEmpty) {
      return const [];
    }

    final uniqueWeekdays = {...weekdays}.toList()..sort();
    return uniqueWeekdays
        .map((weekday) => ClassMeetingSlot(weekday: weekday, time: time))
        .toList();
  }

  String get scheduleSummary {
    const labels = ['', '월', '화', '수', '목', '금', '토', '일'];
    final parts = effectiveSchedules
        .map((slot) => '${labels[slot.weekday]} ${slot.timeRangeLabel}')
        .toList();
    return parts.isEmpty ? '시간 미설정' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'programType': programType.name,
      'schoolName': schoolName,
      'grade': grade,
      'customClassName': customClassName,
      'meetingTime': meetingTime,
      'weekdays': weekdays,
      'schedules': schedules.map((slot) => slot.toJson()).toList(),
      'colorValue': colorValue,
      'note': note,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory ClassMeta.fromJson(Map<String, dynamic> json) {
    final schedulesJson =
        (json['schedules'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClassMeetingSlot.fromJson)
            .where(
              (slot) =>
                  slot.weekday >= DateTime.monday &&
                  slot.weekday <= DateTime.sunday &&
                  slot.time.isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final weekdayCompare = a.weekday.compareTo(b.weekday);
            if (weekdayCompare != 0) return weekdayCompare;
            return a.time.compareTo(b.time);
          });
    final legacyWeekdays = ((json['weekdays'] as List<dynamic>?) ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final legacyMeetingTime = json['meetingTime']?.toString().trim();
    final normalizedSchedules = schedulesJson.isNotEmpty
        ? schedulesJson
        : ((legacyMeetingTime == null || legacyMeetingTime.isEmpty)
              ? const <ClassMeetingSlot>[]
              : ({...legacyWeekdays}.toList()..sort())
                    .map(
                      (weekday) => ClassMeetingSlot(
                        weekday: weekday,
                        time: legacyMeetingTime,
                      ),
                    )
                    .toList());
    final normalizedWeekdays = normalizedSchedules.isNotEmpty
        ? normalizedSchedules.map((slot) => slot.weekday).toSet().toList()
        : {...legacyWeekdays}.toList();
    normalizedWeekdays.sort();
    String? primaryTime;
    if (normalizedSchedules.isNotEmpty) {
      primaryTime = normalizedSchedules.first.time;
    } else if (legacyMeetingTime != null && legacyMeetingTime.isNotEmpty) {
      primaryTime = legacyMeetingTime;
    }

    final typeStr = json['programType']?.toString();
    ClassProgramType programType = ClassProgramType.custom;
    if (typeStr != null) {
      programType = ClassProgramType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => ClassProgramType.custom,
      );
    }

    return ClassMeta(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      programType: programType,
      schoolName: json['schoolName']?.toString(),
      grade: json['grade']?.toString(),
      customClassName: json['customClassName']?.toString(),
      meetingTime: primaryTime,
      weekdays: normalizedWeekdays,
      schedules: normalizedSchedules,
      colorValue:
          json['colorValue'] as int? ?? const Color(0xFF4DA3FF).toARGB32(),
      note: json['note']?.toString(),
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }

  ClassMeta copyWith({
    String? id,
    String? name,
    ClassProgramType? programType,
    Object? schoolName = _classMetaUnset,
    Object? grade = _classMetaUnset,
    Object? customClassName = _classMetaUnset,
    Object? meetingTime = _classMetaUnset,
    List<int>? weekdays,
    List<ClassMeetingSlot>? schedules,
    int? colorValue,
    Object? note = _classMetaUnset,
    int? createdAt,
    int? updatedAt,
  }) {
    return ClassMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      programType: programType ?? this.programType,
      schoolName: identical(schoolName, _classMetaUnset)
          ? this.schoolName
          : schoolName as String?,
      grade: identical(grade, _classMetaUnset) ? this.grade : grade as String?,
      customClassName: identical(customClassName, _classMetaUnset)
          ? this.customClassName
          : customClassName as String?,
      meetingTime: identical(meetingTime, _classMetaUnset)
          ? this.meetingTime
          : meetingTime as String?,
      weekdays: weekdays ?? this.weekdays,
      schedules: schedules ?? this.schedules,
      colorValue: colorValue ?? this.colorValue,
      note: identical(note, _classMetaUnset) ? this.note : note as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
