# V3 Test Suite — Complete

All self-validating tests created. No Tercen backend required.

## Summary

| Test | File | Status | What It Tests |
|------|------|--------|---------------|
| 1 | `test_v3_render.html` | ✅ Verified | WASM init, GPU context, canvas visibility, layout state, chrome rendering, data points |
| 2 | `test_streaming.html` | ⚠️ Ready | Progressive data loading (1K, 50K, 500K points), chunked rendering, cancellation |
| 3 | `test_interaction.html` | ⚠️ Ready | Scroll, pan, zoom, zone detection, event logging |
| 4 | `test_coordinator.html` | ⚠️ Ready | Layer dependencies, invalidation, generation counter, error handling |
| 5 | `test_chrome.html` | ⚠️ Ready | Color parsing (hex, rgb, rgba), invalid colors throw errors, category structure |

## Critical Bugs Fixed (All Applied to Both Copies)

### 1. WGSL Reserved Keyword 'layout'
**Location**: `apps/step_viewer/web/ggrs/ggrs_gpu_v3.js` (and orchestrator copy)

**Problem**: Shader used `var<uniform> layout: LayoutUniforms;` but 'layout' is reserved in WGSL.

**Fix**: Renamed to `u_layout` in both `RECT_SHADER_V3` and `POINT_SHADER_V3`.

**Lines affected**:
- Line 30: `@group(0) @binding(0) var<uniform> u_layout: LayoutUniforms;`
- Line 79: Same for point shader

**Symptom**: Shader compilation failed → invalid pipeline → blank canvas.

### 2. Missing stepMode: 'instance'
**Location**: `apps/step_viewer/web/ggrs/ggrs_gpu_v3.js` (and orchestrator copy)

**Problem**: Vertex buffer descriptors missing `stepMode: 'instance'` → treated as per-vertex instead of per-instance.

**Fix**: Added `stepMode: 'instance'` to both rect and point pipeline vertex buffers.

**Lines affected**:
- Line 271: Rect pipeline vertex buffer
- Line 299: Point pipeline vertex buffer

**Symptom**: WebGPU validation error "Vertex range requires larger buffer".

### 3. Canvas Positioning
**Location**: `apps/step_viewer/web/ggrs/bootstrap_v3.js` (and orchestrator copy)

**Problem**: Canvas created without `position: absolute` → potentially not visible or covered by interaction div.

**Fix**: Added positioning and z-index to canvas.

**Lines affected** (91-97):
```javascript
canvas.style.position = 'absolute';
canvas.style.top = '0';
canvas.style.left = '0';
canvas.style.width = '100%';
canvas.style.height = '100%';
canvas.style.display = 'block';
canvas.style.zIndex = '1'; // Below interaction div (z-index 10)
```

**Symptom**: Canvas invisible despite WebGPU rendering executing.

### 4. MessageRouter dartify() Cast Issue (Orchestrator)
**Location**: `apps/orchestrator/lib/services/message_router.dart`

**Problem**: `event.data.dartify()` returns Map but nested maps aren't `Map<String, dynamic>` → `MessageEnvelope.fromJson()` cast fails.

**Fix**: Use JSON.stringify → json.decode pattern like project_nav does.

**Symptom**: All webapp communication broken, no apps visible in orchestrator.

## How to Run Tests

```bash
cd /home/thiago/workspaces/tercen/main/plot_viewer_operator/apps/step_viewer
python3 -m http.server 8001
```

Then open in browser:
- http://localhost:8001/test_v3_render.html
- http://localhost:8001/test_streaming.html
- http://localhost:8001/test_interaction.html
- http://localhost:8001/test_coordinator.html
- http://localhost:8001/test_chrome.html

## Expected Results

### Test 1: Basic Rendering (✅ Verified Working)
- BRIGHT RED background (impossible to miss)
- BRIGHT GREEN grid lines (5px wide)
- 100 BLUE dots scattered randomly

### Test 2: Streaming
- Points appear progressively as chunks load
- Progress bar fills smoothly (0% → 100%)
- Final render shows all points
- Stats show throughput (points/sec)
- Cancellation test stops mid-stream

### Test 3: Interaction
- Scroll over canvas → vertical pan (chrome rebuilds)
- Ctrl+Scroll → horizontal pan
- Shift+Wheel in center → zoom both axes (cell size changes)
- Shift+Wheel in left strip → zoom height only
- Shift+Wheel in top strip → zoom width only
- Event log shows interaction type + zone

### Test 4: Coordinator
- Layer B blocked until A completes
- Layer C blocked until B completes
- Invalidation increments generation
- Generation counter detects stale renders
- Layer errors don't crash coordinator

### Test 5: Chrome Parsing
- Visual color samples match expected colors:
  - #FF0000 → red
  - #00FF00 → green
  - #0000FF → blue
  - #FF000080 → 50% transparent red
  - rgb(255, 128, 0) → orange
  - rgba(0, 255, 255, 0.7) → cyan 70%
- Invalid colors throw errors (7 test cases):
  - 'gray', '#gray', 'invalid', '', null, 'hsl(...)', '#FFF'
- Chrome structure has 6 categories
- Backgrounds use 'fill', lines use 'color'

## What This Testing Approach Achieved

1. **Fast iteration** - No rebuild, just refresh browser
2. **Isolated bugs** - Found 4 critical bugs in hours, not days
3. **Self-validating** - Visual + console output, no "does it work?" back-and-forth
4. **No backend** - Synthetic data, mock renderers
5. **Reproducible** - Same test every time
6. **Easy debugging** - Small scope, detailed logging
7. **Complete coverage** - Rendering, streaming, interaction, coordinator, chrome parsing

## Next Steps

1. Run tests 2-5 to verify they work (test 1 already verified)
2. Fix any bugs found
3. Apply all verified fixes to main V3 implementation (ggrs_service_v3.dart)
4. Test main app with real Tercen data
5. Compare V3 to V2 performance/behavior

## Files Modified

**Step Viewer**:
- `apps/step_viewer/web/ggrs/ggrs_gpu_v3.js` - shaders + pipelines
- `apps/step_viewer/web/ggrs/bootstrap_v3.js` - canvas positioning
- `apps/step_viewer/web/test_v3_render.html` - created
- `apps/step_viewer/web/test_streaming.html` - created
- `apps/step_viewer/web/test_interaction.html` - created
- `apps/step_viewer/web/test_coordinator.html` - created
- `apps/step_viewer/web/test_chrome.html` - created

**Orchestrator** (copies):
- `apps/orchestrator/web/step_viewer/ggrs/ggrs_gpu_v3.js` - shaders + pipelines
- `apps/orchestrator/web/step_viewer/ggrs/bootstrap_v3.js` - canvas positioning
- `apps/orchestrator/lib/services/message_router.dart` - dartify() fix

**Documentation**:
- `LOGBOOK.md` - 9 entries tracking investigation
- `TEST_SUITE.md` - test plan updated with all 5 tests
- `CRITICAL_FIX.md` - documents 'layout' keyword bug
- `V3_TEST_SUITE_COMPLETE.md` - this file

## Verification Checklist

Before marking V3 complete:

- [ ] test_streaming.html works (progressive loading visible)
- [ ] test_interaction.html works (zoom/pan functional)
- [ ] test_coordinator.html works (all 4 tests PASS)
- [ ] test_chrome.html works (colors match, invalid throws)
- [ ] Main V3 app renders with real Tercen data
- [ ] Y-only binding works (sequential x [1..nRows])
- [ ] Multi-facet rendering works (>1 panel)
- [ ] Zoom/pan works in main app
- [ ] Performance comparable to V2 (475K points < 3s)
