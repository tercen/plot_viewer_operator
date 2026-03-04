# Facet Detection Debug Logging

Debug statements added to track facet counts throughout the data flow. No behavior changes — logging only.

---

## Debug Statements Added

### 1. WASM: initPlotStream Return
**File:** `ggrs/crates/ggrs-wasm/src/lib.rs` lines 515-520

```rust
let n_col = init_result.n_col_facets.max(1);
let n_row = init_result.n_row_facets.max(1);
let is_multi_facet = n_col > 1 || n_row > 1;
web_sys::console::log_1(&format!(
    "[FACET-DEBUG] initPlotStream returning: n_col_facets={} n_row_facets={} isMultiFacet={}",
    n_col, n_row, is_multi_facet
).into());
```

**Shows:** Total facet counts discovered by WASM from the data.

---

### 2. Dart: Metadata Read
**File:** `apps/step_viewer/lib/services/ggrs_service_v2.dart` line 133

```dart
debugPrint('[FACET-DEBUG] initPlotStream metadata: nColFacets=$nColFacets, nRowFacets=$nRowFacets');
```

**Shows:** Facet counts read from WASM metadata in Dart.

---

### 3. Dart: Visible Calculation
**File:** `apps/step_viewer/lib/services/ggrs_service_v2.dart` lines 166-167

```dart
final isMultiFacet = nColFacets > 1 || nRowFacets > 1;
debugPrint('[FACET-DEBUG] Visible calculation: nVisibleCols=$nVisibleCols/$nColFacets, nVisibleRows=$nVisibleRows/$nRowFacets, isMultiFacet=$isMultiFacet');
```

**Shows:**
- Total vs visible facet counts
- Whether we're in multi-facet mode
- How many facets are hidden (if any)

---

### 4. WASM: ViewState Initialization
**File:** `ggrs/crates/ggrs-wasm/src/lib.rs` lines 1363-1368

```rust
let is_multi_facet = vs.n_visible_cols > 1 || vs.n_visible_rows > 1;
web_sys::console::log_1(&format!(
    "[FACET-DEBUG] initView: n_visible={}x{} isMultiFacet={} cell={}x{} canvas={}x{}",
    vs.n_visible_cols, vs.n_visible_rows, is_multi_facet,
    vs.cell_width, vs.cell_height, vs.canvas_width, vs.canvas_height
).into());
```

**Shows:**
- Visible facet counts stored in ViewState
- Initial cell dimensions
- Canvas size

---

### 5. WASM: Zoom Invocation
**File:** `ggrs/crates/ggrs-wasm/src/lib.rs` lines 119-123

```rust
let is_multi_facet = self.n_visible_cols > 1 || self.n_visible_rows > 1;
web_sys::console::log_1(&format!(
    "[FACET-DEBUG] zoom() called: axis={} sign={} n_visible={}x{} isMultiFacet={}",
    axis, sign, self.n_visible_cols, self.n_visible_rows, is_multi_facet
).into());
```

**Shows:**
- Every zoom invocation
- Which axis (x, y, or both)
- Zoom direction (in=1, out=-1)
- Whether we're in multi-facet mode

---

## Expected Console Output

### Single Facet (1x1)
```
[FACET-DEBUG] initPlotStream returning: n_col_facets=1 n_row_facets=1 isMultiFacet=false
[FACET-DEBUG] initPlotStream metadata: nColFacets=1, nRowFacets=1
[FACET-DEBUG] Visible calculation: nVisibleCols=1/1, nVisibleRows=1/1, isMultiFacet=false
[FACET-DEBUG] initView: n_visible=1x1 isMultiFacet=false cell=1820.0x480.0 canvas=1920.0x600.0
[FACET-DEBUG] zoom() called: axis=x sign=1 n_visible=1x1 isMultiFacet=false
[ZOOM-X] factor=1.10 | old_span=523255.7 new_span=475687.0 | ...
```

**Behavior:** Zoom changes axis range (semantic zoom).

---

### Multi-Facet (3x2)
```
[FACET-DEBUG] initPlotStream returning: n_col_facets=3 n_row_facets=2 isMultiFacet=true
[FACET-DEBUG] initPlotStream metadata: nColFacets=3, nRowFacets=2
[FACET-DEBUG] Visible calculation: nVisibleCols=3/3, nVisibleRows=2/2, isMultiFacet=true
[FACET-DEBUG] initView: n_visible=3x2 isMultiFacet=true cell=606.7x240.0 canvas=1920.0x600.0
[FACET-DEBUG] zoom() called: axis=both sign=1 n_visible=3x2 isMultiFacet=true
[ZOOM-X] factor=1.10 | old_span=... | ...
[ZOOM-Y] factor=1.10 | old_span=... | ...
```

**Current behavior:** Zoom still changes axis range.
**Future behavior:** Zoom will change cell size instead.

---

### Multi-Facet with Limited Visible (8x6 total, 3x2 visible)
```
[FACET-DEBUG] initPlotStream returning: n_col_facets=8 n_row_facets=6 isMultiFacet=true
[FACET-DEBUG] initPlotStream metadata: nColFacets=8, nRowFacets=6
[FACET-DEBUG] Visible calculation: nVisibleCols=8/8, nVisibleRows=2/6, isMultiFacet=true
                                    ^^^^ all cols shown  ^^^ only 2 of 6 rows fit
[FACET-DEBUG] initView: n_visible=8x2 isMultiFacet=true cell=240.0x240.0 canvas=1920.0x600.0
[FACET-DEBUG] zoom() called: axis=both sign=-1 n_visible=8x2 isMultiFacet=true
```

**Note:** 4 row facets are hidden (only 2 fit at 80px min height).

---

## What to Look For

### Test 1: Single Facet Data
**Expected:** All logs show `isMultiFacet=false`

### Test 2: Multi-Facet Data (e.g., 3x2 grid)
**Expected:**
- `initPlotStream` returns `n_col_facets=3 n_row_facets=2`
- `isMultiFacet=true` everywhere
- `zoom()` logs show correct `n_visible` values

### Test 3: Large Multi-Facet (e.g., 10x10 grid)
**Expected:**
- `initPlotStream` returns large counts
- `nVisibleRows` limited by screen height (e.g., 2 or 3)
- `nVisibleCols` shows all (no horizontal limit yet)
- Zoom logs confirm multi-facet mode

### Test 4: Zoom in Multi-Facet
**Expected:**
- Every zoom logs `isMultiFacet=true`
- Current behavior: `[ZOOM-X]` and `[ZOOM-Y]` logs show axis range changes
- Future behavior: Will change cell size instead

---

## Next Steps (Not Implemented Yet)

1. **Detect regime in zoom()**
   - If single-facet → zoom axis range (current behavior)
   - If multi-facet → zoom cell size (new behavior)

2. **Cell size zoom anchoring**
   - Anchor at data boundaries (same as axis zoom)
   - X: anchor at `data_x_min` (left)
   - Y: anchor at `data_y_max` (top)

3. **Dynamic visible count adjustment**
   - When cell becomes too small → show one more facet
   - When cell becomes too large → hide one facet
   - Requires chrome recomputation + data streaming

---

## Build Status

✅ WASM rebuilt with debug logging
✅ step_viewer rebuilt
✅ orchestrator rebuilt

Ready to test! Check browser console for `[FACET-DEBUG]` messages.
