import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../providers/splash_provider.dart';
import '../providers/theme_provider.dart';

/// Branded splash screen overlay shown during initialization.
///
/// Displays Tercen logo, name, and loading spinner.
/// Fades out when [SplashProvider.isVisible] becomes false.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isVisible = context.watch<SplashProvider>().isVisible;
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return IgnorePointer(
      ignoring: !isVisible,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: Container(
          color: isDark ? const Color(0xFF111827) : AppColors.white,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo placeholder — "T" in a circle
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'T',
                    style: AppTextStyles.pageTitle.copyWith(
                      color: Colors.white,
                      fontSize: 32,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Tercen',
                  style: AppTextStyles.sectionTitle.copyWith(
                    color: isDark ? Colors.white : AppColors.neutral900,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                    backgroundColor: isDark
                        ? const Color(0xFF374151)
                        : AppColors.neutral200,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
