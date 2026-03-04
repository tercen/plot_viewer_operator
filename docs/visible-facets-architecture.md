# Visible Facets Architecture

Complete reference for how the system determines and uses visible facet counts.

---

## Overview

The system distinguishes between:
- **Total facets** (`n_col_facets`, `n_row_facets`) — data-driven count from WASM
- **Visible facets** (`n_visible_cols`, `n_visible_rows`) — UI-constrained count, limited by screen space

**Key principle:** Visible facets are determined ONCE during initial render based on available screen space and minimum cell size. They remain constant during zoom/pan within a single render cycle.

---

## Data Flow

### 1. WASM Determines Total Facets

**Location:** `ggrs/crates/ggrs-wasm/src/lib.rs` → `initPlotStream()`

```rust
// WASM discovers facet columns during stream initialization
// Returns metadata with total facet counts
{
  "n_col_facets": 12,  // Total column facets in data
  "n_row_facets": 8    // Total row facets in data
}
```

**Source:** WASM queries the CubeQuery tables and counts distinct facet values.

---

### 2. Dart Limits Visible Facets

**Location:** `apps/step_viewer/lib/services/ggrs_service_v2.dart` lines 158-163

```dart
// Limit visible rows to what fits with reasonable cell height
final availableHeight = height - _estimatedChromeReserve;  // ~60px for axis
final maxFittingRows =
    (availableHeight / _minCellHeight).floor().clamp(1, nRowFacets);
final nVisibleRows = maxFittingRows;
final nVisibleCols = nColFacets;  // ALL column facets shown (no horizontal limit yet)
```

**Constants:**
- `_minCellHeight = 80.0` — minimum cell height in pixels
- `_estimatedChromeReserve = 60.0` — space for top margin + bottom axis

**Logic:**
- **Y (rows):** Limit to what fits vertically → `min(totalRows, floor(availableHeight / 80))`
- **X (cols):** Show ALL column facets (no horizontal limit currently)

**Example:**
```
Container height: 600px
Available for cells: 600 - 60 = 540px
Max fitting rows: floor(540 / 80) = 6 rows
Total row facets: 8

→ nVisibleRows = 6  (limited by screen)
→ nVisibleCols = 12 (all columns shown)
```

---

### 3. Dart Passes to WASM ViewState

**Location:** `apps/step_viewer/lib/services/ggrs_service_v2.dart` lines 202-218

```dart
final initViewParams = json.encode({
  // ... layout params
  'n_visible_cols': nVisibleCols,  // From step 2
  'n_visible_rows': nVisibleRows,  // From step 2
  // ...
});
final snapshot = GgrsInteropV2.initView(containerId, _renderer!, initViewParams);
```

**WASM stores in ViewState:**
```rust
struct ViewState {
    n_visible_cols: usize,  // Stored but never mutated
    n_visible_rows: usize,  // Stored but never mutated
    // ...
}
```

**Critical:** These values are **immutable** within a render cycle. Zoom/pan do NOT change visible counts.

---

### 4. WASM Uses for Viewport Filter

**Location:** `ggrs/crates/ggrs-wasm/src/lib.rs` lines 311-320

```rust
fn to_viewport_filter(&self) -> ggrs_core::ViewportFilter {
    ggrs_core::ViewportFilter {
        ci_min: 0,
        ci_max: self.n_visible_cols.saturating_sub(1),  // e.g., 0..11 for 12 cols
        ri_min: 0,
        ri_max: self.n_visible_rows.saturating_sub(1),  // e.g., 0..5 for 6 rows
        x_min: if x_zoomed { Some(self.vis_x_min) } else { None },
        y_min: if y_zoomed { Some(self.vis_y_min) } else { None },
        // ...
    }
}
```

**Used by:**
- `compute_viewport_chrome()` — generates chrome for visible facets only
- Chrome computation filters out facets outside `ci_min..ci_max` and `ri_min..ri_max`

---

### 5. JS Stores in GPU State

**Location:** `apps/step_viewer/web/ggrs/ggrs_gpu_v2.js` lines 428-429

```javascript
setViewUniforms(params) {
    this.nVisibleCols = params.nVisibleCols;
    this.nVisibleRows = params.nVisibleRows;
    // ... write to GPU uniform buffer
}
```

**GPU Uniform Buffer (offset 44, 8 bytes):**
```
Offset 44: u32 n_visible_cols
Offset 48: u32 n_visible_rows
```

---

### 6. GPU Shader Uses for Clipping

**Location:** `apps/step_viewer/web/ggrs/ggrs_gpu_v2.js` lines 89-93 (WGSL shader)

```wgsl
// Clip if outside visible panels
if (pc < 0 || pc >= i32(v.n_visible_cols) ||
    pr < 0 || pr >= i32(v.n_visible_rows)) {
    var out: VertexOutput;
    out.position = vec4f(0.0, 0.0, 0.0, 0.0);  // degenerate triangle
    return out;
}
```

**Effect:** Data points in facets outside the visible range are culled at the GPU level (not rendered).

---

## Where Visible Counts are Checked

### 1. Dart Initial Calculation

**File:** `apps/step_viewer/lib/services/ggrs_service_v2.dart`

**Lines 158-163:** Determine visible counts from screen dimensions
**Line 168:** Pass to computeSkeleton as viewport bounds (`ci_max`, `ri_max`)
**Lines 208-209:** Pass to WASM initView
**Lines 192-197:** Use for bottom overflow check (cell height adjustment)
**Lines 244-245:** Write to setPanelLayout (GPU uniforms)

---

### 2. WASM ViewState

**File:** `ggrs/crates/ggrs-wasm/src/lib.rs`

**Lines 107-108:** Stored in ViewState struct
**Lines 290-291:** Returned in snapshot JSON (`to_snapshot()`)
**Lines 313-315:** Used to build viewport filter (`to_viewport_filter()`)
**Lines 1353-1354:** Initialized from initView params

**NOT USED IN:** `zoom()` or `pan()` functions — these do NOT modify visible counts

---

### 3. JavaScript GPU State

**File:** `apps/step_viewer/web/ggrs/ggrs_gpu_v2.js`

**Lines 245-246:** Initial defaults (1x1)
**Lines 428-429:** Stored from setViewUniforms
**Lines 446-447:** Written to GPU uniform buffer (offset 44)
**Lines 489-493:** Updated via setVisibleCounts (8 bytes at offset 44)

---

### 4. JavaScript Interaction Handlers

**File:** `apps/step_viewer/web/ggrs/bootstrap_v2.js`

**Line 508:** Applied from WASM snapshot during interaction
**Line 801:** Applied from WASM snapshot during programmatic zoom

**Pattern:** Always read from WASM snapshot, never computed in JS.

---

### 5. GPU Vertex Shader

**File:** `apps/step_viewer/web/ggrs/ggrs_gpu_v2.js` (WGSL inline)

**Lines 62-63:** Uniform struct definition
**Line 91:** Clip test for data points outside visible range

---

## Multi-Facet Zoom Behavior

### Current Implementation (Single-Facet Zoom)

**Zoom affects:**
- ✅ Cell size (`cell_width`, `cell_height`) — changes via GPU uniform write
- ✅ Axis ranges (`vis_x_min`, `vis_x_max`, `vis_y_min`, `vis_y_max`)
- ❌ Visible counts (`n_visible_cols`, `n_visible_rows`) — **CONSTANT**

**Result:** Cells grow/shrink in place. Number of visible facets stays fixed.

### Proposed Multi-Facet Zoom

**Would require:**

1. **Dynamic visible count updates**
   ```rust
   // In zoom() function:
   if zoom_out && cell_width_after_zoom < threshold {
       self.n_visible_cols += 1;  // Show one more column
   }
   if zoom_in && cell_width_after_zoom > max_size {
       self.n_visible_cols = max(1, self.n_visible_cols - 1);  // Hide one column
   }
   ```

2. **Chrome recomputation**
   - New visible count → new viewport filter → new chrome
   - Strip labels for newly visible facets
   - Axis ticks for newly visible facets

3. **GPU uniform update**
   ```javascript
   gpu.setVisibleCounts(snapshot.n_visible_cols, snapshot.n_visible_rows);
   ```

4. **Data re-projection**
   - Points in newly visible facets must be rendered
   - Points in newly hidden facets must be culled

### Design Questions

**Q1:** Should zoom change visible facet count at all?
- **Option A:** NO — keep current behavior (cell size changes, facet count fixed)
- **Option B:** YES — add/remove visible facets based on cell size thresholds

**Q2:** If YES, what triggers facet count change?
- **Threshold-based:** `cellWidth < minCellWidth` → add column
- **Step-based:** Every N zoom steps → add/remove one facet
- **Continuous:** Recompute `floor(availableWidth / cellWidth)` on every zoom

**Q3:** How to handle axis zoom vs facet zoom?
- **Current (single-facet):** Shift+wheel zooms axis range (semantic zoom)
- **Multi-facet:** Should axis zoom AND facet count change together? Separate controls?

---

## Summary Table

| Component | Check Location | Purpose |
|-----------|---------------|---------|
| **Dart** | `ggrs_service_v2.dart:158-163` | Calculate initial visible counts from screen size |
| **Dart** | `ggrs_service_v2.dart:168` | Pass to WASM skeleton as viewport bounds |
| **Dart** | `ggrs_service_v2.dart:208-209` | Initialize WASM ViewState |
| **Dart** | `ggrs_service_v2.dart:192-197` | Adjust cell height for bottom overflow |
| **Dart** | `ggrs_service_v2.dart:244-245` | Write to GPU uniforms |
| **WASM ViewState** | `lib.rs:107-108` | Store immutable visible counts |
| **WASM ViewState** | `lib.rs:290-291` | Return in snapshot JSON |
| **WASM ViewState** | `lib.rs:313-315` | Build viewport filter for chrome |
| **JS GPU** | `ggrs_gpu_v2.js:428-429` | Cache from setViewUniforms |
| **JS GPU** | `ggrs_gpu_v2.js:446-447` | Write to uniform buffer (offset 44) |
| **JS GPU** | `ggrs_gpu_v2.js:489-493` | Update via setVisibleCounts |
| **JS Interaction** | `bootstrap_v2.js:508,801` | Apply from WASM snapshot |
| **GPU Shader** | `ggrs_gpu_v2.js:91` | Clip points outside visible range |

---

## Key Invariants

1. **Single Source of Truth:** Dart calculates visible counts ONCE during render setup
2. **Immutable During Interactions:** Zoom/pan do NOT change visible counts
3. **WASM Passthrough:** WASM stores visible counts but never modifies them
4. **GPU Shader Clipping:** GPU culls points outside `[0, n_visible_cols) × [0, n_visible_rows)`
5. **Chrome Filtering:** Viewport filter uses visible counts to generate chrome for visible facets only

---

## Future Considerations

If multi-facet zoom is implemented:
- Add mutation logic to `ViewState::zoom()`
- Update snapshot to return new visible counts
- Trigger chrome recomputation when visible count changes
- Handle data streaming for newly visible facets
- Consider separate "semantic zoom" (axis range) vs "layout zoom" (facet count)
