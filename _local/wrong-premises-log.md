# Wrong Premises — Read Before Any GGRS Work

## The mistake (made 3+ times)
"GGRS WASM cannot make HTTP calls to Tercen" — WRONG. WASM uses browser Fetch API via web-sys.

## Rules that follow
- GGRS queries Tercen directly — Flutter does NOT fetch table data
- ALL data loading uses StreamGenerator trait (ggrs-core)
- WasmStreamGenerator (browser, HTTP+TSON via web-sys) and TercenStreamGenerator (server, gRPC) are the only data paths
- Flutter passes step info + bindings to GGRS. GGRS does the rest.
- Flutter's jobs: factor list UI, binding state, CubeQuery lifecycle (sci_tercen_client), render chrome/points that GGRS returns
- Flutter does NOT: fetch table data, fetch schema data, map columns, build data payloads, do pixel mapping
