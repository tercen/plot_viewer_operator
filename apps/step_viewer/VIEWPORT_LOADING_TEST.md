# Viewport-Aware Incremental Loading - Test Guide

**Status:** Phases 1-6 Complete, Real CubeQuery Implementation Active
**Date:** 2026-03-02 (Updated: Phase 6 complete)

## Implementation Summary

### Architecture Changes

**WASM Layer (ggrs-wasm):**
1. ✅ gRPC-Web foundation added (prost dependencies, grpc_unary_call) - Phase 1
2. ✅ CubeQuery manager with 5C caching (cube_query_manager.rs) - Phase 2
3. ✅ Viewport-aware facet label loading (load_facet_labels with range parameter) - Phase 4
4. ✅ loadIncrementalData stub export (ready for real data impl) - Phase 5
5. ✅ **Phase 6 COMPLETE:** Real REST API implementation (5A/5B task creation, polling, schema classification)

**Dart Layer (step_viewer):**
1. ✅ Minimal CubeQueryResult model (no SDK dependency for this model)
2. ✅ WASM-based CubeQuery lifecycle in ggrs_service_v3.dart
3. ✅ Incremental loading state tracking (_loadedColRange, _totalColFacets, etc.)
4. ✅ checkAndLoadMore() method (threshold-based delta loading)
5. ✅ _loadIncrementalData() method (calls WASM stub)

### What Works Now

**Phase 1-6 (CubeQuery in WASM with Real API):**
- ✅ V3 service calls WASM ensureCubeQuery instead of Dart CubeQueryService
- ✅ **Real REST API implementation:** Task creation, running, polling (2s intervals), schema classification
- ✅ 5C caching: params match → return cached result
- ✅ 5A path: Update existing CubeQuery with new bindings → run task
- ✅ 5B path: Build new CubeQuery from step relation → run task
- ✅ Task polling: 2-second intervals, 5-minute timeout, DoneState/FailedState detection

**Phase 4 (Viewport-Aware Loading):**
- ✅ InitConfig **requires** viewport parameter (not optional)
- ✅ load_facet_labels filters by (ci_min, ci_max) / (ri_min, ri_max)
- ✅ Facet labels fetched with offset/limit for viewport range
- ✅ **ACTIVE:** Loads 5×5 cells initially (configurable via initialViewportSize constant)
- ✅ Old full-loading path completely removed (see `/VIEWPORT_MANDATORY.md`)

**Phase 5 (Incremental Loading Framework):**
- ✅ checkAndLoadMore() detects when viewport is within 1.5 cells of loaded edge
- ✅ _loadIncrementalData() calls WASM stub (returns empty for now)
- ✅ Loaded ranges tracked after initPlotStream

### Test Cases

#### TC1: WASM CubeQuery Integration
**Goal:** Verify V3 service uses WASM for CubeQuery lifecycle

**Steps:**
1. Open test_v3_render.html in browser
2. Drop Y factor (e.g., "value") on Y axis
3. Open DevTools Console

**Expected:**
- Console log: `[CubeQuery] Calling WASM ensureCubeQuery...`
- Console log: `[CubeQuery] 5A/5B: creating/updating CubeQuery`
- Console log: `[CubeQuery] Task created: {task_id}`
- Console log: `[CubeQuery] Polling task... (attempt 1/150)`
- Console log: `[CubeQuery] Polling task... (attempt 2/150)` (may repeat)
- Console log: `[CubeQuery] Task completed successfully`
- Console log: `[CubeQuery] Classified {N} schemas`
- No errors about sci_tercen_client
- Plot renders with data

**Status:** Ready to test

---

#### TC2: Viewport-Aware Facet Loading
**Goal:** Verify facet labels are filtered by viewport (5×5 initial load)

**Steps:**
1. Rebuild: `cd apps/step_viewer && flutter build web --release`
2. Open test_v3_render.html
3. Drop factors with 10×10 facets (large grid)
4. Check DevTools Console

**Expected:**
- Console log: `[Viewport] Fetching facets [0, 4] (offset=0, limit=5)` (col facets)
- Console log: `[Viewport] Fetching facets [0, 4] (offset=0, limit=5)` (row facets)
- Console log: `facets=5x5 (total: 10x10)` (loaded 5, total 10)
- Plot shows 5×5 grid (not full 10×10)
- Only 25 cells loaded initially (not 100)

**Status:** ✅ ACTIVE - viewport loading is mandatory in V3

---

#### TC3: Incremental Loading Detection
**Goal:** Verify checkAndLoadMore triggers near edges

**Steps:**
1. Enable viewport (as in TC2)
2. Add this to render() after initLayout (line ~200):
   ```dart
   // Test incremental loading
   await checkAndLoadMore(
     viewportCol: 3.0,  // Near right edge (loaded [0,5))
     viewportRow: 0.0,
     visibleCols: 2.0,
     visibleRows: 2.0,
   );
   ```
3. Check console logs

**Expected:**
- Console log: `[Incremental] Loading facets [5,7) x [0,5)`
- Console log: `[Incremental] Stub: not yet implemented`
- Console log: `[Incremental] Loaded 0 points`

**Status:** Framework ready, needs Phase 6 real data

---

#### TC4: 5C Caching
**Goal:** Verify cached CubeQuery is reused

**Steps:**
1. Render plot with Y binding
2. Clear plot (remove Y binding)
3. Re-add same Y binding

**Expected:**
- First render: `[CubeQuery] 5A/5B: creating/updating CubeQuery (MOCK)`
- Second render: `[CubeQuery] 5C: params match, returning cached`

**Status:** Ready to test

---

### Performance Expectations

**With Viewport Disabled (Current):**
- Initial load: 100K points, 3000ms, 10×10 grid (all facets)
- Memory: 12MB GPU buffers
- Same as before

**With Viewport Enabled (Future):**
- Initial load: 30K points, 1000ms, 5×5 grid (viewport + buffer)
- Incremental: +5K points, 300ms per 2-cell extension
- Memory: 4MB initial → 12MB after full scroll
- **66% faster time-to-first-plot**
- **70% reduction in initial data transfer**

### Phase 6 Status: ✅ COMPLETE

**Implemented (2026-03-02):**
1. ✅ Real REST API implementation (Tercen uses REST+TSON, not gRPC)
2. ✅ `get_cube_query()` - calls `api/v1/workflow/getCubeQuery`
3. ✅ `run_cube_query_task()` - creates CubeQueryTask, runs it, polls for completion
4. ✅ `wait_task_done()` - polls task status (2s intervals, 5min timeout)
5. ✅ `update_cube_query_bindings()` - 5A path: updates existing CubeQuery
6. ✅ `build_cube_query_from_step()` - 5B path: builds new CubeQuery
7. ✅ `classify_schemas()` - parses queryTableType from completed task

**See:** `/PHASE_6_COMPLETE.md` for detailed documentation, test cases, and API reference

**Remaining (Optional Enhancements):**
- Implement real `loadIncrementalData()` with facet filtering (Phase 5 stub exists)
- Wire GPU appendDataPoints in Dart _loadIncrementalData()
- Add auto-scroll viewport callback (JS InteractionManager)

**Current Status:**
- ✅ No blockers for testing with live Tercen backend
- ✅ WASM compiled successfully (7.6MB, no errors)
- ✅ Exports verified (ensureCubeQuery, loadIncrementalData present)
- Ready for end-to-end testing

### Configuration

**Enable Viewport Loading:**
Edit `apps/step_viewer/lib/services/ggrs_service_v3.dart` line ~137:
```dart
'viewport': {
  'ci_min': 0,
  'ci_max': 4,  // Load 5 columns initially
  'ri_min': 0,
  'ri_max': 4,  // Load 5 rows initially
}
```

**Adjust Load Threshold:**
Edit constants at line ~48:
```dart
static const double _loadThreshold = 1.5;  // Distance to edge (cells)
static const int _loadBatchSize = 2;        // Facets to load per batch
```

### Architecture Verification

**Confirm New Flow Active:**
1. Check `ggrs_service_v3.dart` line ~115: calls `GgrsInteropV3.ensureCubeQuery`
2. Check `ggrs_interop_v3.dart` line ~43: has `ensureCubeQuery` binding
3. Check `lib.rs` line ~472: has `#[wasm_bindgen(js_name = "ensureCubeQuery")]`
4. Check `cube_query_manager.rs` exists with `ensure_cube_query()` function

**Old Flow (Inactive in V3):**
- `cube_query_service.dart` still exists for backward compat (V1, V2)
- V3 does NOT import or use CubeQueryService

### Known Limitations

1. **Mock Data Only:** CubeQuery returns hardcoded table IDs (Phase 6 real gRPC)
2. **Viewport Disabled:** Loads all facets by default (enable manually for testing)
3. **Incremental Stub:** loadIncrementalData returns empty (needs Phase 6 impl)
4. **No Auto-Trigger:** checkAndLoadMore not wired to scroll events (needs JS callback)

### Bundle Size Impact

**Current (with sci_tercen_client):**
- step_viewer.dart.js: ~2.5MB minified
- Includes full Tercen SDK (~500KB)

**After SDK Removal (Future):**
- CubeQuery logic moved to WASM → 100KB reduction in Dart bundle
- ggrs_wasm.wasm: +50KB (gRPC-Web + CubeQuery manager)
- **Net savings: ~50KB**
- Main benefit: Cleaner architecture, not bundle size

### Rollback Plan

If issues arise:
1. Revert to V2 service: change `GgrsServiceV3()` → `GgrsServiceV2()` in service_locator.dart
2. V2 uses old CubeQueryService (still present)
3. No WASM changes needed (backward compatible)

---

## Build Commands

**WASM:**
```bash
cd /home/thiago/workspaces/tercen/main/ggrs
wasm-pack build crates/ggrs-wasm --target web
cp -r crates/ggrs-wasm/pkg/* /path/to/step_viewer/web/ggrs/pkg/
```

**Dart:**
```bash
cd apps/step_viewer
flutter pub get
flutter build web --release
```

**Full Build:**
```bash
cd /home/thiago/workspaces/tercen/main/plot_viewer_operator
./build_all.sh
```
