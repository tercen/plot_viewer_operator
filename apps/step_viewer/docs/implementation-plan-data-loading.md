# Step Viewer — Data Loading Implementation Plan

## Problem Statement

The step_viewer's data loading diverges from the reference implementation (`ggrs_plot_operator`, the PNG/Rust path). Both paths should load data identically — only the rendering target differs (GGRS WASM vs PNG). Currently:

- X domain table is never discovered — code assumes `.minX`/`.maxX` live in the y_domain table
- Table discovery uses column-name heuristics instead of `queryTableType`
- No color support at all
- Facet range replication is broken for multi-panel scenarios
- Y-only x range is 0-indexed instead of 1-indexed

This plan aligns the Flutter data-loading pipeline with the Rust operator's, using a single unified discovery pass.

---

## Reference Architecture (ggrs_plot_operator)

### Table Sources

Tables come from TWO places — not all use discovery:

| Source | Tables | How found |
|--------|--------|-----------|
| **CubeQuery fields** (direct) | qt (`qtHash`), column facets (`columnHash`), row facets (`rowHash`) | Read directly from `CubeQuery` object |
| **schemaIds discovery** (search) | y_domain, x_domain, color_0..N | Loop through `schemaIds`, skip known tables, check `queryTableType` |

**Facets do NOT use discovery.** They come directly from `CubeQuery.columnHash` / `CubeQuery.rowHash`. These are the "known tables" that get *skipped* during domain/color discovery.

### Discovery: One Pass, Categorize All

The Rust operator makes one pass through `schemaIds`, skipping the 3 known tables, and categorizes each remaining table by `CubeQueryTableSchema.queryTableType`:

| `queryTableType` | Variable | Contains |
|---|---|---|
| `"y"` | `y_axis_table_id` | `.minY`, `.maxY`, optionally `.ci`, `.ri`, `.minX`, `.maxX` |
| `"x"` | `x_axis_table_id` | `.minX`, `.maxX`, optionally `.ci` |
| `"color_N"` | `color_table_ids[N]` | Category labels for color factor N |

### Loading Order (after discovery)

```
1. Facet counts    — schema.nRows from columnHash + rowHash (needed for range replication)
2. Y-axis ranges   — from y_domain table → cellRanges map
3. X-axis ranges   — from x_domain table if y_domain lacked .minX/.maxX
                     OR sequential [1.0, nRows] for y-only
4. Facet labels    — from columnHash + rowHash tables
5. Color labels    — from color_N tables (categorical)
6. Data streaming  — chunked from qt table (.ci, .ri, .x, .y, .colorLevels)
```

### Key Rules from Rust Operator

1. **Facet replication** — Ranges replicate based on which index columns are present:
   - Both `.ci` + `.ri` → per-cell
   - `.ri` only → per-row (replicate to all columns)
   - `.ci` only → per-column (replicate to all rows)
   - Neither → global (replicate to all cells)

2. **Y-only sequential x** — `[1.0, nRows]` (1-indexed, not 0-indexed)

3. **X ranges in y_domain are opportunistic** — The y_domain table MAY contain `.minX`/`.maxX`. If present, use them. If absent, check x_domain table. If no x_domain and x is unbound, use sequential range.

4. **Colors pre-computed** — Operator maps `.colorLevels` (categorical index) to RGB during streaming, not during rendering.

---

## Current State

### Working
- CubeQuery lifecycle (5A/5B/5C) → `CubeQueryResult` with `schemaIds`
- Y-domain discovery (by `.minY` column name — wrong method, right result for y-only)
- Facet label fetch from hash tables
- Chunked qt data fetch (`.ci`, `.ri`, `.x`, `.y`)
- 4-phase progressive render (chrome → metadata → real axes → chunked data)
- Y-only binding end-to-end

### Broken / Missing
- X domain table: never discovered, code assumes `.minX`/`.maxX` in y_domain
- Discovery method: column-name heuristic instead of `queryTableType`
- Facet replication: defaults to cell (0,0) when `.ci`/`.ri` absent
- Y-only x range: 0-indexed instead of 1-indexed
- Color: completely absent (no state, no discovery, no data, no rendering)

---

## Implementation Plan

### Step 1: Single-Pass Table Discovery

**File:** `table_data_service.dart`

Replace `_findYDomainTable()` with a single discovery pass that classifies ALL unknown tables at once. This avoids multiple passes through schemaIds and matches the Rust operator's approach.

```dart
/// Result of discovering domain and color tables from schemaIds.
class DiscoveredTables {
  final String? yDomainId;
  final String? xDomainId;
  final Map<int, String> colorTableIds; // color index → schema ID
}

/// One pass through schemaIds, skip known tables, classify by queryTableType.
Future<DiscoveredTables> _discoverTables(
  List<String> schemaIds,
  Set<String> knownIds,
) async {
  String? yDomainId;
  String? xDomainId;
  final colorTableIds = <int, String>{};

  for (final id in schemaIds) {
    if (id.isEmpty || knownIds.contains(id)) continue;
    final schema = await _factory.tableSchemaService.get(id);
    if (schema is! CubeQueryTableSchema) continue;

    final type = schema.queryTableType;
    if (type == 'y') {
      yDomainId = id;
    } else if (type == 'x') {
      xDomainId = id;
    } else if (type.startsWith('color_')) {
      final idx = int.tryParse(type.substring(6));
      if (idx != null) colorTableIds[idx] = id;
    }
  }

  return DiscoveredTables(
    yDomainId: yDomainId,
    xDomainId: xDomainId,
    colorTableIds: colorTableIds,
  );
}
```

**Deletes:** `_findYDomainTable()`

**Adds to `CubeQueryResult`:**
```dart
Set<String> get knownTableIds => {qtHash, columnHash, rowHash};
```

### Step 2: Restructure `fetchMetadata()` — Two-Phase Range Loading

**File:** `table_data_service.dart`

The current `fetchMetadata()` does everything in one tangled pass. Restructure to match the Rust operator's loading order:

**Step 2a: Facet counts first**

Need `nColFacets` and `nRowFacets` before loading ranges (for replication). Get them from hash table schemas:

```dart
final nColFacets = cqResult.columnHash.isNotEmpty
    ? (await _factory.tableSchemaService.get(cqResult.columnHash)).nRows
    : 1;
final nRowFacets = cqResult.rowHash.isNotEmpty
    ? (await _factory.tableSchemaService.get(cqResult.rowHash)).nRows
    : 1;
```

**Step 2b: Y-axis ranges from y_domain table**

Fetch `.minY`, `.maxY` (required), `.ci`, `.ri` (optional), `.minX`, `.maxX` (optional).

Store x as `double.nan` when `.minX`/`.maxX` are absent — this is the signal that x ranges need a second source. Matches the Rust operator's approach.

**Step 2c: Facet replication during y_domain loading**

Replace the current default-to-(0,0) logic with proper replication:

```dart
void _insertWithReplication(
  Map<(int, int), (double, double, double, double)> cellRanges,
  int ci, int ri,
  bool hasCi, bool hasRi,
  int nColFacets, int nRowFacets,
  (double, double, double, double) range,
) {
  if (hasCi && hasRi) {
    cellRanges[(ci, ri)] = range;
  } else if (hasRi && !hasCi) {
    for (int c = 0; c < nColFacets; c++) cellRanges[(c, ri)] = range;
  } else if (hasCi && !hasRi) {
    for (int r = 0; r < nRowFacets; r++) cellRanges[(ci, r)] = range;
  } else {
    for (int c = 0; c < nColFacets; c++) {
      for (int r = 0; r < nRowFacets; r++) cellRanges[(c, r)] = range;
    }
  }
}
```

**Step 2d: X-axis ranges (conditional)**

After y_domain loading, check if any x range is NaN:

```dart
final needsXRange = cellRanges.values.any((r) => r.$1.isNaN || r.$2.isNaN);

if (needsXRange) {
  if (discovered.xDomainId != null) {
    await _loadXRangesFromTable(discovered.xDomainId!, cellRanges, nColFacets, nRowFacets);
  } else if (xColumn == null) {
    _setSequentialXRanges(cellRanges, nRows);  // [1.0, nRows]
  } else {
    throw StateError('X is bound but no x_domain table found in schemaIds');
  }
}
```

**New method `_loadXRangesFromTable()`:**

Fetches `.minX`, `.maxX`, optionally `.ci` from the x_domain table. Merges into existing `cellRanges` — only updates the x portion (first two tuple elements), leaves y portion unchanged. Replicates per-column or globally based on `.ci` presence.

### Step 3: Fix Y-Only X Range (1-Indexed)

Embedded in Step 2. Three touch points:

| Location | Current | Fixed |
|----------|---------|-------|
| `_setSequentialXRanges()` | `(0.0, (nRows-1).toDouble())` | `(1.0, nRows.toDouble())` |
| `fetchDataChunk()` auto-gen x | `(offset + i).toDouble()` | `(offset + i + 1).toDouble()` |
| `_buildMetadataPayload()` y-only | `(nRows - 1).clamp(1.0, ...)` | `nRows.toDouble()` |

### Step 4: Add `PlotMetadata` Fields for Discovery Results

Extend `PlotMetadata` to carry the discovered table info and color metadata so it can be used downstream by the render pipeline:

```dart
class PlotMetadata {
  // Existing
  final Map<(int, int), (double, double, double, double)> cellRanges;
  final Map<int, String> colLabels;
  final Map<int, String> rowLabels;
  final int nRows;

  // New
  final int nColFacets;
  final int nRowFacets;
  final Map<int, List<String>> colorCategoryLabels; // color_N index → labels
}
```

### Step 5: Color Binding State

**File:** `plot_state_provider.dart`

Add `_colorBinding` field, wire into `setBinding()` / `clearBinding()` / `clearAll()`.

### Step 6: Color Data in Chunks

**File:** `table_data_service.dart`

Modify `fetchDataChunk()` to accept an optional `colorColumn` parameter. When present, fetch `.colorLevels` from the qt table:

```dart
if (colorColumn != null) cols.add('.colorLevels');
```

Return type gains `List<int>? colorLevels`.

### Step 7: Color Mapping in Render Pipeline

**File:** `ggrs_service.dart`

Thread color through all 4 phases:

- **Phase 2:** `fetchMetadata()` already discovers color tables via the single-pass. Color category labels loaded from `color_0` table.
- **Phase 3:** `_buildMetadataPayload()` sets color binding to `'bound'` when `colorColumn != null`
- **Phase 4:** `fetchDataChunk()` returns `.colorLevels`, `_mapChunkToPixels()` maps each index to an RGB color from a categorical palette, each pixel gets a `fillColor`.

**Color → RGB mapping:**

The Rust operator reads palette info from the workflow step model. For an initial implementation, use a fixed categorical palette (matching the Tercen default). The palette maps level index → RGB.

Need to verify whether `renderDataPoints` WASM API supports per-point `fillColor`. If not, batch points by color and call once per group with a shared `fillColor` in the style object.

### Step 8: Color Drop Zone in UI

**File:** `drop_zone.dart` (and surrounding widget tree)

Add "Color" alongside existing X, Y, Row Facet, Col Facet drop zones. Connects to `PlotStateProvider.setBinding('color', factor)`.

---

## Unified Code Path Summary

The data loading pipeline mirrors the Rust operator exactly:

```
                  Rust operator (PNG)              Flutter step_viewer
                  ─────────────────              ──────────────────────
Discovery         find_y/x/color_tables()    →   _discoverTables() [single pass]
Facets from       CubeQuery.column_hash/         CubeQuery.columnHash/
                  row_hash (direct)               rowHash (direct)
Facet counts      schema.nRows                →   schema.nRows
Y ranges          load_axis_ranges_from_table →   _loadYRanges() in fetchMetadata
X ranges          load_x_ranges_from_table    →   _loadXRangesFromTable()
Sequential x      set_sequential_x_ranges     →   _setSequentialXRanges()
Facet replication  match (has_ci, has_ri)      →   _insertWithReplication()
Color labels      find_color_tables + fetch   →   _discoverTables + fetch from color_N
Data streaming    stream_bulk_data (TSON)      →   fetchDataChunk (tableSchemaService.select)
Color mapping     add_color_columns            →   color palette lookup in _mapChunkToPixels
                  ↓                               ↓
Output            PNG via GGRS core            →   Pixels via GGRS WASM renderDataPoints
```

The only divergence is the rendering target. Data loading, discovery, range computation, facet replication, and color mapping are structurally identical.

---

## Execution Order

| Batch | Steps | Fixes |
|-------|-------|-------|
| **1** | 1 + 2 + 3 + 4 | X+Y binding, proper discovery, facet replication, y-only 1-indexed |
| **2** | 5 + 6 + 7 | Color state + data + mapping |
| **3** | 8 | Color UI |

Batch 1 is the immediate priority — it fixes the broken X+Y binding.

---

## Testing Checkpoints

### After Batch 1 (axis ranges):
- [ ] Y-only binding renders (regression), x axis now shows 1..nRows instead of 0..nRows-1
- [ ] X+Y binding renders with correct x axis range from x_domain table
- [ ] `debugPrint` shows discovered tables: `y_domain=<id> (queryTableType=y), x_domain=<id> (queryTableType=x)`
- [ ] Col facet: ranges replicated per-column (same y range across all columns)
- [ ] Row facet: ranges replicated per-row (same x range across all rows)
- [ ] Col + Row facet: per-cell ranges from y_domain
- [ ] No facets: global range replicated to single cell (0,0)

### After Batch 2 (colors):
- [ ] Categorical color: points colored by `.colorLevels` index
- [ ] Color labels loaded from color_0 table
- [ ] No color bound: single default color (current behavior preserved)

### After Batch 3 (UI):
- [ ] Color drop zone appears, user can assign a factor
- [ ] Clearing color reverts to single-color rendering

---

## Files Modified

| File | Batch | Changes |
|------|-------|---------|
| `services/table_data_service.dart` | 1, 2 | Replace `_findYDomainTable` with `_discoverTables`; restructure `fetchMetadata` with facet-count-first + two-phase range loading + replication; add `_loadXRangesFromTable`; fix y-only 1-indexed; add color label loading; add `colorColumn` to `fetchDataChunk` |
| `services/cube_query_service.dart` | 1 | Add `knownTableIds` getter on `CubeQueryResult` |
| `services/ggrs_service.dart` | 1, 2 | Fix `_buildMetadataPayload` y-only range; thread color through phases; per-point color in `_mapChunkToPixels` |
| `presentation/providers/plot_state_provider.dart` | 2 | Add `_colorBinding` |
| `presentation/widgets/drop_zone.dart` | 3 | Add Color drop zone |

---

## Open Questions

1. **`renderDataPoints` per-point color** — Does the WASM API accept `fillColor` per-point in the pixel array, or only as a shared style? If shared-only, batch points by color level and call once per group.

2. **Continuous color** — The Rust operator supports Jet/Ramp/Category palettes with quartile rescaling. Categorical is sufficient for initial implementation. Continuous can be added later following the same pipeline (fetch factor column value instead of `.colorLevels`, interpolate against gradient).

3. **Multi-layer (`.axisIndex`)** — Rust operator supports N y-axis layers with per-layer color. Our step_viewer has single y binding. Out of scope for now.

4. **Legend** — Does GGRS WASM render legends from the payload's binding info, or do we need to render separately? If WASM handles it, just passing `color: {status: 'bound', column: name}` in the payload should suffice.
