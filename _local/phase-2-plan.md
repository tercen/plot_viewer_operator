# Phase 2: Per-Panel Data + Tile Cache

Goal: Stream data per-panel. Cache rendered panels. Scroll-back is instant.

## 2.1 WASM: Panel-local pixel mapping

In `load_and_map_chunk` (lib.rs ~lines 410-413), change from absolute to panel-local:

```rust
// Before (absolute canvas coords):
let px = am.px_left + (x - am.x_min) / x_range * (am.px_right - am.px_left);
let py = am.px_bottom - (y - am.y_min) / y_range * (am.px_bottom - am.px_top);

// After (panel-local coords):
let panel_w = am.px_right - am.px_left;
let panel_h = am.px_bottom - am.px_top;
let px = (x - am.x_min) / x_range * panel_w;
let py = panel_h - (y - am.y_min) / y_range * panel_h;
```

Points returned as `{panel_idx, px, py}` where px/py are relative to panel top-left (0,0).

## 2.2 WASM: Tile cache (`tile_cache.rs`, new file)

```rust
pub struct PanelTile {
    pub ci: usize,
    pub ri: usize,
    pub points: Vec<(f64, f64)>,  // panel-local (px, py)
    pub complete: bool,
}

pub struct TileCache {
    tiles: HashMap<(usize, usize), PanelTile>,
    access_order: VecDeque<(usize, usize)>,
    max_tiles: usize,  // default 50
}
```

New WASM exports:
- `hasCachedTile(ci, ri)` -> bool
- `getCachedTilePoints(ci, ri)` -> JSON array of panel-local points
- `invalidateTileCache()` — clears all tiles (called on binding change, zoom, resize)

After `loadAndMapChunk` streams a chunk, WASM partitions points by panel_idx and stores them in the tile cache. When all chunks are done for a panel, mark `complete = true`.

## 2.3 JS: Per-panel point upload in `ggrs_gpu.js`

New method `setViewportPoints(panels, options)`:
- Takes array of `{x_offset, y_offset, points: [{px, py}]}`
- Converts panel-local -> absolute: `px + x_offset`, `py + y_offset`
- Builds single GPU point buffer from all panels
- Replaces `_viewportPoints` (not additive — full replacement each time)

## 2.4 Dart: Scroll with tile cache

```dart
Future<void> renderViewport(PlotStateProvider state) async {
  // 1. Viewport chrome (same as Phase 1)
  final vpChrome = GgrsInterop.getViewportChrome(_renderer!, viewportJson);
  GgrsInterop.renderViewportChrome(containerId, vpChrome);

  // 2. Collect cached panel points + identify uncached panels
  final cachedPanels = <PanelData>[];
  final uncachedPanels = <(int ci, int ri)>[];

  for each visible (ci, ri):
    if GgrsInterop.hasCachedTile(ci, ri):
      cachedPanels.add(getTilePoints + panel offset from vpChrome)
    else:
      uncachedPanels.add((ci, ri))

  // 3. Render cached panels immediately (instant)
  GgrsInterop.setViewportPoints(containerId, cachedPanels, options);

  // 4. Stream data for uncached panels
  //    initPlotStream with viewport scoped to uncached panels only
  //    loadAndMapChunk loop — WASM caches tiles as they complete
  //    After each chunk: re-render all visible points (cached + newly streamed)
}
```

## 2.5 Test checkpoint

- Scroll down 1 row: 4 panels instant from cache, 1 panel streams
- Scroll back up: all 5 panels instant (previously-scrolled panel was cached)
- Rapid scroll (5 rows): generation counter cancels stale, final viewport renders
- Initial render (no cache): all panels stream as before, but tiles cached for future

## Files to modify

| File | Change |
|------|--------|
| `ggrs-wasm/src/lib.rs` | Panel-local pixel mapping in loadAndMapChunk. Add tile cache exports. |
| `ggrs-wasm/src/tile_cache.rs` | NEW. PanelTile, TileCache with LRU. |
| `ggrs_gpu.js` | Add setViewportPoints (panel-local → absolute conversion). |
| `bootstrap.js` | Window exports for tile cache APIs + setViewportPoints. |
| `ggrs_interop.dart` | Dart bindings for tile cache + setViewportPoints. |
| `ggrs_service.dart` | renderViewport with tile cache lookup before streaming. |
