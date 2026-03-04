# Spec Traceability Matrix — Requirements to Implementation Mapping

**Invoke with**: `/spec-traceability-matrix` or when user asks to "check specs vs implementation", "verify requirements are met", "create traceability"

**Purpose**: Systematically map functional requirements from design documents/plans to actual implementation, identify gaps between "what we said we'd build" and "what actually exists".

---

## When to Use This Skill

Use this skill when:
- ✅ After completing a major feature or phase
- ✅ When code compiles but user questions if requirements are met
- ✅ Before declaring a feature "complete" or "ready for testing"
- ✅ When debugging why a feature "doesn't work" despite compiling
- ✅ During code reviews to verify spec compliance
- ✅ User asks "did we implement everything we planned?"

**Do NOT use** when:
- ❌ No spec/plan document exists (create spec first)
- ❌ Code doesn't compile yet (fix compilation first)
- ❌ Reviewing a single function in isolation (use code review)

---

## Step 1: Identify the Specification Source

Locate the document that defines **what should be built**:

**Common locations:**
- Implementation plans in `.claude/plans/*.md`
- Architecture docs in `docs/architecture-*.md`
- Functional specs in `docs/*-functional-spec.md`
- Phase plans in `docs/v3-implementation-complete.md`
- Task lists in plan files (Phase 1: Task 1.1, Task 1.2, etc.)

**What to look for:**
- Requirements stated as "must have", "shall implement", "feature includes"
- Task checklists with `[ ]` checkboxes
- "Subtasks" sections with specific deliverables
- "Verification" sections describing expected behavior
- API contracts ("WASM exports: initLayout, getLayoutState")

**Output**: Note the spec document path and section structure.

---

## Step 2: Extract All Requirements

Read the spec document and create a **flat list of requirements**. Each requirement should be:
- **Atomic** — Tests one specific thing
- **Verifiable** — Can check if it exists in code
- **Traceable** — Can map to specific file/line

**Extraction rules:**
1. Every task checklist item `- [ ] ...` is a requirement
2. Every "WASM exports: X, Y, Z" list becomes 3 requirements
3. Every "Component must do X, Y, Z" becomes 3 requirements
4. Architecture diagrams with boxes/arrows become requirements (e.g., "InteractionManager creates ZoomHandler")

**Output format** (spreadsheet-style):
```
| Req ID | Requirement | Source Location | Category |
|--------|-------------|-----------------|----------|
| R1.1   | LayoutState struct with canvas_width field | Plan: Phase 1, Task 1.1 | Data Structure |
| R1.2   | LayoutState struct with full_x_min/max fields | Plan: Phase 1, Task 1.1 | Data Structure |
| R1.3   | LayoutState.validate() returns Err on negative cell_width | Plan: Phase 1, Task 1.1 | Validation |
| R2.1   | InteractionHandler trait with on_start method | Plan: Phase 2, Task 2.1 | Interface |
| R2.2   | ZoomHandler responds to zone: left strip → Y only | Plan: Phase 2, Task 2.2 | Functionality |
| R2.3   | WASM export: interactionStart(handler_type, zone, ...) | Plan: Phase 2, Task 2.3 | API |
| R3.1   | RenderCoordinator with dependency checking | Plan: Phase 3, Task 3.3 | Architecture |
| R3.2   | ViewStateLayer depends on LayoutLayer | Plan: Phase 3, Task 3.2 | Dependency |
| ...    | ... | ... | ... |
```

**Categories** (for grouping):
- **Data Structure** — Structs, enums, fields
- **Interface** — Traits, abstract classes, method signatures
- **Functionality** — Behavior ("zoom maintains pixel gap", "pan clamps to range")
- **API** — Exported functions, public methods
- **Architecture** — Component relationships, flow control
- **Validation** — Error checking, constraints
- **Integration** — Cross-boundary wiring (Dart↔JS, JS↔WASM)

---

## Step 3: Verify Each Requirement

For **each requirement**, check implementation status:

### 3.1: Locate Implementation

Find the code that should implement this requirement:
- Search codebase for relevant keywords
- Check expected file paths from plan
- Use Grep/Glob to find structs/functions/methods

**Status codes:**
- ✅ **Implemented** — Code exists and appears correct
- ⚠️ **Partial** — Code exists but incomplete/incorrect
- ❌ **Missing** — No code found
- 🔄 **Deferred** — Explicitly documented as future work

### 3.2: Validate Correctness

For ✅ Implemented items, verify:
1. **Signature matches** — Function parameters, return types correct
2. **Behavior matches** — Logic does what spec describes
3. **Integration works** — Called by expected callers, calls expected dependencies
4. **Error handling exists** — Doesn't silently fail
5. **No fallbacks** — Doesn't use defaults instead of validation

**Common gaps to check:**
- Method exists but **parameters ignored** (zone detected but not used)
- Method exists but **always returns default** (validation that never fails)
- Method exported but **callers use wrong name** (typo, casing mismatch)
- Method exists in WASM but **TypeScript definition missing**
- Method called but **target object doesn't have it** (integration gap)

### 3.3: Document Gaps

For ⚠️ Partial or ❌ Missing items, describe the gap:

**Output format**:
```
| Req ID | Requirement | Status | Implementation Location | Gap | Priority |
|--------|-------------|--------|------------------------|-----|----------|
| R1.1   | LayoutState struct with canvas_width | ✅ Implemented | ggrs-core/src/layout_state.rs:15 | None | - |
| R1.2   | LayoutState.validate() on negative cell_width | ✅ Implemented | ggrs-core/src/layout_state.rs:45 | None | - |
| R1.3   | WASM export: getLayoutState | ❌ MISSING | lib.rs has NO such export | JS calls gpu.getLayoutState() which doesn't exist | P0 |
| R2.2   | ZoomHandler zone-aware (left→Y only) | ❌ BROKEN | zoom_handler.rs:46,58 | axis_from_zone() called, result IGNORED in zoom() call | P1 |
| R2.3   | WASM export: interactionStart | ✅ Implemented | lib.rs:405 | None | - |
| R3.2   | ViewStateLayer depends on LayoutLayer | ✅ Implemented | render_coordinator.js:149 | None | - |
| R3.3   | ViewStateLayer null-safe panels[0] | ❌ UNSAFE | render_coordinator.js:174 | No check if panels array empty | P0 |
```

---

## Step 4: Calculate Coverage Metrics

Aggregate results to show overall completion:

**Metrics to calculate:**
1. **Total requirements** — Count of all Req IDs
2. **Implemented** — Count of ✅ status
3. **Partial** — Count of ⚠️ status
4. **Missing** — Count of ❌ status
5. **Coverage %** — `(Implemented + Partial) / Total × 100`
6. **Correct %** — `Implemented / Total × 100`

**By category:**
```
| Category | Total | Implemented | Partial | Missing | Coverage % |
|----------|-------|-------------|---------|---------|------------|
| Data Structure | 12 | 12 | 0 | 0 | 100% |
| Interface | 8 | 8 | 0 | 0 | 100% |
| Functionality | 15 | 7 | 3 | 5 | 67% |
| API | 10 | 9 | 0 | 1 | 90% |
| Architecture | 6 | 5 | 1 | 0 | 100% |
| Validation | 5 | 2 | 0 | 3 | 40% |
| Integration | 8 | 3 | 1 | 4 | 50% |
| **TOTAL** | **64** | **46** | **5** | **13** | **80%** |
```

**By priority:**
```
| Priority | Count | Description |
|----------|-------|-------------|
| P0 | 2 | Will crash immediately |
| P1 | 5 | Feature doesn't work as designed |
| P2 | 3 | Works but has issues |
| P3 | 3 | Nice-to-have, defer to later phase |
```

---

## Step 5: Create Gap Analysis

For each gap (⚠️ Partial or ❌ Missing), provide:

### 5.1: Root Cause

Why does this gap exist?
- **Implementation incomplete** — Ran out of time, deprioritized
- **Integration failure** — Components built separately, not connected
- **Spec drift** — Code written but logic changed during implementation
- **Missing contract** — Caller assumes method exists, but implementer didn't know
- **Silent assumption** — Developer thought it was "obvious" and skipped it

### 5.2: Impact Assessment

What breaks because of this gap?
- **Blocks all usage** — P0, nothing works
- **Feature broken** — P1, specific functionality doesn't work
- **Reduced quality** — P2, works but poorly
- **Future debt** — P3, will need fixing eventually

### 5.3: Fix Recommendation

What needs to happen to close the gap?

**Output format**:
```
## Gap Analysis

### Gap 1: Missing gpu.getLayoutState()
**Requirements affected**: R1.3, R2.5, R3.8
**Root cause**: Integration failure — InteractionManager assumes method exists, but GgrsGpuV3 doesn't export it
**Impact**: P0 — Zone detection crashes immediately, blocks ALL interactions
**Fix**:
- File: `ggrs_gpu_v3.js`
- Add method: `getLayoutState() { return this._layoutState; }`
- Estimated time: 5 minutes

### Gap 2: Zone-aware zoom not implemented
**Requirements affected**: R2.2
**Root cause**: Spec drift — axis_from_zone() written but result ignored in zoom() call
**Impact**: P1 — Zoom always affects both axes, left/top strip zones don't work as specified
**Fix**:
- File: `zoom_handler.rs:58`
- Change: `mgr.zoom(ZoomAxis::Both, direction)` → `mgr.zoom(self.axis.unwrap(), direction)`
- Estimated time: 2 minutes + rebuild WASM

### Gap 3: No coordinator generation counter
**Requirements affected**: R3.7
**Root cause**: Implementation incomplete — Dart has generation counter, coordinator doesn't
**Impact**: P1 — Stale renders can't be cancelled, wasted GPU cycles
**Fix**:
- File: `render_coordinator.js`
- Add field: `this.generation = 0`
- Add check in _renderLoop: `if (this.generation !== currentGen) return;`
- Estimated time: 15 minutes
```

---

## Step 6: Create Fix Plan

Organize gaps into a **prioritized execution plan**:

**Output format**:
```
## Fix Plan

### Step 1: P0 Blockers (Must fix before ANY testing)
**Goal**: Eliminate crashes
**Duration**: 30 minutes

1.1: Add gpu.getLayoutState() (5 min)
1.2: Add panels[0] null check (5 min)
1.3: Test: Drop Y factor, wheel event doesn't crash

### Step 2: P1 Critical Functionality (Must fix for correct behavior)
**Goal**: Features work as spec'd
**Duration**: 4 hours

2.1: Implement zone-aware zoom (15 min)
2.2: Add coordinator generation counter (20 min)
2.3: Optimize chrome rendering (shared cache) (1 hour)
2.4: Add validation (no silent fallbacks) (1.5 hours)
2.5: Test: All specified behaviors work

### Step 3: P2 High Priority (Quality improvements)
**Goal**: Production-ready quality
**Duration**: 3 hours

3.1: Complete DataLayer dependencies (10 min)
3.2: Wire zoom → chrome invalidation (30 min)
3.3: Add listener cleanup (20 min)
3.4: Add render timeout (20 min)
3.5: Test: No leaks, correct dependencies

### Total: 7.5 hours to close all P0/P1/P2 gaps
```

---

## Output Format

Create a markdown document with these sections:

1. **Requirements Table** (all requirements from spec)
2. **Implementation Status** (coverage by category)
3. **Gap Summary** (P0/P1/P2 counts)
4. **Gap Analysis** (detailed root cause + fix for each gap)
5. **Fix Plan** (prioritized steps with time estimates)
6. **Metrics** (coverage %, correct %, category breakdown)

Save to: `IMPLEMENTATION_TRACKER.md` or `_local/traceability-[feature]-[date].md`

---

## Cross-Phase Integration Checks

**Critical**: Some requirements span multiple phases. Check these explicitly:

### Requirement: "Zone-aware zoom"
- **Phase 1** (LayoutManager): zoom(axis) must support X, Y, Both
- **Phase 2** (ZoomHandler): axis_from_zone() must map zone to axis
- **Phase 2** (ZoomHandler): on_start() must USE the mapped axis
- **Phase 2** (InteractionManager): detectZone() must work
- **Phase 1** (GgrsGpuV3): getLayoutState() must exist for zone detection

**If ANY piece missing → feature broken**

### Requirement: "Cancellable renders"
- **Phase 3** (Dart): generation counter increments on new render
- **Phase 3** (Dart): _checkGen() throws on mismatch
- **Phase 3** (Coordinator): generation counter + check in loop
- **Phase 3** (Coordinator): cancelRender() method for Dart to call

**If Dart has it but Coordinator doesn't → gap**

---

## Success Criteria

A complete traceability matrix should:
- ✅ Map EVERY requirement from spec to code (or gap)
- ✅ Include file:line locations for implemented items
- ✅ Identify root cause for each gap
- ✅ Provide actionable fixes with time estimates
- ✅ Calculate coverage metrics
- ✅ Prioritize gaps by impact (P0/P1/P2)

**Red flags** (incomplete traceability):
- ❌ "Mostly implemented" without specific gap list
- ❌ 100% coverage but features don't work (false positive)
- ❌ No cross-phase integration checks
- ❌ No time estimates for fixes
- ❌ No priority levels (can't decide what to fix first)

---

## Tips

1. **Be pedantic** — If spec says "must validate X", check that validation actually fails on bad X (don't assume)

2. **Check boundaries** — Requirements that span Dart/JS/WASM are where gaps hide

3. **Test the contract** — If API says "export getLayoutState()", verify callers can actually call it

4. **Don't accept "close enough"** — If spec says "left strip → Y only" but code always zooms both, that's ❌ Missing, not ⚠️ Partial

5. **Trace dependencies** — If Req A depends on Req B, verify B is implemented before marking A as working

6. **Update as you go** — When fixing gaps, mark them ✅ Implemented with commit hash

---

## When Matrix is Complete

Present to user:
1. **Coverage %** — How much of spec is implemented
2. **Gap count** — Total P0/P1/P2 issues
3. **Fix effort** — Total hours to close gaps
4. **Recommendation** — Fix now vs defer vs re-scope

User decides based on:
- **Coverage < 70%** → Major gaps, consider re-scoping
- **Coverage 70-90%** → Solid foundation, fix gaps incrementally
- **Coverage > 90%** → Nearly done, fix remaining gaps and ship
- **P0 count > 0** → MUST fix before any testing
- **P1 count > 5** → Core functionality broken, don't ship

---

## Example Output Structure

```markdown
# V3 Implementation Traceability Matrix

**Date**: 2026-02-27
**Spec Source**: `.claude/plans/idempotent-leaping-hennessy.md`
**Coverage**: 80% (51/64 requirements)

---

## Phase 1: Layout Module

| Req ID | Requirement | Status | Location | Gap | Priority |
|--------|-------------|--------|----------|-----|----------|
| R1.1   | LayoutState struct | ✅ | layout_state.rs:10 | None | - |
| R1.2   | getLayoutState export | ❌ | Missing | Called but not exported | P0 |

**Phase 1 Coverage**: 85% (11/13)

---

## Phase 2: Interaction Abstraction

| Req ID | Requirement | Status | Location | Gap | Priority |
|--------|-------------|--------|----------|-----|----------|
| R2.1   | InteractionHandler trait | ✅ | interaction.rs:15 | None | - |
| R2.2   | Zone-aware zoom | ❌ | zoom_handler.rs:58 | Axis ignored | P1 |

**Phase 2 Coverage**: 78% (18/23)

---

## Phase 3: Render Orchestration

[Similar structure]

---

## Gap Summary

**P0 Blockers**: 2 (gpu.getLayoutState missing, panels[0] unchecked)
**P1 Critical**: 5 (zone-aware zoom, generation counter, chrome redundancy, validation)
**P2 High**: 3 (incomplete dependencies, no invalidation wiring, listener leak)

---

## Fix Plan

### Step 1: P0 Blockers (30 min)
[Detailed fixes]

### Step 2: P1 Functionality (4 hours)
[Detailed fixes]

### Step 3: P2 Quality (3 hours)
[Detailed fixes]

**Total**: 7.5 hours to close all gaps

---

## Recommendation

Execute all 3 steps (7.5 hours). Architecture is solid, gaps are small and fixable.
```
