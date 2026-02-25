import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../providers/theme_provider.dart';
import '../providers/webapp_provider.dart';

/// Semi-transparent error overlay shown when a webapp reports an error.
///
/// Displays the source webapp name, error message, and a dismiss button.
/// Dismissing does not destroy any webapp state.
class ErrorOverlay extends StatelessWidget {
  const ErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final webappProvider = context.watch<WebappProvider>();
    final error = webappProvider.currentError;
    if (error == null) return const SizedBox.shrink();

    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return GestureDetector(
      onTap: () {}, // Absorb taps on the overlay background
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            margin: const EdgeInsets.all(AppSpacing.xl),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: isDark ? AppColorsDark.surface : AppColors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              boxShadow: const [
                BoxShadow(
                  offset: Offset(0, 20),
                  blurRadius: 25,
                  color: Color(0x26000000),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with warning icon
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.amber,
                      size: 32,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Error in ${error.webappName}',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColorsDark.textPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Error message
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isDark ? AppColorsDark.redLight : AppColors.redLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: isDark ? AppColorsDark.red : AppColors.red,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    error.message,
                    style: AppTextStyles.smallBody.copyWith(
                      color: isDark ? AppColorsDark.red : AppColors.red,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Dismiss button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => webappProvider.dismissError(),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: Text(
                      'Dismiss',
                      style: AppTextStyles.smallBody.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
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
