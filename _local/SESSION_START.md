# Session Start — 2026-02-25

## What was done

### V2 GPU Named Layers + Interaction + Data Streaming

Continued from previous session's named-layer plan. Fixed grey-slab bug, implemented facet zoom/scroll interaction, re-enabled data streaming.

**Files changed:**

1. **`apps/step_viewer/web/ggrs/bootstrap_v2.js`**
   - Removed all `||` fallback defaults for cached theme colors (rule 01-no-fallbacks)
   - Fixed `_parseColor` to throw on unrecognized color instead of returning gray
   - Fixed chromeStyle caching: concatenate both `staticChrome` + `vpChrome` arrays before taking `[0]` (empty array is truthy, was blocking fallthrough)
   - Added `zoomStep()`: below 1px uses 20% of current power of 10; above 1px uses `max(1, sqrt(value))`
   - Fixed Shift+Wheel: browser swaps deltaY→deltaX when Shift held — now uses `e.deltaY !== 0 ? e.deltaY : e.deltaX`
   - Removed redundant `getMousePos()` call in wheel handler
   - Removed all debug `console.log` statements
   - Changed `_rebuildChromeForZoom` to throw (not silently return) when chromeStyle missing

2. **`apps/step_viewer/lib/services/ggrs_service_v2.dart`**
   - Uncommented data streaming block (lines 185-191): `streamAllData` with `radius: 2.5`, `fillColor: 'rgba(0,0,0,0.6)'`

## What needs testing

1. **Theme colors after zoom**: Does `_rebuildChromeForZoom` correctly use WASM theme colors? (grey slab issue was reported but may now be fixed with the array concatenation fix)
2. **Horizontal zoom via Shift+Wheel on top strip**: Verify the deltaX fix works across browsers
3. **Zoom at very small cell sizes**: Verify 20% power-of-10 step feels smooth
4. **Data points after zoom/scroll**: Verify points reproject correctly when cell size changes or scroll offset changes
5. **Double-click reset**: Verify returns to initial cell sizes and zero scroll

## Logical next steps

### 1. Verify theme colors after zoom
- Build and test with Grey theme
- If grey slab persists, inspect what `allGridLines[0]?.color` actually contains
- Files: `bootstrap_v2.js` lines 362-375

### 2. Cell width extends beyond viewport
- Initial `cellWidth` from WASM (~1800px) extends past visible container
- Need to account for label/tick space so cells fit within visible area
- Files: `bootstrap_v2.js` (`ggrsV2SetPanelLayout`), `ggrs_service_v2.dart` (panel params)

### 3. Color/shape/size aesthetic bindings
- Currently only x, y, row_facet, col_facet are wired
- UI: factor drop targets in step_viewer left panel
- `PlotStateProvider`: color/shape/size binding state
- `_buildInitConfig`: pass bound aesthetics to WASM

### 4. factor_nav → orchestrator wiring
- factor_nav (Phase 3 complete) not registered in `webapp_registry.dart` or `build_all.sh`
