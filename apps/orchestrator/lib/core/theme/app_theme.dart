import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_colors_dark.dart';

/// Material 3 ThemeData builders for light and dark themes.
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.white,
          secondary: AppColors.primaryLight,
          surface: AppColors.surface,
          error: AppColors.red,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.firaSansTextTheme(),
        dividerColor: AppColors.borderLight,
        splashFactory: InkSplash.splashFactory,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColorsDark.primary,
          onPrimary: Color(0xFFFFFFFF),
          secondary: AppColorsDark.primaryLight,
          surface: AppColorsDark.surface,
          error: AppColorsDark.red,
        ),
        scaffoldBackgroundColor: AppColorsDark.background,
        textTheme: GoogleFonts.firaSansTextTheme(
          ThemeData.dark().textTheme,
        ),
        dividerColor: AppColorsDark.borderLight,
        splashFactory: InkSplash.splashFactory,
      );
}
