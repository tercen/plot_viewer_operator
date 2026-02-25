# End Session — Documentation Consolidation

Invoke with `/end-session`. Run at the end of every working session.

---

## Steps

### 1. Rule compliance audit

Check all files modified this session against `.claude/rules/00-directives.md`. For each changed file:
- Verify no directive violations (StreamGenerator trait, renderChrome ordering, error handling, app boundaries, styling)
- If violations found → document them in the output and fix immediately

### 2. Strip verbosity

In every file modified this session:
- Remove comments that restate what the code does
- Remove orphaned TODO/FIXME comments for work already completed
- Remove excessive debugPrint/eprintln unless behind a compile flag (`#[cfg(...)]`) and used by benchmarks
- Collapse multi-line doc comments to single-line where the function signature is self-explanatory
- Remove dead code, unused imports, unused variables

Do NOT remove: comments explaining *why* (not *what*), TIMEPROF behind `#[cfg(not(target_arch = "wasm32"))]` (used by bench_layout), doc comments on public API surfaces.

### 3. Update MEMORY.md

File: `/home/thiago/.claude/projects/-home-thiago-workspaces-tercen-main-plot-viewer-operator/memory/MEMORY.md`

- Add new stable patterns discovered this session
- Update status of ongoing work
- Remove entries that are no longer accurate
- Keep it under 200 lines

### 4. Write SESSION_START.md

File: `_local/SESSION_START.md` — **erase all existing content** before writing.

Structure:
```
# Session Start — YYYY-MM-DD

## What was done
[Concise list of changes with file paths. Include benchmark numbers if performance work was done.]

## What needs testing
[Specific test scenarios that haven't been verified yet.]

## Logical next steps
[Numbered list, most important first. Each item: what to do, why, which files.]
```

Rules:
- This file is read by Claude at session start — write for that audience
- Be specific: file paths, function names, line ranges
- No prose — bullet points and tables only
- Include benchmark before/after numbers if performance work was done

### 5. Verify builds

Run and confirm pass:
- `cargo test -p ggrs-core --lib` (if Rust files changed)
- `cargo test -p ggrs-wasm` (if WASM files changed)
- `wasm-pack build crates/ggrs-wasm --target web` (if WASM files changed)
- `cd apps/step_viewer && flutter analyze` (if Dart files changed)

Report any failures. Do NOT leave the session with broken builds.
