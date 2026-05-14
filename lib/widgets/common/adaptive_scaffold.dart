import 'package:flutter/material.dart';

import '../../core/responsive.dart';
import '../../theme/app_colors.dart';
import 'bottom_nav_bar.dart';
import 'main_tab_navigation.dart';

/// Adaptive scaffold that shows:
///  • Phone  → body + BottomNavigationBar
///  • Tablet → NavigationRail (left) + body
class AdaptiveScaffold extends StatelessWidget {
  final int currentIndex;
  final Widget body;
  final Color? backgroundColor;

  const AdaptiveScaffold({
    super.key,
    required this.currentIndex,
    required this.body,
    this.backgroundColor,
  });

  static const _destinations = <NavigationRailDestination>[
    NavigationRailDestination(icon: Icon(Icons.home_rounded), label: Text('홈')),
    NavigationRailDestination(
      icon: Icon(Icons.groups_rounded),
      label: Text('학생'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.calendar_month_rounded),
      label: Text('캘린더'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.folder_open_rounded),
      label: Text('자료'),
    ),
  ];

  void _navigate(BuildContext context, int index) {
    MainTabNavigation.go(
      context,
      index: index,
      currentIndex: currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = Responsive.isTabletOrLarger(context);

    if (wide) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: (i) => _navigate(context, i),
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.overlay,
              selectedIconTheme: const IconThemeData(
                color: AppColors.blue,
                size: 26,
              ),
              unselectedIconTheme: const IconThemeData(
                color: AppColors.subText,
                size: 24,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: AppColors.subText,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              indicatorColor: AppColors.graySoft,
              useIndicator: true,
              destinations: _destinations,
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.line,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: body,
      bottomNavigationBar: AppBottomNavBar(currentIndex: currentIndex),
    );
  }
}
