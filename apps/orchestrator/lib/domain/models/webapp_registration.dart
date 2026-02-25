import 'package:flutter/material.dart';

/// Preferred panel position for a webapp.
enum PanelPosition { top, left, center, bottom }

/// Metadata that each webapp declares to the orchestrator.
class WebappRegistration {
  final String id;
  final String name;
  final IconData icon;
  final PanelPosition preferredPosition;
  final Size defaultSize;
  final bool multiInstance;
  final String url;

  /// Whether this webapp appears in the icon strip for its position.
  /// When false, the strip is opened programmatically (e.g., on step-selected).
  final bool showInIconStrip;

  const WebappRegistration({
    required this.id,
    required this.name,
    required this.icon,
    required this.preferredPosition,
    required this.defaultSize,
    required this.multiInstance,
    required this.url,
    this.showInIconStrip = true,
  });
}
