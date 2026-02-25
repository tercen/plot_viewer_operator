import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_dark.dart';
import '../../core/theme/app_spacing.dart';
import '../providers/theme_provider.dart';
import '../widgets/left_panel/left_panel_section.dart';
import '../widgets/left_panel/search_section.dart';
import '../widgets/left_panel/factors_section.dart';
import '../widgets/left_panel/info_section.dart';

/// Home screen for the factor navigator tool window.
///
/// Unlike apps with a left panel + main content split (via AppShell),
/// the factor navigator is a single-column tool window — the entire
/// iframe is one scrollable panel with header + sections.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final panelBg =
        isDark ? AppColorsDark.panelBackground : AppColors.panelBackground;
    final headerBg = isDark ? AppColorsDark.primary : AppColors.primary;

    return Scaffold(
      body: Container(
        color: panelBg,
        child: Column(
          children: [
            // Header bar
            Container(
              height: AppSpacing.headerHeight,
              color: headerBg,
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: const Row(
                children: [
                  FaIcon(FontAwesomeIcons.layerGroup,
                      color: Colors.white, size: 20),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Factor Navigator',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Scrollable sections
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    LeftPanelSection(
                      icon: Icons.search,
                      label: 'SEARCH',
                      child: const SearchSection(),
                    ),
                    LeftPanelSection(
                      icon: FontAwesomeIcons.layerGroup,
                      label: 'FACTORS',
                      child: const FactorsSection(),
                    ),
                    LeftPanelSection(
                      icon: Icons.info_outline,
                      label: 'INFO',
                      child: const InfoSection(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
