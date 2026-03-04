# V3 Debug Logbook

## 2026-03-02

### Reading error.png
Looking at actual error to understand what's failing before making any changes.
**Observation**: Orchestrator shows "Loading Project Navigator" stuck, center says "No open editors", red error banner at top. Webapps not initializing.

### Reading V2 working code
Reading `/home/thiago/workspaces/tercen/main/sci/sci_web_component2/web/_assets/ggrs/bootstrap.js` to understand working architecture.
**V2 is MUCH simpler**: WASM init → createRenderer → renderPlot(data, w, h) → returns base64 PNG → draw to canvas. No layers, no coordinator, no GPU.

### Comparing working V2 (this project) to broken V3
Reading `ggrs_service_v2.dart` and `ggrs_interop_v2.dart` to understand data flow.
**V2 interop**: Uses `web.window.callMethod('ggrsV2EnsureGpu', ...)` - functions exported directly on window.
**V3 interop**: Uses `globalContext['ggrsV3']` as module - expects `window.ggrsV3.ensureWasmInitialized()` etc. Checking if bootstrap_v3 exports this.
**bootstrap_v3.js**: Line 377 exports `window.ggrsV3 = ggrsV3` ✓ Now checking if index.html loads bootstrap_v3.js.
**index.html**: Loads bootstrap.js, bootstrap_v2.js, and bootstrap_v3.js ✓ All present.

### Reading V3 service code
Checking what ggrs_service_v3.dart does vs V2.
**V3 flow**: CubeQuery → initPlotStream(metadata) → ensureGpu(creates coordinator) → updateCoordinatorContext(triggers render) → waitForRenderComplete.

### WAIT - Error is orchestrator issue
Error.png shows "Loading Project Navigator" stuck. This is orchestrator iframe loading, not step_viewer rendering. Checking orchestrator HTML/JS.

### Checking webapp_provider
Reading how orchestrator handles app-ready messages.
**webapp_provider.dart**: Line 97-103 handles 'app-ready' - sets instance.isReady = true, calls splashProvider.markReady(). This should hide the loading spinner.
**Flow**: Webapp sends request-context → orchestrator sends init-context → webapp sends app-ready → orchestrator marks ready.


### Checking project_nav message flow
**project_nav/main.dart**: Line 55 sends 'request-context', line 42 sends 'app-ready' after init, line 45 sends 'app-error' if fails.
Checking MessageHelper.dart for package:web compatibility.


**MessageHelper.dart**: Uses package:web correctly - addEventListener with web.Event → cast to MessageEvent → JSON.stringify(data) → parse.
postMessage: uses window.parent.postMessage(message.jsify(), '*'.toJS).

### Re-checking MessageRouter (orchestrator)
Earlier fixed dartify() issue. Re-checking the current state.


**MessageRouter fix review**: Lines 72-76 use dartify() → check is! Map → Map.from(). Different from project_nav which uses JSON.stringify → json.decode.
Potential issue: dartData might not be Map<String, dynamic>. Checking MessageEnvelope.fromJson to see if it handles this.


**FOUND THE BUG!**
MessageEnvelope.fromJson expects Map<String, dynamic> for nested maps (line 61, 64).
But dartify() might return plain Map with non-String keys → cast exception!
project_nav uses JSON.stringify → json.decode for safe conversion. MessageRouter should do the same.

### Fixing MessageRouter._handleMessage
Changing from dartify() to JSON.stringify → json.decode pattern like project_nav.


**Fix applied**: MessageRouter._handleMessage now uses JSON.stringify → json.decode instead of dartify().
This ensures nested maps are properly typed as Map<String, dynamic>.


Added missing import dart:js_interop_unsafe for callMethod support.

### Now checking V3 architecture issues
Orchestrator fix done. Now reviewing V3 rendering flow vs working V2.


## V2 vs V3 Architecture Comparison

### V2 Architecture (WORKING)
**Files**: ggrs_service_v2.dart, ggrs_interop_v2.dart, bootstrap_v2.js, ggrs_gpu_v2.js
**Flow**:
1. CubeQuery (Dart/Tercen SDK)
2. initPlotStream → metadata (WASM HTTP)
3. computeSkeleton → skeleton layout (WASM)
4. getStaticChrome + getViewportChrome → split chrome (WASM)
5. ensureGpu → create WebGPU context + 3-layer DOM (JS)
6. initView → create ViewState in WASM, return snapshot (WASM)
7. mergeAndSetChrome → send chrome to GPU layers (JS)
8. streamAllDataPacked → loop loadDataChunk in JS, send to GPU (WASM → JS)
9. attachInteraction → interaction manager for zoom/pan (JS)

**Key points**:
- Direct WASM calls from Dart via window.ggrsV2*() functions
- Simple JS functions, no coordinator, no layers abstraction
- Chrome split into static (panel/strip backgrounds) + viewport (grid/axes/ticks)
- Data streaming managed by ggrsV2StreamAllDataPacked with packed buffers
- Interaction handled by InteractionManager separately

### V3 Architecture (BROKEN)
**Files**: ggrs_service_v3.dart, ggrs_interop_v3.dart, bootstrap_v3.js, ggrs_gpu_v3.js, render_coordinator.js
**Flow**:
1. CubeQuery (Dart/Tercen SDK)
2. initPlotStream → metadata (WASM HTTP)
3. ensureGpu → create RenderCoordinator + layers + InteractionManager (JS)
4. updateCoordinatorContext → pass metadata, trigger coordinator (JS)
5. Coordinator renders layers in order:
   a. LayoutLayer → getStreamLayout (WASM)
   b. ViewStateLayer → initView (WASM)
   c. ChromeLayers (6 categories) → computeSkeleton + getViewChrome (WASM)
   d. DataLayer → loadDataChunk loop (WASM)
6. waitForRenderComplete → Dart waits for coordinator to finish (JS → Dart Promise)

**Key points**:
- Indirect WASM calls through Coordinator layer abstraction
- RenderCoordinator manages layer dependencies, invalidation, progress events
- Chrome split into 6 named layers (panel_backgrounds, strip_backgrounds, grid_lines, axis_lines, tick_marks, panel_borders)
- Data streaming managed by DataLayer inside coordinator
- Interaction handled by InteractionManager with coordinator reference for invalidation


### Logs show rendering SUCCESS but no visible plot
- GPU: ✓ Canvas 1860x1073, WebGPU context
- Chrome: ✓ panel_backgrounds(1), grid_lines(19), tick_marks(10)
- Data: ✓ 475,688 points loaded + drawn
- Render: ✓ Complete in 2939ms

**But invisible!** Checking canvas CSS/positioning/colors...


### Created test_v3_render.html
Self-validating test with synthetic data - tests WASM init, GPU, canvas visibility, manual chrome/data rendering.
Run: `cd apps/step_viewer && python3 -m http.server 8001` → open http://localhost:8001/test_v3_render.html

### Checking canvas positioning issue
Canvas lacks absolute positioning - interaction div might be covering it.


**FIX: Canvas positioning**
- Added position: absolute, top: 0, left: 0
- Added z-index: 1 (below interaction div z-index: 10)
- This ensures canvas is properly positioned and visible

Copied fix to orchestrator/web/step_viewer/ggrs/bootstrap_v3.js


### Created TEST_PLAN.md
Comprehensive test plan with 8 test suites:
- Test 1 (✓ created): Basic rendering with synthetic data
- Tests 2-5: Coordinator, colors, interactions, streaming
- Tests 6-8: Integration + performance + regression


### Fixed test_v3_render.html import issue
Changed from ES6 import to script tag loading + window.ggrsV3 access.
bootstrap_v3.js exports to window, not as ES6 module.


### Created test_simple.html
Minimal test with better error logging to diagnose module loading issues.
Path: apps/step_viewer/web/test_simple.html


### Added pixel check to test
Test 11 samples canvas pixel to verify if WebGPU actually rendered or if canvas is blank white.
If all white → WebGPU render pipeline not executing properly.


### Created test_debug.html
Minimal WebGPU test - just clears canvas to blue.
If canvas stays red (background color) → WebGPU not working at all.
If canvas turns blue → WebGPU works, issue is in GgrsGpuV3 render pipeline.


### ERROR FOUND: Render executes but canvas blank
Browser console shows [GgrsGpuV3] render logs → _render() is being called.
But canvas is blank white → WebGPU not drawing to canvas.
Issue: Context configuration or shader problem.


### ROOT CAUSE FOUND: Uniform buffer not initialized
`syncLayoutState()` never called → `canvas_size` in uniform buffer = (0, 0)
→ Shader NDC conversion: `pos.x / 0` = NaN → nothing renders!

FIX: Call `gpu.syncLayoutState()` before rendering chrome/points.


### Changed test colors to be OBVIOUS
Red background, green grid lines (5px wide), blue points.
If still blank → rendering completely broken, not just color issue.


### CRITICAL BUG FIXED: Reserved keyword 'layout' in shader
WGSL error: 'layout' is reserved keyword → shader compilation fails → invalid pipeline → no rendering!
FIX: Renamed uniform var from `layout` to `u_layout` in both RECT_SHADER_V3 and POINT_SHADER_V3.
Applied to both step_viewer and orchestrator copies.


### Fixed coordinate system mismatch
Points were in pixel coords (0-800) but point shader expects data-space (0-100).
Changed test to generate points in 0-100 range matching layoutState x_range/y_range.


### Created test_streaming.html and test_interaction.html
Self-contained tests for streaming and interaction subsystems.
test_streaming.html: Tests 1K, 50K, 500K point datasets with progress bar, simulates network delay, tests cancellation.
test_interaction.html: Tests scroll, pan, zoom with event logging, zone detection.


### Verified all critical fixes applied to both copies
Checked apps/step_viewer and apps/orchestrator copies of ggrs_gpu_v3.js and bootstrap_v3.js.
All fixes present: u_layout (not layout), stepMode: 'instance' in both pipelines, canvas positioning with z-index.


### Created test_coordinator.html and test_chrome.html
Completed the self-validating test suite. test_coordinator.html tests layer dependencies, invalidation, generation counter, error handling. test_chrome.html tests color parsing (hex, rgb, rgba), invalid color detection, chrome category structure. All 5 tests now complete (render, streaming, interaction, coordinator, chrome).


### Created V3_TEST_SUITE_COMPLETE.md
Comprehensive summary of all tests, bugs fixed, expected results, and verification checklist. Documents 4 critical bugs fixed (WGSL keyword, stepMode, canvas positioning, MessageRouter), all applied to both step_viewer and orchestrator copies. Test suite ready for user verification.


### Fixed coordinate system in test files
User reported strange plot placement (points clustered in upper-left). Issue: hardcoded cell_width/cell_height (800x600) didn't match actual canvas CSS dimensions. Fixed all 3 tests (render, streaming, interaction) to read canvas.clientWidth/clientHeight and use actual dimensions for layoutState. Points should now distribute across full canvas.


### Added safety checks to test files
Added null checks for canvas element and fallback dimensions (|| 800, || 600) in case clientWidth/clientHeight are 0. Added console logging to help debug dimension issues. User reported error in test_streaming.html specifically.


### Fixed CSS selector mismatch in test files
User reported canvas overlaying entire page, couldn't click buttons. CSS used `#container` but HTML had `id="test-container"`. Without `position: relative` on container, canvas with `position: absolute` positioned relative to viewport instead of container. Fixed in test_streaming.html and test_interaction.html - changed CSS selector to `#test-container`.


### Changed test_streaming.html to use diagonal pattern
User requested structured data pattern to make progressive rendering visible. Changed from random scatter to diagonal line (10,10)→(90,90) with ±5 noise. Now you can see the line being drawn chunk by chunk as data streams.


### Enhanced MockStreamingRenderer with full production pipeline
User requested realistic simulation of all prod steps except Tercen querying. MockStreamingRenderer now simulates: (1) Quantized int16 data generation (Tercen table format), (2) HTTP fetch delay (15-25ms), (3) TSON parsing (3-5ms), (4) Dequantization (int16→float using min/max), (5) Pixel mapping timing, (6) Grid culling (visibility check). Logs timing breakdown per chunk like real WASM. More realistic performance testing.


### Added 10×10 facet grid with 3×3 viewport and scrolling
User requested facets to test scrolling. test_streaming.html now has 10 cols × 10 rows (100 facets total), showing 3×3 viewport at 250×250px per cell with 10px spacing. Points distributed across facets (ci, ri). GPU shader culls points outside viewport automatically. Added scroll controls (←→↑↓ buttons) to change viewport_col_start/viewport_row_start. Chrome renders 3×3 grid structure. Tests viewport scrolling and facet culling.


### Implemented fractional viewport zoom (unified architecture)
User proposed brilliant insight: unify zoom and viewport control using fractional visible extent. Changed from separate zoom state (cell dimensions) to single concept: n_visible_cols/rows as floats. Zoom IN = show less (e.g., 2.1 facets) → cells bigger. Zoom OUT = show more (e.g., 4.5 facets) → cells smaller. Cell dimensions DERIVED from fractional extent: cell_width = (canvas_width - spacing) / n_visible_cols. Changed shader uniforms from u32 to f32 for n_visible_cols/rows and viewport_col/row_start. Updated shader culling to use float comparisons. Zoom keeps top-left stable (viewport_start constant), grows right/down. No max bounds, min bound > 0. Pan uses fractional increments (0.5). Applied to both step_viewer and orchestrator copies.


### Fixed syntax error in test_streaming.html
Extra closing brace on line 325 caused SyntaxError. Removed orphaned brace.


### Added facet labels and smooth animation to test_streaming.html
User reported facets not moving (only data). Added green facet labels showing (col,row) indices for each visible cell. Labels positioned absolute, update when viewport changes. Now clear which facets are visible. Implemented smooth animation (200ms ease-out cubic) for zoom and pan operations using requestAnimationFrame. Interpolates viewport_col/row and visible_cols/rows over time. Chrome rebuilds during zoom animation, labels update during pan. Makes viewport changes feel natural.


### Implemented proper layer z-ordering system
User corrected: no hardcoded z-index, layout module must control z-ordering. Implemented semantic layer system with LAYER_Z_INDEX constants (CANVAS=1, TEXT=3, INTERACTION=10). Created text layer div with z-index assigned by layout system. Labels render into text layer, not directly to container. Tests architecture where layers have semantic meaning and z-order is centrally managed. No z-index in CSS, all controlled by layout module.


### Fixed fractional viewport misalignment (layout module architecture)
User observed data crossing between facets after fractional scroll (viewport at [0.5, 0.0]). Root cause: chrome rendering used visual indices [0,1,2] while data used `pc = facet_index - viewport_start`. Different formulas → misalignment. User clarified architectural principle: **ALL rendering (chrome, labels, data) must go through layout module using SAME position formula**. Fixed by computing chrome and label positions using identical formula to shader: `pc = facetCol - viewportCol`, then `x = pc * (cellWidth + spacing)`. Now chrome grid boundaries, facet labels, and data points all move together as unified system. Layout module determines visible facets (floor/ceil viewport range), computes position for each, all rendering uses same output → perfect alignment.


### Fixed scroll not moving backgrounds (layout module recomputation)
User observed zoom was adjusting plot backgrounds but scroll was not. Root cause: pan/scroll button handlers passed `needsChromeRebuild=false`, so chrome wasn't rebuilt during scroll. Only labels updated. User clarified: **both zoom AND scroll change viewport parameters → layout module must recompute chrome positions for both**. Zoom changes cell dimensions (visibleCols/Rows), scroll changes viewport offset (viewportCol/Row) → both change where facets are positioned → both need chrome rebuild. Fixed all scroll button handlers to pass `needsChromeRebuild=true`. Now backgrounds, grid lines, labels, and data all move together for both zoom and scroll operations.


### Implemented viewport buffering for data fetching
User clarified data fetching strategy: (1) **Render partial cells** - if viewport starts at 1.5, fetch from floor(1.5)=1 and render partial facet. (2) **Fetch buffer zone** - fetch 2-3 extra cells beyond visible viewport in each direction for performance (pre-load data for smooth scrolling). Implemented in MockStreamingRenderer: calculates visible range from viewport (floor to ceil), expands by FETCH_BUFFER_CELLS=2 in each direction (clamped to grid bounds), generates data only for facets in expanded range. Chrome/labels render visible range only, GPU shader culls points outside visible viewport automatically. Example: viewport [1.5, 4.5] → visible [1,5] → fetch [max(0,1-2), min(10,5+2)] = [0,7]. When user scrolls 1-2 cells, data already loaded.


### Implemented viewport culling for chrome rendering
User observed facet 0 missing when viewport at [0.5, 0.0] (marked with blue rectangles in screenshot). Facet 0 at pc=-0.5 positioned at x=-131.5px (negative coords). User clarified: **negative positions should be streamed and rendered WITHIN viewport confines (viewport culling)**. Root cause: chrome rendering sent rects at negative x to GPU, GPU clipped entire rect instead of showing visible portion. Fixed: added viewport culling to chrome rendering - clips rects to canvas bounds [0, 0, width, height] before sending to GPU. Facet 0 at x=-131.5, width=253 → clipped to x=0, width=121.5 (visible right half only). Also clips borders to match clipped dimensions. Labels clamped to canvas bounds (x<0 → x=5). Now partially visible facets at viewport edges render correctly within viewport confines.


### Fixed data points not rendering in partially visible facets (pixel-level culling)
User could see facet labels (chrome culling working) but not data points in partially visible facet 0. Root cause: GPU shader used **facet-level culling** (`if pc < 0.0 → cull all points`), so all points in facet 0 were culled even though facet was partially visible. User expected: "I should see the upper half of the diagonal data points" in visible portion. Fixed: changed shader from facet-level to **pixel-level culling**. Shader now: (1) computes pixel position `px, py` for each point, (2) culls if `px < 0 || px > canvas_width || py < 0 || py > canvas_height`. Points in facet 0 at x ∈ [0, 131.5] now render (visible portion), points at x < 0 culled (off-screen). Matches chrome culling behavior - both use pixel-level viewport bounds. Applied to both step_viewer and orchestrator copies.


### Implemented incremental/progressive data loading (viewport-aware fetching)
User observed data missing when scrolling beyond initial fetch range (viewport [3.5, 0.0], facets 5-6 had no data). Asked how production handles this. User clarified: **production is wrong - should fetch only visible + buffer, not all facets**. For large grids (100×100), loading all 10K facets would waste memory and slow initial load. Implemented **Option 2: incremental loading**. Architecture: (1) Track loaded regions (`loadedColRange`, `loadedRowRange`), (2) On viewport change, `checkAndLoadMore()` checks distance to edge, (3) When within `LOAD_THRESHOLD=1.5` cells of boundary, trigger `loadIncrementalData()` for next `LOAD_BATCH_SIZE=2` cells, (4) Append new points to `allLoadedPoints`, update GPU with full dataset, (5) Expand loaded range. Called after animation completes. Example: show 3×3, initial load 5×5. Scroll to 0.5 → seeing up to 3.5, distance to edge (5) = 1.5 → triggers load [5,7]. By time user reaches 4, data ready. Clear button resets ranges. This is correct architecture for production.

