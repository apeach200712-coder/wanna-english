import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/home_alert_service.dart';
import '../../services/todo_service.dart';
import '../../theme/app_colors.dart';

enum _AlertSheetKind { homework, testRetake }

class AlertCards extends StatefulWidget {
  final bool isHome;
  final String? selectedClass;
  final String? selectedClassId;
  final VoidCallback? onHomeworkTap;
  final VoidCallback? onTestRetakeTap;
  final void Function(String classId, {DateTime? focusDate})? onNavigateHomeworkClass;
  final void Function(
    String classId, {
    String? examTypeId,
    String? examTypeDisplayName,
    DateTime? focusDate,
  })? onNavigateGradeClass;
  final double tileHeight;
  final double tileBottomMargin;
  final double titleFontSize;
  final double countFontSize;

  const AlertCards({
    super.key,
    required this.isHome,
    this.selectedClass,
    this.selectedClassId,
    this.onHomeworkTap,
    this.onTestRetakeTap,
    this.onNavigateHomeworkClass,
    this.onNavigateGradeClass,
    this.tileHeight = 76,
    this.tileBottomMargin = 10,
    this.titleFontSize = 18,
    this.countFontSize = 18,
  });

  @override
  State<AlertCards> createState() => _AlertCardsState();
}

class _AlertCardsState extends State<AlertCards> {
  HomeAlertSnapshot? _snapshot;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AlertCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isHome != widget.isHome ||
        oldWidget.selectedClass != widget.selectedClass ||
        oldWidget.selectedClassId != widget.selectedClassId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });
    final service = await HomeAlertService.create();
    final snapshot = await service.build(
      className: widget.isHome ? null : widget.selectedClass,
    );
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _isLoading = false;
    });
  }

  void _openSheet(_AlertSheetKind kind) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final groups = kind == _AlertSheetKind.homework
        ? snapshot.homeworkGroups
        : snapshot.testRetakeGroups;
    final title = kind == _AlertSheetKind.homework
        ? '숙제 미완료자 확인'
        : '테스트 재시험자 확인';
    final manageLabel = kind == _AlertSheetKind.homework
        ? '숙제 관리 열기'
        : '성적 관리 열기';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HomeAlertSheet(
        kind: kind,
        title: title,
        groups: groups,
        isHome: widget.isHome,
        forcedClassId: widget.isHome ? null : widget.selectedClassId,
        manageLabel: manageLabel,
        onManageFallback: kind == _AlertSheetKind.homework
            ? widget.onHomeworkTap
            : widget.onTestRetakeTap,
        onNavigateHomeworkClass: widget.onNavigateHomeworkClass,
        onNavigateGradeClass: widget.onNavigateGradeClass,
      ),
    );
  }

  String _countLabel(HomeAlertType type) {
    if (_isLoading) return '...';
    final count = _snapshot?.countFor(type) ?? 0;
    return '$count명';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ActionAlertTile(
          icon: Icons.menu_book_rounded,
          iconColor: AppColors.pink,
          softColor: AppColors.pinkSoft,
          title: '숙제 미완료자 확인',
          count: _countLabel(HomeAlertType.homework),
          height: widget.tileHeight,
          bottomMargin: widget.tileBottomMargin,
          titleFontSize: widget.titleFontSize,
          countFontSize: widget.countFontSize,
          onTap: () => _openSheet(_AlertSheetKind.homework),
        ),
        ActionAlertTile(
          icon: Icons.fact_check_rounded,
          iconColor: AppColors.purple,
          softColor: AppColors.purpleSoft,
          title: '테스트 재시험자 확인',
          count: _countLabel(HomeAlertType.testRetake),
          height: widget.tileHeight,
          bottomMargin: widget.tileBottomMargin,
          titleFontSize: widget.titleFontSize,
          countFontSize: widget.countFontSize,
          onTap: () => _openSheet(_AlertSheetKind.testRetake),
        ),
      ],
    );
  }
}

class ActionAlertTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color softColor;
  final String title;
  final String count;
  final VoidCallback? onTap;
  final double height;
  final double bottomMargin;
  final double titleFontSize;
  final double countFontSize;

  const ActionAlertTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.softColor,
    required this.title,
    required this.count,
    this.onTap,
    this.height = 76,
    this.bottomMargin = 10,
    this.titleFontSize = 18,
    this.countFontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = (height * 0.62).clamp(40.0, 48.0);
    final chevronSize = (titleFontSize + 4).clamp(20.0, 24.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: EdgeInsets.only(bottom: bottomMargin),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(
                color: softColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: (iconBox * 0.52).clamp(22.0, 27.0),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            Text(
              count,
              style: TextStyle(
                fontSize: countFontSize,
                fontWeight: FontWeight.w900,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.subText, size: chevronSize),
          ],
        ),
      ),
    );
  }
}

double _estimateAlertSheetContentHeight(
  List<HomeAlertGroup> groups,
  bool showClassHeaders,
  bool showDropdown,
  bool showManageButton,
) {
  const handle = 17.0;
  const titleBlock = 64.0;
  const dropdownBlock = 52.0;
  const listBottomPad = 20.0;
  const buttonBlock = 84.0;
  const safeBottomPad = 12.0;
  var top = handle + titleBlock;
  if (showDropdown) top += dropdownBlock;
  final bottom = showManageButton ? buttonBlock : safeBottomPad;
  if (groups.isEmpty) {
    return top + 120 + bottom;
  }
  const groupSep = 12.0;
  const classHeader = 31.0;
  const row = 118.0;
  var body = 0.0;
  for (var gi = 0; gi < groups.length; gi++) {
    final g = groups[gi];
    if (gi > 0) body += groupSep;
    if (showClassHeaders) body += classHeader;
    body += g.items.length * row;
  }
  return top + body + listBottomPad + bottom;
}

class _HomeAlertSheet extends StatefulWidget {
  final _AlertSheetKind kind;
  final String title;
  final List<HomeAlertGroup> groups;
  final bool isHome;
  final String? forcedClassId;
  final String manageLabel;
  final VoidCallback? onManageFallback;
  final void Function(String classId, {DateTime? focusDate})? onNavigateHomeworkClass;
  final void Function(
    String classId, {
    String? examTypeId,
    String? examTypeDisplayName,
    DateTime? focusDate,
  })? onNavigateGradeClass;

  const _HomeAlertSheet({
    required this.kind,
    required this.title,
    required this.groups,
    required this.isHome,
    required this.forcedClassId,
    required this.manageLabel,
    required this.onManageFallback,
    required this.onNavigateHomeworkClass,
    required this.onNavigateGradeClass,
  });

  @override
  State<_HomeAlertSheet> createState() => _HomeAlertSheetState();
}

class _HomeAlertSheetState extends State<_HomeAlertSheet>
    with SingleTickerProviderStateMixin {
  double _dragOffsetY = 0;
  bool _isSettling = false;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );

  Animation<double>? _settleAnim;

  /// null = 전체 클래스
  String? _filterClassId;

  @override
  void initState() {
    super.initState();
    _filterClassId = widget.forcedClassId;
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  bool get _showDropdown =>
      widget.isHome && widget.forcedClassId == null && widget.groups.isNotEmpty;

  bool get _showClassHeaders =>
      widget.isHome ? _filterClassId == null : false;

  List<HomeAlertGroup> get _visibleGroups {
    if (_filterClassId == null) return widget.groups;
    return widget.groups
        .where((g) => g.classId == _filterClassId)
        .toList();
  }

  bool get _showManageButton => _filterClassId != null;

  List<DropdownMenuItem<String?>> _dropdownItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('전체 클래스'),
      ),
    ];
    for (final g in widget.groups) {
      final id = g.classId;
      if (id == null || id.isEmpty) continue;
      if (items.any((e) => e.value == id)) continue;
      items.add(
        DropdownMenuItem<String?>(
          value: id,
          child: Text(
            g.className,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return items;
  }

  double _targetSheetHeight(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    const defaultFrac = 0.7;
    const maxFrac = 0.92;
    const minFrac = 0.45;
    final defaultH = screenH * defaultFrac;
    final maxH = screenH * maxFrac;
    final minH = screenH * minFrac;
    final content = _estimateAlertSheetContentHeight(
      _visibleGroups,
      _showClassHeaders,
      _showDropdown,
      _showManageButton,
    );
    if (content <= defaultH) {
      return math.max(minH, math.min(defaultH, content));
    }
    return math.min(maxH, math.max(defaultH, content));
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_isSettling) return;
    setState(() {
      _dragOffsetY = (_dragOffsetY + d.delta.dy).clamp(0.0, 1e6);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_isSettling) return;
    final vy = d.velocity.pixelsPerSecond.dy;
    const dismissDist = 52.0;
    const fastDown = 520.0;
    const fastUp = 380.0;

    if (vy < -fastUp) {
      _runSettleAnimation(0);
      return;
    }
    if (_dragOffsetY < 24 && vy <= 180) {
      _runSettleAnimation(0);
      return;
    }
    if (vy > fastDown || (_dragOffsetY > dismissDist && vy >= -120)) {
      _runCloseAnimation();
      return;
    }
    if (_dragOffsetY > dismissDist * 0.65) {
      _runCloseAnimation();
      return;
    }
    _runSettleAnimation(0);
  }

  void _runSettleAnimation(double target) {
    _settleAnim?.removeListener(_tickSettle);
    _settle.stop();
    _settle.reset();
    final start = _dragOffsetY;
    if ((start - target).abs() < 0.5) {
      setState(() => _dragOffsetY = target);
      return;
    }
    _isSettling = true;
    _settleAnim = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic),
    );
    _settleAnim!.addListener(_tickSettle);
    _settle.forward().whenComplete(() {
      _settleAnim?.removeListener(_tickSettle);
      if (mounted) {
        setState(() {
          _dragOffsetY = target;
          _isSettling = false;
        });
      }
    });
  }

  void _tickSettle() {
    if (!mounted || _settleAnim == null) return;
    setState(() => _dragOffsetY = _settleAnim!.value);
  }

  void _runCloseAnimation() {
    _settleAnim?.removeListener(_tickSettle);
    _settle.stop();
    _settle.reset();
    final start = _dragOffsetY;
    final h = MediaQuery.sizeOf(context).height;
    _isSettling = true;
    _settleAnim = Tween<double>(begin: start, end: h).animate(
      CurvedAnimation(parent: _settle, curve: Curves.easeOut),
    );
    _settleAnim!.addListener(_tickSettle);
    _settle.forward().whenComplete(() {
      _settleAnim?.removeListener(_tickSettle);
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onStudentTap(HomeAlertItem item) {
    final cid = item.classId;
    if (cid == null || cid.isEmpty) return;

    if (widget.kind == _AlertSheetKind.homework) {
      final nav = widget.onNavigateHomeworkClass;
      if (nav == null) return;
      Navigator.pop(context);
      nav(
        cid,
        focusDate: TodoService.calendarDayOnly(item.anchorDate),
      );
      return;
    }

    final eid = item.examTypeId;
    if (eid == null || eid.isEmpty) return;
    final nav = widget.onNavigateGradeClass;
    if (nav == null) return;
    Navigator.pop(context);
    nav(
      cid,
      examTypeId: eid,
      examTypeDisplayName: item.examTypeDisplayName,
      focusDate: TodoService.calendarDayOnly(item.anchorDate),
    );
  }

  void _onManagePressed() {
    final id = _filterClassId;
    Navigator.pop(context);
    if (id == null || id.isEmpty) {
      widget.onManageFallback?.call();
      return;
    }
    if (widget.kind == _AlertSheetKind.homework) {
      final nav = widget.onNavigateHomeworkClass;
      if (nav != null) {
        nav(id);
      } else {
        widget.onManageFallback?.call();
      }
    } else {
      final nav = widget.onNavigateGradeClass;
      if (nav != null) {
        nav(id);
      } else {
        widget.onManageFallback?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = _targetSheetHeight(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Transform.translate(
      offset: Offset(0, _dragOffsetY),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Container(
            width: double.infinity,
            height: h,
            color: AppColors.overlay,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD6DCE6),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showDropdown)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _filterClassId,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(12),
                          items: _dropdownItems(),
                          onChanged: (v) =>
                              setState(() => _filterClassId = v),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _visibleGroups.isEmpty
                      ? const Center(child: Text('표시할 학생이 없습니다.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          itemCount: _visibleGroups.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _AlertGroupSection(
                              group: _visibleGroups[index],
                              showHeader: _showClassHeaders,
                              kind: widget.kind,
                              onStudentTap: _onStudentTap,
                            );
                          },
                        ),
                ),
                if (_showManageButton)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + safeBottom),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _onManagePressed,
                          child: Text(widget.manageLabel),
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(height: math.max(8.0, safeBottom)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertGroupSection extends StatelessWidget {
  final HomeAlertGroup group;
  final bool showHeader;
  final _AlertSheetKind kind;
  final void Function(HomeAlertItem item) onStudentTap;

  const _AlertGroupSection({
    required this.group,
    required this.showHeader,
    required this.kind,
    required this.onStudentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Text(
            group.className,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 8),
        ],
        ...group.items.map(
          (item) => _AlertStudentRow(
            item: item,
            kind: kind,
            onTap: () => onStudentTap(item),
          ),
        ),
      ],
    );
  }
}

class _AlertStudentRow extends StatelessWidget {
  final HomeAlertItem item;
  final _AlertSheetKind kind;
  final VoidCallback onTap;

  const _AlertStudentRow({
    required this.item,
    required this.kind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = item.classId != null &&
        item.classId!.isNotEmpty &&
        (kind == _AlertSheetKind.homework ||
            (item.examTypeId != null && item.examTypeId!.isNotEmpty));

    final detail = item.detail.trim();
    final secondary = (item.secondaryDetail ?? '').trim();
    final hasDetail = detail.isNotEmpty;
    final hasSecondary = secondary.isNotEmpty;

    // 학생 이름 + 시험/숙제 메인 + 작은 회색 보조줄은 모두 같은 정보 묶음으로 보이게
    // 왼쪽 Column 안에 차곡차곡 쌓아두고, 상태 뱃지만 오른쪽에 띄운다.
    // 보조줄(completion / threshold)을 카드 하단으로 떼어놓지 않는 게 핵심.
    final infoColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.studentName,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
            height: 1.2,
          ),
        ),
        if (hasDetail) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
              height: 1.25,
            ),
            softWrap: true,
          ),
        ],
        if (hasSecondary) ...[
          const SizedBox(height: 2),
          Text(
            secondary,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.25,
              color: Colors.grey[700],
            ),
            softWrap: true,
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: canTap ? onTap : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: infoColumn),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: item.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: item.status.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
