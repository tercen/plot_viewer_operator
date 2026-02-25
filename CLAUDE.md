# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Tercen PWA monorepo — a suite of independent Flutter web apps composed into an IDE-like workbench by an orchestrator. Each app runs in its own iframe. The orchestrator is a JetBrains-style panel management shell (split-tree layout, icon strips, draggable splitters). See `apps/orchestrator/docs/functional-spec.md` for the full architecture.

## Build & Development

Flutter web monorepo. Each app is a standalone Flutter web project. Requires Flutter >=3.5.0.

```bash
# Build all apps for production (sub-apps built and copied into orchestrator/web/):
./build_all.sh

# Run an individual app for development:
cd apps/<app_name>
flutter pub get
flutter run -d chrome

# Orchestrator (the main entry point users run):
cd apps/orchestrator
flutter run -d chrome --web-port 8080

# Build single app:
cd apps/<app_name>
flutter build web --release

# Lint:
cd apps/<app_name>
flutter analyze
```

### Local Development with Tercen Backend

For apps with Tercen integration (Phase 3), pass dart-defines for authentication. JetBrains run config flags:

```
--web-browser-flag=--user-data-dir=/tmp/chrome-dev \
--web-browser-flag=--disable-web-security \
--web-port 8080 \
--dart-define=TERCEN_TOKEN=<jwt-token> \
--dart-define=SERVICE_URI=http://127.0.0.1:5400 \
--dart-define=TEAM_ID=test
```

The `--disable-web-security` flag is needed because the app runs on localhost but calls the Tercen API on a different port.

### Build Script (`build_all.sh`)

Builds GGRS WASM via `wasm-pack`, copies WASM assets into `apps/step_viewer/web/ggrs/pkg/`, then builds every sub-app and copies into `apps/orchestrator/web/<app_name>/`, then builds orchestrator last.

### Key Dependencies

- **State management:** `provider` ^6.1.2 (ChangeNotifier pattern)
- **Dependency injection:** `get_it` ^8.0.3 (sub-apps; orchestrator uses Provider directly)
- **Icons:** `font_awesome_flutter` ^10.8.0
- **Fonts:** `google_fonts` ^6.2.1 (Fira Sans)
- **Tercen API:** `sci_tercen_client` via local path (`/home/thiago/workspaces/tercen/main/sci_tercen_client/sci_tercen_client`)
- **Web interop:** `web` ^0.5.1
- **Shared widgets/theme:** `packages/widget_library` (local path dependency)

## Architecture

### Iframe Communication Model
- Apps run in **iframes**, not as Flutter widgets in the same app
- Inter-app communication via **postMessage** with standard envelope: `{ type, source, target, payload }`
- The orchestrator routes messages — it does NOT interpret payloads
- Apps never import from each other; shared code lives in `packages/widget_library/`

### Known Message Types
| Type | Source | Target | Purpose |
|------|--------|--------|---------|
| `init-context` | orchestrator | any webapp | Passes token, serviceUri, themeMode |
| `request-context` | webapp | orchestrator | Webapp requests initialization |
| `app-ready` | any webapp | orchestrator | Webapp finished loading |
| `app-error` | any webapp | orchestrator | Webapp encountered an error |
| `step-selected` | project_nav | step_viewer | User selected a data step |
| `run-requested` | toolbar | active webapp | Run button pressed |
| `save-requested` | toolbar | active webapp | Save button pressed |
| `export-requested` | toolbar | active webapp | Export button pressed |
| `theme-changed` | orchestrator | * (broadcast) | Light/dark mode toggle |
| `render-progress` | step_viewer | toolbar | Plot rendering progress |

### Orchestrator Webapp Registry (`webapp_registry.dart`)
Six webapps registered. Three are real Flutter apps; three are mock HTML placeholders:
- **Real Flutter apps:** project-nav (left panel), step-viewer (center, multi-instance)
- **Mock HTML:** toolbar (top), team-nav (left), ai-chat (bottom), task-manager (bottom)
- **Not registered:** factor-nav (Phase 3 complete, but not wired into orchestrator)

`WebappRegistration` fields: `multiInstance` (step-viewer sets `true`), `defaultSize` (Size.zero = auto-size).

To add a new app: register in `webapp_registry.dart`, add to `APP_REGISTRY_IDS` in `build_all.sh`, rebuild both the sub-app and orchestrator.

### Shared Package (`packages/widget_library/`)
Shared Flutter package used by sub-apps. Contains:
- `lib/theme/` — Tercen Design System (colors, spacing, text styles, theme)
- `lib/models/factor.dart` — Factor model (name, namespace, type)
- `lib/widgets/` — `FactorPanel`, `LeftPanelSection`

Apps depend on this via `path: ../../packages/widget_library` in pubspec.yaml.

### GGRS Rendering (Step Viewer) — CRITICAL

**READ `_local/wrong-premises-log.md` before any step_viewer / GGRS work.** It documents wrong assumptions made in previous sessions that led to hours of wasted work.

The step viewer embeds a GGRS WASM web component via `HtmlElementView`. Two WASM modules coexist:
1. **CanvasKit** (Flutter UI) — WebGL context
2. **GGRS** (plot data) — 6-layer DOM: `<canvas>` background + `<svg>` chrome + `<canvas>` data + `<div>` text + `<svg>` annotations + `<div>` interaction

#### Data Flow Architecture (4-Phase StreamGenerator)

ALL data loading uses the `StreamGenerator` trait (ggrs-core). `WasmStreamGenerator` (browser HTTP via web-sys) is the only data path. GGRS queries Tercen directly — Flutter does NOT fetch table data, schema data, or do pixel mapping.

CubeQuery lifecycle runs in **Flutter** via `sci_tercen_client` SDK. Everything else happens in WASM. `GgrsService.render()` uses a 4-phase progressive flow:

```
User drops factor on Y
  → PlotStateProvider updates binding
  → GgrsService.render()

  Phase 1: Instant chrome (no network)
    → empty payload + bindings → computeLayout() → renderChrome()
    → Shows axes labels, drop zones — immediate visual feedback

  Phase 2: CubeQuery (~1s)
    → CubeQueryService.ensureCubeQuery()           [Flutter/Dart SDK]
      → 5C (match): existing CubeQuery, bindings match → return as-is
      → 5A (mismatch): update bindings → re-run CubeQueryTask
      → 5B (missing): build from scratch → run CubeQueryTask

  Phase 3: initPlotStream + getStreamLayout + renderChrome
    → WASM discovers domain tables from schemaIds (queryTableType)
    → WASM fetches metadata: axis ranges, facet labels, nRows
    → WasmStreamGenerator created → PlotGenerator trained (scales)
    → getStreamLayout() → LayoutInfo with real axes
    → renderChrome() with real axis ticks + labels

  Phase 4: Chunked data streaming (15K rows/chunk)
    → loop: loadAndMapChunk(15000)
      → WASM fetches qt chunk via HTTP
      → WASM dequantizes using cached axis ranges
      → WASM pixel-maps using cached LayoutInfo axis_mappings
      → WASM grid-culls (O(1) spatial overlap, persistent across chunks)
      → returns visible pixel points
    → renderDataPoints(): additive canvas draw
    → yield frame between chunks for progressive paint
```

**Three WASM API paths:**
- **Stateless** (`computeLayout`): Phase 1 — empty data, returns skeleton chrome. No Tercen connection.
- **Streaming init** (`initPlotStream`): Phase 3 — discovers domain tables, fetches metadata, creates PlotGenerator with trained scales. Returns n_rows, n_col_facets, n_row_facets.
- **Streaming data** (`loadAndMapChunk`): Phase 4 — fetches chunk, dequantizes, pixel-maps, culls, returns pixel points. Call repeatedly until `done: true`.

**Y-only binding**: Flutter marks x as bound with column `.obs`. WASM generates sequential x values [1..nRows] during dequantization when x axis has NaN ranges.

**Generation counter**: Every `render()` call increments a counter; all async steps check it to cancel stale renders.

#### Key Services (step_viewer)

| Service | File | Role |
|---------|------|------|
| `CubeQueryService` | `services/cube_query_service.dart` | CubeQuery 5A/5B/5C lifecycle via `sci_tercen_client` |
| `GgrsService` | `services/ggrs_service.dart` | 4-phase render: chrome → cubeQuery → stream init → chunked data |
| `GgrsInterop` | `services/ggrs_interop.dart` | Dart↔JS bindings for GGRS WASM functions |

#### GGRS WASM Architecture (ggrs-wasm crate)

| File | Role |
|------|------|
| `wasm_stream_generator.rs` | `StreamGenerator` impl using `TercenWasmClient` (browser HTTP). Metadata-only: pre-loads axis ranges, facet labels, nRows during async init. |
| `lib.rs` | WASM exports: `initPlotStream`, `getStreamLayout`, `loadAndMapChunk` (streaming) + `computeLayout*` (stateless) |
| `tercen_client.rs` | HTTP client using browser Fetch API via web-sys with TSON encoding |
| `incremental_spec.rs` | `IncrementalPlotSpec` for stateless layout computation (Phase 1 chrome) |

#### 6-Layer DOM Structure (`bootstrap.js`)

```
Layer 0: <canvas class="ggrs-background">  — plot bg + panel/strip backgrounds
Layer 1: <svg class="ggrs-chrome">          — grid, axes, ticks, panel borders
Layer 2: <canvas class="ggrs-data">         — data points (ABOVE chrome)
Layer 3: <div class="ggrs-text">            — tick labels, axis labels, titles
Layer 4: <svg class="ggrs-annotations">     — user annotations
Layer 5: <div class="ggrs-interaction">     — mouse/touch handling
```

Data canvas MUST be above SVG chrome — opaque panel_backgrounds in the SVG would hide data points on a canvas below.

**GGRS source**: `/home/thiago/workspaces/tercen/main/ggrs/`
**WASM build**: `cd /home/thiago/workspaces/tercen/main/ggrs && wasm-pack build crates/ggrs-wasm --target web`
**Test harness**: `cd ggrs/web && python3 -m http.server 8000` → `test_interactive.html`
**API reference**: `ggrs/docs/WASM_API_REFERENCE.md`

### App Code Structure (consistent across sub-apps)
```
lib/
├── core/theme/          # Tercen Design System (DO NOT MODIFY)
├── core/utils/          # Context detector (embedded vs standalone)
├── di/service_locator.dart  # GetIt DI setup
├── domain/models/       # Data models
├── domain/services/     # Service interfaces (abstract)
├── implementations/services/  # Mock or real service implementations
├── presentation/providers/    # ChangeNotifier state (AppState, Theme)
├── presentation/widgets/      # UI components (AppShell, LeftPanel, etc.)
└── main.dart
```

Wiring pattern: `control.onChanged → provider.setXxx(value) → notifyListeners() → Consumer rebuilds main content`

**Tool window apps** (left/bottom panels, ~280px wide): Use single-column layout, NOT `AppShell`. `AppShell` is only for center content (full-width) or standalone mode.

## Testing

```bash
# Run widget/unit tests for an app:
cd apps/<app_name>
flutter test

# Run a single test file:
cd apps/<app_name>
flutter test test/<test_file>.dart

# GGRS tests (in separate repo):
cd /home/thiago/workspaces/tercen/main/ggrs
cargo test -p ggrs-core   # 204 tests
cargo test -p ggrs-wasm   # 15 tests

# CLI test scripts for Tercen API integration:
cd _local/api_test
dart run bin/test_api.dart      # Basic API connectivity
dart run bin/test_factors.dart   # Factor loading verification
dart run bin/test_links.dart     # Workflow link graph walking
```

Orchestrator has widget tests in `apps/orchestrator/test/`. Other apps rely on manual testing via `flutter run -d chrome`.

## Tercen Workflow Data Model

Understanding these concepts is essential for any app that reads workflow data (factor_nav, step_viewer).

### Step Types
```
Step (base: id, name)
├── TableStep — model.relation points to uploaded CSV/table data
├── DataStep — computedRelation holds processed output; extends CrossTabStep (model: Crosstab)
├── JoinStep, GroupStep, InStep, OutStep, MeltStep, etc.
```

### Workflow Link Graph
Steps connect via `Workflow.links`. Each `Link` has:
- `inputId`: consumer port — format `{stepId}-i-{N}` (e.g., `b9659735-i-0`)
- `outputId`: producer port — format `{stepId}-o-{N}` (e.g., `92bd54ef-o-0`)
- Data flows FROM `outputId` step TO `inputId` step

**Port ID parsing**: Step IDs contain hyphens (UUIDs, `ts-` prefixes), so use regex `^(.+)-[io]-(\d+)$` to extract the step ID.

### Factor Loading (BFS backward through links)
To get all factors available at a DataStep:
1. Build reverse link graph from `workflow.links` (consumer → set of producers)
2. BFS backward from target step to find all ancestor steps
3. For each ancestor: `TableStep` → walk `model.relation`, `DataStep` → walk `computedRelation`
4. Walk relation tree to find leaf `SimpleRelation` nodes (CouchDB-format IDs)
5. Fetch schema: `tableSchemaService.get(leafId)` → extract `schema.columns` (name + type)
6. Also walk target step's own `computedRelation`
7. Deduplicate by name, filter system columns (`.` prefix, `._rids`/`.tlbId` suffix)

**Key gotcha**: Only `SimpleRelation` has valid schema IDs. Base `Relation` with UUID IDs returns 404. Do NOT fallback-fetch for any Relation with a non-empty ID.

### Relation Tree Types
- `SimpleRelation` — leaf, fetch schema by ID (ONLY type with fetchable IDs)
- `CompositeRelation` — walk `mainRelation` + `joinOperator.rightRelation`
- `UnionRelation` — walk `.relations`
- Wrapper types (`WhereRelation`, `RenameRelation`, `GatherRelation`, etc.) — walk `.relation`
- `SelectPairwiseRelation` — walk `columnRelation`, `rowRelation`, `qtRelation`
- `InMemoryRelation` — skip

### Factor Namespaces
- Name with dot: `namespace.column` → namespace = before first dot, shortName = after last dot
- Name without dot: namespace = empty string, shortName = full name
- Empty namespace is valid — never filter out empty strings

## Current Implementation Status

| App | Phase | Notes |
|-----|-------|-------|
| orchestrator | Phase 2 (mock build) | Composition shell — layout, routing, iframe hosting |
| project_nav | Phase 3 (Tercen integration) | Flow D entity navigation |
| factor_nav | Phase 3 (Tercen integration) | Link graph walking, real Tercen factors; NOT in webapp_registry |
| step_viewer | Phase 3 (in progress) | StreamGenerator-based WASM rendering; needs end-to-end testing |
| toolbar, team-nav, ai-chat, task-manager | Mock HTML | Placeholders in `apps/orchestrator/web/mock_apps/` |

Each webapp that can run as a standalone Tercen operator includes an `operator.json` for Tercen's operator registry.

### step_viewer — Status

**Architecture**: 4-phase StreamGenerator-based progressive rendering. See "Data Flow Architecture" section above. ALL data loading, dequantization, pixel mapping, and culling happen in WASM via `WasmStreamGenerator`. Flutter only handles CubeQuery lifecycle and UI phases.

**Needs end-to-end testing:** Y-only, X+Y, facets — all against live Tercen.

## Known Architectural TODOs

- **factor_nav not wired**: Phase 3 complete but not registered in `webapp_registry.dart` or `build_all.sh`
- **Y-only native**: Currently uses `.obs` workaround from Dart side. Native y-only in WASM would be cleaner

## References

- `docs/architecture-ggrs-interactive.md` — StreamGenerator trait, rendering pipeline, schemaIds layout
- `_local/wrong-premises-log.md` — **Required reading** before step_viewer/GGRS work
- GGRS WASM API: `ggrs/docs/WASM_API_REFERENCE.md`
- Tercen Design System: https://github.com/tercen/tercen-style
- Tercen Client SDK: https://github.com/tercen/sci_tercen_client
