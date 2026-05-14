import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const textTheme = TextTheme(
      headlineLarge: TextStyle(
        color: AppColors.navy,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.05,
      ),
      headlineMedium: TextStyle(
        color: AppColors.navy,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.1,
      ),
      headlineSmall: TextStyle(
        color: AppColors.navy,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.15,
      ),
      titleLarge: TextStyle(
        color: AppColors.navy,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.2,
      ),
      titleMedium: TextStyle(
        color: AppColors.navy,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleSmall: TextStyle(
        color: AppColors.navy,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      bodyLarge: TextStyle(
        color: AppColors.navy,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        color: AppColors.navy,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: AppColors.subText,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        color: AppColors.navy,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      labelMedium: TextStyle(
        color: AppColors.subText,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: AppColors.subText,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: AppColors.background,
      brightness: Brightness.dark,
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blue,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: Brightness.dark,
      ),
      dividerColor: AppColors.line,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.overlay,
        foregroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.navy,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.overlay,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: AppColors.navy,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.subText,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardAlt,
        hintStyle: const TextStyle(color: AppColors.subText),
        labelStyle: const TextStyle(color: AppColors.subText),
        prefixIconColor: AppColors.subText,
        suffixIconColor: AppColors.subText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.blue),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: textTheme.bodyMedium,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.subText,
        textColor: AppColors.navy,
        titleTextStyle: TextStyle(
          color: AppColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: TextStyle(
          color: AppColors.subText,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardAlt,
        contentTextStyle: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: AppColors.background,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            color: AppColors.background,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.subText,
          textStyle: textTheme.labelLarge?.copyWith(color: AppColors.subText),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.line),
          backgroundColor: AppColors.cardAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: AppColors.navy),
      ),
    );
  }
}
