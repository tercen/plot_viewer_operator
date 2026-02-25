# Init Session — Context Bootstrap

Invoke with `/init-session`. Run at the start of every working session.

---

## Steps

### 1. Read core context

Read these files in parallel:
- `CLAUDE.md` (project root)
- `.claude/rules/00-directives.md`
- `_local/wrong-premises-log.md`
- `_local/SESSION_START.md`
- MEMORY.md at `/home/thiago/.claude/projects/-home-thiago-workspaces-tercen-main-plot-viewer-operator/memory/MEMORY.md`

### 2. Identify next work

From SESSION_START.md, read the "Logical next steps" section. Pick the top item unless the user specifies otherwise.

### 3. Load working knowledge

For the identified next step, read all files listed in SESSION_START.md under "What was done" that are relevant to that step. Also read any files explicitly referenced in the next step description.

If the next step involves:
- **GGRS WASM changes**: read `ggrs/crates/ggrs-wasm/src/lib.rs`, `ggrs/crates/ggrs-wasm/src/wasm_stream_generator.rs`
- **GGRS core changes**: read the specific file mentioned (e.g., `compute_layout.rs`, `engine.rs`, `stream/memory.rs`)
- **step_viewer Dart changes**: read `apps/step_viewer/lib/services/ggrs_service.dart`, `apps/step_viewer/lib/services/ggrs_interop.dart`
- **bootstrap.js changes**: read `apps/step_viewer/web/ggrs/bootstrap.js`
- **Orchestrator changes**: read `apps/orchestrator/lib/services/webapp_registry.dart`
- **New app work**: read that app's `docs/functional-spec.md` and `lib/main.dart`

### 4. Present summary to user

Output a brief summary:
```
Session initialized.

**Last session**: [one-line summary of what was done]
**Next step**: [the identified next task]
**Files loaded**: [list of files read]

Ready to proceed with [next step]. Confirm or redirect.
```

Wait for user confirmation before starting work.
