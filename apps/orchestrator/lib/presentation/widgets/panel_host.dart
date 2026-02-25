import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../providers/theme_provider.dart';
import '../providers/webapp_provider.dart';
import 'webapp_iframe.dart';

/// Hosts a webapp iframe for a given instanceId.
///
/// If no instanceId is provided, shows an empty state.
/// While the webapp has not sent `app-ready`, a loading overlay covers
/// the iframe. The iframe loads in the background underneath.
class PanelHost extends StatelessWidget {
  final String? instanceId;

  const PanelHost({super.key, this.instanceId});

  @override
  Widget build(BuildContext context) {
    if (instanceId == null) {
      return _EmptyPanel();
    }

    final webappProvider = context.watch<WebappProvider>();
    final instance = webappProvider.getInstance(instanceId!);
    if (instance == null) {
      return _EmptyPanel();
    }

    return Stack(
      children: [
        WebappIframe(
          key: ValueKey(instanceId),
          instanceId: instance.instanceId,
          url: instance.registration.url,
          messageRouter: webappProvider.messageRouter,
          onDispose: () =>
              webappProvider.resetInstanceReady(instance.instanceId),
        ),
        if (!instance.isReady)
          _LoadingOverlay(appName: instance.registration.name),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final String appName;

  const _LoadingOverlay({required this.appName});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final bgColor = isDark ? AppColorsDark.surface : AppColors.surface;
    final textColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;
    final spinnerColor = isDark ? AppColorsDark.primary : AppColors.primary;
    final trackColor = isDark ? AppColorsDark.neutral200 : AppColors.neutral200;

    return Positioned.fill(
      child: Container(
        color: bgColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: spinnerColor,
                  backgroundColor: trackColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading $appName',
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Container(
      color: isDark ? AppColorsDark.surface : AppColors.neutral50,
    );
  }
}
