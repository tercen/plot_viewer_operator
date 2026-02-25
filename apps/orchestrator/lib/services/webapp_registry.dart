import 'package:flutter/material.dart';
import '../domain/models/webapp_registration.dart';

/// Registry of known webapp types.
///
/// In Phase 2 (mock build), this is pre-populated with hardcoded registrations.
/// In Phase 3, webapps will register dynamically.
///
/// URL resolution: when a sub-app has been built and copied into the
/// orchestrator's web/ directory (by build_all.sh), the URL points to
/// the real Flutter build (e.g. 'project_nav/index.html'). Otherwise
/// it falls back to the mock HTML placeholder.
class WebappRegistry {
  final Map<String, WebappRegistration> _registrations = {};

  WebappRegistry() {
    _registerWebapps();
  }

  void _registerWebapps() {
    final webapps = [
      const WebappRegistration(
        id: 'toolbar',
        name: 'Toolbar',
        icon: Icons.menu,
        preferredPosition: PanelPosition.top,
        defaultSize: Size(0, 48),
        multiInstance: false,
        url: 'mock_apps/toolbar.html',
      ),
      const WebappRegistration(
        id: 'project-nav',
        name: 'Project Navigator',
        icon: Icons.folder_open,
        preferredPosition: PanelPosition.left,
        defaultSize: Size(280, 0),
        multiInstance: false,
        url: 'project_nav/index.html',
      ),
      const WebappRegistration(
        id: 'team-nav',
        name: 'Team Navigator',
        icon: Icons.people,
        preferredPosition: PanelPosition.left,
        defaultSize: Size(280, 0),
        multiInstance: false,
        url: 'mock_apps/team_nav.html',
      ),
      const WebappRegistration(
        id: 'step-viewer',
        name: 'Step Viewer',
        icon: Icons.bar_chart,
        preferredPosition: PanelPosition.center,
        defaultSize: Size.zero,
        multiInstance: true,
        url: 'step_viewer/index.html',
      ),
      const WebappRegistration(
        id: 'ai-chat',
        name: 'AI Chat',
        icon: Icons.chat_bubble_outline,
        preferredPosition: PanelPosition.bottom,
        defaultSize: Size(0, 200),
        multiInstance: false,
        url: 'mock_apps/ai_chat.html',
      ),
      const WebappRegistration(
        id: 'task-manager',
        name: 'Task Manager',
        icon: Icons.checklist,
        preferredPosition: PanelPosition.bottom,
        defaultSize: Size(0, 200),
        multiInstance: false,
        url: 'mock_apps/task_manager.html',
      ),
    ];

    for (final reg in webapps) {
      _registrations[reg.id] = reg;
    }
  }

  WebappRegistration? get(String id) => _registrations[id];

  List<WebappRegistration> getByPosition(PanelPosition position) {
    return _registrations.values
        .where((r) => r.preferredPosition == position)
        .toList();
  }

  List<WebappRegistration> get all => _registrations.values.toList();
}
