# Use Case Review — Code Verification Through User Flows

**Invoke with**: `/use-case-review` or when user asks to "review code with use cases", "trace user interactions", "verify flows"

**Purpose**: Verify implementation correctness by tracing actual user interaction scenarios through the codebase, exposing integration gaps that compilation checks miss.

---

## When to Use This Skill

Use this skill when:
- ✅ Code compiles successfully but correctness is uncertain
- ✅ Multiple components were built in isolation and need integration verification
- ✅ After completing a feature phase (Phase 1, 2, 3)
- ✅ Before declaring a feature "complete"
- ✅ When debugging mysterious failures in production
- ✅ User requests "thorough review" or "end-to-end verification"

**Do NOT use** when:
- ❌ Code doesn't compile yet (fix compilation first)
- ❌ Only reviewing a single isolated function (use code review instead)
- ❌ Reviewing documentation or specs (not executable code)

---

## Step 1: Identify Core User Flows

Based on the feature being reviewed, list **all meaningful user interactions** that the code is supposed to support.

**Categories to consider:**
1. **Initial state** — First time setup, empty state
2. **Core operations** — Main functionality (render, zoom, save, etc.)
3. **Variations** — Different modes/contexts (single vs multi-facet, Y-only vs X+Y)
4. **Edge interactions** — Modifiers (Shift+click, Ctrl+drag), zones (left strip, data grid)
5. **Error paths** — Invalid input, missing data, network failures
6. **State transitions** — Mid-operation cancellation, rapid changes
7. **Cleanup** — Disposal, navigation away, browser close

**Output format** (minimum 15 use cases):
```
UC1: [User action in plain language]
UC2: [User action in plain language]
...
UC15: [User action in plain language]
```

**Example** (for GGRS V3 interaction system):
```
UC1: User drops Y factor "expression" onto Y-axis drop zone (initial render)
UC2: User drops row facet (3 levels) + col facet (2 levels) + Y factor (multi-facet render)
UC3: User holds Shift, scrolls wheel up while mouse in left strip (Y-only zoom)
UC4: User holds Shift, scrolls wheel up while mouse in data grid (both axes zoom)
UC5: User holds Ctrl, drags mouse from (400,300) to (420,280) (pan)
UC6: User double-clicks in data grid (reset view)
UC7: User starts Ctrl+drag pan, presses Escape mid-drag (cancel interaction)
UC8: User drops Y="expression", render starts, immediately drops Y="intensity" (mid-render cancellation)
... (continue to 15+)
```

---

## Step 2: Trace Each Use Case Through Code

For **each use case**, trace the complete execution path:

1. **Entry point** — What event/function starts the flow?
2. **Key decision points** — Conditionals, switches, handler selection
3. **Data transformations** — JSON serialization, coordinate conversion, validation
4. **Cross-boundary calls** — Dart→JS, JS→WASM, WASM→Rust core
5. **State changes** — What fields get updated? In what order?
6. **Exit point** — What's the final user-visible result?

**Output format for each use case:**
```
## Use Case N: [User action]

**Code Trace:**
<entry_file>:<line> (<function_name>)
  → <next_file>:<line> (<function_name>)
    → <next_file>:<line> (<function_name>)
      [Key decision: if/match statement, what path taken]
      [Data transformation: JSON.parse, coordinate conversion]
      [Boundary crossing: Dart→JS→WASM]
    → <next_file>:<line> (<function_name>)
  → <final_file>:<line> (returns/renders result)

**Summary**: [1-2 sentences describing what ACTUALLY happens in the code, including any bugs/gaps found]
```

**Important**:
- Follow the **actual code**, not assumptions
- Note where code **should** call something but doesn't
- Mark **missing null checks**, **ignored return values**, **unvalidated inputs**
- Identify **silent fallbacks** that violate no-fallback rule

**Example**:
```
## Use Case 3: Shift+Wheel in Left Strip (Y-only zoom)

**Code Trace:**
interaction_manager.js:215 (onWheel event)
  → Line 41: detectZone(50, 300)
    → gpu.getLayoutState() **[BLOCKER: Method doesn't exist!]** → crashes
  → SHOULD BE: zone='left'
  → Line 220: selectHandler('wheel', 'left', {shift: true}) → 'Zoom'
  → Line 223: startInteraction('Zoom', 'left', 50, 300, {delta: -120})
    → renderer.interactionStart() → ggrs-wasm/src/lib.rs:405
      → Creates ZoomHandler → zoom_handler.rs:40
      → on_start(zone='LeftStrip', ..., {delta: -120})
        → Line 46: axis_from_zone(LeftStrip) → ZoomAxis::Y **[IGNORED! Bug]**
        → Line 58: layout_manager.zoom(ZoomAxis::Both, ZoomDirection::In)
          **[Should use ZoomAxis::Y from line 46, but hardcoded Both!]**
        → Returns LayoutState JSON with BOTH axes zoomed
      → Returns {"type": "view_update", "snapshot": {...}}
  → Line 90: _applySnapshot → gpu.syncLayoutState(snapshot)
  → Line 225: endInteraction()

**Summary**: Zone detection crashes due to missing getLayoutState(). IF FIXED, would detect left strip correctly BUT ZoomHandler ignores zone and zooms BOTH axes (critical bug - zone-aware zoom not implemented).
```

---

## Step 3: Categorize Findings

After tracing all use cases, categorize issues found:

**P0 Blockers** — Will crash immediately, blocks ALL testing:
- Missing methods/functions that are called
- Unchecked array/null access that will throw
- Type mismatches that cause runtime errors

**P1 Critical** — Feature doesn't work as designed:
- Ignored parameters (zone detection works but result ignored)
- Wrong logic (always does X when should sometimes do Y)
- Missing validation (invalid input accepted, corrupts state)
- Silent fallbacks (returns default instead of error)

**P2 High** — Works but has issues:
- Performance problems (redundant calls, N² loops)
- Memory leaks (listeners not cleaned up)
- Incomplete error handling (some paths throw, others don't)
- Race conditions (async operations not synchronized)

**Output format**:
```
## Findings Summary

**P0 Blockers** (Must fix before ANY testing):
1. [Issue] — [Affected use cases] — [File:line]
2. [Issue] — [Affected use cases] — [File:line]

**P1 Critical** (Feature broken):
3. [Issue] — [Affected use cases] — [File:line]
4. [Issue] — [Affected use cases] — [File:line]

**P2 High** (Works but problematic):
5. [Issue] — [Affected use cases] — [File:line]

**Total**: [N] use cases traced, [X] critical issues found
```

---

## Step 4: Create Fix Recommendations

For each **P0 and P1 issue**, provide:
1. Exact file and line number
2. Root cause (what's missing/wrong)
3. Specific fix (code snippet showing before/after)
4. Verification method (how to test the fix)

**Output format**:
```
## Fix Recommendations

### P0 Blocker: [Issue name]
**Affected use cases**: UC3, UC4, UC14
**File**: `path/to/file.js:41`
**Root cause**: [Explanation]
**Fix**:
```javascript
// BEFORE (crashes):
const layoutState = this.gpu.getLayoutState();

// AFTER (works):
const layoutState = this.gpu.getLayoutState();
if (!layoutState) {
    console.error('GPU layout state not initialized');
    return 'outside';
}
```
**Verification**: Drop Y factor, Shift+wheel in left strip → no crash

---

### P1 Critical: [Issue name]
**Affected use cases**: UC3
**File**: `zoom_handler.rs:58`
**Root cause**: [Explanation]
**Fix**:
```rust
// BEFORE (ignores zone):
let new_state = mgr.zoom(ZoomAxis::Both, direction)

// AFTER (uses zone):
let new_state = mgr.zoom(self.axis.unwrap(), direction)
```
**Verification**: Shift+wheel in left strip → only Y-axis zooms (X unchanged)
```

---

## Output Format

Create a markdown document with:

1. **Use Case List** (15+ use cases minimum)
2. **Detailed Traces** (one section per use case with code path)
3. **Findings Summary** (categorized by priority)
4. **Fix Recommendations** (P0 and P1 only, with code snippets)

Save to: `_local/use-case-review-[feature-name]-[date].md`

---

## Examples of Good Use Cases

**Good** (specific, testable):
- ✅ "User holds Shift, scrolls wheel up while mouse at x=50, y=300 (inside left strip)"
- ✅ "User drops Y factor 'expression', render starts (500ms in), user drops Y='intensity'"
- ✅ "User double-clicks at (500, 400) in data grid"

**Bad** (vague, not traceable):
- ❌ "User zooms"
- ❌ "Render fails"
- ❌ "Something breaks during interaction"

---

## Success Criteria

A complete use case review should:
- ✅ Cover ALL major user interactions (not just happy path)
- ✅ Include at least 15 distinct use cases
- ✅ Trace through actual code (with file:line references)
- ✅ Identify integration gaps (missing methods, ignored parameters)
- ✅ Distinguish between "compiles" and "works correctly"
- ✅ Provide actionable fixes for all P0/P1 issues

**Red flags** (incomplete review):
- ❌ Fewer than 15 use cases
- ❌ No file:line references in traces
- ❌ No bugs found (if code is complex, there are bugs)
- ❌ Only happy path tested
- ❌ No cross-boundary traces (Dart→JS→WASM)

---

## Tips

1. **Follow the data** — Trace how user input (mouse x/y, wheel delta) flows through transformations (pixels→data units, zone detection, JSON serialization)

2. **Don't assume** — If code calls `foo.bar()`, verify that `bar()` method actually exists

3. **Check boundaries** — Dart↔JS and JS↔WASM are where type mismatches hide

4. **Look for early returns** — Code that returns/throws before reaching expected behavior

5. **Test edge cases** — Empty arrays, null values, out-of-bounds coordinates

6. **Verify state changes** — If UC3 should change only Y-axis, check that X-axis values don't change

---

## When Review is Complete

Present findings to user with:
1. Total use cases traced
2. Number of issues found (P0/P1/P2)
3. Recommendation (fix now vs incremental vs re-scope)
4. Estimated fix time based on issue count

User decides next action based on severity and scope.
