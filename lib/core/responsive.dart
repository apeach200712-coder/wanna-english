import 'package:flutter/material.dart';

/// Screen classification based on available width (logical pixels / dp).
///
/// Uses current layout width so it reacts to both orientation and
/// split-screen / foldable states correctly.
///
/// Reference widths (portrait, logical px):
///   iPhone SE 2/3           : 375 pt
///   iPhone 15 / 16 / 17 Pro : 390–393 pt
///   Galaxy S22–S25          : 360–393 dp
///   iPhone 17 Pro Max       : 430 pt
///   Galaxy S24+/Ultra, S25U : 412 dp
///   Galaxy Z Flip (folded)  : ~263 dp  → treated as smallPhone
///   Galaxy Z Fold (folded)  : ~300 dp  → treated as smallPhone
///   Galaxy Z Fold (inner)   : ~717 dp  → treated as foldableInner
///   iPad mini 6             : 768 pt
///   Galaxy Tab S6 Lite      : 800 dp
///   iPad 10th gen           : 820 pt
///   Galaxy Tab S8/S9        : 800 dp
///   iPad Pro 11"            : 834 pt
///   Galaxy Tab S8 Ultra     : ~927 dp
///   iPad Pro 13"            : 1024 pt
enum ScreenClass {
  /// ≤ 380 dp  — iPhone SE, old small Android, Galaxy Z Fold folded
  smallPhone,

  /// 381–430 dp — iPhone 15/16/17 Pro, Galaxy S22–S25, Pixel 7–9
  phone,

  /// 431–599 dp — iPhone 17 Pro Max, Galaxy S24+/Ultra, landscape small phones
  largePhone,

  /// 600–839 dp — Galaxy Z Fold inner, iPad mini, Galaxy Tab compact
  foldableInner,

  /// 840–1099 dp — iPad 10th gen, iPad Pro 11", Galaxy Tab S8/S9
  tablet,

  /// ≥ 1100 dp — iPad Pro 13", Galaxy Tab S8 Ultra, desktop
  largeTablet,
}

/// Breakpoint-based responsive helpers.
/// Always read from `MediaQuery.sizeOf(context).width` (current layout width).
class Responsive {
  Responsive._();

  // ── Classification ────────────────────────────────────────────────────────

  static ScreenClass screenClass(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return ScreenClass.largeTablet;
    if (w >= 840) return ScreenClass.tablet;
    if (w >= 600) return ScreenClass.foldableInner;
    if (w >= 431) return ScreenClass.largePhone;
    if (w >= 381) return ScreenClass.phone;
    return ScreenClass.smallPhone;
  }

  static bool isPhone(BuildContext context) {
    final sc = screenClass(context);
    return sc == ScreenClass.smallPhone ||
        sc == ScreenClass.phone ||
        sc == ScreenClass.largePhone;
  }

  static bool isTabletOrLarger(BuildContext context) {
    final sc = screenClass(context);
    return sc == ScreenClass.foldableInner ||
        sc == ScreenClass.tablet ||
        sc == ScreenClass.largeTablet;
  }

  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  // ── Horizontal padding ────────────────────────────────────────────────────

  static double hPadding(BuildContext context) {
    switch (screenClass(context)) {
      case ScreenClass.smallPhone:
        return 16;
      case ScreenClass.phone:
        return 22;
      case ScreenClass.largePhone:
        return 24;
      case ScreenClass.foldableInner:
        return 32;
      case ScreenClass.tablet:
        return 40;
      case ScreenClass.largeTablet:
        return 56;
    }
  }

  // ── Vertical padding ──────────────────────────────────────────────────────

  static double vPaddingTop(BuildContext context) {
    if (isLandscape(context) && isPhone(context)) return 8;
    return 16;
  }

  static double vPaddingBottom(BuildContext context) {
    switch (screenClass(context)) {
      case ScreenClass.smallPhone:
        return 24;
      case ScreenClass.phone:
      case ScreenClass.largePhone:
        return 28;
      case ScreenClass.foldableInner:
      case ScreenClass.tablet:
      case ScreenClass.largeTablet:
        return 40;
    }
  }

  // ── Content width cap ─────────────────────────────────────────────────────

  /// Caps content width on wide screens so text/cards don't stretch too far.
  static double maxContentWidth(BuildContext context) {
    switch (screenClass(context)) {
      case ScreenClass.largeTablet:
        return 920;
      case ScreenClass.tablet:
        return 780;
      case ScreenClass.foldableInner:
        return 640;
      default:
        return double.infinity;
    }
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  /// Columns for the quick-action card grid.
  static int gridColumns(BuildContext context) {
    switch (screenClass(context)) {
      case ScreenClass.largeTablet:
        return 4;
      case ScreenClass.tablet:
        return 4;
      case ScreenClass.foldableInner:
        return 3;
      default:
        return 2;
    }
  }

  static double gridChildAspectRatio(BuildContext context) {
    switch (screenClass(context)) {
      case ScreenClass.largeTablet:
      case ScreenClass.tablet:
        return 1.45;
      case ScreenClass.foldableInner:
        return 1.38;
      default:
        return 1.32;
    }
  }

  // ── Todo feed ─────────────────────────────────────────────────────────────

  static double todoSectionGap(BuildContext context) {
    if (isLandscape(context) && isPhone(context)) return 14;
    return 22;
  }

  /// Show two-column section layout in todo feed.
  static bool todoTwoColumns(BuildContext context) {
    final sc = screenClass(context);
    return (sc == ScreenClass.tablet || sc == ScreenClass.largeTablet) &&
        isLandscape(context);
  }

  // ── Typography ────────────────────────────────────────────────────────────

  static double fontSize(BuildContext context, double base) {
    switch (screenClass(context)) {
      case ScreenClass.smallPhone:
        return base * 0.92;
      case ScreenClass.phone:
        return base;
      case ScreenClass.largePhone:
        return base * 1.02;
      case ScreenClass.foldableInner:
        return base * 1.06;
      case ScreenClass.tablet:
        return base * 1.10;
      case ScreenClass.largeTablet:
        return base * 1.16;
    }
  }
}
