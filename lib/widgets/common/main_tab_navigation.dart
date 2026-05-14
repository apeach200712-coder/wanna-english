import 'package:flutter/material.dart';

import '../../core/routes.dart';

/// Shared logic for Home / Students / Calendar / Materials rail & bottom bar.
abstract final class MainTabNavigation {
  static const routes = [
    AppRoutes.home,
    AppRoutes.students,
    AppRoutes.calendar,
    AppRoutes.materials,
  ];

  /// Picks a main-tab route without duplicating [Home] on the stack.
  ///
  /// Home shortcuts sometimes use [Navigator.pushNamed] (stack `[Home, Tab]`),
  /// while the rail previously used [pushReplacementNamed] for other tabs,
  /// which produced `[Home, Home]` when returning home. When a tab had replaced
  /// the root (e.g. `[Materials]` only), a naive pop + push stacked routes wrong.
  static void go(
    BuildContext context, {
    required int index,
    required int currentIndex,
  }) {
    if (index == currentIndex) return;
    final navigator = Navigator.of(context);
    final target = routes[index];

    RouteSettings? rootSettings;
    navigator.popUntil((route) {
      if (route.isFirst) {
        rootSettings = route.settings;
        return true;
      }
      return false;
    });

    final rootName = rootSettings?.name;
    if (rootName == target) return;

    final builder = AppRoutes.routes[target];
    if (builder == null) return;

    final route = AppRoutes.instantPageRoute(target, builder);
    final rootIsHomeShell = rootName == AppRoutes.home ||
        rootName == Navigator.defaultRouteName ||
        rootName == null ||
        rootName.isEmpty;
    if (rootIsHomeShell) {
      navigator.push(route);
    } else {
      navigator.pushReplacement(route);
    }
  }
}
