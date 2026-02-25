# Skill Feedback

## Phase 2: Mock Build — Orchestrator (2026-02-13)

### Gap: Skeleton not available

The Phase 2 skill requires `skeleton/` from `tercen-flutter-skills`, but the repository is not cloned in the workspace and the GitHub URL returns 404. The orchestrator was built from scratch instead.

### Gap: Skeleton pattern doesn't fit composition shells

The Phase 2 skill is designed for apps with left panel sections, controls, main content, and a data service. The orchestrator is a composition shell with none of these — it manages panels, iframes, and postMessage routing. A dedicated "composition shell" skeleton or skill variant would be useful for apps like the orchestrator.

### Adaptation

Built the orchestrator from scratch following:
- Theme system from `.claude/rules/04-tercen-style-reference.md`
- Layout rules from `.claude/rules/05-tercen-layout-principles.md`
- Icon system from `.claude/rules/06-icon-system.md`
- Functional spec from `apps/orchestrator/docs/functional-spec.md`

Used `dart:html` for iframe management and postMessage (web-only app). Used `dart:ui_web` for platform view registration. Provider/ChangeNotifier for state management.
