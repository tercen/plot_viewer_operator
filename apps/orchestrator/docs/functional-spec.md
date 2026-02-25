# Orchestrator — Functional Specification

**Version:** 2.0.0
**Status:** Draft
**Last Updated:** 2026-02-12
**Reference:** docs/plan-overview.md, docs/architecture-pwa.md

---

## 1. Overview

### 1.1 Purpose

The orchestrator is a **panel management shell** — an IDE-like workbench that composes many independent webapps into a single page. Each webapp runs in its own iframe. The orchestrator owns the page layout, panel arrangement, icon strips, inter-app messaging (via postMessage), authentication distribution, and error display. It contains no business logic or domain-specific data access.

This is the Tercen IDE: a dynamic, resizable, dockable panel system that hosts tens of webapps (plot viewer, workflow visualizer, project navigator, AI chat, task manager, etc.) in a JetBrains-style layout.

### 1.2 Users

Tercen platform users who work with data analysis workflows, visualizations, and project management — all within a single browser page.

### 1.3 Scope

**In Scope (v1 — simplified layout, architected for growth):**
- Panel layout engine with a fixed default arrangement and drag-to-resize splitters
- Icon strips on panel edges for toggling webapp visibility
- Webapp lifecycle: load, show, hide, and cache iframes
- Inter-app message routing via postMessage
- Authentication credential distribution to all webapps
- Branded splash screen during initialization
- Global error display for errors thrown by webapps
- Support for multiple instances of the same webapp (e.g., two plot viewers)

**Full Vision (future — designed for in v1, built incrementally):**
- User-dockable panels (drag webapps between positions)
- Layout persistence across sessions (restore user's arrangement)
- Dynamic webapp registration / discovery
- Custom layout presets / perspectives

**Out of Scope:**
- Business logic (belongs to individual webapps)
- Data access / Tercen API calls (belongs to individual webapps)
- Rendering, plotting, workflow editing (belongs to individual webapps)

### 1.4 App Type

The orchestrator is a **composition shell**. It has no domain data, no left panel controls of its own, and no main content of its own. Its only job is managing panels and routing messages.

---

## 2. Domain Context

### 2.1 Background

Tercen is a data analysis platform where users build workflows of steps. Each step applies an operator to data. The platform offers many tools: visualization, navigation, workflow editing, team management, AI assistance, and more. Each tool is an independent webapp. The orchestrator composes them into a single IDE-like page.

### 2.2 Known Webapps

The orchestrator does not hardcode which webapps exist. Webapps register with the orchestrator and declare their preferred panel position and default size. The current set includes:

| Webapp | Description | Typical position |
|--------|-------------|-----------------|
| Toolbar | Save, run, export, theme toggle | Top bar |
| Project navigator | Project / workflow / step tree | Left tool window |
| Team navigator | Team browsing and CRUD | Left tool window |
| Operator library | Browse and manage operators | Left tool window |
| Plot viewer | Interactive plot visualization (GGRS) | Center content |
| Workflow visualizer | Visual workflow editor | Center content |
| Report viewer | View generated reports | Center content |
| Text file editor | Simple text editing | Center content |
| Gating | Flow cytometry gating (may use plot viewer) | Center content |
| AI chat | AI assistant | Bottom or right tool window |
| Task manager | Task/job monitoring | Bottom tool window |
| User manager | User administration | Center content or modal |

This list will grow. The orchestrator must handle webapps it has never seen before.

### 2.3 Data Source

The orchestrator does not access Tercen data directly. It receives:

- **Authentication credentials** from the Tercen platform (URL parameters or cookies)
- **Webapp manifest** — each webapp declares its metadata (name, icon, preferred position, default size, singleton vs multi-instance)

### 2.4 Typical Workflow

1. User opens the Tercen IDE from within the Tercen platform
2. Orchestrator shows branded splash screen
3. Orchestrator receives authentication credentials
4. Orchestrator loads the default layout and initializes webapps (iframes)
5. Splash screen dismisses; IDE layout appears
6. User interacts with webapps: clicking in project navigator causes plot viewer to load a step, toolbar actions route to the active content webapp, AI chat opens in a side panel, etc.
7. All inter-webapp communication flows through the orchestrator via postMessage

---

## 3. Functional Requirements

### 3.1 Panel Layout Engine

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Arrange panels in a split tree of rows and columns (recursive horizontal/vertical splits) | Must |
| FR-02 | Each split has a draggable splitter for resizing adjacent panels | Must |
| FR-03 | Panels have minimum and maximum size constraints | Must |
| FR-04 | Provide a default layout that loads on first use (see Section 4.1) | Must |
| FR-05 | The layout model is a data structure (split tree) that can be serialized | Must |
| FR-06 | Support collapsing a panel to zero width/height (hidden but not destroyed) | Should |
| FR-07 | Persist the user's layout across sessions (local storage or Tercen backend) | Should |
| FR-08 | Allow users to drag panels to different positions (docking) | Could |

### 3.2 Icon Strips

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-09 | Display icon strips at panel edges (left, bottom, right as needed) | Must |
| FR-10 | Each icon in the strip represents a registered webapp | Must |
| FR-11 | Clicking an icon toggles the webapp's panel visibility (show/hide) | Must |
| FR-12 | The active webapp's icon is visually highlighted | Must |
| FR-13 | Icons show the webapp's registered icon and tooltip with the webapp name | Must |

### 3.3 Webapp Lifecycle

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-14 | Load each webapp as a separate iframe | Must |
| FR-15 | Cache loaded iframes when hidden (do not destroy and recreate) | Must |
| FR-16 | Support multiple simultaneous instances of the same webapp type | Must |
| FR-17 | Each webapp instance has a unique identifier assigned by the orchestrator | Must |
| FR-18 | Webapps declare metadata: name, icon, preferred position, default size, singleton/multi-instance | Must |
| FR-19 | Orchestrator loads webapps concurrently (parallel iframe initialization) | Must |
| FR-20 | Orchestrator detects when a webapp iframe has finished loading (ready signal) | Must |

### 3.4 Inter-App Messaging

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-21 | Route messages between webapps via postMessage (cross-iframe) | Must |
| FR-22 | Messages have a standard envelope: `{ type, source, target, payload }` | Must |
| FR-23 | Support targeted messages (to a specific webapp instance) and broadcast messages (to all) | Must |
| FR-24 | Orchestrator does not interpret message payloads — it routes based on envelope | Must |
| FR-25 | Webapps can subscribe to message types they care about | Should |

### 3.5 Authentication

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-26 | Receive authentication credentials from Tercen platform at load time | Must |
| FR-27 | Distribute credentials to each webapp iframe on initialization | Must |
| FR-28 | If credentials expire or are revoked, notify all webapps | Should |

### 3.6 Error Handling

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-29 | Catch errors reported by webapps (via postMessage error events) | Must |
| FR-30 | Display formatted error in an overlay (identifies which webapp threw) | Must |
| FR-31 | Error overlay has a dismiss button; dismissing does not destroy webapp state | Must |

### 3.7 Splash Screen

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-32 | Display a branded splash screen (Tercen logo, "Tercen", spinner) during initialization | Must |
| FR-33 | Dismiss splash only after authentication and initial webapps are ready | Must |

---

## 4. User Interface Components

### 4.1 App Structure

The orchestrator has two visual states: **splash** and **workbench**.

#### State: Splash Screen (full-screen, shown during load)

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│                                                          │
│                                                          │
│                     [Tercen Logo]                         │
│                       Tercen                              │
│                     ◌ Loading...                          │
│                                                          │
│                                                          │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

#### State: Workbench (v1 default layout)

```
┌──────────────────────────────────────────────────────────┐
│  Toolbar webapp (full width, fixed height)                │
│  [Save] [Run] [Export]                      [Theme ☀]   │
├──┬──────────┬┬───────────────────────────────────────────┤
│  │          ││                                            │
│  │ Tool     ││  Center content area                      │
│I │ window   ││                                            │
│C │ panel    ││  ┌──────────────────────────────────────┐ │
│O │          ││  │ Active webapp (e.g., Plot Viewer)    │ │
│N │ (one     ││  │                                      │ │
│  │ webapp   ││  │                                      │ │
│S │ visible  ││  │                                      │ │
│T │ at a     ││  │                                      │ │
│R │ time,    ││  │                                      │ │
│I │ toggled  ││  │                                      │ │
│P │ via icon ││  │                                      │ │
│  │ strip)   ││  │                                      │ │
│  │          ││  └──────────────────────────────────────┘ │
│  │          ││                                            │
├──┼──────────┴┴───────────────────────────────────────────┤
│  │  Bottom panel (optional, e.g., AI chat, Task manager) │
│  │                                                        │
└──┴───────────────────────────────────────────────────────┘
```

**Layout description:**
- **Top bar:** Toolbar webapp. Fixed height. Full width.
- **Icon strip (left edge):** Vertical strip of icons. Each icon toggles a tool window panel. Fixed narrow width.
- **Tool window panel:** Appears to the right of the icon strip when an icon is active. Resizable width. One webapp visible at a time per strip position.
- **Center content area:** The main area. Hosts content webapps. Fills remaining space.
- **Bottom panel (optional):** Horizontal panel below the center. Hidden by default. Toggled via a bottom icon strip.
- **Splitters:** Draggable dividers between all adjacent panels.

#### State: Error Overlay (on top of workbench)

```
┌──────────────────────────────────────────────────────────┐
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
│  ░░░░░░░  ┌───────────────────────────┐  ░░░░░░░░░░░░░  │
│  ░░░░░░░  │  ⚠ Error in [webapp name] │  ░░░░░░░░░░░░░  │
│  ░░░░░░░  │                           │  ░░░░░░░░░░░░░  │
│  ░░░░░░░  │  [Formatted error message]│  ░░░░░░░░░░░░░  │
│  ░░░░░░░  │                           │  ░░░░░░░░░░░░░  │
│  ░░░░░░░  │             [Dismiss]     │  ░░░░░░░░░░░░░  │
│  ░░░░░░░  └───────────────────────────┘  ░░░░░░░░░░░░░  │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
└──────────────────────────────────────────────────────────┘
```

### 4.2 Left Panel Sections

The orchestrator has no left panel sections of its own. It provides the panel infrastructure; webapps provide the content within their panels.

### 4.3 Main Panel

The orchestrator has no main panel content of its own. The center content area hosts webapp iframes. When no content webapp is active, the area is empty (blank).

### 4.4 Panel Layout Model

The layout is a **split tree**:

```
Root (vertical split)
├── Toolbar panel (fixed height)
└── Body (horizontal split)
    ├── Icon strip (fixed width)
    ├── Tool window panel (resizable width, collapsible)
    ├── Center content panel (fills remaining)
    └── [Optional: right tool window panel]
    └── [Below: optional bottom panel (horizontal split)]
```

Each node in the tree is either:
- A **split node** (horizontal or vertical) with a ratio and two or more children
- A **panel node** hosting one or more webapp iframes (stacked, one visible at a time)

Splitters between children of a split node are draggable.

### 4.5 Icon Strips

Each icon strip is a narrow bar at a panel edge containing webapp toggle icons.

- **Left icon strip:** Toggles left tool window webapps (project nav, team nav, operator library)
- **Bottom icon strip:** Toggles bottom panel webapps (AI chat, task manager)

Icon strip behavior:
- Clicking an inactive icon opens that webapp's panel and shows the webapp
- Clicking the currently active icon collapses the panel (hides it)
- At most one webapp is visible per icon strip group at a time
- Icons display the webapp's registered icon (FontAwesome) and show the webapp name as a tooltip

### 4.6 Webapp Registration

Each webapp provides metadata to the orchestrator:

| Field | Description | Example |
|-------|-------------|---------|
| `id` | Unique webapp type identifier | `"plot-viewer"` |
| `name` | Human-readable display name | `"Plot Viewer"` |
| `icon` | FontAwesome icon class | `"fa-solid fa-chart-bar"` |
| `preferredPosition` | Where the webapp prefers to open | `"left"`, `"center"`, `"bottom"` |
| `defaultSize` | Preferred initial size | `{ width: 280, height: 300 }` |
| `multiInstance` | Whether multiple instances are allowed | `true` / `false` |

### 4.7 Inter-App Message Envelope

All messages between webapps use a standard envelope:

```
{
  type: "step-selected",
  source: { appId: "project-nav", instanceId: "pn-1" },
  target: { appId: "plot-viewer" } | "*" (broadcast),
  payload: { projectId, workflowId, stepId }
}
```

The orchestrator listens for postMessage from all iframes, inspects the envelope, and forwards to the target iframe(s). It does not read or transform the payload.

**Known initial message types:**

| Message type | From | To | Payload |
|-------------|------|----|---------|
| `step-selected` | project_nav | plot_viewer | `{ projectId, workflowId, stepId }` |
| `run-requested` | toolbar | active content webapp | `{}` |
| `save-requested` | toolbar | active content webapp | `{}` |
| `export-requested` | toolbar | active content webapp | `{ format }` |
| `theme-changed` | toolbar | `*` (all) | `{ theme: "light" \| "dark" }` |
| `render-progress` | plot_viewer | toolbar | `{ progress: 0.0–1.0 }` |
| `app-ready` | any webapp | orchestrator | `{}` |
| `app-error` | any webapp | orchestrator | `{ message, stack? }` |

This list grows as new webapps are added. The orchestrator routes any message type without needing to know about it in advance.

### 4.8 Splash Screen

- Full-screen, displayed on initial load
- Shows: Tercen logo (centered), "Tercen", and a loading spinner
- Dismissed when authentication is complete and the default layout webapps report readiness
- No user interaction during splash

### 4.9 Error Overlay

- Semi-transparent overlay on top of the workbench
- Identifies which webapp threw the error (by name)
- Displays the formatted error message
- Includes a "Dismiss" button
- Dismissing does not destroy any webapp state — the workbench returns to its previous state

---

## 5. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | Splash screen appears within 500ms of page load (before webapps are ready) |
| NFR-02 | Webapp iframes load concurrently (parallel initialization) |
| NFR-03 | Drag-resizing splitters is smooth (60fps, no layout thrashing) |
| NFR-04 | Hidden iframes are cached, not destroyed — toggling a tool window is instant |
| NFR-05 | The orchestrator itself is lightweight — no heavy frameworks, no domain logic |
| NFR-06 | Message routing latency is negligible (< 5ms per hop) |
| NFR-07 | The orchestrator works with webapps it has never seen before (no hardcoded list) |

---

## 6. Feature Summary

### Must Have

| Feature | Status |
|---------|--------|
| Split-tree panel layout with default arrangement | Planned |
| Draggable splitters between all panels | Planned |
| Icon strips (left, bottom) for toggling tool window webapps | Planned |
| Webapp loading as iframes (parallel, cached) | Planned |
| Inter-app message routing via postMessage | Planned |
| Standard message envelope (type, source, target, payload) | Planned |
| Webapp registration with metadata (name, icon, position, size) | Planned |
| Multiple instances of the same webapp | Planned |
| Authentication credential distribution | Planned |
| Branded splash screen | Planned |
| Error overlay (identifies source webapp, dismiss button) | Planned |
| Panel min/max size constraints | Planned |

### Should Have

| Feature | Status |
|---------|--------|
| Panel collapsing (icon strip toggle hides/shows panel) | Planned |
| Layout persistence across sessions | Planned |
| Message type subscription (webapps declare which types they receive) | Planned |
| Credential expiry notification to all webapps | Planned |

### Could Have

| Feature | Status |
|---------|--------|
| User-dockable panels (drag to rearrange) | Planned |
| Layout presets / perspectives | Planned |
| Dynamic webapp discovery (auto-detect available webapps) | Planned |

---

## 7. Assumptions

### 7.1 Data Assumptions

- The orchestrator does not access Tercen data directly
- Authentication credentials are provided by the Tercen platform at load time (URL parameters or cookies)
- Each webapp handles its own data access independently within its iframe

### 7.2 Environment Assumptions

- Runs inside the Tercen web platform (not standalone)
- Modern browser: Chrome 113+, Edge 113+, or Firefox 141+
- User is already authenticated in Tercen (credentials are pre-existing)
- Each webapp is an independent Flutter web app deployable as a standalone page
- Webapps communicate only via postMessage — no shared memory, no direct DOM access across iframes

### 7.3 Mock Data

For Phase 2 (mock build), the orchestrator needs:

- **Panel layout:** A hardcoded default split tree (toolbar + left tool window + center content + bottom panel)
- **Mock webapps:** Simple placeholder iframes (colored rectangles with labels) for each panel slot, to validate layout, resizing, and icon strip toggling
- **Mock messages:** Hardcoded postMessage events to validate routing between mock webapps
  - Mock `step-selected`: `{ type: "step-selected", source: { appId: "project-nav", instanceId: "pn-1" }, target: { appId: "plot-viewer" }, payload: { projectId: "p1", workflowId: "w1", stepId: "s1" } }`
  - Mock `theme-changed` broadcast: `{ type: "theme-changed", source: { appId: "toolbar", instanceId: "tb-1" }, target: "*", payload: { theme: "light" } }`
  - Mock `app-error`: `{ type: "app-error", source: { appId: "plot-viewer", instanceId: "pv-1" }, target: "orchestrator", payload: { message: "Connection to Tercen lost" } }`
- **Mock icon strip:** Icons for 3-4 tool window webapps to validate toggle behavior
- **Mock registration:** Hardcoded webapp metadata entries to validate the registration model

---

## 8. Glossary

| Term | Definition |
|------|------------|
| Orchestrator | The panel management shell that composes webapps into a single IDE-like page |
| Webapp | An independent Flutter web application that runs in its own iframe within the orchestrator |
| Panel | A rectangular region of the orchestrator's layout that hosts one or more webapp iframes |
| Split tree | The data structure representing the panel layout — a tree of horizontal/vertical splits and panel leaves |
| Splitter | A draggable divider between two adjacent panels in a split |
| Icon strip | A narrow bar at a panel edge containing icons that toggle tool window webapps |
| Tool window | A webapp that occupies a side or bottom panel, toggled via the icon strip (like JetBrains tool windows) |
| Center content | The main area of the workbench, hosting the primary active webapp(s) |
| Message envelope | The standard wrapper for inter-app messages: `{ type, source, target, payload }` |
| postMessage | The browser API used for cross-iframe communication |
| Webapp registration | The process by which a webapp declares its metadata (name, icon, position, size) to the orchestrator |
| Instance | A single running copy of a webapp; the same webapp type can have multiple instances |
| Layout persistence | Saving and restoring the user's panel arrangement across browser sessions |
| Docking | Moving a panel to a different position in the layout by dragging |
