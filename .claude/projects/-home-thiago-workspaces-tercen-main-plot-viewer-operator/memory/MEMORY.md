# Plot Viewer Operator — Memory

## Critical Architecture Correction

The docs (plan-overview.md, CLAUDE.md) describe 4 apps. This is **outdated/incomplete**. The real architecture is:

- **Orchestrator = IDE-like panel manager** (JetBrains-style), NOT a simple 3-app shell
- Hosts **tens of webapps** (not just 4), each in its own **iframe**
- Dynamic split-tree layout with draggable splitters, icon strips, docking
- Communication via **postMessage** (cross-iframe), NOT CustomEvent
- Webapps self-register with metadata (name, icon, preferred position, size, multi-instance)
- Multiple instances of the same webapp supported (e.g., 2 plot viewers)

## Known Webapps (from user, 2026-02-12)

toolbar, project_nav, team_nav, operator_library, workflow_visualizer, plot_viewer, report_viewer, ai_chat, text_file_editor, gating, user_manager, task_manager

## Orchestrator Spec Status

- File: `apps/orchestrator/docs/functional-spec.md` — v2.0.0 Draft
- **Needs user review** before Phase 1 is complete
- See `_local/session-2026-02-12.md` for full session log

## Key User Preferences

- Prefers JetBrains IDE model over VS Code
- Wants simplified v1 first, architected for full docking later
- Branded splash screen (Tercen logo + spinner)
- Empty main area before step selection (no welcome message)
- Auth: orchestrator receives credentials from Tercen, distributes to webapps
- Errors: webapps throw via postMessage, orchestrator catches, formats, displays overlay
