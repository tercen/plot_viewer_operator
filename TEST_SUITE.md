# V3 Self-Validating Test Suite

All tests run standalone in the browser with synthetic data - no Tercen backend required.

## Test 1: Basic Rendering ✅ COMPLETE

**File**: `apps/step_viewer/web/test_v3_render.html`

**Tests**:
- WASM initialization
- GPU context creation
- Canvas visibility (CSS validation)
- Layout state (uniform buffer)
- Chrome rendering (rects)
- Data point rendering
- Coordinate transforms (data-space → pixels)

**Expected output**:
- Red background, green grid lines, 100 blue dots scattered

**Status**: ✅ Working - all critical bugs fixed

---

## Test 2: Streaming ⚠️ NEW

**File**: `apps/step_viewer/web/test_streaming.html`

**Tests**:
- Small dataset (1K points, 500/chunk)
- Medium dataset (50K points, 5K/chunk)
- Large dataset (500K points, 15K/chunk)
- Progressive rendering (GPU updates per chunk)
- Cancellation (mid-stream abort)
- Performance (points/sec)

**Features**:
- Progress bar
- Live stats (loaded/total, rate)
- Simulated network delay (10-30ms/chunk)
- Mock WASM renderer (no real Tercen needed)

**Expected output**:
- Points appear progressively as chunks load
- Progress bar fills smoothly
- Final render shows all points
- Stats show throughput

**How to test**:
```
http://localhost:8001/test_streaming.html
```
Click buttons to test different dataset sizes.

---

## Test 3: Interaction ⚠️ NEW

**File**: `apps/step_viewer/web/test_interaction.html`

**Tests**:
- Scroll → vertical pan
- Ctrl+Scroll → horizontal pan
- Shift+Wheel in grid → zoom both axes
- Shift+Wheel in left strip → zoom height only
- Shift+Wheel in top strip → zoom width only
- Zone detection (grid vs strips)
- Chrome invalidation on zoom
- Event logging

**Features**:
- Visual feedback (chrome updates)
- Event log (shows interaction type + zone)
- Reset view button
- 200 test points + grid chrome

**Expected output**:
- Scroll moves the grid/points
- Zoom changes cell size
- Chrome rebuilds after zoom
- Events logged to console

**How to test**:
```
http://localhost:8001/test_interaction.html
```
Interact with canvas, check event log.

---

## Test 4: Coordinator ✅ COMPLETE

**File**: `apps/step_viewer/web/test_coordinator.html`

**Tests**:
- Layer registration
- Dependency resolution (canRender checks)
- Invalidation mechanism (generation increment, state reset)
- Generation counter (stale render detection)
- Error handling (layer failures)

**Features**:
- Mock layers with configurable dependencies
- Four independent test scenarios
- No WASM or GPU required - pure JS layer logic

**How to test**:
```
http://localhost:8001/test_coordinator.html
```
Click buttons to run each test scenario. All should show PASS.

---

## Test 5: Chrome Parsing ✅ COMPLETE

**File**: `apps/step_viewer/web/test_chrome.html`

**Tests**:
- Color parsing: #RRGGBB (6 digits)
- Color parsing: #RRGGBBAA (8 digits with alpha)
- Color parsing: rgb(r, g, b)
- Color parsing: rgba(r, g, b, a)
- Invalid color handling: throws error (not default to gray)
- Chrome category splitting: 6 named categories
- Chrome property naming: backgrounds use 'fill', lines use 'color'

**Features**:
- Visual color samples (rendered boxes)
- Invalid color detection (7 test cases)
- Chrome structure validation
- No WASM required - tests _parseColor directly

**How to test**:
```
http://localhost:8001/test_chrome.html
```
Click buttons to run tests. Check visual samples match expected colors.

---

## Benefits of This Approach

1. **Fast iteration** - No rebuild, just refresh browser
2. **Isolated testing** - One subsystem at a time
3. **Self-validating** - Visual + console output
4. **No backend** - Synthetic data, mock renderers
5. **Reproducible** - Same test every time
6. **Easy debugging** - Small scope, detailed logging

---

## Next Steps

1. ✅ Created all 5 test files
2. Run all tests to verify:
   - `test_v3_render.html` - basic rendering ✅ verified
   - `test_streaming.html` - progressive data loading
   - `test_interaction.html` - zoom/pan/scroll
   - `test_coordinator.html` - layer dependencies
   - `test_chrome.html` - color parsing
3. Fix any bugs found
4. Apply all verified fixes to main app
5. Test main app with real Tercen data
