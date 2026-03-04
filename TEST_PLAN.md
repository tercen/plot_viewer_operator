# V3 Rendering Test Plan

## Self-Validating Tests

These tests can be run independently without Tercen backend and validate the rendering pipeline.

### Test 1: Basic Rendering (`test_v3_render.html`)

**Location**: `apps/step_viewer/web/test_v3_render.html`

**Run**:
```bash
cd apps/step_viewer
python3 -m http.server 8001
# Open http://localhost:8001/test_v3_render.html
```

**What it tests**:
1. WASM initialization
2. Renderer creation
3. GPU context creation
4. Canvas visibility (display, position, z-index)
5. Manual chrome rendering (background + grid lines)
6. Manual data points (100 synthetic red dots)

**Expected output**:
- All tests show ✓ PASS
- Canvas shows:
  - Gray background
  - Grid lines (vertical + horizontal)
  - 100 red dots scattered randomly

**If this fails**:
- Canvas not found → bootstrap_v3.js not creating canvas
- Canvas hidden → CSS issue (display: none or visibility: hidden)
- No chrome → GPU rendering broken or color parsing issue
- No points → Point pipeline broken

---

### Test 2: Coordinator Layer Dependencies

**TODO**: Create `test_coordinator.html`

**Tests**:
1. Layer registration order
2. Dependency resolution (ViewStateLayer before ChromeLayers)
3. Invalidation cascades (invalidate ViewState → invalidates all chrome)
4. Generation counter (new render cancels old)

---

### Test 3: Color Parsing

**TODO**: Create `test_colors.html`

**Tests**:
- Hex colors: `#FF0000`, `#00FF00AA`
- RGB colors: `rgb(255, 0, 0)`
- RGBA colors: `rgba(0, 255, 0, 0.5)`
- Invalid colors (should fail loudly, not default to gray)

**Current bug**: `_parseColor` returns gray `[0.5, 0.5, 0.5, 1.0]` on invalid - should throw!

---

### Test 4: Zoom/Pan Interactions

**TODO**: Create `test_interactions.html`

**Tests**:
1. Scroll → vertical pan
2. Ctrl+Scroll → horizontal pan
3. Shift+Wheel in grid → facet zoom (both axes)
4. Shift+Wheel in left strip → cell height only
5. Shift+Wheel in top strip → cell width only
6. Chrome invalidation on zoom (grid/axes/ticks rebuilt)

---

### Test 5: Data Streaming

**TODO**: Create `test_streaming.html`

**Tests**:
1. Small dataset (100 points) → single chunk
2. Large dataset (500K points) → multiple chunks, progressive render
3. Chunk cancellation (new render while streaming)
4. Empty dataset (0 rows)

---

## Integration Tests (Require Tercen Backend)

### Test 6: Full Render Pipeline

**Run**: Flutter app with real Tercen data

**Tests**:
1. CubeQuery creation
2. initPlotStream → metadata
3. Coordinator render loop
4. Chrome + data visible
5. Interaction (zoom, pan) updates chrome

**Test datasets**:
- Y-only (x = .obs sequential)
- X+Y
- X+Y+ColFacet (2 columns)
- X+Y+RowFacet (2 rows)
- X+Y+ColFacet+RowFacet (2x2 grid)

---

## Performance Benchmarks

### Test 7: Render Performance

**Metrics**:
- Time to first chrome (should be < 100ms)
- Time to full data load (15K rows should be < 500ms)
- Frame rate during interaction (should be 60fps)

**Test with**:
- 10K points
- 100K points
- 500K points
- 1M points

---

## Regression Tests

### Test 8: Known Bugs (from ISSUES_FOR_LATER.md)

1. **Color format inconsistency**: Chrome uses `fill` vs `color` fields
2. **No-fallback validation**: Missing data_x_min should throw, not default to 0.0
3. **dartify() type issues**: Nested maps must be Map<String, dynamic>

---

## Current Status

✓ Test 1: Created (test_v3_render.html)
☐ Test 2-8: TODO

**Next**: Run Test 1 to validate basic rendering, then create Tests 2-5.
