import 'package:flutter/material.dart';

import '../../core/time_utils.dart';
import '../../data/models/class_model.dart';
import '../../theme/app_colors.dart';

class TodayScheduleBar extends StatelessWidget {
  final bool isHome;
  final String selectedMode;
  /// 수업 모드일 때 선택된 반. 동명 반 구분용.
  final ClassMeta? selectedClassMeta;
  /// 일정 줄에 표시할 반 이름 (보통 [ClassDisplayItem.displayName]).
  final String? scheduleDetailLabel;
  final VoidCallback? onTap;
  final List<ClassMeta> classes;
  final double barHeight;
  final double labelFontSize;

  const TodayScheduleBar({
    super.key,
    required this.isHome,
    required this.selectedMode,
    this.selectedClassMeta,
    this.scheduleDetailLabel,
    required this.classes,
    this.onTap,
    this.barHeight = 62,
    this.labelFontSize = 17,
  });

  static const _weekdayNames = ['', '월', '화', '수', '목', '금', '토', '일'];

  Iterable<({String className, int weekday, String time})> _scheduleEntries(
    Iterable<ClassMeta> items,
  ) {
    return items.expand(
      (item) => item.effectiveSchedules.map(
        (slot) => (
          className: item.name,
          weekday: slot.weekday,
          time: slot.timeRangeLabel,
        ),
      ),
    );
  }

  /// 오늘 수업이 있으면 ('오늘 수업', '18:00 이화여고 2학년') 반환
  /// 없으면 ('다음 수업', '화 17:00 개포고 1학년') 반환
  ({String label, String detail}) _computeScheduleInfo() {
    final now = nowKst();
    final todayWeekday = now.weekday;

    // 오늘 수업 있는지 확인
    final todayClasses =
        _scheduleEntries(
            classes,
          ).where((entry) => entry.weekday == todayWeekday).toList()
          ..sort((a, b) => a.time.compareTo(b.time));

    if (todayClasses.isNotEmpty) {
      final names = todayClasses
          .map((s) => '${s.time} ${s.className}')
          .join(' · ');
      return (label: '오늘 수업', detail: names);
    }

    // 다음 수업 찾기 (최대 7일 이내)
    for (int offset = 1; offset <= 7; offset++) {
      final nextDay = todayWeekday % 7 + 1 == 8
          ? 1
          : ((todayWeekday - 1 + offset) % 7) + 1;
      final nextClasses =
          _scheduleEntries(
              classes,
            ).where((entry) => entry.weekday == nextDay).toList()
            ..sort((a, b) => a.time.compareTo(b.time));

      if (nextClasses.isNotEmpty) {
        final dayName = _weekdayNames[nextDay];
        final first = nextClasses.first;
        return (
          label: '다음 수업',
          detail: '$dayName ${first.time} ${first.className}',
        );
      }
    }

    return (label: '다음 수업', detail: '일정 없음');
  }

  /// 특정 클래스의 오늘/다음 수업 정보 반환
  ({String label, String detail}) _computeClassScheduleInfo(
    ClassMeta? meta,
    String detailTitle,
  ) {
    final scope = meta != null
        ? classes.where((item) => item.id == meta.id)
        : classes;
    final entries =
        _scheduleEntries(scope).toList()..sort((a, b) {
          final weekdayCompare = a.weekday.compareTo(b.weekday);
          if (weekdayCompare != 0) return weekdayCompare;
          return a.time.compareTo(b.time);
        });
    if (entries.isEmpty) {
      return (label: '수업 정보', detail: detailTitle);
    }

    final now = nowKst();
    final todayWeekday = now.weekday;

    final todayEntries =
        entries.where((entry) => entry.weekday == todayWeekday).toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (todayEntries.isNotEmpty) {
      return (
        label: '오늘 수업',
        detail: todayEntries
            .map((entry) => '${entry.time} $detailTitle')
            .join(' · '),
      );
    }

    for (int offset = 1; offset <= 7; offset++) {
      final nextDay = ((todayWeekday - 1 + offset) % 7) + 1;
      final nextEntries =
          entries.where((entry) => entry.weekday == nextDay).toList()
            ..sort((a, b) => a.time.compareTo(b.time));
      if (nextEntries.isNotEmpty) {
        final dayName = _weekdayNames[nextDay];
        return (
          label: '다음 수업',
          detail: '$dayName ${nextEntries.first.time} $detailTitle',
        );
      }
    }

    return (label: '수업 정보', detail: detailTitle);
  }

  @override
  Widget build(BuildContext context) {
    final info = isHome
        ? _computeScheduleInfo()
        : _computeClassScheduleInfo(
            selectedClassMeta,
            scheduleDetailLabel ?? selectedMode,
          );

    final iconSize = (labelFontSize + 5).clamp(20.0, 24.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: barHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded,
                color: AppColors.blue, size: iconSize),
            const SizedBox(width: 14),
            Text(
              info.label,
              style: TextStyle(
                color: AppColors.blue,
                fontSize: labelFontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '  ·  ',
              style: TextStyle(
                color: AppColors.subText,
                fontSize: labelFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: Text(
                info.detail,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.subText, size: iconSize),
          ],
        ),
      ),
    );
  }
}
