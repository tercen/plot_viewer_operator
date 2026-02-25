import 'package:flutter/material.dart';
import '../../core/theme/app_spacing.dart';

/// Manages the workbench panel layout state (v3.0 multi-tool-strip model).
///
/// Left edge: multiple tool strips open simultaneously, side-by-side.
/// Center: content grid with configurable column count.
/// Bottom: radio-toggle between bottom-bar apps (unchanged from v2.0).
class LayoutProvider extends ChangeNotifier {
  // ── Tool strips (left edge) ──────────────────────────────────────────

  /// Ordered list of open tool strip app IDs (open-order = left-to-right).
  final List<String> _openToolStrips = [];

  /// Per-tool width. Initialized to defaultToolStripWidth on first open.
  final Map<String, double> _toolStripWidths = {};

  List<String> get openToolStrips => List.unmodifiable(_openToolStrips);

  bool get hasOpenToolStrips => _openToolStrips.isNotEmpty;

  bool isToolStripOpen(String appId) => _openToolStrips.contains(appId);

  double toolStripWidth(String appId) =>
      _toolStripWidths[appId] ?? AppSpacing.defaultToolStripWidth;

  /// Total width consumed by all open tool strips + their splitters.
  double get totalToolStripWidth {
    if (_openToolStrips.isEmpty) return 0.0;
    double total = 0.0;
    for (final id in _openToolStrips) {
      total += toolStripWidth(id);
      total += AppSpacing.splitterThickness;
    }
    return total;
  }

  /// Toggle a tool strip open or closed.
  ///
  /// [availableWidth] is the width available for tool strips + content
  /// (i.e., workbench width minus icon strip width).
  /// Returns false if the open was blocked by the minimum content width guard.
  bool toggleToolStrip(String appId, {required double availableWidth}) {
    if (_openToolStrips.contains(appId)) {
      // Close: always allowed
      _openToolStrips.remove(appId);
      notifyListeners();
      return true;
    } else {
      // Open: check that content area won't shrink below minimum
      final newStripWidth =
          _toolStripWidths[appId] ?? AppSpacing.defaultToolStripWidth;
      final newTotalToolWidth =
          totalToolStripWidth + newStripWidth + AppSpacing.splitterThickness;
      final remainingContent = availableWidth - newTotalToolWidth;
      if (remainingContent < AppSpacing.minContentWidth) {
        return false;
      }
      _openToolStrips.add(appId);
      _toolStripWidths.putIfAbsent(
          appId, () => AppSpacing.defaultToolStripWidth);
      notifyListeners();
      return true;
    }
  }

  /// Update the width of a specific tool strip during splitter drag.
  ///
  /// [maxWidth] is an optional dynamic max to prevent the content area
  /// from shrinking below the minimum.
  void setToolStripWidth(String appId, double width, {double? maxWidth}) {
    final effectiveMax = maxWidth ?? 800.0;
    _toolStripWidths[appId] =
        width.clamp(AppSpacing.minPanelSize, effectiveMax);
    notifyListeners();
  }

  /// Open a tool strip during startup (no guard check, no notifyListeners).
  void openToolStripDefault(String appId) {
    if (_openToolStrips.contains(appId)) return;
    _openToolStrips.add(appId);
    _toolStripWidths.putIfAbsent(appId, () => AppSpacing.defaultToolStripWidth);
  }

  /// Ensure a tool strip is open (no-op if already open). Notifies listeners.
  void ensureToolStripOpen(String appId) {
    if (_openToolStrips.contains(appId)) return;
    _openToolStrips.add(appId);
    _toolStripWidths.putIfAbsent(appId, () => AppSpacing.defaultToolStripWidth);
    notifyListeners();
  }

  // ── Content grid (center area) ───────────────────────────────────────

  /// Ordered list of content app instance IDs.
  final List<String> _contentInstanceIds = [];

  /// Column count for the content grid (1 = single, 2 = side-by-side, 3+ = grid).
  int _contentColumns = 1;

  List<String> get contentInstanceIds =>
      List.unmodifiable(_contentInstanceIds);

  int get contentColumns => _contentColumns;

  void setContentColumns(int n) {
    _contentColumns = n.clamp(1, 4);
    notifyListeners();
  }

  void addContentInstance(String instanceId) {
    if (!_contentInstanceIds.contains(instanceId)) {
      _contentInstanceIds.add(instanceId);
      // Don't notifyListeners — called during init before the widget tree.
    }
  }

  void removeContentInstance(String instanceId) {
    _contentInstanceIds.remove(instanceId);
    notifyListeners();
  }

  // ── Bottom panel (unchanged from v2.0, radio toggle) ─────────────────

  bool _isBottomPanelVisible = false;
  double _bottomPanelHeight = AppSpacing.defaultBottomPanelHeight;
  String? _activeBottomAppId;

  bool get isBottomPanelVisible => _isBottomPanelVisible;
  double get bottomPanelHeight => _bottomPanelHeight;
  String? get activeBottomAppId => _activeBottomAppId;

  void toggleBottomPanel(String appId) {
    if (_activeBottomAppId == appId && _isBottomPanelVisible) {
      _isBottomPanelVisible = false;
    } else {
      _activeBottomAppId = appId;
      _isBottomPanelVisible = true;
    }
    notifyListeners();
  }

  void setBottomPanelHeight(double height) {
    _bottomPanelHeight = height.clamp(
      AppSpacing.minPanelSize,
      600.0,
    );
    notifyListeners();
  }
}
