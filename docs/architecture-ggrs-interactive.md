# GGRS Rendering Architecture

Full WASM API reference: `ggrs/docs/WASM_API_REFERENCE.md`

## Data Flow Rule
Whoever renders queries the data. No double network trips.

| Mode | GGRS runs | Queries via | Data path |
|------|-----------|-------------|-----------|
| Raster (batch PNG) | Server | gRPC | Tercen → GGRS → PNG |
| Real-time (client) | Browser WASM | HTTP+TSON (web-sys) | Tercen → browser GGRS |
| Real-time (server) | Server | gRPC | Tercen → GGRS → DrawBatch → client |

## StreamGenerator Trait (ggrs-core)
ALL data loading goes through this. No exceptions.

```rust
pub trait StreamGenerator: Send + Sync {
    fn n_col_facets(&self) -> usize;
    fn n_row_facets(&self) -> usize;
    fn n_total_data_rows(&self) -> usize;
    fn query_col_facet_labels(&self) -> DataFrame;
    fn query_row_facet_labels(&self) -> DataFrame;
    fn query_x_axis(&self, col_idx: usize, row_idx: usize) -> AxisData;
    fn query_y_axis(&self, col_idx: usize, row_idx: usize) -> AxisData;
    fn query_data(&self, data_range: Range, facet_filter: Option<&FacetFilter>) -> DataFrame;
    fn n_data_rows(&self, facet_filter: Option<&FacetFilter>) -> usize;
    fn preferred_chunk_size(&self) -> Option<usize> { None }
}
```

| Impl | Location | Transport | Used by |
|------|----------|-----------|---------|
| InMemoryStreamGenerator | ggrs-core | In-memory | Tests |
| TercenStreamGenerator | ggrs_plot_operator | gRPC | Raster, server real-time |
| WasmStreamGenerator | ggrs-wasm | HTTP+TSON (web-sys) | Client real-time |

## TercenStreamGenerator (reference implementation)
- `new()` is async — pre-fetches metadata: facet labels, axis ranges, nRows
- `query_data_multi_facet()` makes network calls per chunk (block_in_place)
- `query_x_axis()` / `query_y_axis()` — sync, from pre-loaded cache
- Y-only: `set_sequential_x_ranges(1..n_rows)` when no x_axis_table
- `query_data_chunk()` panics — GGRS uses bulk mode only

## WasmStreamGenerator (browser implementation)
Same contract as TercenStreamGenerator. WASM constraint: browser HTTP is async but StreamGenerator methods are sync.

Solution: two-phase approach.
1. Async init: fetch metadata (facet labels, axis ranges, nRows) + discover domain tables from schemaIds
2. Async chunked loading: fetch qt data in chunks, accumulate in memory
3. Sync trait methods: answer from cached metadata + accumulated data

## Rendering Pipeline
```
Flutter: CubeQuery lifecycle → schemaIds
WASM:   initPlotStream(config + schemaIds)
          → WasmStreamGenerator.init() [async: metadata + domain discovery]
          → PlotGenerator::new() [sync: trains scales from axis ranges]
        getStreamLayout(w, h)
          → compute_layout_info() → LayoutInfo JSON
        loadAndMapChunk(chunk_size) [repeat until done]
          → fetch qt chunk [async]
          → dequantize + pixel map + cull [sync]
          → return pixel points
Flutter: renderChrome(layout) → renderDataPoints(chunk) [additive, progressive]
```

## CubeQuery schemaIds
| Index | Table | Content |
|-------|-------|---------|
| 0 | qt_hash | Main quantized data |
| 1 | column_hash | Column facet summary |
| 2 | row_hash | Row facet summary |
| 3 | y_axis | Y domain values |
| 4 | x_axis | X domain values (if x bound) |
| 5+ | color_N | Color mapping per layer |

Flutter passes raw schemaIds + known IDs (qt, col, row) to WASM. WASM discovers domain table types via queryTableType.

## Client vs Server Decision
Large data: transferring raw data to browser too slow. Server-side GGRS processes locally, applies culling, sends only visible draw commands (10-50x reduction).
