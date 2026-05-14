import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class ClassSelector extends StatelessWidget {
  final String selectedMode;
  final VoidCallback onTap;

  const ClassSelector({
    super.key,
    required this.selectedMode,
    required this.onTap,
  });

  String get label {
    if (selectedMode == 'HOME') return 'HOME';
    if (selectedMode.trim().isEmpty) return '수업';
    // 동명 반(예: 이화여고 3학년(1)/(2)) 구분을 위해 저장된 표시 문자열을 그대로 씁니다.
    return selectedMode.trim();
  }

  @override
  Widget build(BuildContext context) {
    final maxChip =
        (MediaQuery.sizeOf(context).width * 0.38).clamp(120.0, 320.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.chip,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxChip),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 7),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: AppColors.subText,
            ),
          ],
        ),
      ),
    );
  }
}
