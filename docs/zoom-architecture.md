# Single-Facet Zoom Architecture

**Status:** Working correctly as of 2026-02-27
**Purpose:** Semantic zoom (narrow data range) with viewport anchored at data origin

## The Critical Insight

### Two Coordinate Systems

**Axis Coordinates** (`full_x_min` / `full_x_max`):
- Include margins for axis labels and ticks
- The axis ORIGIN (where labels start) is at `full_x_min`
- Example: `full_x_min = -23783`, `full_x_max = 499472`

**Data Coordinates** (`data_x_min` / `data_x_max`):
- The actual bounds of the data points (no margins)
- The FIRST data point is at `data_x_min`
- Example: `data_x_min = 0`, `data_x_max = 499472`

**The Gap:**
```
|--- margin ---| data points →
full_x_min     data_x_min
   ↓              ↓
 -23783           0
```

This gap MUST stay constant in **pixel width** as you zoom.

---

## Data Flow

### 1. Initial Setup

**WASM `initPlotStream()` returns:**
```javascript
{
  x_min: -23783,      // Axis origin (with margin)
  x_max: 499472,      // Axis end
  data_x_min: 0,      // First data point
  data_x_max: 499472, // Last data point
  // ... other metadata
}
```

**Flutter reads BOTH:**
```dart
final xMin = metadata['x_min'];        // Axis ranges
final dataXMin = metadata['data_x_min']; // Data ranges
```

**Flutter passes to `initView()`:**
```dart
{
  full_x_min: xMin,      // Axis origin
  full_x_max: xMax,
  data_x_min: dataXMin,  // Data anchor
  data_y_min: dataYMin,
  // ... layout params
}
```

**WASM `ViewState` initialized:**
```rust
ViewState {
  full_x_min: -23783,  // Axis origin
  full_x_max: 499472,
  data_x_min: 0,       // Data anchor (CRITICAL!)
  vis_x_min: -23783,   // Initially same as full
  vis_x_max: 499472,
  cell_width: 1820,    // Grid width in pixels
  // ...
}
```

---

## Zoom Algorithm

### Goal
Maintain **constant pixel gap** between axis origin and first data point.

### Math

**Pixel gap formula:**
```rust
pixel_gap = (data_x_min - vis_x_min) / (vis_x_max - vis_x_min) × cell_width
```

**Before zoom:**
```
span = 523255 data units
pixel_gap = (0 - (-23783)) / 523255 × 1820 ≈ 82.7 pixels
```

**After zoom (factor 1.1, narrower span):**
```
new_span = 523255 / 1.1 = 475687 data units

// To maintain same pixel gap:
data_units_gap = 82.7 × 475687 / 1820 ≈ 21621 data units

// Position vis_x_min to maintain gap:
new_vis_x_min = data_x_min - data_units_gap = 0 - 21621 = -21621
new_vis_x_max = new_vis_x_min + new_span = -21621 + 475687 = 454066
```

**Result:**
```
pixel_gap = (0 - (-21621)) / 475687 × 1820 ≈ 82.7 pixels ✓ CONSTANT
```

### Implementation

```rust
fn zoom(&mut self, axis: &str, sign: i32) {
    let factor = ZOOM_FACTOR.powi(sign);  // 1.1^sign

    if axis == "x" || axis == "both" {
        let old_span = self.vis_x_max - self.vis_x_min;
        let new_span = (old_span / factor).max(1e-15).min(full_span);

        // Calculate current pixel gap
        let old_pixel_gap = if old_span.abs() > 1e-15 {
            (self.data_x_min - self.vis_x_min) / old_span * self.cell_width
        } else {
            0.0
        };

        // Maintain same pixel gap in new span
        let data_units_gap = if new_span.abs() > 1e-15 {
            old_pixel_gap * new_span / self.cell_width
        } else {
            0.0
        };

        // Anchor at data_x_min
        self.vis_x_min = self.data_x_min - data_units_gap;
        self.vis_x_max = self.vis_x_min + new_span;

        // Clamp to full range
        // ... (shift both if hit boundaries)
    }
}
```

---

## Logging

**Console output format:**
```
[ZOOM-X] factor=1.10 |
  old_span=523255.7 new_span=475687.0 |
  full_x_min=-23783.3 data_x_min=0.0 |
  old: vis=[-23783.3, 499472.3] gap_px=82.7 |
  new: vis=[-21621.0, 454066.0] gap_data=21621.0 gap_px=82.7 |
  data_anchor_px=82.7
```

**Key values to verify:**
- `gap_px` (old) = `gap_px` (new) → **MUST be constant!**
- `data_x_min` ≠ `full_x_min` → **Must have a gap**
- `new_vis_x_min` adjusts to maintain gap
- `data_anchor_px` = pixel position of first data point (constant)

---

## Visual Behavior

### Initial State
```
Viewport: [-------------- 1820px --------------]
Axis:     |----|-------------------------->
          -23k   0                      499k
          full   data

Grid shows entire data range: 0 to 499k
Gap: 82px (constant)
```

### After Zoom In (10x)
```
Viewport: [-------------- 1820px --------------]
Axis:     |----|--------->
          -23k   0      50k              499k (outside)
          full   data

Grid shows narrowed range: 0 to 50k
Gap: 82px (STILL CONSTANT!)
Data "stretches" right outside viewport
```

**Crucially:**
- The **gap stays 82px** — first data point at same screen position
- The **viewport doesn't slide** — no horizontal shifting
- Only the **right edge narrows** — less data visible
- **No cell growth** — grid size unchanged

---

## The No-Fallback Principle

### What Was Broken

**Original code (WRONG):**
```rust
data_x_min: params.data_x_min.unwrap_or(params.full_x_min), // ❌ FALLBACK!
```

If `data_x_min` wasn't passed, it silently used `full_x_min`. This made:
- `data_x_min = full_x_min` → gap = 0
- Zoom anchored at axis origin instead of data origin
- Data appeared to slide because anchor was wrong

**The bug was HIDDEN** by the fallback. No error, just wrong behavior.

### The Fix

**Remove fallback (CORRECT):**
```rust
data_x_min: params.data_x_min,  // ✓ REQUIRED — error if missing
```

**Result:**
- Missing `data_x_min` → **parse error** → immediate failure
- Forces caller to pass correct value
- Bugs are visible, not masked

### The Rule

**From `.claude/rules/01-no-fallbacks.md`:**
> NEVER implement fallback logic, graceful degradation, or silent error recovery unless explicitly told. Fallbacks mask errors in logic and other bugs. When something fails, it must fail visibly.

**Applied here:**
- No `unwrap_or()` defaults
- No "if missing, use X" logic
- Parse errors propagate to caller
- Missing data = loud failure

---

## Files Modified

### WASM (Rust)
**`ggrs/crates/ggrs-wasm/src/lib.rs`:**

1. **`InitViewParams` struct** (lines 242-262):
   - Made `data_x_min` and `data_y_min` required (not `Option<f64>`)
   - Removed `#[serde(default)]` annotations
   - Added comment: "REQUIRED" not "Falls back to..."

2. **`init_view()` function** (lines 1268-1273):
   - Removed `.unwrap_or(params.full_x_min)` fallback
   - Direct assignment: `data_x_min: params.data_x_min`

3. **`ViewState::zoom()` function** (lines 115-235):
   - Calculate pixel gap from `data_x_min` position
   - Maintain constant pixel gap across zoom
   - Comprehensive logging with all relevant values

### Flutter (Dart)
**`apps/step_viewer/lib/services/ggrs_service_v2.dart`:**

1. **Read both ranges** (lines 135-148):
   ```dart
   final xMin = metadata['x_min'];        // Axis with margin
   final dataXMin = metadata['data_x_min']; // Data bounds
   ```

2. **Pass both to `initView()`** (lines 204-213):
   ```dart
   'full_x_min': xMin,
   'full_x_max': xMax,
   'data_x_min': dataXMin,  // NEW!
   'data_y_min': dataYMin,  // NEW!
   ```

3. **Updated log** (line 142):
   ```dart
   'axis=[$xMin,$xMax]×[$yMin,$yMax] data=[$dataXMin,$dataXMax]×[$dataYMin,$dataYMax]'
   ```

---

## Testing

### Verification Checklist

**Initial render:**
- [ ] Console shows `[ZOOM-X]` with `data_x_min` ≠ `full_x_min`
- [ ] `gap_px` is non-zero (typically 50-150px)
- [ ] Data curve starts at expected position

**After zoom (Shift+wheel):**
- [ ] `gap_px` stays constant (±0.1px tolerance)
- [ ] `data_anchor_px` stays constant
- [ ] Visible range narrows (span decreases)
- [ ] Data doesn't "slide" horizontally
- [ ] First data point stays at same screen position

**After multiple zooms:**
- [ ] `gap_px` still constant after 10+ zoom operations
- [ ] Can zoom in until ~1% of data visible
- [ ] Can zoom out to full range
- [ ] No horizontal shifting at any zoom level

### Common Issues

**If `gap_px = 0.0`:**
- `data_x_min = full_x_min` → fallback was triggered
- Check that Flutter passes `data_x_min` in `initViewParams`
- Check that WASM doesn't have `.unwrap_or()` fallback

**If gap grows/shrinks:**
- Bug in pixel gap calculation
- Check `cell_width` is correct
- Check division by zero guards

**If data slides horizontally:**
- Not anchoring at `data_x_min`
- Check zoom function uses `self.data_x_min` not `self.full_x_min`

---

## Future Extensions

This architecture forms the basis for:

### Planned Tomorrow
1. **Pan/scroll** — maintain gap while shifting visible range
2. **Multi-facet zoom** — apply same logic per facet
3. **Zoom to selection** — anchor at selection bounds
4. **Reset view** — restore initial `vis_x_min = full_x_min`

### Key Principle for All
The gap between axis origin and data origin must remain constant in pixels during ANY viewport transformation. This ensures:
- Consistent visual layout
- No jarring shifts
- Predictable zoom/pan behavior
- Data-anchored transformations

### Reusable Components
- `calculate_pixel_gap()` — extract to helper
- `maintain_gap()` — apply to any range transformation
- Gap validation — assert constant before/after
- Logging format — reuse for pan/scroll

---

## References

- **Architecture doc:** `docs/architecture-ggrs-interactive.md`
- **4-Phase flow:** `CLAUDE.md` lines 116-149
- **No-fallback rule:** `.claude/rules/01-no-fallbacks.md`
- **WASM API:** `ggrs/docs/WASM_API_REFERENCE.md`

---

## Change Log

**2026-02-27:**
- Initial implementation of single-facet semantic zoom
- Removed fallback for `data_x_min` (no-fallback principle)
- Added comprehensive logging
- Verified constant pixel gap across zoom operations
- Documented architecture for future viewport interactions
