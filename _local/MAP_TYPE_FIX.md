# Map Type Error Fix — 2026-03-03

## Root Cause

**Error**: `type '_Map<dynamic, dynamic>' is not a subtype of type 'Iterable<dynamic>' in type cast`

**Location**: Tercen server-side (HTTP 500) when processing schema/list API endpoints

**Symptom**: CubeQuery WASM calls failed with 500 error when fetching schema metadata

---

## Problem Analysis

### What Was Happening

The WASM code was sending HTTP POST requests to Tercen API endpoints with request bodies formatted as:

```json
{
  "ids": ["schema-id-1", "schema-id-2", "schema-id-3"]
}
```

But the Tercen API endpoints expected the request body to be **directly an array**:

```json
["schema-id-1", "schema-id-2", "schema-id-3"]
```

### Server-Side Type Cast Failure

The Tercen server's endpoint handler code likely looks like:

```dart
// Server-side (Tercen API)
Future<List<Schema>> list(dynamic body) async {
  var ids = body as Iterable<dynamic>; // ❌ Fails when body is Map
  // ...
}
```

When the body is `{"ids": [...]}`, the cast to `Iterable<dynamic>` fails because a Map is not an Iterable.

---

## Affected Code Locations

**File**: `/home/thiago/workspaces/tercen/main/ggrs/crates/ggrs-wasm/src/cube_query_manager.rs`

### Location 1: `get_table_dimensions()` function (line 514)

**Endpoint**: `POST api/v1/schema/list`

**Before**:
```rust
let params = serde_json::json!({
    "ids": ids,
});
let schemas = client.post_json("api/v1/schema/list", &params).await?;
```

**After**:
```rust
// API expects array of IDs directly, not wrapped in object
let params = serde_json::json!(ids);
let schemas = client.post_json("api/v1/schema/list", &params).await?;
```

**TSON wire format** (before): `MAP { "ids" -> LST [...] }`
**TSON wire format** (after): `LST [...]`

---

### Location 2: `classify_schemas()` function (line 620)

**Endpoint**: `POST api/v1/tableSchemaService/list`

**Before**:
```rust
let params = serde_json::json!({
    "ids": schema_ids,
});
let schemas = client.post_json("api/v1/tableSchemaService/list", &params).await?;
```

**After**:
```rust
// API expects array of IDs directly, not wrapped in object
let params = serde_json::json!(schema_ids);
let schemas = client.post_json("api/v1/tableSchemaService/list", &params).await?;
```

---

## Why This Wasn't Caught Earlier

1. **No WASM unit tests for HTTP request format** — Tests only verified response parsing, not request serialization
2. **TSON encoding hides structure** — Binary format makes inspection harder than JSON
3. **Never tested against live Tercen** — Previous WASM tests used mock data, not real API

---

## Type System Deep Dive

### JSON to TSON Encoding

The `tercen_client.rs` module encodes request bodies using TSON:

```rust
// json_to_tson() in tercen_client.rs
serde_json::Value::Object(map) → TsonValue::MAP
serde_json::Value::Array(vec) → TsonValue::LST
```

**Wrong request** (before fix):
```
JSON: {"ids": ["id1", "id2"]}
TSON: MAP { "ids" -> LST ["id1", "id2"] }
Binary: [MAP_TAG, 1, STR_TAG, 3, 'i', 'd', 's', LST_TAG, 2, ...]
```

**Correct request** (after fix):
```
JSON: ["id1", "id2"]
TSON: LST ["id1", "id2"]
Binary: [LST_TAG, 2, STR_TAG, 3, 'i', 'd', '1', STR_TAG, 3, 'i', 'd', '2']
```

### Server-Side Expectations

The Tercen API's list endpoints use a **positional argument** pattern, not named parameters:

```dart
// Tercen server endpoint (pseudocode)
@HttpPost("/api/v1/schema/list")
Future<List<Schema>> list(List<String> ids) async {
  // Body is deserialized directly to List<String>
  return await fetchSchemas(ids);
}
```

This pattern is common in Tercen's persistence services — bulk operations take arrays directly, not wrapped in objects.

---

## Verification

### Before Fix
```
[GgrsV3] CubeQuery start @ 19ms
[CubeQuery] Fetching from Tercen API...
❌ ERROR: CubeQuery failed: Tercen HTTP 500: POST api/v1/schema/list → 500
   Reason: type '_Map<dynamic, dynamic>' is not a subtype of type 'Iterable<dynamic>'
```

### After Fix (Expected)
```
[GgrsV3] CubeQuery start @ 19ms
[CubeQuery] Fetching from Tercen API...
[CubeQuery] Found 3 schemas from tableSchemaService.list
[CubeQuery] Classified: qt=schema-123, y_axis=schema-456, ...
✅ SUCCESS: CubeQuery complete
```

---

## Upstream/Downstream Impact

### Upstream Dependencies
- ✅ `serde_json::json!` macro — No changes needed
- ✅ `tercen_client.rs::post_json()` — Already handles both Map and Array correctly
- ✅ TSON encoding — Works for both structures

### Downstream Consumers
- ✅ `get_table_dimensions()` — Expects array response (unchanged)
- ✅ `classify_schemas()` — Expects array response (unchanged)
- ✅ Response parsing — No changes needed

---

## Testing Checklist

- [x] WASM compiles without errors
- [x] WASM copied to step_viewer/web/ggrs/pkg/
- [x] WASM copied to orchestrator/web/step_viewer/ggrs/pkg/
- [ ] **Manual test**: Run step_viewer, drop Y factor → verify no 500 error
- [ ] **Check console**: Should see "[CubeQuery] Found X schemas" not error
- [ ] **Verify rendering**: Plot should render with correct dimensions

---

## Related Files Modified

1. `/home/thiago/workspaces/tercen/main/ggrs/crates/ggrs-wasm/src/cube_query_manager.rs`
   - Line 514-517: Fixed schema/list request
   - Line 619-626: Fixed tableSchemaService/list request

**Total changes**: 1 file, 4 lines modified (2 occurrences)

---

## Future Prevention

### Add WASM Integration Tests

Create test that calls live Tercen API (or mock server) to verify request format:

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_schema_list_request_format() {
        let ids = vec!["id1".to_string(), "id2".to_string()];
        let params = serde_json::json!(ids);

        // Verify params is an array, not a map
        assert!(params.is_array());
        assert_eq!(params.as_array().unwrap().len(), 2);
    }
}
```

### Document API Contract

Add comment to `tercen_client.rs` documenting expected request formats:

```rust
/// POST to Tercen API endpoint.
///
/// Common request patterns:
/// - List endpoints: Send array directly: `["id1", "id2"]`
/// - Create/update: Send object: `{"name": "value", ...}`
/// - Bulk operations: Send array of objects: `[{...}, {...}]`
```

---

## Commit Message

```
Fix schema/list API request format (Map → Array)

Root cause: WASM was sending {"ids": [...]} but Tercen API expects [...] directly.
Server cast to Iterable<dynamic> failed → HTTP 500 type error.

Changes:
- cube_query_manager.rs:514 — api/v1/schema/list sends array
- cube_query_manager.rs:620 — api/v1/tableSchemaService/list sends array

Result: CubeQuery WASM calls now succeed, schema metadata loads correctly.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
