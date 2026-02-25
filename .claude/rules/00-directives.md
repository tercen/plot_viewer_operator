# Directives — STOP and re-read if you are about to violate ANY of these

Each line is a hard constraint. Violating any one is a session failure.

---

## GGRS / step_viewer Architecture

1. ALL data loading uses `StreamGenerator` trait. No reimplementing fetch, dequantization, pixel mapping, or culling in Dart or custom WASM code.
2. `WasmStreamGenerator` (ggrs-wasm, browser Fetch) and `TercenStreamGenerator` (plot operator, gRPC) are the ONLY data paths.
3. GGRS queries Tercen directly. Flutter does NOT fetch table data, schema data, or do pixel mapping.
4. Flutter's jobs: factor list UI, binding state, CubeQuery lifecycle (sci_tercen_client), render chrome/points that GGRS returns.
5. Y-only: WasmStreamGenerator sets sequential X range [1..nRows] when no x_axis_table — same as TercenStreamGenerator. No fake column names.
6. `renderChrome()` replaces the entire 6-layer DOM and destroys data points — NEVER call it after data streaming has started.
7. `renderDataPoints()` is additive — it draws on the existing data canvas without clearing.
8. Domain table discovery (queryTableType) happens in WASM, not Flutter. Flutter passes raw schemaIds.
9. Read `_local/wrong-premises-log.md` before any step_viewer or GGRS work.

## Error Handling

10. NEVER catch errors and return defaults — let errors propagate visibly.
11. NEVER substitute mock data when real data fails — stop and surface the error.
12. NEVER add retry loops, "if X fails try Y" chains, or graceful degradation without explicit user approval.

## App Boundaries

13. Apps NEVER import from each other — shared code goes in `packages/widget_library/`.
14. Tool window apps (left/bottom panels, ~280px) NEVER use `AppShell` — use single-column layout with `LeftPanelSection` widgets.

## Styling — Tercen Design System Only

15. Spacing values are ONLY 4, 8, 16, 24, 32, 48 — NEVER use 10, 15, 18, 22, or any other value.
16. NEVER invent colors — use `AppColors` from `widget_library/theme/`.
17. NEVER invent icons — use FontAwesome 6 Solid, or the 6 Tercen custom icons (`tercen-Data-Step`, `tercen-Workflow`, `tercen-Submodule`, `tercen-Gather`, `tercen-Join`, `tercen-clone`).
18. If a visual decision is not covered by the design system, ASK — do not improvise.

## Layout

19. NO right sidebars — all persistent panels on the left.
20. NO `Expanded` / `flex: 1` on dropdowns or controls — size for content, not available space.
21. NO hover-to-reveal or hotkey-only features — every feature needs a visible clickable affordance.
22. NO `justify-content: space-between` or stretched layouts — left-align, let right side be empty.
23. All controls go in the left panel — the main content area is display only.

## Skeleton / Theme Files

24. NEVER modify: `left_panel.dart`, `left_panel_header.dart`, `left_panel_section.dart`, `app_shell.dart`, `top_bar.dart`, `app_colors.dart`, `app_colors_dark.dart`, `app_spacing.dart`, `app_text_styles.dart`, `app_theme.dart`, `context_detector.dart`, `theme_provider.dart`.
25. Skill files in `.claude/skills/` are READ-ONLY — never modify them.

## Tercen SDK

26. CubeQueryTask creation: ALWAYS set `state = sci.InitState()`, `owner = workflow.acl.owner`, `isDeleted = false` — SDK defaults are wrong.
27. NEVER use `dart:html` or `http` for Tercen API calls — use `sci_tercen_client`.
28. Only `SimpleRelation` has fetchable schema IDs — base `Relation` UUIDs return 404, do NOT attempt to fetch them.
29. Parse workflow port IDs with regex `^(.+)-[io]-(\d+)$` — step IDs contain hyphens (UUIDs, `ts-` prefixes).
30. Empty factor namespace is valid — NEVER filter with `.where((n) => n.isNotEmpty)`.

## Behavioral

31. When asked to remove X, remove ONLY X — do not remove or restructure neighboring working code.
32. When something works, do NOT restructure it unless explicitly asked.
33. When a request is ambiguous, ASK which specific piece to change before touching code.
34. One skill phase per session — never load multiple skills.
