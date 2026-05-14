import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF79A8FF);
  static const background = Color(0xFF0F1115);
  static const card = Color(0xFF181B20);

  static const navy = Color(0xFFF3F5F8);
  static const subText = Color(0xFF8B93A1);
  static const line = Color(0xFF262B33);

  static const blue = Color(0xFF7DA8FF);
  static const green = Color(0xFF73D6A4);
  static const yellow = Color(0xFFF0C96B);
  static const orange = Color(0xFFF3A25B);
  static const red = Color(0xFFE97777);
  static const pink = Color(0xFFE48AAA);
  static const purple = Color(0xFF9D8CFF);
  static const mint = Color(0xFF67C8BE);
  static const gray = Color(0xFF697180);

  static const blueSoft = Color(0xFF1A2333);
  static const greenSoft = Color(0xFF16251F);
  static const orangeSoft = Color(0xFF2A2119);
  static const pinkSoft = Color(0xFF2A1D23);
  static const purpleSoft = Color(0xFF211C30);
  static const graySoft = Color(0xFF21252C);

  static const overlay = Color(0xFF12151A);
  static const cardAlt = Color(0xFF14181E);
  static const chip = Color(0xFF20252D);
}

List<BoxShadow> softShadow() {
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.24),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];
}
