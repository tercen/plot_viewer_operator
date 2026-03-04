# Session Start — 2026-03-03

## What was done

**Root cause analysis and fix for empty data points:**

1. **ggrs-wasm/src/mock_stream_generator.rs** (lines 49, 155-156)
   - Fixed column naming: `x`, `y` → `.x`, `.y`
   - Fixed aes mapping: `Aes::new().x(".x").y(".y")`
   - **Why**: load_data_chunk hardcodes `.x`/`.y` lookup, MockStreamGenerator was only generator using non-dotted names

2. **ggrs-wasm/src/lib.rs** (lines 1447-1505, 1587-1594)
   - Added filtered total calculation in load_data_chunk
   - `effective_total = total_rows × (active_facets / total_facets)`
   - **Why**: WASM was streaming full 500K dataset even when filtering to 6×6 facets (180K)

**Result:**
- Before: 100 chunks, 500K rows, 0 points (wrong columns)
- After: 36 chunks, 180K rows, 180K points (correct columns + filtered total)

## What needs testing

1. **Mock data rendering** (`flutter run -d chrome` in `apps/orchestrator/`)
   - Console should show: `Fetched chunk N: X/180000 rows` (not 500000)
   - Points should appear progressively during streaming
   - Final count: ~180K points rendered

2. **Real Tercen data** (with dart-defines)
   - Verify WasmStreamGenerator still works (already uses `.x`/`.y`)
   - Check that filtered streaming works with real data

3. **Different facet filters**
   - Test 3×3 (9 facets, 45K rows)
   - Test 10×10 (100 facets, 500K rows)
   - Verify chunk counts and point counts match expectations

## ⚠️ PRIORITY FOR NEXT SESSION

**User reported two critical issues:**

1. **Data points not appearing after scrolling** — Initial facets render correctly, but scrolling to new facets shows no points
   - Likely issue: Background facet loading (appendDataPoints) or viewport filter
   - Files to investigate:
     - `apps/step_viewer/lib/services/ggrs_service_v3.dart` (loadFacetsInBackground)
     - `apps/step_viewer/web/ggrs/bootstrap_v3.js` (viewport filter generation)
     - `apps/step_viewer/web/ggrs/plot_state.js` (checkAndLoadNewFacets)

2. **Data flow is confusing and needs simplification**
   - Current issues:
     - Hardcoded column lookups ignore aes mapping
     - Two data paths (Mock vs Wasm) with different patterns
     - No type enforcement for `.x`, `.y`, `.ci`, `.ri` contract
     - Filter semantics split between calculation and generation
   - User wants architectural review and simplification

## Logical next steps

1. **Debug scrolling issue** — Why new facets don't show points
   - Add logging to loadFacetsInBackground and appendDataPoints
   - Check if viewport filter is being constructed correctly
   - Verify background streaming returns points with correct columns
   - File: `apps/step_viewer/lib/services/ggrs_service_v3.dart`

2. **Test the column naming fix** — Verify initial render works
   - Expected: 36 chunks, ~180K points, no empty chunks
   - File: `apps/orchestrator/` → `flutter run -d chrome`

3. **Review and simplify data flow architecture** — HIGH PRIORITY
   - Map the full flow: Dart → JS → WASM → JS → GPU
   - Identify where aes mapping should be used vs hardcoded lookups
   - Propose simplifications:
     - Single column naming contract enforced by trait
     - Unified filter handling
     - Remove redundant code paths
   - Files: All data streaming code (lib.rs, mock_stream_generator.rs, bootstrap_v3.js, ggrs_service_v3.dart)

4. **Clean up diagnostic logging** — After debugging is complete
   - File: `apps/step_viewer/web/ggrs/bootstrap_v3.js` (lines ~545-587)

5. **Document column naming standard** — After architecture review
   - Why `.x`/`.y` with dots (dequantized data convention)
   - Where enforced (load_data_chunk, WasmStreamGenerator)
   - File: Create `docs/column-naming-standard.md`
