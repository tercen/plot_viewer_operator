# Session Start — 2026-02-24

## What was done

### Axis Zoom — Data Range Narrowing (two-regime zoom)

When zoomed to a single visible facet, further zoom narrows Y/X data range instead of changing facet cell sizes. All 204 ggrs-core + ggrs-wasm tests pass. WASM builds clean.

**Files changed:**

1. **`ggrs-core/src/layout_info.rs`** — Added `y_min`, `y_max`, `x_min`, `x_max` (all `Option<f64>`, `#[serde(default)]`) to `ViewportFilter`
2. **`ggrs-core/src/compute_layout.rs`** — `build_scale_caches(generator, viewport)` and `compute_viewport_chrome(..., viewport)` now accept optional viewport; override tick breaks, grid lines, axis_mappings when axis zoom fields present. Added `breaks_to_labels()` helper using `extended_breaks` + `format_break`.
3. **`ggrs-wasm/src/lib.rs`** — `init_plot_stream` returns `x_min/x_max/y_min/y_max` in metadata JSON. `get_viewport_chrome` parses viewport JSON and passes to compute functions.
4. **`step_viewer/lib/presentation/providers/plot_state_provider.dart`** — Added `_axisZoomLevel`, `_baseYMin/Max`, `_baseXMin/Max`, computed range getters (`yMinOverride` etc.), `applyZoom(delta, allFacetsFit:)` returns bool for regime detection, `setBaseAxisRanges()`.
5. **`step_viewer/lib/services/ggrs_service.dart`** — Added `_storeBaseAxisRanges()`, `_renderWithAxisZoom()`, `_handleZoom()`. Zoom callback dispatches to axis or facet zoom. `render()` stores base ranges after `initPlotStream`.

## What needs testing

1. **End-to-end axis zoom against live Tercen**: Load a step, zoom in until single facet visible, verify axis range narrows (tick labels update, grid lines reposition)
2. **Zoom out transition**: From axis zoom back to facet zoom — verify smooth transition at `axisZoomLevel == 1.0`
3. **Single-panel plot (no facets)**: Axis zoom should start immediately on first zoom-in
4. **Existing facet zoom behavior**: Verify unchanged — zoom in/out with many facets still changes cell count

## Logical next steps

### 1. End-to-end testing against live Tercen
- Build + copy WASM: `cd ggrs && wasm-pack build crates/ggrs-wasm --target web && cp -r crates/ggrs-wasm/pkg/* ../plot_viewer_operator/apps/step_viewer/web/ggrs/pkg/`
- Run: `cd apps/step_viewer && flutter run -d chrome --web-port 8080` with Tercen dart-defines
- Test: Y-only, X+Y, row facets, zoom in/out across both regimes

### 2. Axis zoom data re-rendering
- Currently axis zoom only re-renders chrome (ticks, grid lines). Data points are NOT re-rendered with the narrowed range.
- Data points still show the full-range pixel mapping — they need to be re-mapped to the narrowed viewport.
- Options: (a) re-stream data with narrowed axis_mappings pixel coords, (b) apply CSS transform/clip to data canvas
- Files: `ggrs_service.dart` (`_renderWithAxisZoom`), possibly `bootstrap.js` for canvas transform

### 3. Color/shape/size aesthetic bindings
- Currently only x, y, row_facet, col_facet are wired
- UI: factor drop targets in step_viewer left panel
- `PlotStateProvider`: color/shape/size binding state
- `_buildInitConfig`: pass bound aesthetics to WASM

### 4. factor_nav → orchestrator wiring
- factor_nav (Phase 3 complete) not registered in `webapp_registry.dart` or `build_all.sh`
