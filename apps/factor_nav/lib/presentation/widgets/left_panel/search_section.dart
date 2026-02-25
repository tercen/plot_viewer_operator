import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_colors_dark.dart';
import '../../../core/theme/app_spacing.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/theme_provider.dart';

/// SEARCH section: text input that filters factors by name.
class SearchSection extends StatefulWidget {
  const SearchSection({super.key});

  @override
  State<SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<SearchSection> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final mutedColor = isDark ? AppColorsDark.textMuted : AppColors.textMuted;

    // Sync controller when provider value changes externally
    // (e.g., step-selected clears search)
    if (!_focusNode.hasFocus && _controller.text != provider.searchQuery) {
      _controller.text = provider.searchQuery;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: 'Filter factors...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: provider.searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, size: 16, color: mutedColor),
                    onPressed: () {
                      _controller.clear();
                      provider.setSearchQuery('');
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.xl,
                      minHeight: AppSpacing.xl,
                    ),
                  )
                : null,
          ),
          onChanged: provider.setSearchQuery,
        ),
      ],
    );
  }
}
