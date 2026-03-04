# Session Fixes - 2026-03-02

## Critical Bugs Fixed

### 1. Orchestrator MessageRouter (BLOCKING BUG)

**File**: `apps/orchestrator/lib/services/message_router.dart`

**Problem**: Using `dartify()` to convert JS message data, but nested maps weren't `Map<String, dynamic>` → cast exception in `MessageEnvelope.fromJson()`.

**Fix**: Changed to JSON.stringify → json.decode pattern (same as project_nav):
```dart
// BEFORE (BROKEN):
final dartData = jsData.dartify();
final data = Map<String, dynamic>.from(dartData as Map);

// AFTER (FIXED):
final jsonObj = web.window['JSON'] as JSObject;
final jsonStr = jsonObj.callMethod('stringify'.toJS, jsData) as JSString;
final data = json.decode(jsonStr.toDart) as Map<String, dynamic>;
```

**Impact**: Orchestrator couldn't route any messages → all webapps stuck on "Loading...".

---

### 2. Canvas Positioning (RENDERING BUG)

**File**: `apps/step_viewer/web/ggrs/bootstrap_v3.js` (line 89-94)
**File**: `apps/orchestrator/web/step_viewer/ggrs/bootstrap_v3.js` (same)

**Problem**: Canvas created without `position: absolute` → not properly positioned, potentially behind interaction div.

**Fix**: Added absolute positioning + z-index:
```javascript
// BEFORE:
canvas.style.width = '100%';
canvas.style.height = '100%';
canvas.style.display = 'block';

// AFTER:
canvas.style.position = 'absolute';
canvas.style.top = '0';
canvas.style.left = '0';
canvas.style.width = '100%';
canvas.style.height = '100%';
canvas.style.display = 'block';
canvas.style.zIndex = '1'; // Below interaction div (z-index 10)
```

**Impact**: Canvas renders but invisible → user sees blank white area despite logs showing 475K points drawn.

---

### 3. Missing Import

**File**: `apps/orchestrator/lib/services/message_router.dart`

**Problem**: Using `web.window['JSON']` and `callMethod` without `dart:js_interop_unsafe`.

**Fix**: Added import:
```dart
import 'dart:js_interop_unsafe';
```

---

## Self-Validating Tests Created

### Test 1: Basic Rendering (`test_v3_render.html`)

**Location**: `apps/step_viewer/web/test_v3_render.html`

**Run**:
```bash
cd apps/step_viewer
python3 -m http.server 8001
# Open http://localhost:8001/test_v3_render.html
```

**Tests**:
1. WASM init
2. Renderer creation
3. GPU context
4. Canvas visibility (CSS checks)
5. Manual chrome (gray background + grid)
6. Manual data points (100 red dots)

**Expected**: All ✓ PASS + visible gray background, grid lines, red dots.

---

## Test Plan

See `TEST_PLAN.md` for full 8-test suite (Tests 2-8 TODO).

---

## Build & Test

```bash
# 1. Build orchestrator
cd apps/orchestrator
flutter build web --release

# 2. Build step_viewer
cd apps/step_viewer
flutter build web --release

# 3. Run test
cd apps/step_viewer
python3 -m http.server 8001
# Open http://localhost:8001/test_v3_render.html

# 4. Run full app
cd apps/orchestrator
flutter run -d chrome --web-port 8080
```

---

## Known Remaining Issues

See `ISSUES_FOR_LATER.md`:
1. Chrome color format inconsistency (`fill` vs `color` fields)
2. Color parser returns default gray instead of throwing on invalid
3. Multiple color formats supported (hex, rgb, rgba) - should standardize

---

## Logbook

See `LOGBOOK.md` for full investigation trace (17 entries).

**Summary**:
- Found orchestrator message routing broken (dartify cast issue)
- Found canvas invisible (missing absolute positioning)
- Created self-validating test harness
- Both fixes are minimal, targeted, and match working V2 patterns
