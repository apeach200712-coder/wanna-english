import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'class_selector.dart';

class TeacherSearchBar extends StatelessWidget {
  final String selectedMode;
  final VoidCallback onModeTap;
  final VoidCallback onSearchTap;
  final double height;
  final double hintFontSize;
  final double searchIconSize;

  const TeacherSearchBar({
    super.key,
    required this.selectedMode,
    required this.onModeTap,
    required this.onSearchTap,
    this.height = 66,
    this.hintFontSize = 16,
    this.searchIconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = (height * 0.72).clamp(40.0, 48.0);
    final dividerH = (height * 0.38).clamp(22.0, 26.0);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          ClassSelector(selectedMode: selectedMode, onTap: onModeTap),
          const SizedBox(width: 14),
          Container(width: 1, height: dividerH, color: AppColors.line),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: onSearchTap,
              child: Text(
                '학생 이름 검색 또는 선택',
                style: TextStyle(
                  fontSize: hintFontSize,
                  color: AppColors.subText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onSearchTap,
            child: Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(
                color: AppColors.graySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.search_rounded,
                color: AppColors.blue,
                size: searchIconSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
