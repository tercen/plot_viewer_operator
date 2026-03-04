# V3 Code Changes — Exact Instructions

Specific code changes needed to activate V3 for testing.

---

## Change 1: Add V3 Scripts to HTML

**File:** `apps/step_viewer/web/index.html`

**Action:** Add these three script tags (find the existing `<script type="module" src="ggrs/bootstrap_v2.js"></script>` line and add these after it):

```html
<script type="module" src="ggrs/bootstrap_v3.js"></script>
<script type="module" src="ggrs/ggrs_gpu_v3.js"></script>
<script type="module" src="ggrs/interaction_manager.js"></script>
```

---

## Change 2: Update Service Locator

**File:** `apps/step_viewer/lib/di/service_locator.dart`

**Line 8:** Add new import after the existing v2 import:
```dart
import '../services/ggrs_service_v2.dart';
import '../services/ggrs_service_v3.dart';  // ADD THIS LINE
```

**After line 10 (after `final GetIt serviceLocator = GetIt.instance;`):** Add feature flag:
```dart
final GetIt serviceLocator = GetIt.instance;

/// Feature flag: set to false to revert to V2
const bool _useV3 = true;  // ADD THESE TWO LINES
```

**Lines 25-27:** Replace the GgrsServiceV2 registration with conditional:
```dart
// OLD (DELETE):
serviceLocator.registerLazySingleton<GgrsServiceV2>(
  () => GgrsServiceV2(),
);

// NEW (REPLACE WITH):
if (_useV3) {
  serviceLocator.registerLazySingleton<GgrsServiceV3>(
    () => GgrsServiceV3(),
  );
} else {
  serviceLocator.registerLazySingleton<GgrsServiceV2>(
    () => GgrsServiceV2(),
  );
}
```

---

## Change 3: Update main.dart

**File:** `apps/step_viewer/lib/main.dart`

**Line 10:** Add v3 import after the existing v2 import:
```dart
import 'services/ggrs_service_v2.dart';
import 'services/ggrs_service_v3.dart';  // ADD THIS LINE
```

**Lines 37-40:** Replace credential setup (make it conditional):
```dart
// OLD (DELETE):
serviceLocator<GgrsServiceV2>().setTercenCredentials(
  serviceUri ?? '',
  token,
);

// NEW (REPLACE WITH):
if (_useV3) {
  serviceLocator<GgrsServiceV3>().setTercenCredentials(
    serviceUri ?? '',
    token,
  );
} else {
  serviceLocator<GgrsServiceV2>().setTercenCredentials(
    serviceUri ?? '',
    token,
  );
}
```

**Line 78:** Replace service lookup:
```dart
// OLD (DELETE):
final ggrsService = serviceLocator<GgrsServiceV2>();

// NEW (REPLACE WITH):
final ggrsService = _useV3
    ? serviceLocator<GgrsServiceV3>()
    : serviceLocator<GgrsServiceV2>();
```

**IMPORTANT:** Also update the MultiProvider to accept the correct type. If there are type errors, change line 83 to:
```dart
ChangeNotifierProvider<ChangeNotifier>.value(value: ggrsService),
```

This works because both GgrsServiceV2 and GgrsServiceV3 extend ChangeNotifier.

---

## Change 4: Update plot_area.dart

**File:** `apps/step_viewer/lib/presentation/widgets/plot_area.dart`

**Lines 6-7:** Add v3 imports:
```dart
import '../../services/ggrs_interop_v2.dart';
import '../../services/ggrs_service_v2.dart';
import '../../services/ggrs_interop_v3.dart';  // ADD THIS
import '../../services/ggrs_service_v3.dart';  // ADD THIS
```

**Note:** This file likely has Provider.of or Consumer usage. If you see type errors after activating v3, change:
```dart
// Old:
Provider.of<GgrsServiceV2>(context)

// New:
Provider.of<ChangeNotifier>(context) as dynamic
```

Or better yet, check if this widget even needs to access the service directly (it might just consume PlotStateProvider).

---

## Change 5: Update ggrs_plot_view.dart (if needed)

**File:** `apps/step_viewer/lib/presentation/widgets/ggrs_plot_view.dart`

**Check:** Read this file and see if it directly references GgrsServiceV2. If so, add the same imports as Change 4.

If there are Provider.of<GgrsServiceV2> usages, change them to accept ChangeNotifier or make them conditional based on _useV3.

---

## Summary of Files Modified

1. `web/index.html` — add 3 script tags
2. `lib/di/service_locator.dart` — import, feature flag, conditional registration
3. `lib/main.dart` — import, conditional credential setup, conditional service lookup
4. `lib/presentation/widgets/plot_area.dart` — add imports (may need Provider fixes)
5. `lib/presentation/widgets/ggrs_plot_view.dart` — add imports (may need Provider fixes)

---

## Build & Test

After making these changes:

```bash
# 1. Build WASM
cd /home/thiago/workspaces/tercen/main/ggrs
wasm-pack build crates/ggrs-wasm --target web --out-dir ../../plot_viewer_operator/apps/step_viewer/web/ggrs/pkg

# 2. Verify exports
cd /home/thiago/workspaces/tercen/main/plot_viewer_operator
grep "initLayout" apps/step_viewer/web/ggrs/pkg/ggrs_wasm.d.ts

# 3. Run Flutter
cd apps/step_viewer
flutter run -d chrome --web-port 8080 \
  --dart-define=TERCEN_TOKEN=<token> \
  --dart-define=SERVICE_URI=http://127.0.0.1:5400 \
  --dart-define=TEAM_ID=test \
  --web-browser-flag=--user-data-dir=/tmp/chrome-dev \
  --web-browser-flag=--disable-web-security
```

**Console check:**
Look for `[GgrsV3]` logs, NOT `[GgrsV2]`.

---

## Rollback

To revert to V2, simply change one line:

**In `lib/di/service_locator.dart`:**
```dart
const bool _useV3 = false;  // Change true → false
```

Then hot-reload or restart the app.

---

## Next Steps

Once app runs successfully:
1. Follow test cases in `v3-testing-guide.md`
2. Document issues in `_local/v3-testing-notes.md`
3. If critical issues found, rollback and investigate
4. If tests pass, proceed to Phase 3 (Render Orchestration)
