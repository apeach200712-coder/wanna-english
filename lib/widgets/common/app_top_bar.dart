import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../theme/app_colors.dart';

class AppTopBar extends StatelessWidget {
  final VoidCallback? onNotificationTap;
  final VoidCallback? onSettingsTap;
  final bool showActionIcons;

  const AppTopBar({
    super.key,
    this.onNotificationTap,
    this.onSettingsTap,
    this.showActionIcons = true,
  });

  /// `wanna_logo_white_tight.png` — 스크롤/Column 등에서 세로 제약 풀릴 때도 크기 고정
  static const double _logoAspect = 700 / 331;

  /// 학원 카드·알림/설정(46) 높이와 맞는 정도의 컴팩트 로고 폭
  static const double _logoWidth = 118.0;

  @override
  Widget build(BuildContext context) {
    final logoHeight = _logoWidth / _logoAspect;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: _logoWidth,
            height: logoHeight,
            child: Image.asset(
              'assets/wanna_logo_white_tight.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.academyName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              SizedBox(height: 2),
              Text(
                AppConstants.academyBranch,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (showActionIcons) ...[
          const SizedBox(width: 10),
          _CircleIcon(
            icon: Icons.notifications_none_rounded,
            onTap: onNotificationTap,
          ),
          const SizedBox(width: 8),
          _CircleIcon(icon: Icons.settings_outlined, onTap: onSettingsTap),
        ],
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleIcon({required this.icon, this.onTap});

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
