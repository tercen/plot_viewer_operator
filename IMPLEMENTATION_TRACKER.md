# V3 Implementation Traceability Matrix

**Purpose**: Map functional requirements from plan to actual implementation, identify gaps, prioritize fixes.

**Date**: 2026-02-27
**Status**: Post-compilation review reveals critical integration gaps

---

## Phase 1: Layout Module

| Requirement | Plan Location | Implementation Status | Gap | Priority |
|------------|---------------|----------------------|-----|----------|
| LayoutState struct with all fields | Task 1.1 | ✅ Created in ggrs-core | None | - |
| validate() method | Task 1.1 | ✅ Implemented | None | - |
| LayoutManager zoom/pan/reset | Task 1.2 | ✅ Implemented | None | - |
| WASM export: initLayout | Task 1.3 | ✅ Exported | None | - |
| **WASM export: getLayoutState** | **Task 1.3** | **❌ MISSING** | **JS calls gpu.getLayoutState() but method doesn't exist** | **P0** |
| LayoutManager wired to handlers | Task 1.2 | ⚠️ Partial | Handlers exist but zone-awareness broken | P1 |
| Zone-aware zoom (left→Y, top→X, data→both) | Task 2.2 (ZoomHandler) | ❌ NOT IMPLEMENTED | ZoomHandler ignores zone parameter | P1 |

**Phase 1 Verdict**: Core structs/methods exist, but **critical integration gaps** prevent any interaction from working.

---

## Phase 2: Interaction Abstraction

| Requirement | Plan Location | Implementation Status | Gap | Priority |
|------------|---------------|----------------------|-----|----------|
| InteractionHandler trait | Task 2.1 | ✅ Created | None | - |
| InteractionZone enum | Task 2.1 | ✅ Created | None | - |
| InteractionResult enum | Task 2.1 | ✅ Created | None | - |
| ZoomHandler with zone awareness | Task 2.2 | ❌ BROKEN | axis_from_zone() result IGNORED | P1 |
| PanHandler with cancel on small distance | Task 2.2 | ✅ Working | None | - |
| ResetHandler | Task 2.2 | ✅ Working | None | - |
| WASM exports: interactionStart/Move/End/Cancel | Task 2.3 | ✅ Exported | None | - |
| **InteractionManager zone detection** | **Task 2.4** | **❌ CRASHES** | **Calls gpu.getLayoutState() which doesn't exist** | **P0** |
| Handler selection based on modifiers | Task 2.4 | ✅ Implemented | None | - |
| Snapshot application (ViewUpdate → GPU) | Task 2.4 | ✅ Implemented | None | - |
| Bootstrap integration (create manager) | Task 2.5 | ✅ Integrated | None | - |

**Phase 2 Verdict**: Framework complete, but **zone detection crashes immediately** due to missing GPU method. Even if fixed, zone-aware zoom logic is broken.

---

## Phase 3: Render Orchestration

| Requirement | Plan Location | Implementation Status | Gap | Priority |
|------------|---------------|----------------------|-----|----------|
| RenderLayer base class | Task 3.1 | ✅ Created | None | - |
| RenderCoordinator with dependency checking | Task 3.3 | ✅ Implemented | None | - |
| LayoutLayer (getStreamLayout) | Task 3.2 | ✅ Implemented | None | - |
| **ViewStateLayer null safety** | **Task 3.2** | **❌ UNSAFE** | **panels[0] unchecked, will crash if empty** | **P0** |
| ViewStateLayer context validation | Task 3.2 | ❌ MISSING | Missing fields become 0.0 silently | P1 |
| ChromeLayer (6 categories) | Task 3.2 | ✅ Implemented | None | - |
| **Chrome rendering efficiency** | **Implicit** | **❌ INEFFICIENT** | **Each of 6 layers calls getViewChrome() independently** | **P1** |
| DataLayer with chunked streaming | Task 3.2 | ✅ Implemented | None | - |
| **DataLayer dependencies** | **Task 3.2** | **❌ INCOMPLETE** | **Only checks 3 of 6 chrome layers** | **P2** |
| **Coordinator generation counter** | **Task 3.3** | **❌ MISSING** | **No cancellation mechanism for stale renders** | **P1** |
| Coordinator invalidateLayers() | Task 3.3 | ✅ Implemented | None | - |
| **Invalidation wiring to interactions** | **Task 3.4** | **❌ NOT WIRED** | **Zoom doesn't invalidate chrome layers** | **P2** |
| Bootstrap integration (create coordinator) | Task 3.4 | ✅ Integrated | None | - |
| Dart simplified render flow (7→5 phases) | Task 3.5 | ✅ Implemented | None | - |
| Dart waitForRenderComplete | Task 3.5 | ⚠️ Partial | No timeout, infinite wait if event missed | P2 |
| **Coordinator listener cleanup** | **Task 3.5** | **❌ MEMORY LEAK** | **No removal mechanism, listeners accumulate** | **P2** |

**Phase 3 Verdict**: Layer architecture works, but **missing generation counter** means renders can't be cancelled. Chrome rendering is **wastefully redundant**.

---

## Critical Integration Gaps (Cross-Phase)

| Issue | Affected Use Cases | Root Cause | Priority |
|-------|-------------------|------------|----------|
| **gpu.getLayoutState() doesn't exist** | UC3, UC4, UC14 (all interactions) | JS assumes method exists, WASM never exported it | **P0** |
| **Zone-aware zoom not implemented** | UC3 (left strip zoom) | ZoomHandler.axis_from_zone() called but result IGNORED | **P1** |
| **No coordinator generation counter** | UC8 (mid-render cancellation) | Dart has generation counter, coordinator doesn't | **P1** |
| **Chrome called 6× redundantly** | UC1, UC9 (all renders) | Each ChromeLayer calls getViewChrome() independently | **P1** |
| **No validation in error paths** | UC12 (invalid ranges), UC15 (null colors), UC17 (missing context) | Silent fallbacks violate no-fallback rule | P1 |

---

## Elegant Fix Strategy

### Step 1: Fix P0 Blockers (Crashes) - 2 hours
**Goal**: Get ANY interaction working without crashes

**Fix 1.1: Add getLayoutState() to GgrsGpuV3**
- File: `apps/step_viewer/web/ggrs/ggrs_gpu_v3.js`
- Add method after syncLayoutState():
```javascript
getLayoutState() {
    return this._layoutState;
}
```
- Called by: `interaction_manager.js:41`

**Fix 1.2: Add null check for panels[0]**
- File: `apps/step_viewer/web/ggrs/render_coordinator.js:174`
- Before line 174, add:
```javascript
if (!layoutInfo.panels || layoutInfo.panels.length === 0) {
    throw new Error('ViewStateLayer: layoutInfo.panels is empty');
}
```

**Verification**: Drop Y factor, wheel event doesn't crash

---

### Step 2: Fix P1 Critical Functionality - 4 hours
**Goal**: Core features work as spec'd

**Fix 2.1: Implement zone-aware zoom**
- File: `ggrs/crates/ggrs-wasm/src/interactions/zoom_handler.rs:50-60`
- Problem: axis_from_zone() called but result ignored in zoom() call
- Change line ~58 from:
```rust
let new_state = mgr.zoom(ZoomAxis::Both, direction)
```
To:
```rust
let new_state = mgr.zoom(self.axis.unwrap(), direction)
```

**Fix 2.2: Add coordinator generation counter**
- File: `apps/step_viewer/web/ggrs/render_coordinator.js`
- Add to constructor (after line 323):
```javascript
this.generation = 0;
```
- Modify _renderLoop() start (line 393):
```javascript
async _renderLoop() {
    const currentGen = ++this.generation;
    while (true) {
        if (this.generation !== currentGen) {
            console.log('[RenderCoordinator] Render cancelled (stale generation)');
            this.renderLoopActive = false;
            return;
        }
        // ... existing loop code
    }
}
```
- Add method for Dart to call:
```javascript
cancelRender() {
    this.generation++;
    for (const layer of this.layers.values()) {
        layer.cancel();
    }
}
```

**Fix 2.3: Optimize chrome rendering (shared cache)**
- File: `apps/step_viewer/web/ggrs/render_coordinator.js:193`
- Modify ChromeLayer.render():
```javascript
async render(ctx) {
    console.log(`[ChromeLayer:${this.category}] Rendering...`);
    
    // Cache chrome JSON in context (first layer fetches, others reuse)
    if (!ctx.chromeCache) {
        const chromeJson = this.renderer.getViewChrome();
        ctx.chromeCache = JSON.parse(chromeJson);
        if (ctx.chromeCache.error) {
            throw new Error(`Chrome failed: ${ctx.chromeCache.error}`);
        }
    }
    
    const elements = ctx.chromeCache[this.category];
    // ... rest of method unchanged
}
```

**Fix 2.4: Add error validation (no silent fallbacks)**

File: `render_coordinator.js:234` (_parseColor):
```javascript
_parseColor(str) {
    if (str && str.startsWith('#')) {
        const hex = str.slice(1);
        if (hex.length === 6) {
            return [
                parseInt(hex.slice(0, 2), 16) / 255,
                parseInt(hex.slice(2, 4), 16) / 255,
                parseInt(hex.slice(4, 6), 16) / 255,
                1.0,
            ];
        }
    }
    // NO FALLBACK - throw error
    throw new Error(`Invalid color: ${str}`);
}
```

File: `render_coordinator.js:162` (ViewStateLayer.render):
```javascript
// Before creating viewParams, validate context fields exist
const requiredFields = ['xMin', 'xMax', 'yMin', 'yMax', 'dataXMin', 'dataXMax', 'dataYMin', 'dataYMax'];
for (const field of requiredFields) {
    if (ctx[field] === undefined || ctx[field] === null) {
        throw new Error(`ViewStateLayer: missing required context field '${field}'`);
    }
}
```

**Verification**: 
- UC3: Shift+wheel in left strip only zooms Y
- UC8: Drop new factor mid-render cancels old render
- UC12: Invalid ranges show error (not silent failure)

---

### Step 3: Fix P2 Architectural Issues - 3 hours
**Goal**: Clean architecture, no leaks/races

**Fix 3.1: Complete DataLayer dependencies**
- File: `render_coordinator.js:256`
- Change from:
```javascript
this.dependencies = ['chrome:panel_backgrounds', 'chrome:grid_lines', 'chrome:axis_lines'];
```
To:
```javascript
this.dependencies = [
    'chrome:panel_backgrounds',
    'chrome:strip_backgrounds',
    'chrome:grid_lines',
    'chrome:axis_lines',
    'chrome:tick_marks',
    'chrome:panel_borders'
];
```

**Fix 3.2: Wire zoom to chrome invalidation**
- File: `interaction_manager.js:90` (_applySnapshot)
- After `gpu.syncLayoutState(JSON.stringify(snapshot))`, add:
```javascript
// Invalidate geometric chrome layers (grid, axes, ticks adjust on zoom)
const instance = this.gpu._parentInstance;  // Need reference to instance
if (instance && instance.coordinator) {
    instance.coordinator.invalidateLayers([
        'chrome:grid_lines',
        'chrome:axis_lines', 
        'chrome:tick_marks'
    ]);
}
```
- Requires bootstrap_v3.js to store coordinator reference in gpu object

**Fix 3.3: Add coordinator listener cleanup**
- File: `render_coordinator.js`, add method:
```javascript
removeAllListeners() {
    this.listeners = [];
}
```
- File: `bootstrap_v3.js:360` (ggrsV3Cleanup), add:
```javascript
if (instance.coordinator) {
    instance.coordinator.removeAllListeners();
}
```

**Fix 3.4: Add waitForRenderComplete timeout**
- File: `ggrs_interop_v3.dart:180`
- Wrap promise with timeout:
```dart
static Future<void> waitForRenderComplete(String containerId, {Duration timeout = const Duration(seconds: 30)}) async {
  // ... existing code ...
  await promise.toDart.timeout(timeout, onTimeout: () {
    throw TimeoutException('Render did not complete within ${timeout.inSeconds}s');
  });
}
```

**Verification**:
- UC10: Zoom only updates geometric chrome
- UC16: DataLayer waits for all 6 chrome
- UC18: Multiple renders don't leak listeners

---

## Timeline

| Step | Duration | Deliverable |
|------|----------|-------------|
| Step 1: P0 Blockers | 2 hours | No crashes on wheel event |
| Step 2: P1 Functionality | 4 hours | Zone-aware zoom, cancellable renders, efficient chrome |
| Step 3: P2 Architecture | 3 hours | No leaks, complete dependencies, validation |
| **TOTAL** | **9 hours** | **Production-ready V3** |

---

## Root Cause: Why Did This Happen?

1. **Compilation ≠ Integration** - We verified each file compiled, but never tested USER FLOWS
2. **Missing interface contracts** - No explicit contract that GgrsGpuV3 must have getLayoutState()
3. **Spec drift** - ZoomHandler comments say "zone-aware" but code ignores zone
4. **No end-to-end validation** - Should have tested "Shift+wheel in left strip" before declaring Phase 2 complete

**Prevention**: Add integration test checklist for each phase completion.

---

## Next Action

**Recommendation**: Execute Steps 1-3 systematically (9 hours). Architecture is solid, just needs glue code.

Your choice:
- **Option A**: Fix all now (9 hours) → production-ready V3
- **Option B**: Fix Step 1 only (2 hours) → validate approach, then continue
- **Option C**: Re-scope → simplify to MVP first
