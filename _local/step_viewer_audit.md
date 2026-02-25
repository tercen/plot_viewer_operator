# step_viewer Audit Report

Strict code review of `apps/step_viewer/`. Organized by severity and category.
Data rendering is known-disabled — not flagged.

---

## CRITICAL — Bugs and correctness errors

### C1. PlotStateProvider created inside StatelessWidget.build()
**File:** `main.dart:75`
```dart
Widget build(BuildContext context) {
    final plotState = PlotStateProvider();
    _plotStateProvider = plotState;
```
`StepViewerApp` is a `StatelessWidget`. Every call to `build()` creates a NEW `PlotStateProvider`, discarding all state (bindings, factors, viewport). While `runApp()` is only called once, any MaterialApp-level rebuild (theme change, locale change) triggers `build()` and destroys the provider.

**Fix:** Move provider creation to a `StatefulWidget.initState()` or create it before `runApp()` in `main()`.

---

### C2. Listener leak in GgrsPlotView.didChangeDependencies
**File:** `ggrs_plot_view.dart:52-56`
```dart
void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<PlotStateProvider>();
    state.addListener(_onStateChanged);
}
```
`didChangeDependencies()` is called after `initState()` AND on every InheritedWidget change (e.g. theme). Each call adds a NEW listener. `dispose()` only removes ONE. After N dependency changes, there are N+1 listeners, each calling `_scheduleRender()` — causing N+1 render calls per state change.

**Fix:** Add listener in `initState()` only, or track whether listener is already attached and remove before re-adding.

---

### C3. No generation counter in PlotStateProvider._initStep
**File:** `plot_state_provider.dart:87-124`
`_initStep` is async but has no cancellation mechanism. If a user selects step A, then quickly step B:
1. `_initStep(A)` starts, `_initStep(B)` starts
2. B completes first → sets factors/bindings
3. A completes later → overwrites B's state with stale data

**Fix:** Add a generation counter (like `GgrsService._renderGeneration`), check it after each await.

---

### C4. CubeQuery binding match ignores extra existing facets
**File:** `cube_query_service.dart:202-214`
```dart
final colMatch = colFacetColumn == null
    ? existingColFacets.isEmpty
    : existingColFacets.contains(colFacetColumn);
```
If existing CQ has col facets [A, B] and caller wants [A], this reports "match" (contains A). But the CQ has an extra facet B that changes the result. The check should verify exact equality, not just containment.

---

### C5. Only first facet sent to CubeQuery and WASM
**Files:** `ggrs_service_v2.dart:245-246`, `ggrs_service_v2.dart:273-284`
```dart
colFacetColumn: state.colFacetBindings.isNotEmpty
    ? state.colFacetBindings.first.name : null,
```
The UI supports multiple facets (`addFacet`), but `_runCubeQuery` and `_buildInitConfig` only use `.first`. All facets after the first are silently ignored.

**Fix:** Pass all facet bindings as lists to CubeQuery and WASM config.

---

### C6. Factor types hardcoded in CubeQuery mutations
**File:** `cube_query_service.dart:233-259`
```dart
aq.yAxis = sci.Factor()..name = yColumn..type = 'double';
```
All axis factors are forced to `'double'`, all facet factors to `'string'`. But the real `Factor` object has the actual schema type. The type information is lost because `ensureCubeQuery` only receives `String?` column names, not `Factor` objects.

**Fix:** Pass `Factor` objects (or at minimum name+type pairs) to `ensureCubeQuery`.

---

### C7. getCubeQuery failure silently treated as "no CQ exists"
**File:** `cube_query_service.dart:56-59`
```dart
try {
    existingCq = await _factory.workflowService.getCubeQuery(workflowId, stepId);
} catch (e) {
    debugPrint('CubeQueryService: getCubeQuery failed: $e');
}
```
Network errors, auth failures, and server errors are caught and silently treated as 5B (build from scratch). This masks real errors and can cause unnecessary CubeQueryTask creation on transient failures.

---

## HIGH — Dead code and waste

### H1. Entire v1 stack is dead code, still loaded
**Files:** `ggrs_service.dart` (667 lines), `ggrs_interop.dart` (227 lines), `bootstrap.js` (~1600 lines), `ggrs_gpu.js` (~1000 lines)

Only v2 is used: `main.dart` imports `ggrs_service_v2.dart`, DI registers `GgrsServiceV2`.

**BUT** — v2 Dart interop (`ggrs_interop_v2.dart`) calls v1 window functions registered by `bootstrap.js`:
- `ensureWasmInitialized`, `createGGRSRenderer`, `ggrsCreateTextMeasurer`
- `ggrsInitPlotStream`, `ggrsComputeLayout`, `ggrsRenderChrome`
- `ggrsComputeSkeleton`, `ggrsGetStaticChrome`, `ggrsGetViewportChrome`

So `bootstrap.js` IS needed for its WASM init and window function exports. But ~90% of its code (the entire v1 rendering pipeline: `ggrsRenderChromeCanvas`, `ggrsRenderStaticChrome`, `ggrsRenderViewportChrome`, staging, split-buffer DOM rendering, viewport handlers, all 6-layer DOM code) is dead.

**Action:** Extract the shared WASM init + window function bindings into a minimal `ggrs_wasm_bridge.js`. Remove all v1 rendering code. Remove `ggrs_gpu.js`. Remove `ggrs_service.dart` and `ggrs_interop.dart`.

---

### H2. GgrsInteropV2 duplicates all shared methods from GgrsInterop
**File:** `ggrs_interop_v2.dart`
Methods `ensureWasmInitialized`, `createRenderer`, `createTextMeasurer`, `initializeTercen`, `initPlotStream`, `computeLayout`, `renderChrome`, `computeSkeleton`, `getStaticChrome`, `getViewportChrome`, `yieldFrame` are byte-for-byte identical to `GgrsInterop`.

**Action:** After removing v1, rename `GgrsInteropV2` → `GgrsInterop` and consolidate.

---

### H3. _logPointDiagnostics is never called
**File:** `ggrs_service.dart:620-629`
Dead diagnostic method. Part of the dead v1 service.

---

### H4. _parseColor duplicated 3 times in JS with inconsistent behavior
- `ggrs_gpu.js`: throws on unrecognized color
- `ggrs_gpu_v2.js`: throws on unrecognized color
- `bootstrap_v2.js`: returns `[0.5, 0.5, 0.5, 1.0]` fallback on unrecognized

**Action:** Single shared `parseColor` function in a utility module.

---

### H5. _lineToRect duplicated in bootstrap_v2.js and ggrs_gpu.js
Different fallback behavior. `bootstrap_v2.js` uses `ln.width || 1` (silent default), `ggrs_gpu.js` throws if width is null.

---

### H6. RenderPhase enum defined twice
**Files:** `ggrs_service.dart:11`, `ggrs_service_v2.dart:12`
Identical enum. Symptom of the dead v1 code.

---

### H7. _buildBindingsMap duplicated
**Files:** `ggrs_service.dart:646`, `ggrs_service_v2.dart:383`
Identical method.

---

## MEDIUM — Architecture and design

### M1. PlotStateProvider accumulates too many responsibilities
**File:** `plot_state_provider.dart`
Currently manages:
1. Factor loading state (isLoading, error, factors list)
2. Plot bindings (x, y, row/col facets)
3. Plot configuration (geomType, plotTheme)
4. UI state (isFactorPanelOpen)
5. Viewport state (14 fields: row/col start, window counts, total facets, cell dimensions)
6. Committed axis state (4 fields + axis mappings list)
7. `computeNewViewport()` — a 100-line computation

**Candidate split:**
- `FactorLoadingState` — factor loading lifecycle
- `PlotBindingState` — bindings + geom/theme
- `ViewportState` — viewport tracking + committed state + computeNewViewport

---

### M2. GgrsServiceV2.render() always re-renders Phase 1 chrome
**File:** `ggrs_service_v2.dart:68`
Phase 1 chrome (DOM-based SVG) is always rendered, then immediately destroyed by GPU setup in Phase 3. V1 had `gpuAlreadyExists` guard to skip Phase 1 when GPU content already existed.

**Impact:** On every binding change, the DOM is populated with SVG chrome only to be immediately torn down.

---

### M3. V2 render() recreates GPU device on every resize
**File:** `ggrs_service_v2.dart:107`
`setupGpu()` creates new DOM elements, requests a new GPU adapter+device, creates new pipelines. This happens on every render() call, including resizes. GPU device creation is expensive (~10-50ms).

**Fix:** Only call `setupGpu` on first render or when container size actually changes. On resize, call `setCanvasSize` and re-render.

---

### M4. V2 mergeChrome does JS→JSON→Dart→JSON→JS round-trip
**File:** `ggrs_service_v2.dart:295-361`
To merge two JSObjects:
1. `JSON.stringify(obj)` → JS string
2. `json.decode(string)` → Dart Map
3. Merge Dart Maps
4. `json.encode(map)` → Dart String
5. `JSON.parse(string)` → JSObject

Four serialization boundaries. This should be a single JS-side merge function in `bootstrap_v2.js`.

---

### M5. CubeQueryService has no abstract interface
`CubeQueryService` is a concrete class accessed via `serviceLocator<CubeQueryService>()`. Unlike `DataService` (which has an abstract interface), it can't be substituted for testing.

---

### M6. String-based role dispatching in PlotStateProvider
**File:** `plot_state_provider.dart:127-170`
```dart
void setBinding(String role, Factor binding) {
    switch (role) {
        case 'x': ...
        case 'y': ...
    }
}
```
The roles `'x'`, `'y'`, `'row_facet'`, `'col_facet'` are raw strings used in switch statements across setBinding, clearBinding, addFacet, removeFacet. This should be an enum (`BindingRole`) to catch typos at compile time.

---

### M7. Binding configuration uses Map<String, dynamic> instead of typed structure
**Files:** `ggrs_service_v2.dart:254-290`, `ggrs_service.dart:249-282`
`_buildInitConfig` constructs a JSON map with string keys and nested maps. This binding spec (`{status, column}`) is a clear candidate for a typed class or at minimum a named constructor.

---

### M8. No viewport/facet scrolling in V2
V1 `GgrsService` has `renderViewport()` for viewport-only re-renders (skipping CubeQuery). V2 `GgrsServiceV2` has no equivalent — every interaction requires a full render cycle.

---

### M9. GgrsPlotView._onStateChanged triggers render on ALL state changes
**File:** `ggrs_plot_view.dart:65-69`
The listener fires on EVERY `notifyListeners()` call — including:
- `toggleFactorPanel()` (irrelevant to rendering)
- Factor loading state changes (isLoading toggling)
- Factor list updates (no render needed until binding changes)

**Fix:** Either use `Selector` to filter relevant changes, or split the provider so GgrsPlotView only watches render-relevant state.

---

## LOW — Hard-coded values and style violations

### L1. Hard-coded point rendering options
**File:** `ggrs_service_v2.dart:171-174`
```dart
'radius': 2.5,
'fillColor': 'rgba(0,0,0,0.6)',
```
Should derive from `geomType` + `plotTheme`.

---

### L2. Hard-coded grid/tick styling in bootstrap_v2.js
**File:** `bootstrap_v2.js:304-305`
```js
const gridColor = '#E5E7EB';  // neutral-200
const gridWidth = 1;
```
And lines 391-398, 415-419: tick label font size `11`, offset `12px`, font family `Fira Sans, sans-serif`, color `#374151`. These should come from GGRS theme/layout output, not be hardcoded in JS.

---

### L3. Hard-coded cell size heuristics (v1 only — dead code)
**File:** `ggrs_service.dart:114`
```dart
final windowRowCount = (height / 60).floor().clamp(1, 1 << 30);
final windowColCount = (width / 100).floor().clamp(1, 1 << 30);
```

---

### L4. PlotArea spacing values not all from design system
**File:** `plot_area.dart:24-28`
```dart
static const double _axisDropWidth = 36.0;   // NOT in 4/8/16/24/32/48
static const double _axisDropHeight = 32.0;  // OK (32)
static const double _facetStripSize = 28.0;  // NOT in design system
static const double _facetDropSize = 36.0;   // NOT in design system
static const double _facetAddSize = 24.0;    // OK (24)
```
Values 36 and 28 are not in the Tercen spacing system (4, 8, 16, 24, 32, 48).

---

### L5. Hard-coded debounce timings
- `ggrs_service_v2.dart:59`: `Duration(milliseconds: 16)` — frame-time debounce
- `bootstrap_v2.js:484`: `setTimeout(updateTicks, 200)` — tick update debounce
- `bootstrap_v2.js:491`: `Math.exp(-e.deltaY * 0.002)` — zoom sensitivity

None documented or configurable.

---

### L6. Hard-coded WASM renderer ID
**File:** `ggrs_service_v2.dart:205`, `ggrs_service.dart:206`
```dart
_renderer ??= GgrsInteropV2.createRenderer('ggrs-canvas');
```
The canvas ID `'ggrs-canvas'` is hardcoded. The actual DOM container has ID `'ggrs-container-N'`. The WASM renderer's canvas ID doesn't correspond to any DOM element — it's just a label passed to the Rust constructor.

---

### L7. No touch events in V2 interaction handlers
**File:** `bootstrap_v2.js:584-588`
Only mouse events: `wheel`, `mousedown`, `mousemove`, `mouseup`, `dblclick`. No touch events. The Tercen Layout Principles require: "Tablet test: can a user with no keyboard and no hover discover every feature?"

---

### L8. No origin validation in MessageHelper
**File:** `message_helper.dart:24-38`
Accepts messages from ANY origin. Should validate `event.origin` against expected orchestrator origin.

---

## STRUCTURAL — Consolidation opportunities

### S1. Factor objects carry name+type but type is discarded at every boundary
- `PlotStateProvider.setBinding` stores `Factor` (has type)
- `_runCubeQuery` extracts only `.name` strings
- `CubeQueryService.ensureCubeQuery` receives `String?` parameters
- CubeQuery mutations hardcode types

**Pattern:** Pass `Factor` objects through the entire pipeline instead of extracting names.

---

### S2. Binding spec construction is duplicated
`_buildBindingsMap` (UI chrome) and `_buildInitConfig` (WASM init) both construct binding maps from PlotStateProvider state. The logic for determining unbound/bound/.obs status is duplicated.

**Pattern:** Extract a `PlotBindingSpec` value class that both methods consume.

---

### S3. Global mutable state for provider reference
**File:** `main.dart:14`
```dart
PlotStateProvider? _plotStateProvider;
```
Used to route `step-selected` messages to the provider. This is a code smell — the message listener should be inside the widget tree (via a StatefulWidget that has access to context).

---

### S4. V2 JS bootstrap exports could be a class/module
`bootstrap_v2.js` exposes 10+ functions on `window`. These could be methods on a single `GgrsV2` module object, reducing global namespace pollution and making the API surface explicit.

---

### S5. WebGPU requirement not checked early
WebGPU is checked at GPU init time (Phase 3). If not available, user sees Phase 1 chrome then a render error. Should check at `ensureWasmInitialized` time and show a clear "WebGPU required" message.

---

### S6. _CancelledException pattern duplicated
Both `ggrs_service.dart` and `ggrs_service_v2.dart` define private `_CancelledException` and identical `_checkGen`/`_yieldFrame`/`_setPhase` methods.

---

## SUMMARY — Priority action items

| Priority | Item | Impact |
|----------|------|--------|
| P0 | C2: Fix listener leak in GgrsPlotView | Memory leak, exponential render calls |
| P0 | C3: Add generation counter to _initStep | Race condition on rapid step selection |
| P0 | H1: Remove dead v1 code, extract shared WASM bridge | ~3500 lines of dead code loaded at runtime |
| P1 | C1: Move provider creation out of build() | State loss on MaterialApp rebuild |
| P1 | M3: Cache GPU device, only resize canvas | GPU device recreation on every render |
| P1 | C5: Pass all facets to CQ and WASM | Silent data loss (only first facet used) |
| P1 | M4: Move chrome merge to JS side | 4x unnecessary serialization |
| P2 | M1: Split PlotStateProvider | Maintainability, testability |
| P2 | C4: Fix binding match to check exact equality | Incorrect 5C cache hits |
| P2 | C6: Pass Factor objects to CubeQueryService | Wrong types in CubeQuery mutations |
| P2 | M9: Filter state changes that trigger render | Unnecessary WASM calls |
| P3 | L1-L6: Extract hard-coded constants | Maintainability, design system compliance |
| P3 | S1-S6: Structural consolidation | Code health |