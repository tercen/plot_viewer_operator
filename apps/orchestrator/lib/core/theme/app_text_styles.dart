import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography tokens from the Tercen Design System.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get _fira => GoogleFonts.firaSans();

  static TextStyle get pageTitle => _fira.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );

  static TextStyle get sectionTitle => _fira.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  static TextStyle get subsectionTitle => _fira.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.4,
      );

  static TextStyle get body => _fira.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get smallBody => _fira.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get caption => _fira.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  static TextStyle get label => _fira.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
      );

  static TextStyle get code => GoogleFonts.sourceCodePro(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );
}
