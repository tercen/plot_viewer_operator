# V3 Activation Checklist

Quick checklist to switch from V2 to V3 for testing.

---

## Prerequisites

- [ ] Phase 1 complete (Layout Module)
- [ ] Phase 2 complete (Interaction Abstraction)
- [ ] All V3 files created with .bak checkpoints
- [ ] 44 Rust tests passing

---

## Step 1: Build WASM

```bash
cd /home/thiago/workspaces/tercen/main/ggrs
wasm-pack build crates/ggrs-wasm --target web --out-dir ../../plot_viewer_operator/apps/step_viewer/web/ggrs/pkg
```

**Verify new exports:**
```bash
cd /home/thiago/workspaces/tercen/main/plot_viewer_operator
grep -E "(initLayout|interactionStart)" apps/step_viewer/web/ggrs/pkg/ggrs_wasm.d.ts
```

Expected: `export function initLayout(...)` and `export function interactionStart(...)`

---

## Step 2: Add V3 Scripts to HTML

**File:** `apps/step_viewer/web/index.html`

Add after existing bootstrap_v2.js script:
```html
<script type="module" src="ggrs/bootstrap_v3.js"></script>
<script type="module" src="ggrs/ggrs_gpu_v3.js"></script>
<script type="module" src="ggrs/interaction_manager.js"></script>
```

---

## Step 3: Create Service Locator Import

**File:** `apps/step_viewer/lib/di/service_locator.dart`

Add at top:
```dart
import '../services/ggrs_service_v3.dart';
```

Add feature flag:
```dart
const bool _useV3 = true;  // Set to false to revert to v2
```

Modify registration:
```dart
void setupServiceLocator() {
  // ... existing registrations ...

  if (_useV3) {
    getIt.registerLazySingleton<GgrsServiceV3>(() => GgrsServiceV3());
  } else {
    getIt.registerLazySingleton<GgrsService>(() => GgrsService());
  }
}
```

---

## Step 4: Update Widget to Use V3

**File:** Find the widget that renders the plot (likely `lib/presentation/widgets/plot_canvas.dart` or similar)

**Option A: If using GetIt directly:**
```dart
// Old:
// final ggrsService = getIt<GgrsService>();

// New (if _useV3 = true):
final ggrsService = getIt<GgrsServiceV3>();
```

**Option B: If using Provider:**
Check `lib/main.dart` or similar for ChangeNotifierProvider setup. Update to use GgrsServiceV3.

---

## Step 5: Run and Test

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

## Step 6: Verify Basic Render

1. Drop Y factor
2. Check console for `[GgrsV3]` logs
3. Verify plot appears

**Expected console output:**
```
[GgrsV3] WASM ready @ Xms
[GgrsV3] CubeQuery complete: <id> @ Yms
[GgrsV3] initPlotStream complete @ Zms
[GgrsV3] computeSkeleton complete @ Ams
[GgrsV3] initLayout complete @ Bms
[GgrsV3] Layout synced to GPU @ Cms
[GgrsV3] Chrome rendered @ Dms
[GgrsV3] streamData complete @ Ems
```

---

## Step 7: Run Test Suite

Follow test cases in `v3-testing-guide.md`:
- Test 1: Initial Render
- Test 2: Zone Detection
- Test 3-6: Zoom (data grid, left strip, top strip, multi-facet)
- Test 7-8: Pan
- Test 9: Reset
- Test 10: Error propagation
- Test 11: Generation counter

---

## Quick Rollback (if needed)

**Revert to V2:**
```dart
// In service_locator.dart
const bool _useV3 = false;
```

**Or remove V3 from GetIt:**
```dart
getIt.registerLazySingleton<GgrsService>(() => GgrsService());
// Delete GgrsServiceV3 registration
```

**Restore from .bak (if V3 files corrupted):**
```bash
cd /home/thiago/workspaces/tercen/main/plot_viewer_operator/apps/step_viewer
cp lib/services/ggrs_service_v3.dart.bak lib/services/ggrs_service_v3.dart
cp lib/services/ggrs_interop_v3.dart.bak lib/services/ggrs_interop_v3.dart
cp web/ggrs/bootstrap_v3.js.bak web/ggrs/bootstrap_v3.js
cp web/ggrs/ggrs_gpu_v3.js.bak web/ggrs/ggrs_gpu_v3.js
cp web/ggrs/interaction_manager.js.bak web/ggrs/interaction_manager.js
```

---

## Files Modified (for reference)

**New files (all with .bak):**
- `lib/services/ggrs_service_v3.dart`
- `lib/services/ggrs_interop_v3.dart`
- `web/ggrs/bootstrap_v3.js`
- `web/ggrs/ggrs_gpu_v3.js`
- `web/ggrs/interaction_manager.js`

**Modified files:**
- `lib/di/service_locator.dart` (add import + feature flag)
- `web/index.html` (add v3 script tags)
- Widget file that uses GgrsService (change to GgrsServiceV3)

**Unchanged V2 files:**
- `lib/services/ggrs_service_v2.dart` (or ggrs_service.dart)
- `web/ggrs/bootstrap_v2.js`
- `web/ggrs/ggrs_gpu_v2.js`

---

## Success Criteria

✅ V3 activated successfully if:
- App builds without errors
- Console shows `[GgrsV3]` logs (not `[GgrsV2]`)
- Plot renders with chrome + data
- Shift+wheel zooms
- Drag pans
- Double-click resets
- No console errors

---

## Issues Tracking

Document any issues in: `_local/v3-testing-notes.md`

Format:
```markdown
## Issue: [Short title]
**Test:** Test N from v3-testing-guide.md
**Symptom:** What went wrong
**Expected:** What should happen
**Root cause:** (if known)
**Fix:** (if applied)
```
