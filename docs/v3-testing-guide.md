# V3 Testing Guide — Early Integration Testing

This document explains how to wire up and test the V3 architecture (Layout + Interaction modules) before proceeding to Phase 3 (Render Orchestration).

## Status

✅ **Completed:**
- Phase 1: Layout Module (LayoutState, LayoutManager, WASM exports)
- Phase 2: Interaction Abstraction (InteractionHandler trait, zoom/pan/reset handlers)
- 44 Rust tests passing (29 layout + 15 interaction)
- All V3 files created with .bak checkpoints
- V2 files restored to original working state

🔄 **Current Goal:**
Test V3 Layout + Interaction with simplified sequential rendering (skip Phase 3 coordinator for now).

---

## Architecture Overview

**V3 Files:**
```
WASM:
  ggrs-core/src/layout_state.rs          ← Single source of truth
  ggrs-core/src/layout_manager.rs        ← Centralized mutations
  ggrs-wasm/src/interaction.rs           ← Handler trait
  ggrs-wasm/src/interactions/*.rs        ← Zoom/Pan/Reset handlers
  ggrs-wasm/src/lib.rs                   ← WASM exports (initLayout, interaction*)

JS:
  web/ggrs/bootstrap_v3.js                ← GPU setup, InteractionManager
  web/ggrs/ggrs_gpu_v3.js                 ← LayoutState-driven GPU rendering
  web/ggrs/interaction_manager.js         ← Event routing, zone detection

Dart:
  lib/services/ggrs_service_v3.dart       ← 7-phase render pipeline
  lib/services/ggrs_interop_v3.dart       ← Dart↔JS interop
```

**V2 Files (unchanged, working):**
```
  web/ggrs/bootstrap_v2.js
  web/ggrs/ggrs_gpu_v2.js
  lib/services/ggrs_service_v2.dart
  lib/services/ggrs_interop_v2.dart (if exists, or uses ggrs_interop.dart)
```

---

## Integration Steps

### 1. Build WASM with V3 Changes

```bash
cd /home/thiago/workspaces/tercen/main/ggrs
wasm-pack build crates/ggrs-wasm --target web --out-dir ../../plot_viewer_operator/apps/step_viewer/web/ggrs/pkg
```

Verify new exports exist:
```bash
grep -E "(initLayout|interactionStart|interactionMove|interactionEnd)" apps/step_viewer/web/ggrs/pkg/ggrs_wasm.d.ts
```

Expected output:
```typescript
export function initLayout(params_json: string): string;
export function getLayoutState(): string;
export function interactionStart(handler_type: string, zone: string, x: number, y: number, params_json: string): string;
export function interactionMove(dx: number, dy: number, x: number, y: number, params_json: string): string;
export function interactionEnd(): string;
export function interactionCancel(): string;
```

### 2. Add V3 HTML Script Tags

Edit `/home/thiago/workspaces/tercen/main/plot_viewer_operator/apps/step_viewer/web/index.html`:

```html
<!-- After existing bootstrap_v2.js script -->
<script type="module" src="ggrs/bootstrap_v3.js"></script>
<script type="module" src="ggrs/ggrs_gpu_v3.js"></script>
<script type="module" src="ggrs/interaction_manager.js"></script>
```

**Note:** Both v2 and v3 scripts can coexist. We'll control which is used via Dart service selection.

### 3. Switch Dart to Use V3 Service

**Option A: Direct replacement (recommended for testing)**

Edit `/home/thiago/workspaces/tercen/main/plot_viewer_operator/apps/step_viewer/lib/di/service_locator.dart`:

```dart
import '../services/ggrs_service_v3.dart';  // Add this

void setupServiceLocator() {
  // ... existing code ...

  // Replace GgrsService registration:
  getIt.registerLazySingleton<GgrsServiceV3>(() => GgrsServiceV3());
  // OLD: getIt.registerLazySingleton<GgrsService>(() => GgrsService());
}
```

Edit widget that uses the service (likely in `lib/presentation/widgets/plot_canvas.dart` or similar):

```dart
// Old:
// final ggrsService = getIt<GgrsService>();

// New:
final ggrsService = getIt<GgrsServiceV3>();
```

**Option B: Feature flag (safer, allows A/B testing)**

Add to service_locator.dart:
```dart
const bool _useV3 = true;  // Toggle to switch versions

void setupServiceLocator() {
  if (_useV3) {
    getIt.registerLazySingleton<GgrsServiceV3>(() => GgrsServiceV3());
  } else {
    getIt.registerLazySingleton<GgrsService>(() => GgrsService());
  }
}
```

### 4. Run Step Viewer

```bash
cd /home/thiago/workspaces/tercen/main/plot_viewer_operator/apps/step_viewer
flutter run -d chrome --web-port 8080 \
  --dart-define=TERCEN_TOKEN=<your-token> \
  --dart-define=SERVICE_URI=http://127.0.0.1:5400 \
  --dart-define=TEAM_ID=test \
  --web-browser-flag=--user-data-dir=/tmp/chrome-dev \
  --web-browser-flag=--disable-web-security
```

---

## Test Cases

### Test 1: Initial Render (Layout State Sync)

**Steps:**
1. Open step_viewer
2. Drop a Y factor (continuous variable)
3. Open browser DevTools console

**Expected Console Logs:**
```
[GgrsV3] WASM ready @ Xms
[GgrsV3] CubeQuery complete: <id> @ Yms
[GgrsV3] initPlotStream complete @ Zms
[GgrsV3] computeSkeleton complete @ Ams
[GgrsV3] initLayout complete @ Bms
[GgrsV3] Layout synced to GPU @ Cms
[GgrsV3] Chrome rendered @ Dms
[GgrsV3] streamData complete @ Ems
[GgrsV3] Render complete @ Fms
```

**Visual Check:**
- Plot appears with axes, grid lines, data points
- No missing chrome (backgrounds, borders, ticks)
- No console errors

**Failure Indicators:**
- `{"error": "..."}` in console
- Missing layout state fields
- GPU uniform buffer not written (black canvas)

---

### Test 2: Zone Detection

**Verify geometric zone boundaries work correctly.**

**Steps:**
1. Render a plot with facets (drop col_facet or row_facet)
2. Open DevTools console
3. Hover mouse in different zones
4. Check console for zone detection logs (if you add debug logging to interaction_manager.js)

**Expected Zones:**
- **Left strip** (row facet labels): `x < grid_origin_x`
- **Top strip** (col facet labels): `y < grid_origin_y`
- **Data grid**: `x >= grid_origin_x && y >= grid_origin_y`
- **Outside** (margins): elsewhere

**Manual Test (no logging needed):**
- Zone detection happens on first wheel/click — watch for correct axis response

---

### Test 3: Zoom — Data Grid (Both Axes)

**Data-anchored zoom with constant pixel gap.**

**Steps:**
1. Render a plot with single facet (no col/row facets)
2. Hover mouse inside data grid
3. Hold Shift + scroll wheel DOWN (zoom in)

**Expected Behavior:**
- Both X and Y axes zoom in
- **X-axis**: Left edge stays fixed (data_x_min anchor)
- **Y-axis**: Top edge stays fixed (data_y_max anchor)
- Data points get larger
- Grid lines recompute (WASM chrome rebuild)

**Visual Check:**
- Bottom-left data point stays at same pixel position
- Right edge moves left, bottom edge moves up
- Axis labels update

**Console Check:**
```
[InteractionManager] Start Zoom in data at (X, Y)
[GgrsV3] Layout synced to GPU
```

**Repeat:** Shift + scroll wheel UP (zoom out)
- Opposite behavior
- Eventually clamps to full range (can't zoom out beyond data bounds)

**Failure Indicators:**
- Anchor drifts (top-left corner moves)
- Axis ranges don't change
- Console error from WASM

---

### Test 4: Zoom — Left Strip (Y-axis Only)

**Zone-aware zoom.**

**Steps:**
1. Hover mouse in LEFT STRIP (over row facet labels or Y-axis area)
2. Hold Shift + scroll wheel DOWN

**Expected Behavior:**
- **Only Y-axis zooms** (X-axis unchanged)
- Top edge stays fixed (data_y_max anchor)
- Bottom edge moves up

**Visual Check:**
- X-axis tick labels unchanged
- Y-axis tick labels update
- Data points stretch vertically only

**Console Check:**
```
[InteractionManager] Start Zoom in left at (X, Y)
```

**Failure Indicators:**
- Both axes zoom (zone detection broken)
- No zoom happens (handler not called)

---

### Test 5: Zoom — Top Strip (X-axis Only)

**Steps:**
1. Hover mouse in TOP STRIP (over col facet labels or X-axis area)
2. Hold Shift + scroll wheel DOWN

**Expected Behavior:**
- **Only X-axis zooms** (Y-axis unchanged)
- Left edge stays fixed (data_x_min anchor)
- Right edge moves left

**Visual Check:**
- Y-axis unchanged
- X-axis tick labels update
- Data points stretch horizontally only

---

### Test 6: Multi-Facet Zoom (Cell Size)

**For plots with multiple facets, zoom changes cell size instead of axis ranges.**

**Steps:**
1. Drop Y factor + col_facet (creates multiple columns)
2. Shift + scroll wheel in data grid

**Expected Behavior:**
- **Cell width increases** (not axis zoom)
- Grid origin (top-left) stays fixed
- All panels grow uniformly
- Axis ranges unchanged (data still spans full range)

**Visual Check:**
- More space between panels
- Axis tick labels unchanged
- Data points get larger within each panel

**Console Check:**
```
[FACET-DEBUG] isMultiFacet=true
```

**Failure Indicators:**
- Axis ranges change (should stay at full range)
- Cells don't grow
- Top-left anchor drifts

---

### Test 7: Pan — Drag in Data Grid

**Steps:**
1. Zoom in first (so there's room to pan)
2. Click and drag inside data grid (NO modifiers)

**Expected Behavior:**
- Viewport shifts in direction of drag
- **Y-axis inverted**: Drag down → viewport moves down (Y range decreases)
- Clamped to full range (can't pan beyond data bounds)

**Visual Check:**
- Data points slide smoothly
- Axis labels update
- Chrome rebuilds on 6ms debounce (after drag stops)

**Console Check:**
```
[InteractionManager] Start Pan in data at (X, Y)
[InteractionManager] Move Pan (dx, dy)
[InteractionManager] End Pan
```

**Failure Indicators:**
- Viewport doesn't move
- Pan not clamped (axis ranges exceed full range)
- Y-axis not inverted

---

### Test 8: Pan Cancellation (Small Distance)

**Steps:**
1. Zoom in
2. Click and release immediately (no drag, or drag < 2 pixels)

**Expected Behavior:**
- Interaction cancelled (was a click, not a drag)
- No viewport change

**Console Check:**
```
[InteractionManager] Start Pan
[InteractionManager] End Pan
{"cancelled": true}
```

---

### Test 9: Reset View — Double-Click

**Steps:**
1. Zoom in and pan around
2. Double-click anywhere in data grid

**Expected Behavior:**
- Viewport resets to full range
- `vis_x/y = full_x/y`
- Facet viewport resets to `(0, 0)`
- Scroll offsets reset to `(0, 0)`

**Visual Check:**
- All data visible
- Axes show full range
- Chrome rebuilds

**Console Check:**
```
[InteractionManager] Start Reset in data at (X, Y)
```

---

### Test 10: Escape to Cancel

**Steps:**
1. Start dragging (Pan handler active)
2. Press Escape key before releasing mouse

**Expected Behavior:**
- Interaction cancelled
- Viewport restored to pre-drag state (TODO: requires undo stack — may not work yet)

**Console Check:**
```
[InteractionManager] Cancel Pan
```

**Known Issue:**
If undo stack not implemented, viewport won't restore. This is acceptable for now — just verify no crash.

---

### Test 11: Keyboard Modifier Detection

**Verify browser doesn't interfere with Shift+Wheel.**

**Steps:**
1. Shift + scroll wheel

**Expected Behavior:**
- Zoom happens (NOT horizontal scroll)
- Browser's default Shift+Wheel behavior overridden

**Failure Indicator:**
- Page scrolls horizontally instead of zooming
- Event not prevented (missing `e.preventDefault()`)

---

### Test 12: Error Propagation (No Fallbacks)

**Verify errors fail visibly.**

**Steps:**
1. Manually corrupt layout params (edit ggrs_service_v3.dart temporarily):
   ```dart
   'cell_width': -10,  // Invalid
   ```
2. Try to render

**Expected Behavior:**
- Render stops
- Error visible in console: `"error": "Cell dimensions must be positive"`
- NO default fallback, NO silent recovery

**Console Check:**
```
[GgrsV3] Error: initLayout failed: Cell dimensions must be positive
```

**Failure Indicator:**
- Plot renders anyway (fallback logic present)
- Error swallowed

---

### Test 13: Generation Counter (Stale Render Cancellation)

**Steps:**
1. Drop Y factor
2. Immediately drop different Y factor (before first render completes)

**Expected Behavior:**
- First render cancelled (generation mismatch)
- Second render completes
- No data points from first render

**Console Check:**
```
[GgrsV3] Render cancelled (stale generation)
```

---

### Test 14: Layout State JSON Roundtrip

**Verify LayoutState serialization is lossless.**

**Steps:**
1. Render plot
2. Open DevTools console
3. Call manually:
   ```javascript
   const state1 = renderer.getLayoutState();
   const parsed = JSON.parse(state1);
   console.log(parsed);
   ```

**Expected Output:**
All fields present, correct types:
```json
{
  "canvas_width": 800,
  "canvas_height": 600,
  "full_x_min": 0.0,
  "full_x_max": 10.0,
  "vis_x_min": 0.0,
  "vis_x_max": 10.0,
  "data_x_min": 1.0,
  "data_x_max": 9.0,
  "grid_origin_x": 80.0,
  "cell_width": 600.0,
  ...
}
```

**Failure Indicators:**
- Missing fields
- NaN or Infinity values
- Type mismatches (string instead of number)

---

## Known Issues / Acceptable Gaps

Since we're skipping Phase 3 (Render Orchestration), the following are expected:

1. **No concurrent rendering** — chrome and data render sequentially (blocking)
2. **No progressive data streaming UI** — data loads in chunks but no per-chunk feedback
3. **No undo stack** — Escape during pan won't restore view (PanHandler TODO)
4. **No text layers** — tick labels, axis labels may not render (depending on whether we're using v2 chrome for now)
5. **Chrome rebuild performance** — may rebuild entire chrome on every zoom tick (no debouncing in v3 yet)

These are NOT bugs — they're deferred to Phase 3.

---

## Success Criteria

V3 is ready to proceed to Phase 3 if:

✅ All 12 test cases pass (except Test 10 undo, which is TODO)
✅ No console errors during normal usage
✅ Zoom anchors at correct edges (X left, Y top)
✅ Multi-facet zoom changes cell size
✅ Zone-aware zoom works (left strip → Y only, etc.)
✅ Pan clamped to full range
✅ Reset view works
✅ Errors propagate visibly (no silent fallbacks)
✅ Layout state JSON roundtrip is lossless

---

## Glaring Issues to Watch For

🚨 **Critical (stop and fix):**
- WASM exports missing or return undefined
- GPU uniform buffer not written (canvas stays black)
- Zone detection always returns "outside"
- Zoom anchor drifts (pixel gap not constant)
- Pan not clamped (can pan beyond full range)
- Errors swallowed with defaults

⚠️ **Important (note for later):**
- Chrome rebuild on every zoom tick (performance hit)
- No text rendering (may need v2 fallback temporarily)
- Wheel event not prevented (page scrolls instead of zooming)

ℹ️ **Acceptable for now:**
- Sequential rendering (blocking)
- No undo stack
- No render progress feedback

---

## Rollback Plan

If critical issues arise:

1. **Revert to v2** (immediate):
   ```dart
   // In service_locator.dart
   const bool _useV3 = false;  // Switch back to v2
   ```

2. **Restore v3 from .bak** (if v3 files get corrupted):
   ```bash
   cp apps/step_viewer/web/ggrs/bootstrap_v3.js.bak apps/step_viewer/web/ggrs/bootstrap_v3.js
   cp apps/step_viewer/web/ggrs/ggrs_gpu_v3.js.bak apps/step_viewer/web/ggrs/ggrs_gpu_v3.js
   # etc.
   ```

3. **Git clean slate**:
   ```bash
   git status  # Check what's been modified
   git checkout -- <file>  # Restore specific files
   ```

---

## Next Steps After Testing

Once testing is complete and no glaring issues found:

**Phase 3: Render Orchestration** (Week 2, Days 3-5 + Week 3, Days 1-2)
- RenderLayer interface
- Layer implementations (ViewStateLayer, ChromeLayer, DataLayer)
- RenderCoordinator pull-based queue
- Independent layer rendering

**Phase 4: Testing & Validation** (Week 3, Days 3-5)
- Unit tests (Rust layout/interaction)
- Integration tests (browser)
- Manual end-to-end testing

**Phase 5: Documentation & Cleanup** (Week 3, Day 5)
- Update architecture docs
- Remove deprecated code
- Memory.md update

---

## Contact / Issues

If you encounter issues not covered in this guide, check:
- `_local/wrong-premises-log.md` — common mistakes
- `.claude/rules/01-no-fallbacks.md` — error handling philosophy
- `docs/zoom-architecture.md` — detailed zoom math

Add findings to `_local/v3-testing-notes.md` (create if needed).
