import 'package:flutter/material.dart';

class AppleViolinTheme {
  // Apple HIG Dark Mode Palette
  static const Color darkBg = Color(0xFF000000);
  static const Color cardDark = Color(0xFF1C1C1E);
  static const Color elevatedDark = Color(0xFF2C2C2E);
  static const Color borderDark = Color(0xFF38383A);
  static const Color subtext = Color(0xFF8E8E93);

  // System Accent Colors
  static const Color appleBlue = Color(0xFF007AFF);
  static const Color appleGreen = Color(0xFF34C759);
  static const Color appleOrange = Color(0xFFFF9500);
  static const Color appleRed = Color(0xFFFF3B30);
  static const Color appleIndigo = Color(0xFF5856D6);
  static const Color applePurple = Color(0xFFAF52DE);
  static const Color appleTeal = Color(0xFF5AC8FA);
  static const Color appleYellow = Color(0xFFFFCC00);

  // Borders
  static final BorderRadius cardRadius = BorderRadius.circular(20);
  static final BorderRadius btnRadius = BorderRadius.circular(14);
  static final BorderRadius pillRadius = BorderRadius.circular(999);

  // Shadows
  static const BoxShadow softShadow = BoxShadow(
    color: Colors.black45,
    blurRadius: 15,
    offset: Offset(0, 4),
  );

  static const BoxShadow blueGlow = BoxShadow(
    color: Color(0x4D007AFF),
    blurRadius: 20,
    spreadRadius: 2,
  );

  static const BoxShadow greenGlow = BoxShadow(
    color: Color(0x4D34C759),
    blurRadius: 20,
    spreadRadius: 2,
  );
}
