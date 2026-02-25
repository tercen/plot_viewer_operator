# Skills Workflow (3-Phase Build Process)

Each app in this monorepo follows the Tercen Flutter Skills workflow.
Skills are in `.claude/skills/` and invokable via `/` commands.

## Phases

| Phase | Invoke with | What happens |
|-------|------------|--------------|
| 1 | `/phase-1-functional-spec` | Write functional spec (no code) |
| 2 | `/phase-2-mock-build` | Build mock app from spec + skeleton |
| 3 | `/phase-3-tercen-integration` | Replace mocks with real Tercen data |

## Rules

- **One skill per session.** Do not load multiple skills.
- **Skills are READ-ONLY.** Never modify skill files during app builds.
- Phase 1 output (functional spec) bridges to Phase 2. Phase 2 output (working mock app) bridges to Phase 3.
- If a skill gap or error is encountered, note it in `_local/skill-feedback.md` and continue.

## Tercen Design Constraints (from skills)

1. **ALL controls go in the left panel.** Main content area is display only.
2. **Left panel sections scroll vertically.** No tabs. No internal collapse.
3. **Every section has an icon and UPPERCASE label.**
4. **INFO section is mandatory** at the bottom of the left panel with a GitHub repository link.
5. **Available control types**: dropdown, slider, range slider, toggle, number input, button, searchable input, text input. Do not invent new control types.

## Skeleton Rules (Phase 2)

- Copy the skeleton, rename it, replace placeholders. **Do NOT restructure** the app shell, left panel, or theme system.
- DO NOT MODIFY: left_panel.dart, left_panel_header.dart, left_panel_section.dart, app_shell.dart, top_bar.dart, app_colors.dart, app_colors_dark.dart, app_spacing.dart, app_text_styles.dart, app_theme.dart, context_detector.dart, theme_provider.dart, service_locator.dart (structure), main.dart (structure).
- If panel collapse/resize/theme toggle breaks, a DO NOT MODIFY file was changed. Revert.

## Wiring Golden Rule

```
control.onChanged -> provider.setXxx(value) -> notifyListeners() -> Consumer rebuilds main content
```

## Phase 3 Rules

- Never navigate JSON relation tree for tabular data — use `tableSchemaService.select()`
- Always use explicit GetIt type parameters: `getIt.registerSingleton<ServiceFactory>(factory)`
- Never use `dart:html` or `http` for Tercen API calls — use `sci_tercen_client`
- When data access fails: STOP, run diagnostic report, present to user
