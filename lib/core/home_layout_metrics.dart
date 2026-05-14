import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'responsive.dart';

/// Height- and width-aware spacing and typography for the home screen.
///
/// Uses the scaffold body constraints so tablet [NavigationRail] and phone
/// bottom nav are already accounted for in [bodyMaxHeight].
class HomeLayoutMetrics {
  const HomeLayoutMetrics({
    required this.bodyMaxHeight,
    required this.bodyMaxWidth,
    required this.heightT,
    required this.lockOuterScroll,
    required this.vPadTop,
    required this.vPadBottom,
    required this.hPad,
    required this.maxContentWidth,
    required this.afterHeader,
    required this.afterSearch,
    required this.afterSchedule,
    required this.beforeAlerts,
    required this.searchBarHeight,
    required this.scheduleBarHeight,
    required this.alertTileHeight,
    required this.alertTileBottomMargin,
    required this.todoMaxListHeight,
    required this.todoFillRemaining,
    required this.headerMidGap,
    required this.logoTopNudge,
    required this.logoWidthFactor,
    required this.logoWidthMin,
    required this.logoWidthMax,
    required this.dateFontSize,
    required this.dayFontSize,
    required this.academyTitleSize,
    required this.academyBranchSize,
    required this.searchHintFontSize,
    required this.scheduleLabelFontSize,
    required this.todoTitleFontSize,
    required this.todoRowTitleFontSize,
    required this.todoEmptyFontSize,
    required this.alertTitleFontSize,
    required this.alertCountFontSize,
  });

  final double bodyMaxHeight;
  final double bodyMaxWidth;

  /// 0 = short viewport (compact), 1 = tall (comfortable).
  final double heightT;

  /// When true, home uses a [Column] with [Expanded] To-Do (no outer scroll).
  final bool lockOuterScroll;

  final double vPadTop;
  final double vPadBottom;
  final double hPad;
  final double maxContentWidth;

  final double afterHeader;
  final double afterSearch;
  final double afterSchedule;
  final double beforeAlerts;

  final double searchBarHeight;
  final double scheduleBarHeight;
  final double alertTileHeight;
  final double alertTileBottomMargin;

  /// Cap for the scrollable To-Do list when outer scroll is used.
  final double todoMaxListHeight;

  /// When true, To-Do fills remaining space in a locked layout.
  final bool todoFillRemaining;

  final double headerMidGap;
  final double logoTopNudge;
  final double logoWidthFactor;
  final double logoWidthMin;
  final double logoWidthMax;

  final double dateFontSize;
  final double dayFontSize;
  final double academyTitleSize;
  final double academyBranchSize;
  final double searchHintFontSize;
  final double scheduleLabelFontSize;
  final double todoTitleFontSize;
  final double todoRowTitleFontSize;
  final double todoEmptyFontSize;
  final double alertTitleFontSize;
  final double alertCountFontSize;

  static const double _shortBody = 520;
  static const double _tallBody = 920;

  /// Minimum body height before we try a non-scrolling home layout.
  static const double _lockScrollMinHeight = 720;

  /// Need enough width so the header + cards don't feel crushed.
  static const double _lockScrollMinWidth = 560;

  static HomeLayoutMetrics from({
    required BuildContext context,
    required BoxConstraints bodyConstraints,
    required bool isHome,
  }) {
    final mq = MediaQuery.of(context);
    final hRaw = bodyConstraints.maxHeight;
    final wRaw = bodyConstraints.maxWidth;

    final bodyH = hRaw.isFinite
        ? hRaw
        : (mq.size.height -
              mq.padding.top -
              mq.padding.bottom -
              (Responsive.isTabletOrLarger(context) ? 0 : 84));
    final bodyW = wRaw.isFinite ? wRaw : mq.size.width;

    final heightT =
        ((bodyH - _shortBody) / (_tallBody - _shortBody)).clamp(0.0, 1.0);

    final lockOuterScroll = isHome &&
        Responsive.isTabletOrLarger(context) &&
        bodyH >= _lockScrollMinHeight &&
        bodyW >= _lockScrollMinWidth;

    double lerp(double a, double b) => lerpDouble(a, b, heightT)!;

    final vTopBase = Responsive.vPaddingTop(context);
    final vBotBase = Responsive.vPaddingBottom(context);
    final hPadBase = Responsive.hPadding(context);
    final maxWBase = Responsive.maxContentWidth(context);

    final vPadTop = lerp(vTopBase * 0.5, vTopBase);
    final vPadBottom = lockOuterScroll
        ? lerp(vBotBase * 0.65, vBotBase * 0.85)
        : lerp(vBotBase * 0.75, vBotBase);
    final hPad = hPadBase;
    final maxContentWidth = maxWBase == double.infinity
        ? double.infinity
        : lerp(maxWBase * 0.98, maxWBase);

    final afterHeader = lerp(6, 10);
    final afterSearch = lerp(10, 14);
    final afterSchedule = lerp(12, 16);
    final beforeAlerts = lerp(12, 18);

    final searchBarHeight = lerp(56, 66);
    final scheduleBarHeight = lerp(54, 62);
    final alertTileHeight = lerp(68, 76);
    final alertTileBottomMargin = lerp(6, 10);

    final headerMidGap = lerp(10, 14);
    final logoTopNudge = lerp(10, 13);
    final logoWidthFactor = lerp(0.76, 0.80);
    final logoWidthMin = lerp(88.0, 96.0);
    final logoWidthMax = lerp(200.0, 220.0);

    final dateFontSize = lerp(30, 40);
    final dayFontSize = lerp(14, 18);
    final academyTitleSize = lerp(14, 15);
    final academyBranchSize = lerp(12, 13);
    final searchHintFontSize = lerp(14, 16);
    final scheduleLabelFontSize = lerp(15, 17);
    final todoTitleFontSize = lerp(19, 22);
    final todoRowTitleFontSize = lerp(15, 17);
    final todoEmptyFontSize = lerp(14, 15);
    final alertTitleFontSize = lerp(16, 18);
    final alertCountFontSize = lerp(16, 18);

    // To-Do list cap when scrolling: shorter on small heights, taller when room.
    final todoMaxListHeight = lerp(132.0, 220.0);

    return HomeLayoutMetrics(
      bodyMaxHeight: bodyH,
      bodyMaxWidth: bodyW,
      heightT: heightT,
      lockOuterScroll: lockOuterScroll,
      vPadTop: vPadTop,
      vPadBottom: vPadBottom,
      hPad: hPad,
      maxContentWidth: maxContentWidth,
      afterHeader: afterHeader,
      afterSearch: afterSearch,
      afterSchedule: afterSchedule,
      beforeAlerts: beforeAlerts,
      searchBarHeight: searchBarHeight,
      scheduleBarHeight: scheduleBarHeight,
      alertTileHeight: alertTileHeight,
      alertTileBottomMargin: alertTileBottomMargin,
      todoMaxListHeight: todoMaxListHeight,
      todoFillRemaining: lockOuterScroll,
      headerMidGap: headerMidGap,
      logoTopNudge: logoTopNudge,
      logoWidthFactor: logoWidthFactor,
      logoWidthMin: logoWidthMin,
      logoWidthMax: logoWidthMax,
      dateFontSize: dateFontSize,
      dayFontSize: dayFontSize,
      academyTitleSize: academyTitleSize,
      academyBranchSize: academyBranchSize,
      searchHintFontSize: searchHintFontSize,
      scheduleLabelFontSize: scheduleLabelFontSize,
      todoTitleFontSize: todoTitleFontSize,
      todoRowTitleFontSize: todoRowTitleFontSize,
      todoEmptyFontSize: todoEmptyFontSize,
      alertTitleFontSize: alertTitleFontSize,
      alertCountFontSize: alertCountFontSize,
    );
  }
}
