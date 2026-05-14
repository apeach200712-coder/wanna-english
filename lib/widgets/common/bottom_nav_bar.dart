import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'main_tab_navigation.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomNavBar({super.key, required this.currentIndex});

  void _go(BuildContext context, int index) {
    MainTabNavigation.go(
      context,
      index: index,
      currentIndex: currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: AppColors.overlay,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.home_rounded,
            label: '홈',
            active: currentIndex == 0,
            onTap: () => _go(context, 0),
          ),
          _NavItem(
            icon: Icons.groups_rounded,
            label: '학생',
            active: currentIndex == 1,
            onTap: () => _go(context, 1),
          ),
          _NavItem(
            icon: Icons.calendar_month_rounded,
            label: '캘린더',
            active: currentIndex == 2,
            onTap: () => _go(context, 2),
          ),
          _NavItem(
            icon: Icons.folder_open_rounded,
            label: '자료',
            active: currentIndex == 3,
            onTap: () => _go(context, 3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.blue : AppColors.subText;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active ? AppColors.graySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
