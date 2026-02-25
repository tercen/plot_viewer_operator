import 'package:flutter/material.dart';

/// Dark theme color tokens from the Tercen Design System.
class AppColorsDark {
  AppColorsDark._();

  // Primary (same hues, adjusted for dark backgrounds)
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primarySurface = Color(0xFF1E3A5F);
  static const Color primaryBg = Color(0xFF172554);

  // Status / Accent (same as light — these read well on dark)
  static const Color green = Color(0xFF059669);
  static const Color greenLight = Color(0xFF064E3B);
  static const Color amber = Color(0xFFD97706);
  static const Color amberLight = Color(0xFF78350F);
  static const Color red = Color(0xFFDC2626);
  static const Color redLight = Color(0xFF7F1D1D);

  // Neutrals (inverted)
  static const Color neutral900 = Color(0xFFF9FAFB);
  static const Color neutral800 = Color(0xFFF3F4F6);
  static const Color neutral700 = Color(0xFFE5E7EB);
  static const Color neutral600 = Color(0xFFD1D5DB);
  static const Color neutral500 = Color(0xFF9CA3AF);
  static const Color neutral400 = Color(0xFF6B7280);
  static const Color neutral300 = Color(0xFF4B5563);
  static const Color neutral200 = Color(0xFF374151);
  static const Color neutral100 = Color(0xFF1F2937);
  static const Color neutral50 = Color(0xFF1A2332);
  static const Color white = Color(0xFF111827);

  // Semantic aliases
  static const Color textPrimary = neutral900;
  static const Color textSecondary = neutral700;
  static const Color textMuted = neutral500;
  static const Color textDisabled = neutral400;
  static const Color border = neutral300;
  static const Color borderLight = neutral200;
  static const Color surfaceHover = neutral50;
  static const Color surface = Color(0xFF1F2937);
  static const Color background = Color(0xFF111827);
}
