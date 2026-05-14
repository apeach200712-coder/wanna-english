import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/home_layout_metrics.dart';
import '../../core/routes.dart';
import '../../core/responsive.dart';
import '../../core/time_utils.dart';
import '../../data/models/class_model.dart';
import '../../services/class_selection_service.dart';
import '../../services/class_management_service.dart';
import '../../services/class_service.dart';
import '../../services/lesson_content_service.dart';
import '../../services/student_service.dart';
import '../../services/weather_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/adaptive_scaffold.dart';
import '../../widgets/common/lesson_content_editor_sheet.dart';
import '../../widgets/common/search_bar.dart';
import '../../widgets/home/alert_cards.dart';
import '../../widgets/home/today_schedule_bar.dart';
import '../../widgets/home/todo_preview_card.dart';
import '../students/student_search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String selectedMode = 'HOME';
  List<String> modes = const ['HOME'];
  List<ClassMeta> _classes = const [];
  List<ClassDisplayItem> _classDisplayItems = const [];
  bool _loggedFirstBuild = false;
  bool _showDeferredHomeSections = false;

  ClassDisplayItem? get _selectedDisplayItem {
    if (selectedMode == 'HOME') return null;
    for (final item in _classDisplayItems) {
      if (item.displayName == selectedMode) return item;
    }
    return null;
  }

  void _syncGlobalSelectedClass([String? mode]) {
    final selected = mode ?? selectedMode;
    if (selected == 'HOME') return;
    context.read<ClassSelectionService>().selectClass(selected);
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[STARTUP_DIAG] home: initState');
    _loadModes();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showDeferredHomeSections = true;
      });
    });
  }

  Future<void> _loadModes() async {
    try {
      debugPrint('[STARTUP_DIAG] home: _loadModes start');
      final prefs = await SharedPreferences.getInstance();
      final studentService = StudentService(prefs: prefs);
      final classManagementService = ClassManagementService(prefs: prefs);
      final classService = ClassService(prefs: prefs);
      await studentService.initializeMockStudents();
      await classManagementService.ensureClassMetaForStudentNames();
      await classService.initializeFromMockIfNeeded();
      final classes = await classService.getAllClasses();
      final displayItems = await classService.getDisplayItems();
      if (!mounted) return;

      setState(() {
        _classes = classes;
        _classDisplayItems = displayItems;
        modes = ['HOME', ...displayItems.map((e) => e.displayName)];
        if (!modes.contains(selectedMode)) {
          selectedMode = 'HOME';
        }
      });
      debugPrint(
        '[STARTUP_DIAG] home: _loadModes done classes=${classes.length} displayItems=${displayItems.length} selectedMode=$selectedMode',
      );
      _syncGlobalSelectedClass();
    } catch (e, st) {
      debugPrint('HomePage._loadModes error: $e\n$st');
    }
  }

  void _openModePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 34),
          decoration: const BoxDecoration(
            color: AppColors.overlay,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '수업 선택',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...modes.map(
                (mode) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    mode,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: mode == selectedMode
                          ? FontWeight.w900
                          : FontWeight.w500,
                      color: mode == selectedMode
                          ? AppColors.blue
                          : AppColors.navy,
                    ),
                  ),
                  trailing: mode == selectedMode
                      ? const Icon(Icons.check_rounded, color: AppColors.blue)
                      : null,
                  onTap: () {
                    setState(() => selectedMode = mode);
                    _syncGlobalSelectedClass(mode);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openStudentSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentSearchPage(selectedMode: selectedMode),
      ),
    );
  }

  void _openGradeCalculator() {
    _syncGlobalSelectedClass();
    Navigator.pushNamed(
      context,
      AppRoutes.gradeCalculator,
      arguments: selectedMode == 'HOME' ? null : selectedMode,
    );
  }

  void _openAnnouncementPage() {
    if (selectedMode == 'HOME') return;
    _syncGlobalSelectedClass();
    Navigator.pushNamed(
      context,
      AppRoutes.announcements,
      arguments: selectedMode,
    );
  }

  void _openAttendancePage() {
    if (selectedMode == 'HOME') return;
    _syncGlobalSelectedClass();
    Navigator.pushNamed(context, AppRoutes.attendance, arguments: selectedMode);
  }

  void _openHomeworkPage() {
    if (selectedMode == 'HOME') return;
    _syncGlobalSelectedClass();
    final item = _selectedDisplayItem;
    Navigator.pushNamed(
      context,
      AppRoutes.homework,
      arguments: item == null
          ? selectedMode
          : {
              'classId': item.id,
              'className': item.name,
              'classDisplayName': item.displayName,
            },
    );
  }

  /// 홈 알림 시트 등에서 classId로 숙제관리 진입.
  void _openHomeworkForClass(String classId, {DateTime? focusDate}) {
    _syncGlobalSelectedClass();
    ClassDisplayItem? item;
    for (final i in _classDisplayItems) {
      if (i.id == classId) {
        item = i;
        break;
      }
    }
    if (item == null) return;
    Navigator.pushNamed(
      context,
      AppRoutes.homework,
      arguments: {
        'classId': item.id,
        'className': item.name,
        'classDisplayName': item.displayName,
        'focusDate': ?focusDate,
      },
    );
  }

  void _openExamManagementPage() {
    _syncGlobalSelectedClass();
    final item = _selectedDisplayItem;
    Navigator.pushNamed(
      context,
      AppRoutes.gradeInput,
      arguments: selectedMode == 'HOME'
          ? null
          : (item != null ? {'classId': item.id} : selectedMode),
    );
  }

  /// 홈 알림 시트 등에서 classId로 성적관리 진입.
  void _openGradeForClass(
    String classId, {
    String? examTypeId,
    String? examTypeDisplayName,
    DateTime? focusDate,
  }) {
    _syncGlobalSelectedClass();
    Navigator.pushNamed(
      context,
      AppRoutes.gradeInput,
      arguments: {
        'classId': classId,
        if (examTypeId != null && examTypeId.isNotEmpty)
          'examTypeId': examTypeId,
        if (examTypeDisplayName != null &&
            examTypeDisplayName.trim().isNotEmpty)
          'examTypeDisplayName': examTypeDisplayName.trim(),
        'focusDate': ?focusDate,
      },
    );
  }

  /// `ClassQuickActions`에서 `자료제작` 카드를 제거하면서 사라진 그리드 행 높이.
  ///
  /// 같은 만큼을 [LessonContentCard]의 최소 높이에 보태 빈 자리를 흡수한다.
  /// 그리드 컬럼 수에 따라 행이 줄지 않는 화면(예: 3열)에서는 0을 반환한다.
  double _classQuickActionsSavedHeight(
    BuildContext context,
    HomeLayoutMetrics m,
  ) {
    const int kButtonsBeforeRemoval = 5;
    const int kButtonsAfterRemoval = 4;
    const double kCrossAxisSpacing = 12;
    const double kMainAxisSpacing = 12;

    final cols = Responsive.gridColumns(context);
    if (cols <= 0) return 0;

    final rowsBefore = (kButtonsBeforeRemoval + cols - 1) ~/ cols;
    final rowsAfter = (kButtonsAfterRemoval + cols - 1) ~/ cols;
    final savedRows = rowsBefore - rowsAfter;
    if (savedRows <= 0) return 0;

    final paddedWidth = m.bodyMaxWidth - 2 * m.hPad;
    final contentWidth = m.maxContentWidth == double.infinity
        ? paddedWidth
        : (paddedWidth < m.maxContentWidth ? paddedWidth : m.maxContentWidth);
    if (contentWidth <= 0) return 0;

    final ratio = Responsive.gridChildAspectRatio(context);
    final cellWidth = (contentWidth - (cols - 1) * kCrossAxisSpacing) / cols;
    if (cellWidth <= 0 || ratio <= 0) return 0;
    final cellHeight = cellWidth / ratio;

    // 사라진 행의 셀 높이 + 행 사이 간격만큼 회수.
    return savedRows * (cellHeight + kMainAxisSpacing);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedFirstBuild) {
      _loggedFirstBuild = true;
      debugPrint('[STARTUP_DIAG] home: first build');
    }
    final isHome = selectedMode == 'HOME';

    return AdaptiveScaffold(
      currentIndex: 0,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final m = HomeLayoutMetrics.from(
            context: context,
            bodyConstraints: constraints,
            isHome: isHome,
          );

          final header = HomeHeader(
            metrics: m,
            onSettingsTap: () async {
              await Navigator.pushNamed(context, AppRoutes.settings);
              await _loadModes();
            },
          );

          final search = TeacherSearchBar(
            selectedMode: selectedMode,
            onModeTap: _openModePicker,
            onSearchTap: _openStudentSearch,
            height: m.searchBarHeight,
            hintFontSize: m.searchHintFontSize,
            searchIconSize: (m.searchHintFontSize + 8).clamp(22.0, 26.0),
          );

          final schedule = TodayScheduleBar(
            isHome: isHome,
            selectedMode: selectedMode,
            selectedClassMeta: _selectedDisplayItem?.meta,
            scheduleDetailLabel:
                _selectedDisplayItem?.displayName ?? selectedMode,
            classes: _classes,
            barHeight: m.scheduleBarHeight,
            labelFontSize: m.scheduleLabelFontSize,
            onTap: () =>
                AppRoutes.pushNamedInstant(context, AppRoutes.calendar),
          );

          final todoPadding = EdgeInsets.fromLTRB(
            20,
            lerpDouble(16, 20, m.heightT)!,
            20,
            lerpDouble(12, 15, m.heightT)!,
          );

          final todo = TodoPreviewCard(
            fillRemaining: m.todoFillRemaining,
            maxListHeight: m.todoFillRemaining ? null : m.todoMaxListHeight,
            titleFontSize: m.todoTitleFontSize,
            rowTitleFontSize: m.todoRowTitleFontSize,
            emptyMessageFontSize: m.todoEmptyFontSize,
            padding: todoPadding,
          );

          final homeAlerts = AlertCards(
            isHome: true,
            selectedClass: null,
            onNavigateHomeworkClass: _openHomeworkForClass,
            onNavigateGradeClass: _openGradeForClass,
            tileHeight: m.alertTileHeight,
            tileBottomMargin: m.alertTileBottomMargin,
            titleFontSize: m.alertTitleFontSize,
            countFontSize: m.alertCountFontSize,
          );

          final deferredPlaceholder = Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.blue,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '홈 정보를 불러오는 중...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.subText,
                  ),
                ),
              ],
            ),
          );

          final classAlerts = AlertCards(
            isHome: false,
            selectedClass: selectedMode,
            selectedClassId: _selectedDisplayItem?.id,
            onHomeworkTap: _openHomeworkPage,
            onTestRetakeTap: _openExamManagementPage,
            onNavigateHomeworkClass: _openHomeworkForClass,
            onNavigateGradeClass: _openGradeForClass,
            tileHeight: m.alertTileHeight,
            tileBottomMargin: m.alertTileBottomMargin,
            titleFontSize: m.alertTitleFontSize,
            countFontSize: m.alertCountFontSize,
          );

          final padded = EdgeInsets.fromLTRB(
            m.hPad,
            m.vPadTop,
            m.hPad,
            m.vPadBottom,
          );

          Widget homeLocked() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                SizedBox(height: m.afterHeader),
                search,
                SizedBox(height: m.afterSearch),
                schedule,
                SizedBox(height: m.afterSchedule),
                Expanded(
                  child: _showDeferredHomeSections
                      ? todo
                      : Center(child: deferredPlaceholder),
                ),
                SizedBox(height: m.beforeAlerts),
                _showDeferredHomeSections ? homeAlerts : deferredPlaceholder,
              ],
            );
          }

          Widget homeScrollable() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                SizedBox(height: m.afterHeader),
                search,
                SizedBox(height: m.afterSearch),
                schedule,
                SizedBox(height: m.afterSchedule),
                _showDeferredHomeSections ? todo : deferredPlaceholder,
                SizedBox(height: m.beforeAlerts),
                _showDeferredHomeSections ? homeAlerts : deferredPlaceholder,
              ],
            );
          }

          Widget classScrollable() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                SizedBox(height: m.afterHeader),
                search,
                SizedBox(height: m.afterSearch),
                schedule,
                SizedBox(height: m.afterSchedule),
                ClassQuickActions(
                  className: selectedMode,
                  onOpenAttendance: _openAttendancePage,
                  onOpenHomework: _openHomeworkPage,
                  onOpenGradeCalculator: _openGradeCalculator,
                  onOpenExamManagement: _openExamManagementPage,
                  onOpenAnnouncements: _openAnnouncementPage,
                ),
                SizedBox(height: m.beforeAlerts),
                LessonContentCard(
                  className: selectedMode,
                  lessonStorageKey: _selectedDisplayItem?.id ?? selectedMode,
                  extraMinHeight: _classQuickActionsSavedHeight(context, m),
                ),
                SizedBox(height: m.beforeAlerts),
                classAlerts,
              ],
            );
          }

          final inner = ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: m.maxContentWidth == double.infinity
                  ? double.infinity
                  : m.maxContentWidth,
            ),
            child: isHome && m.lockOuterScroll
                ? homeLocked()
                : isHome
                ? homeScrollable()
                : classScrollable(),
          );

          final body = SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: padded,
                child: isHome && m.lockOuterScroll
                    ? inner
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: inner,
                        ),
                      ),
              ),
            ),
          );

          return body;
        },
      ),
    );
  }
}

class HomeHeader extends StatefulWidget {
  final HomeLayoutMetrics metrics;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onSettingsTap;

  const HomeHeader({
    super.key,
    required this.metrics,
    this.onNotificationTap,
    this.onSettingsTap,
  });

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// `wanna_logo_white_tight.png` 픽셀 비율 (스크롤/무한 세로 제약에서 Image 높이 고정용)
  static const _tightLogoAspect = 700 / 331;

  WeatherData? _weather;
  bool _loadingWeather = true;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    if (!mounted) return;
    setState(() {
      _loadingWeather = true;
    });
    try {
      final data = await WeatherService().fetchCurrentWeather();
      if (!mounted) return;
      setState(() {
        _weather = data;
        _loadingWeather = false;
      });
    } catch (e, st) {
      debugPrint('HomeHeader._fetchWeather error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _weather = null;
        _loadingWeather = false;
      });
    }
  }

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final now = nowKst();
    final dateLabel = '${now.month}.${now.day}';
    final dayLabel = '(${_weekdays[now.weekday - 1]})';
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = widget.metrics;
        final dateStyle = TextStyle(
          fontSize: m.dateFontSize,
          fontWeight: FontWeight.w800,
          height: 1,
          color: AppColors.navy,
        );
        final dayStyle = TextStyle(
          fontSize: m.dayFontSize,
          color: AppColors.subText,
          fontWeight: FontWeight.w600,
        );

        final dateNumericWidth = _measureTextWidth(
          context,
          dateLabel,
          dateStyle,
        );
        final logoWidth = (dateNumericWidth * m.logoWidthFactor).clamp(
          m.logoWidthMin,
          m.logoWidthMax,
        );
        final headerMidGap = m.headerMidGap;
        final logoTopNudge = m.logoTopNudge;

        final logoHeight = logoWidth / _tightLogoAspect;
        final logoWidget = Padding(
          padding: EdgeInsets.only(top: logoTopNudge),
          child: SizedBox(
            width: logoWidth,
            height: logoHeight,
            child: Image.asset(
              'assets/wanna_logo_white_tight.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        );

        final dateRow = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(dateLabel, style: dateStyle),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(dayLabel, style: dayStyle),
            ),
          ],
        );

        final academyCard = Container(
          padding: EdgeInsets.symmetric(
            horizontal: lerpDouble(14, 15, m.heightT)!,
            vertical: lerpDouble(8, 9, m.heightT)!,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.academyName,
                style: TextStyle(
                  fontSize: m.academyTitleSize,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppConstants.academyBranch,
                style: TextStyle(
                  fontSize: m.academyBranchSize,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );

        final weatherWidget = _loadingWeather
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.subText,
                ),
              )
            : _weather != null
            ? _WeatherChip(weather: _weather!)
            : TextButton.icon(
                onPressed: _fetchWeather,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('날씨 다시 불러오기'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.subText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );

        final rightTopRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            academyCard,
            const SizedBox(width: 10),
            _HeaderCircleIcon(
              icon: Icons.notifications_none_rounded,
              onTap: widget.onNotificationTap,
            ),
            const SizedBox(width: 8),
            _HeaderCircleIcon(
              icon: Icons.settings_outlined,
              onTap: widget.onSettingsTap,
            ),
          ],
        );

        // 두 줄 구조: 1) 로고 | 학원·알림·설정  2) 날짜 | 날씨 — 중간 간격 공유로 세로 정렬 유지
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [logoWidget, const Spacer(), rightTopRow],
            ),
            SizedBox(height: headerMidGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [dateRow, const Spacer(), weatherWidget],
            ),
          ],
        );
      },
    );
  }
}

class _HeaderCircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderCircleIcon({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(icon, size: 25, color: AppColors.navy),
      ),
    );
  }
}

class _WeatherChip extends StatelessWidget {
  final WeatherData weather;

  const _WeatherChip({required this.weather});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(weather.emoji, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 5),
          Text(
            weather.tempLabel,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              weather.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.subText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ClassQuickActions extends StatelessWidget {
  final String className;
  final VoidCallback? onOpenAttendance;
  final VoidCallback? onOpenHomework;
  final VoidCallback? onOpenGradeCalculator;
  final VoidCallback? onOpenExamManagement;
  final VoidCallback? onOpenAnnouncements;

  const ClassQuickActions({
    super.key,
    required this.className,
    this.onOpenAttendance,
    this.onOpenHomework,
    this.onOpenGradeCalculator,
    this.onOpenExamManagement,
    this.onOpenAnnouncements,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: Responsive.gridColumns(context),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: Responsive.gridChildAspectRatio(context),
      children: [
        QuickActionCard(
          icon: Icons.how_to_reg_rounded,
          title: '출결관리',
          subtitle: '입실 · 결석 · 조퇴',
          color: AppColors.blue,
          softColor: AppColors.blueSoft,
          onTap: onOpenAttendance,
        ),
        QuickActionCard(
          icon: Icons.fact_check_rounded,
          title: '숙제관리',
          subtitle: '완성도 체크',
          color: AppColors.green,
          softColor: AppColors.greenSoft,
          onTap: onOpenHomework,
        ),
        QuickActionCard(
          icon: Icons.grade_rounded,
          title: '성적관리',
          subtitle: '시험 · 재시험',
          color: AppColors.purple,
          softColor: AppColors.purpleSoft,
          onTap: onOpenExamManagement ?? onOpenGradeCalculator,
        ),
        QuickActionCard(
          icon: Icons.notifications_active_rounded,
          title: '공지관리',
          subtitle: '학부모 전송',
          color: AppColors.pink,
          softColor: AppColors.pinkSoft,
          onTap: onOpenAnnouncements,
        ),
      ],
    );
  }
}

class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color softColor;
  final VoidCallback? onTap;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.softColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 1 : 0.98,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
            boxShadow: softShadow(),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: softColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LessonContentCard extends StatefulWidget {
  /// 표시·시트 제목용 (보통 [ClassDisplayItem.displayName]).
  final String className;

  /// [LessonContentService] 저장 키 — 반별로 고유해야 하므로 기본은 [ClassMeta.id].
  final String lessonStorageKey;

  /// 카드가 차지해야 할 최소 추가 높이.
  ///
  /// `ClassQuickActions`에서 카드 한 행이 사라지면 동일한 만큼을 이 카드가
  /// 흡수해 빈 공간을 메운다. 자연 콘텐츠 높이가 더 크면 무시된다.
  final double extraMinHeight;

  // ignore: prefer_const_constructors_in_immutables — [lessonStorageKey] 기본값이 [className]에 의존
  LessonContentCard({
    super.key,
    required this.className,
    String? lessonStorageKey,
    this.extraMinHeight = 0,
  }) : lessonStorageKey = lessonStorageKey ?? className;

  @override
  State<LessonContentCard> createState() => _LessonContentCardState();
}

class _LessonContentCardState extends State<LessonContentCard> {
  bool _isLoading = true;
  List<String> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LessonContentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.className != widget.className ||
        oldWidget.lessonStorageKey != widget.lessonStorageKey) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final service = LessonContentService(prefs: prefs);
    final items = await service.getLessonContent(widget.lessonStorageKey);
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _openEditor() async {
    final lines = await showLessonContentEditorSheet(
      context: context,
      className: widget.className,
      initialLines: _items,
    );
    if (lines == null) return;
    final prefs = await SharedPreferences.getInstance();
    final service = LessonContentService(prefs: prefs);
    await service.saveLessonContent(widget.lessonStorageKey, lines);
    if (!mounted) return;
    setState(() => _items = lines);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('오늘 수업 내용을 저장했습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '오늘 수업 내용',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _openEditor,
                child: const Text(
                  '수정',
                  style: TextStyle(
                    color: AppColors.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '저장된 수업 내용이 없습니다. 우측 수정으로 입력하세요.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ..._items.map((item) => LessonLine(text: item)),
        ],
      ),
    );

    if (widget.extraMinHeight <= 0) return card;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.extraMinHeight),
      child: card,
    );
  }
}

class LessonLine extends StatelessWidget {
  final String text;

  const LessonLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              color: AppColors.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
