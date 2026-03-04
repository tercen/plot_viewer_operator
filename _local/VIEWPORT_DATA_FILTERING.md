# Viewport-Aware Data Filtering Implementation

**Date:** 2026-03-03
**Status:** ✅ Complete and wired to UI (viewport-aware loading active)

## Overview

Implemented unified `query_data()` interface across the StreamGenerator trait that allows efficient viewport-aware data fetching. The system can now load only the data for visible facets instead of the entire grid.

## Architecture

### DataFilter Structure

The StreamGenerator trait already had a `query_data(data_range: Range, filter: Option<&DataFilter>)` method with:

```rust
pub struct DataFilter {
    pub facet: Option<FacetFilter>,
    pub spatial: Option<SpatialFilter>,
}

pub struct FacetFilter {
    pub col_range: Option<(usize, usize)>,  // Which columns (panels)
    pub row_range: Option<(usize, usize)>,  // Which rows (panels)
}

pub struct SpatialFilter {
    pub x_column: String,
    pub x_min: Option<f64>,  // Axis value range (not panel range)
    pub x_max: Option<f64>,
    pub y_column: String,
    pub y_min: Option<f64>,
    pub y_max: Option<f64>,
}
```

### Key Distinction: Facet Ranges vs Axis Ranges

- **Facet ranges** (`FacetFilter`): Which panels in the spatial grid to query (e.g., columns 0-5, rows 0-5)
- **Axis ranges** (`SpatialFilter`): Which data values to return based on axis scales (e.g., x between 25 and 75)

Both are independent filters that can be combined.

## Implementation Details

### 1. Rust WASM Layer

**File:** `/home/thiago/workspaces/tercen/main/ggrs/crates/ggrs-wasm/src/mock_stream_generator.rs`

- Added `generate_chunk_filtered()` method with optional filtering
- Overrode `query_data()` to generate ONLY filtered data (not post-filter)
- Efficient implementation: filters during generation, not after

**File:** `/home/thiago/workspaces/tercen/main/ggrs/crates/ggrs-wasm/src/lib.rs`

- Updated `loadDataChunk` signature: `pub async fn load_data_chunk(&self, chunk_size: u32, filter_json: Option<String>)`
- Added `parse_data_filter()` helper function to parse JSON into DataFilter struct
- Changed from `query_data_multi_facet(range)` to `query_data(range, filter.as_ref())`

### 2. JavaScript Bootstrap Layer

**File:** `apps/step_viewer/web/ggrs/bootstrap_v3.js`

Updated `ggrsV3StreamData()`:
```javascript
async ggrsV3StreamData(containerId, chunkSize = 15000, filter = null) {
  const filterJson = filter ? JSON.stringify(filter) : null;
  // ...
  const resultJson = await instance.renderer.loadDataChunk(chunkSize, filterJson);
}
```

### 3. Dart Interop Layer

**File:** `apps/step_viewer/lib/services/ggrs_interop_v3.dart`

Updated `streamData()`:
```dart
static Future<void> streamData(
  String containerId, {
  int chunkSize = 15000,
  Map<String, dynamic>? filter,
}) async {
  final promise = fn.callAsFunction(
    null,
    containerId.toJS,
    chunkSize.toJS,
    filter?.jsify(),
  ) as JSPromise;
}
```

## Usage Example

To load only the first 5×5 facets (25 out of 100 panels in a 10×10 grid):

```dart
final facetFilter = {
  'facet': {
    'col_range': [0, 5],  // Columns 0-4 (5 panels)
    'row_range': [0, 5],  // Rows 0-4 (5 panels)
  },
  'spatial': {
    'x_column': 'x',
    'x_min': null,  // No axis value filtering
    'x_max': null,
    'y_column': 'y',
    'y_min': null,
    'y_max': null,
  },
};

// For viewport-aware loading:
await GgrsInteropV3.streamMockData(
  containerId,
  chunkSize: 5000,
  facet_filter: facetFilter,
);

// Or for real data:
await GgrsInteropV3.streamData(
  containerId,
  chunkSize: 15000,
  facet_filter: facetFilter,
);

// For PNG export (load all facets):
await GgrsInteropV3.streamData(
  containerId,
  chunkSize: 15000,
  facet_filter: null,  // null = all facets
);
```

## Data Flow

1. **GgrsServiceV3:** Calculates viewport-based facet ranges (60% of grid: 6x6 facets of 10x10)
2. **Dart Interop:** Constructs facet_filter map with col_range/row_range
3. **JavaScript:** Converts to JSON string, passes to WASM
4. **WASM:** Parses JSON into DataFilter struct
5. **MockStreamGenerator:** Generates only data for specified facets (efficient, not post-filter)
6. **Return:** Only viewport points (e.g., 180K points for 36 facets instead of 500K for 100 facets)

## Performance Impact

**Before:** Loading all 500K points for 10×10 grid (100 facets)
- All data generated regardless of viewport
- Post-filtering happens client-side

**After:** Loading with 5×5 viewport (25 facets)
- Only 125K points generated (25% of data)
- Server-side filtering during generation
- 4× reduction in data transfer and processing

## PNG Export Use Case

The `facet_filter` parameter is essential for PNG export:

```dart
// During interactive viewing - load viewport only:
await GgrsInteropV3.streamMockData(
  containerId,
  chunkSize: 5000,
  facet_filter: currentViewportFilter,  // 6x6 facets
);

// During PNG export - load full dataset:
await GgrsInteropV3.streamMockData(
  containerId,
  chunkSize: 5000,
  facet_filter: null,  // null = all 100 facets
);
```

This allows the export function to render the complete plot with all data while maintaining viewport-aware loading during interactive use.

## Next Steps (Future Work)

1. **Dynamic viewport tracking:** Calculate visible facet range from scroll/zoom interactions
2. **Buffer zone:** Include +1 facet on each edge for smooth panning (7x7 instead of 6x6)
3. **Progressive loading:** Load visible facets first, then buffer zone in background
4. **Axis value filtering:** Add support for zoomed-in axis ranges (SpatialFilter with x_min/x_max)
5. **PNG export function:** Implement export that calls streamData with facet_filter: null

## Files Modified

- `/home/thiago/workspaces/tercen/main/ggrs/crates/ggrs-wasm/src/mock_stream_generator.rs` (added filtering)
- `/home/thiago/workspaces/tercen/main/ggrs/crates/ggrs-wasm/src/lib.rs` (parse_data_filter, updated loadDataChunk)
- `apps/step_viewer/web/ggrs/bootstrap_v3.js` (filter parameter)
- `apps/step_viewer/lib/services/ggrs_interop_v3.dart` (filter parameter)
- `apps/orchestrator/web/step_viewer/ggrs/bootstrap_v3.js` (copied from step_viewer)

## UI Integration

**Viewport calculation (GgrsServiceV3.dart):**
- Calculates viewport as 60% of total grid (e.g., 6x6 facets of 10x10 grid = 36 visible facets)
- Constructs facet_filter with col_range: [0, 6], row_range: [0, 6]
- Passes to `streamMockData()` or `streamData()`

**Parameter naming:**
- Renamed `filter` → `facet_filter` to distinguish from future use cases
- `facet_filter: null` loads all facets (useful for PNG export with full data)
- `facet_filter: {...}` loads only specified viewport facets

## Testing

**Current behavior:**
- Mock data: Loads 6×6 facets (36 panels) instead of 10×10 (100 panels)
- Data reduction: ~180K points loaded instead of 500K (64% reduction)
- Console log shows: "Streaming mock data with viewport filter: 6x6 facets (of 10x10)"

**To verify:**
1. Run `flutter run -d chrome` in apps/step_viewer
2. Check browser console for viewport filter message
3. Observe faster initial load (fewer points)
4. GPU should show points only in first 6 columns and 6 rows

## Notes

- The JavaScript MockStreamingRenderer (old JS mock) is now superseded by WASM MockStreamGenerator
- All StreamGenerator implementations should support the unified `query_data(range, filter)` interface
- Real data sources (WasmStreamGenerator with Tercen HTTP) will implement the same filtering
- Filter is completely optional — passing null loads all data (current behavior)
