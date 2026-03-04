# PlotState Refactor — Centralized Metadata Architecture

## Summary

Refactored V3 rendering to use a single centralized `PlotState` object instead of scattered metadata across multiple components. All plot information now lives in one place, populated once from WASM and updated synchronously by JS interactions.

**Status**: Phase 1 (mock data) complete. Phase 2 (real WASM metadata) infrastructure ready.

---

## Architecture Changes

### Before (scattered metadata)

```
ViewportState
  ├─ viewportCol, viewportRow, visibleCols, visibleRows
  ├─ totalCols, totalRows (grid dimensions)
  ├─ cellSpacing
  └─ animation state

Elsewhere (undefined locations):
  ├─ Axis ranges (xMin, xMax, yMin, yMax)
  ├─ Facet labels (colLabels[], rowLabels[])
  ├─ Chrome styles (panelFill, borderColor, etc)
  └─ Data bounds (nRows)

InteractionManager
  └─ queries scattered sources for hit-testing
```

**Problems:**
- Metadata spread across multiple objects
- No single source of truth
- Hard to track what's populated when
- Unclear where axis ranges/facet labels should live

### After (centralized PlotState)

```
PlotState (single source of truth)
  ├─ metadata (from WASM)
  │   ├─ grid: { totalCols, totalRows }
  │   ├─ axes: { xMin, xMax, yMin, yMax }
  │   ├─ facets: { colLabels[], rowLabels[] }
  │   ├─ chrome: { panelFill, borderColor, gridLineColor, ... }
  │   └─ data: { nRows }
  │
  ├─ viewport (user interactions)
  │   ├─ col, row (fractional scroll position)
  │   └─ visibleCols, visibleRows (zoom level)
  │
  ├─ layout (derived)
  │   ├─ cellWidth, cellHeight (computed from viewport + metadata)
  │   └─ [future: axis mappings, facet pixel positions]
  │
  └─ spatialIndex (Phase 2)
      └─ quadtree for O(log n) point queries

InteractionManager
  └─ queries PlotState for all hit-testing
```

**Benefits:**
- All metadata in one object
- Clear lifecycle: populated once from WASM, updated by interactions
- Easy to inspect state for debugging
- No confusion about where data lives

---

## Component Responsibilities

| Component | Old Role | New Role |
|-----------|----------|----------|
| **PlotState** | *(didn't exist)* | Single source of truth for metadata + viewport + layout |
| **InteractionManager** | Query scattered sources | Query PlotState only |
| **bootstrap_v3.js** | Create ViewportState, wire components | Create PlotState, wire components |
| **GgrsServiceV3** | Pass config piecemeal | Pass metadata once via setPlotMetadata |
| **WASM** | Return metadata in initPlotStream | Same, but now Dart forwards to JS as single blob |

---

## Lifecycle

### Phase 1 (Mock Mode) — Current

```
Dart: GgrsServiceV3.render()
  ↓
JS: ggrsV3EnsureGpu()
  → creates PlotState with default config
  ↓
Dart: ggrsV3SetViewportConfig({ totalCols: 10, totalRows: 10, ... })
  → populates plotState.metadata.grid + axes
  ↓
Dart: ggrsV3RenderChrome()
  → plotState.renderChrome() generates rects
  ↓
Dart: ggrsV3SyncLayout()
  → plotState.buildLayoutState() → GPU uniform buffer
  ↓
Dart: ggrsV3StreamMockData()
  → MockStreamingRenderer generates points
  → GPU.setDataPoints()
  ↓
User zooms (Shift+wheel):
  → InteractionManager.onWheel()
  → plotState.animateTo() (200ms animation)
  → plotState._recomputeLayout()
  → GPU.syncLayoutState()
  → plotState.renderChrome() → GPU.setLayer()
```

### Phase 2 (Real WASM) — Infrastructure Ready

```
Dart: GgrsServiceV3.render()
  ↓
WASM: initPlotStream()
  → discovers tables, fetches ranges, returns metadata JSON
  ↓
Dart: receives metadata
  {
    grid: { totalCols, totalRows },
    axes: { xMin, xMax, yMin, yMax },
    facets: { colLabels[], rowLabels[] },
    chrome: { panelFill, borderColor, ... },
    data: { nRows }
  }
  ↓
Dart: ggrsV3SetPlotMetadata(containerId, metadata)
  → populates entire plotState.metadata in one call
  ↓
[rest is same as Phase 1]
```

---

## Files Changed

| File | Action | Phase |
|------|--------|-------|
| `web/ggrs/plot_state.js` | **CREATED** — Centralized state object | 1 |
| `web/ggrs/interaction_manager.js` | **REFACTORED** — Use plotState instead of viewportState | 1 |
| `web/ggrs/bootstrap_v3.js` | **REFACTORED** — Create PlotState, add setPlotMetadata API | 1 |
| `lib/services/ggrs_interop_v3.dart` | **ADDED** — setPlotMetadata() method | 1 |
| `web/ggrs/viewport_state.js` | *(not removed, but unused)* — May delete later | — |

---

## PlotState API

### Metadata Management

```javascript
// Set full metadata from WASM (Phase 2)
plotState.setMetadata({
  grid: { totalCols, totalRows },
  axes: { xMin, xMax, yMin, yMax },
  facets: { colLabels, rowLabels },
  chrome: { panelFill, borderColor, ... },
  data: { nRows },
});

// Set grid config (Phase 1 mock mode)
plotState.setGridConfig({
  totalCols: 10,
  totalRows: 10,
  xMin: 0, xMax: 100,
  yMin: 0, yMax: 100,
});
```

### Viewport Management

```javascript
// Set viewport position/zoom (immediate)
plotState.setViewport(col, row, visibleCols, visibleRows);

// Animate viewport change (200ms ease-out cubic)
plotState.animateTo(
  targetCol, targetRow, targetVisCols, targetVisRows,
  onFrame,    // called each RAF tick
  onComplete, // called when done
);

// Cancel ongoing animation
plotState.cancelAnimation();
```

### Layout Queries

```javascript
// Get full layout state for GPU
const layoutState = plotState.buildLayoutState();
// Returns: { canvas_width, canvas_height, n_col_facets, n_row_facets,
//            cell_width, cell_height, cell_spacing,
//            viewport_start_col, viewport_start_row,
//            viewport_visible_cols, viewport_visible_rows }

// Generate chrome rects for visible facets
const chrome = plotState.renderChrome();
// Returns: { panel_backgrounds: [...], grid_lines: [...], panel_borders: [...] }
```

### Hit Testing

```javascript
// Get facet at pixel coordinates
const facet = plotState.getFacetAt(canvasX, canvasY);
// Returns: { col, row } or null

// Get zone at pixel coordinates
const zone = plotState.getZoneAt(canvasX, canvasY);
// Returns: 'left' | 'top' | 'data' | 'outside'

// Get points near pixel coordinates (Phase 2, requires spatial index)
const points = plotState.getPointsNear(canvasX, canvasY, radius);
// Returns: array of point objects
```

---

## Testing

**Phase 1 (Mock Mode)** — Ready to test:

```bash
cd apps/step_viewer
flutter run -d chrome --web-port 8080
```

Expected behavior:
- 10×10 facet grid
- 50K blue points (mock data)
- Shift+wheel zoom: cells grow/shrink
- Plain wheel: vertical scroll
- Ctrl+wheel: horizontal scroll
- Ctrl+drag: pan
- Double-click: reset view
- All changes animated (200ms)

**Phase 2 (Real WASM)** — Infrastructure ready, needs:
1. CubeQuery lifecycle (exists in GgrsServiceV3, currently disabled)
2. initPlotStream call (exists in interop, currently disabled)
3. Wire metadata from WASM to PlotState via setPlotMetadata
4. Replace streamMockData with streamData (WASM chunks)

---

## Next Steps (Phase 2)

1. **Enable CubeQuery**: Uncomment CubeQuery lifecycle in GgrsServiceV3
2. **Enable initPlotStream**: Call WASM to get real metadata
3. **Wire metadata**: Parse initPlotStream result, call setPlotMetadata
4. **Test with real Tercen**: Drop Y factor, verify facet grid renders
5. **Stream real data**: Replace ggrsV3StreamMockData with ggrsV3StreamData

---

## Benefits of This Refactor

1. **Single source of truth**: No more hunting for where axis ranges or facet labels live
2. **Clear lifecycle**: Metadata populated once, viewport updated by interactions
3. **Easy debugging**: Inspect `plotState` object to see entire plot configuration
4. **Fast interactions**: All queries are synchronous JS (no WASM boundary)
5. **Extensible**: Easy to add spatial index, facet label lookup, etc in Phase 2
6. **Testable**: Can mock PlotState in tests without touching WASM or GPU

---

## Migration Notes

**Removed:**
- ViewportState as standalone component (logic absorbed into PlotState)
- Scattered metadata locations

**Added:**
- PlotState class (centralized state)
- setPlotMetadata API (for Phase 2)

**Changed:**
- InteractionManager constructor: takes `plotState` instead of `viewportState`
- bootstrap_v3 creates PlotState instead of ViewportState
- All viewport/metadata queries go through PlotState

**Unchanged:**
- GgrsGpuV3 (WebGPU renderer)
- WASM interface (initPlotStream, loadDataChunk)
- Animation behavior (200ms ease-out cubic)
- Interaction patterns (Shift+wheel zoom, etc)
