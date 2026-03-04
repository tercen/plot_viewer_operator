# Viewport-Aware Data Filtering - UI Wiring Complete

**Date:** 2026-03-03
**Status:** ✅ Wired to UI and active

## Changes Made

### 1. Parameter Rename: `filter` → `facet_filter`

Renamed across all layers to distinguish from future use cases and clarify purpose for PNG export:

- **Dart Interop:** `GgrsInteropV3.streamMockData()` and `streamData()`
- **JavaScript:** `ggrsV3StreamMockData()` and `ggrsV3StreamData()`
- **WASM:** Parameter passed as `filter_json` (internal naming unchanged)

### 2. Updated streamMockData to Use WASM

**Before:** JavaScript `MockStreamingRenderer` class generated data client-side

**After:** WASM `MockStreamGenerator` with filter support
- Calls WASM `loadDataChunk(chunkSize, filterJson)` in loop
- Same architecture as `streamData()` for real data
- Supports viewport-aware filtering

### 3. UI Integration in GgrsServiceV3

Added viewport calculation and facet filter construction:

```dart
// Calculate viewport-based facet filter (60% of grid)
final totalCols = metadata['n_col_facets'] as int;
final totalRows = metadata['n_row_facets'] as int;
final viewportCols = (totalCols * 0.6).ceil(); // 6 of 10
final viewportRows = (totalRows * 0.6).ceil(); // 6 of 10

final facetFilter = {
  'facet': {
    'col_range': [0, viewportCols],
    'row_range': [0, viewportRows],
  },
  'spatial': {
    'x_column': 'x',
    'x_min': null,
    'x_max': null,
    'y_column': 'y',
    'y_min': null,
    'y_max': null,
  },
};

await GgrsInteropV3.streamMockData(
  containerId,
  chunkSize: 5000,
  facet_filter: facetFilter,
);
```

## Viewport Strategy

**Initial viewport:** 60% of grid (6x6 facets of 10x10 = 36 visible panels)

**Reasoning:**
- Provides reasonable initial view without overwhelming GPU
- Leaves room for scroll buffer zones in future updates
- Balances data load vs visual coverage

**Data reduction:**
- Full grid: 500K points across 100 facets
- Viewport: ~180K points across 36 facets (64% reduction)

## Call Chain

```
GgrsServiceV3.render()
  ↓ calculates viewport (6x6)
  ↓ builds facetFilter map
GgrsInteropV3.streamMockData(containerId, facet_filter: facetFilter)
  ↓ converts to JSObject
JavaScript ggrsV3StreamMockData(containerId, opts)
  ↓ extracts opts.facet_filter
  ↓ JSON.stringify(facet_filter)
WASM renderer.loadDataChunk(chunkSize, filterJson)
  ↓ parse_data_filter(json)
  ↓ DataFilter { facet: Some(...), spatial: Some(...) }
MockStreamGenerator.query_data(range, filter)
  ↓ generate_chunk_filtered(...)
  ↓ only generates points for col_range [0,6), row_range [0,6)
Returns { points: [...], done: bool, loaded: N, total: M }
  ↓ back through JS/Dart layers
GPU.setDataPoints(allPoints)
```

## PNG Export Pattern

The `facet_filter` parameter is kept optional specifically for PNG export:

```dart
// Interactive viewing:
streamMockData(containerId, facet_filter: viewportFilter)  // 36 facets

// PNG export:
streamMockData(containerId, facet_filter: null)  // all 100 facets
```

This allows:
- Fast interactive rendering with viewport subset
- Complete plot export with full dataset
- Single API for both use cases

## Console Output

When running with viewport filter, console shows:

```
[GgrsV3] Streaming mock data with viewport filter: 6x6 facets (of 10x10) @ XXXms
[bootstrap_v3] Streaming mock data, chunkSize=5000, filter=yes
[bootstrap_v3] Mock chunk 1: 5000/180000 rows
[bootstrap_v3] Mock chunk 2: 10000/180000 rows
...
[bootstrap_v3] Mock streaming complete: 180000 points in 36 chunks
```

## Files Modified

1. **apps/step_viewer/lib/services/ggrs_service_v3.dart**
   - Added viewport calculation (60% of grid)
   - Builds facetFilter map with col_range/row_range
   - Passes to streamMockData()

2. **apps/step_viewer/lib/services/ggrs_interop_v3.dart**
   - Renamed `filter` → `facet_filter` in streamMockData()
   - Renamed `filter` → `facet_filter` in streamData()
   - Updated documentation with PNG export use case

3. **apps/step_viewer/web/ggrs/bootstrap_v3.js**
   - Rewrote ggrsV3StreamMockData to use WASM loadDataChunk
   - Added facet_filter parameter extraction from opts
   - Removed dependency on JavaScript MockStreamingRenderer
   - Updated ggrsV3StreamData parameter name to facet_filter

4. **apps/orchestrator/web/step_viewer/ggrs/bootstrap_v3.js**
   - Copied from step_viewer (same changes)

5. **_local/VIEWPORT_DATA_FILTERING.md**
   - Updated status: "Complete and wired to UI"
   - Added UI Integration section
   - Added PNG Export use case
   - Updated examples with facet_filter naming

## Testing

Run step_viewer and verify:
1. Console shows "viewport filter: 6x6 facets (of 10x10)"
2. Only first 6 columns and 6 rows have data points
3. Columns 7-10 and rows 7-10 are empty (no data loaded)
4. Initial load is faster (180K vs 500K points)

## Future Work

- Dynamic viewport tracking from scroll/pan interactions
- Buffer zones (+1 facet on each edge)
- Progressive loading (visible first, buffer second)
- Axis value filtering (SpatialFilter with zoom)
- PNG export function implementation
