# Orchestrator Layout Evolution — v3.0

**Status:** Proposed
**Date:** 2026-02-17
**Supersedes:** Sections 3.1, 4.1, 4.4, 4.5, 4.6 of functional-spec.md (v2.0.0)
**Context:** The v2.0 layout assumes a fixed arrangement with one tool window visible at a time. This document describes the evolution to a flexible, category-driven layout that supports multiple simultaneous tool panels and user-arranged content splits.

---

## 1. Motivation

The v2.0 layout has two limitations:

1. **Only one tool window visible at a time.** Clicking a different icon in the left strip hides the current tool window and shows the new one. This breaks down when two tools need to be visible simultaneously (e.g., project navigator + factor navigator side-by-side).

2. **No user-driven content arrangement.** The center content area hosts one active webapp. There is no way to split it — e.g., two plot viewers side-by-side, or a plot viewer above a report viewer.

Both limitations block planned features (factor navigator alongside project navigator, comparative plot viewing).

---

## 2. App Categories

Replace the `preferredPosition` enum (`top`, `left`, `center`, `bottom`) with a **category** enum that describes the app's layout role. The orchestrator maps categories to layout behavior.

### 2.1 Category Definitions

| Category | Behavior | Instance policy | Examples |
|----------|----------|-----------------|---------|
| **bar** | Fixed position, not user-arrangeable. Occupies a full-width horizontal strip at the top or bottom edge. | Single instance only. | toolbar |
| **tool** | Opens as a vertical strip on the left edge. Multiple tools can be open simultaneously, arranged side-by-side in the order they were opened. Each strip is independently resizable. | Single instance per tool type. | project_nav, factor_nav, team_nav, operator_library |
| **content** | Opens in the center content area. The content area is a split-tree with tab groups at each leaf. Users can split, tab, and rearrange content panels freely. | Multiple instances allowed (configurable per app). | plot_viewer, workflow_visualizer, report_viewer, text_file_editor, gating, user_manager |

### 2.2 Registration Model Change

```dart
enum AppCategory { bar, tool, content }

class WebappRegistration {
  final String id;
  final String name;
  final IconData icon;
  final AppCategory category;        // replaces preferredPosition
  final Size defaultSize;
  final bool multiInstance;           // only meaningful for content apps
  final String url;
}
```

The `preferredPosition` field is removed. `category` fully determines layout placement.

### 2.3 Migration from v2.0

| v2.0 preferredPosition | v3.0 category | Notes |
|------------------------|---------------|-------|
| `top` | `bar` | Only toolbar uses this |
| `left` | `tool` | project-nav, team-nav, operator-library |
| `center` | `content` | plot-viewer, workflow-visualizer, etc. |
| `bottom` | `bar` | ai-chat and task-manager stay as fixed bottom bar apps |

**Decision:** ai-chat and task-manager remain as `bar` (fixed bottom strip). They are not user-arrangeable.

---

## 3. Tool Strip Layout

### 3.1 Behavior

Tool apps open as vertical strips on the left edge of the workbench, between the icon strip and the content area.

**Opening:** When a user activates a tool (via icon strip click or programmatic trigger), it opens as a new vertical strip. The strip is inserted at the **rightmost position** among open tool strips — i.e., the most recently opened tool is closest to the content area.

**Ordering:** Open-order determines left-to-right position. The first tool opened is leftmost; the most recently opened tool is rightmost. There is no static ordering — the arrangement depends entirely on which tools the user has opened and in what sequence.

**Closing:** Toggling off a tool (clicking its active icon) collapses its strip. Remaining strips reflow to close the gap, preserving their relative order.

**Resizing:** Each tool strip has an independent width with a draggable splitter on its right edge. Default width comes from the app's `defaultSize.width`. Min/max constraints apply (min 200px, max 400px per the existing style spec for left panels).

### 3.2 Icon Strip

The left icon strip remains as in v2.0, but its toggle behavior changes:

| v2.0 | v3.0 |
|------|------|
| Clicking an inactive icon **hides the current tool** and shows the new one (radio behavior) | Clicking an inactive icon **opens an additional strip** for that tool (additive behavior) |
| Clicking the active icon **collapses the tool panel** | Clicking an active icon **collapses that tool's strip only** |
| At most one tool visible at a time | Multiple tools visible simultaneously |

The icon strip still highlights all active (open) tools. Multiple icons can be highlighted at once.

### 3.3 Layout Diagram — Multiple Tool Strips

```
┌──────────────────────────────────────────────────────────────────┐
│  Toolbar (bar)                                                    │
├──┬──────────┬┬──────────┬┬───────────────────────────────────────┤
│  │          ││          ││                                        │
│  │ Tool A   ││ Tool B   ││  Content area                         │
│I │ (opened  ││ (opened  ││  (split-tree, see Section 4)          │
│C │  first)  ││  second) ││                                        │
│O │          ││          ││                                        │
│N │  280px   ││  280px   ││                                        │
│  │  ↔       ││  ↔       ││                                        │
│S │          ││          ││                                        │
│T │          ││          ││                                        │
│R │          ││          ││                                        │
│I │          ││          ││                                        │
│P │          ││          ││                                        │
│  │          ││          ││                                        │
├──┴──────────┴┴──────────┴┴───────────────────────────────────────┤
```

↔ = draggable splitter

### 3.4 Constraints

- **Maximum simultaneous tool strips:** No hard limit, but practical screen width limits it. If opening another tool strip would push the content area below its minimum width (e.g., 400px), the orchestrator should warn or prevent the open.
- **Tool strips are always on the left.** No right-edge docking for tool strips (per the left-out layout rule).
- **Single instance per tool type.** You cannot open two project navigators. The `multiInstance` flag on tool apps is always false.

---

## 4. Content Area — Split-Tree with Tab Groups

### 4.1 Structure

The content area (everything to the right of tool strips, below the top bar) is a **split-tree** where each leaf node is a **tab group**.

```
Content area (split-tree root)
├── SplitNode (vertical split)
│   ├── TabGroup [plot-viewer-1, plot-viewer-2]  ← two tabs
│   └── TabGroup [report-viewer-1]               ← one tab
└── (or a single TabGroup if no splits)
```

A **tab group** holds one or more webapp instances as tabs. One tab is active (visible); the others are loaded but hidden (cached iframes, as in v2.0).

### 4.2 Tab Group Behavior

- Each tab shows the webapp's name and icon, plus a close button.
- Clicking a tab makes it the active (visible) instance in that group.
- Dragging a tab to another tab group moves it there.
- Dragging a tab to the edge of a tab group (left/right/top/bottom drop zone) creates a new split with a new tab group containing that tab.
- If a tab group has only one tab and that tab is closed, the tab group and its split are removed (the tree collapses).
- Tab order within a group is based on insertion order (most recent = rightmost).

### 4.3 Splitting

Users create splits by:

1. **Drag-to-edge:** Dragging a tab to the edge of the content area or a tab group shows a drop zone indicator. Dropping creates a new split.
2. **Context menu:** Right-clicking a tab offers "Split Right" and "Split Down" options.
3. **Programmatic:** A webapp (or the orchestrator) can request a split via message — e.g., project_nav sends a message to open factor_nav, and the orchestrator opens it in a new split next to the current content.

Split directions:
- **Split Right:** Creates a vertical split (side-by-side).
- **Split Down:** Creates a horizontal split (stacked).

### 4.4 Content Split-Tree Examples

**Single content app (default):**
```
┌────────────────────────────────────┐
│ [Plot Viewer ×]                    │
│                                    │
│         Plot Viewer                │
│                                    │
└────────────────────────────────────┘
```

**Two content apps side-by-side (Split Right):**
```
┌─────────────────┬┬─────────────────┐
│ [Plot Viewer ×] ││ [Report ×]      │
│                 ││                  │
│   Plot Viewer   ││   Report        │
│                 ││                  │
└─────────────────┴┴─────────────────┘
```

**Two plot viewers + report below (Split Right, then Split Down):**
```
┌─────────────────┬┬─────────────────┐
│ [Plot A ×]      ││ [Plot B ×]      │
│                 ││                  │
│   Plot A        ││   Plot B        │
│                 ││                  │
├─────────────────┴┴─────────────────┤
│ [Report ×]                         │
│                                    │
│            Report                  │
│                                    │
└────────────────────────────────────┘
```

**Tabbed content (two apps in same space):**
```
┌────────────────────────────────────┐
│ [Plot Viewer ×] [Report ×]        │
│                                    │
│         Plot Viewer (active)       │
│                                    │
└────────────────────────────────────┘
```

### 4.5 Data Model Changes

The existing `LeafNode` already holds `webappInstanceIds` and `activeInstanceId` — this is effectively a tab group. The split-tree model requires minimal changes:

```dart
// Existing — no change needed
sealed class PanelNode { ... }

class SplitNode extends PanelNode {
  final String id;
  final SplitDirection direction;
  final List<PanelNode> children;
  final List<double> ratios;
  final Map<int, double> fixedSizes;
}

class LeafNode extends PanelNode {
  final String id;
  final List<String> webappInstanceIds;  // tab group — ordered list of tabs
  final String? activeInstanceId;        // active tab
}
```

**What changes:** The content area is no longer a single LeafNode. It becomes a SplitNode (or LeafNode if unsplit) that the user can split and rearrange. The top-level layout tree nests the content split-tree inside the existing workbench structure.

### 4.6 Content Area Constraints

- **Minimum tab group size:** 200px width, 150px height. Splits that would violate this are prevented.
- **Maximum split depth:** No hard limit, but deeply nested splits become impractical. Recommend a soft limit of 4 levels.
- **Empty content area:** If all content tabs are closed, the content area shows an empty state (centered message: "No open editors. Select a step from the navigator to begin.").

---

## 5. Opening Apps — Programmatic and User-Initiated

### 5.1 Open Triggers

| Trigger | Example | Behavior |
|---------|---------|----------|
| Icon strip click (tool) | Click project-nav icon | Opens/closes tool strip on left edge |
| Cross-app message | project_nav sends `open-app` targeting factor_nav | Opens factor_nav as a tool strip (if tool) or in content area (if content) |
| Context menu "Open to Right" | Right-click tab → "Split Right" | Splits content area, opens new instance in the new split |
| Default layout on startup | Initial load | Opens the apps defined in the default layout preset |

### 5.2 open-app Message

New message type for requesting the orchestrator to open an app:

```
{
  type: "open-app",
  source: { appId: "project-nav", instanceId: "pn-1" },
  target: "orchestrator",
  payload: {
    appId: "factor-nav",
    splitDirection: "right" | "down" | null,
    relativeTo: "pv-1" | null
  }
}
```

- `splitDirection`: If provided, the orchestrator creates a new split in the content area. If null, opens in the current active tab group (as a new tab) or as a new tool strip.
- `relativeTo`: The instance ID to split relative to. If null, splits relative to the currently focused tab group.

### 5.3 Open-Order Tracking

The orchestrator maintains an **open-order list** for tool strips:

```dart
List<String> toolStripOrder;  // ordered list of tool app IDs, by open time
```

When a tool is opened, its ID is appended. When closed, its ID is removed. The left-to-right arrangement of tool strips matches this list.

---

## 6. Updated Workbench Layout

### 6.1 Full Layout Diagram (v3.0)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  Toolbar (bar, fixed)                                              │  │
│  └────────────────────────────────────────────────────────────────────┘  │
├──┬──────────┬┬──────────┬┬───────────────────────────────────────────────┤
│  │          ││          ││ ┌──────────────────┬┬──────────────────────┐  │
│  │ Tool A   ││ Tool B   ││ │ [Tab1×] [Tab2×]  ││ [Tab3×]             │  │
│I │          ││          ││ │                   ││                     │  │
│C │          ││          ││ │   Content         ││   Content           │  │
│O │          ││          ││ │   (tab group 1)   ││   (tab group 2)    │  │
│N │          ││          ││ │                   ││                     │  │
│  │          ││          ││ ├───────────────────┴┴─────────────────────┤  │
│S │          ││          ││ │ [Tab4×]                                  │  │
│T │          ││          ││ │                                          │  │
│R │          ││          ││ │   Content (tab group 3)                  │  │
│I │          ││          ││ │                                          │  │
│P │          ││          ││ └──────────────────────────────────────────┘  │
│  │          ││          ││                                               │
├──┴──────────┴┴──────────┴┴──────────────────────────────────────────────┤
```

### 6.2 Top-Level Split-Tree

```
Root (vertical split)
├── Toolbar bar (fixed height: 48px)
└── Body (horizontal split)
    ├── Icon strip (fixed width: 40px)
    ├── Tool strip: Tool A (resizable, default 280px)      ← open-order 1
    ├── Tool strip: Tool B (resizable, default 280px)      ← open-order 2
    └── Content split-tree (fills remaining)
        ├── SplitNode (vertical)
        │   ├── TabGroup [tab1, tab2]
        │   └── TabGroup [tab3]
        └── TabGroup [tab4]
```

Tool strips are dynamic children of the Body split. They are inserted/removed as tools are opened/closed, always between the icon strip and the content area.

---

## 7. Default Layout Preset

On first load (no saved layout), the orchestrator uses this default:

```
Root (vertical split)
├── Toolbar (fixed, 48px)
└── Body (horizontal split)
    ├── Icon strip (fixed, 40px)
    ├── project-nav tool strip (280px)
    └── Content area
        └── TabGroup [empty — "Select a step to begin"]
```

Only one tool strip (project-nav) is open by default. Other tools are available in the icon strip but closed. The content area starts empty until a step is selected.

---

## 8. Impact on Existing Implementation

### 8.1 Model Changes

| File | Change |
|------|--------|
| `WebappRegistration` | Replace `preferredPosition` with `category` (AppCategory enum) |
| `PanelNode` | No structural change — already supports split-tree with LeafNode tab groups |
| `WebappInstance` | No change |
| `MessageEnvelope` | No change (new `open-app` type uses existing envelope) |

### 8.2 Service Changes

| File | Change |
|------|--------|
| `WebappRegistry` | Update registrations to use `category` instead of `preferredPosition` |
| `LayoutProvider` (new or updated) | Track `toolStripOrder`, handle dynamic tool strip insertion/removal, manage content split-tree mutations (split, move tab, close tab) |
| `MessageRouter` | Handle new `open-app` message type |

### 8.3 Widget Changes

| Widget | Change |
|--------|--------|
| `Workbench` | Render dynamic number of tool strips based on `toolStripOrder`; render content split-tree recursively |
| `IconStrip` | Change from radio behavior (one active) to checkbox behavior (multiple active) |
| `PanelHost` | Add tab bar rendering for LeafNodes with multiple instances |
| New: `TabBar` | Tab strip with drag-and-drop, close buttons, active indicator |
| New: `SplitDropZone` | Edge drop zones for drag-to-split |

### 8.4 New Message Types

| Type | Source | Target | Payload | Purpose |
|------|--------|--------|---------|---------|
| `open-app` | any webapp | orchestrator | `{ appId, splitDirection?, relativeTo? }` | Request orchestrator to open an app |
| `close-app` | any webapp | orchestrator | `{ instanceId }` | Request orchestrator to close a specific instance |
| `focus-app` | any webapp | orchestrator | `{ instanceId }` | Request orchestrator to bring an instance's tab to front |

---

## 9. Implementation Phasing

This layout evolution does not need to ship all at once. Recommended increments:

### Phase A — Multi-Tool Strips (minimal change)
- Change icon strip from radio to additive toggle
- Support multiple tool strips side-by-side with open-order positioning
- No content area changes yet

### Phase B — Content Tab Groups
- Add tab bar to content LeafNodes
- Support multiple content instances as tabs within a single group
- No splitting yet

### Phase C — Content Splitting
- Add split-tree mutations (Split Right, Split Down)
- Add context menu for splitting
- Add drag-to-edge drop zones

### Phase D — Cross-App Open
- Implement `open-app` message handling
- Allow webapps to programmatically open other apps in specific arrangements

Each phase is independently useful and testable.

---

## 10. Open Questions

1. ~~**ai-chat and task-manager category:**~~ **Resolved.** These remain as `bar` (fixed bottom strip).

2. **Layout persistence scope:** When saving layout to restore across sessions, should tool strip open-order be persisted? (Recommendation: yes — save the full layout tree including which tools are open and in what order.)

3. **Maximum tool strip count:** Should there be a hard limit (e.g., 3 simultaneous tool strips) or just the soft constraint of minimum content area width?
