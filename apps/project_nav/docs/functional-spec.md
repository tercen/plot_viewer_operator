# Project Navigator — Functional Specification

**Version:** 1.0.0
**Status:** Draft
**Last Updated:** 2026-02-13
**Reference:** docs/plan-overview.md, apps/orchestrator/docs/functional-spec.md

---

## 1. Overview

### 1.1 Purpose

The project navigator is a tree browser that lets users navigate their Tercen project hierarchy: projects, workflows, and data steps. Selecting a data step broadcasts a message so that other webapps (plot viewer, factor selector, etc.) can load the corresponding data. It is the primary entry point for users to find and open their work.

### 1.2 Users

Tercen platform users who need to locate and open data steps within their projects and workflows.

### 1.3 Scope

**In Scope:**
- Hierarchical tree display: Projects → Workflows → Data Steps
- Expand/collapse tree nodes to browse the hierarchy
- Search/filter tree by name (matches across all node types)
- Broadcast `step-selected` message when a data step is clicked
- Show all projects belonging to the authenticated user

**Out of Scope:**
- Creating, renaming, or deleting projects, workflows, or steps (read-only)
- Workflow editing or step configuration
- Displaying step results, previews, or status indicators
- Drag-and-drop reordering of tree items
- Folder/grouping beyond the natural project → workflow → step hierarchy

### 1.4 App Type

**Type 1 (Read-only navigation).** Data flows from Tercen to the app for display. The app writes nothing back to Tercen. User interaction (selecting a data step) produces a broadcast message to other webapps.

---

## 2. Domain Context

### 2.1 Background

In Tercen, a **project** is a container for related analysis work. Each project contains one or more **workflows** — pipelines of connected steps. Each workflow contains **data steps** — individual processing units where an operator is applied to data. Users build workflows by chaining data steps together.

To visualize or interact with data at a particular step, the user must first navigate to that step. The project navigator provides this navigation.

### 2.2 Data Source

The project navigator fetches data from the Tercen backend via `sci_tercen_client`.

**Tree hierarchy:**

| Level | Object | Key fields | Fetched when |
|-------|--------|------------|--------------|
| Root | Project | id, name | App initialization (all user projects) |
| Child of Project | Workflow | id, name, projectId | User expands a project node |
| Child of Workflow | Data Step | id, name, workflowId | User expands a workflow node |

Each level is loaded lazily — children are fetched only when the parent node is expanded.

### 2.3 Typical Workflow

1. User opens the Tercen IDE; the project navigator loads in the left tool window
2. The tree shows all projects for the authenticated user (collapsed)
3. User expands a project to see its workflows
4. User expands a workflow to see its data steps
5. User clicks a data step
6. The project navigator broadcasts `step-selected` with `{ projectId, workflowId, stepId }`
7. Other webapps (plot viewer, factor selector) receive the message and load the step's data

---

## 3. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Display all projects for the authenticated user as root-level tree nodes | Must |
| FR-02 | Expand a project node to show its workflows as child nodes | Must |
| FR-03 | Expand a workflow node to show its data steps as child nodes | Must |
| FR-04 | Each tree node displays an icon and the object's name | Must |
| FR-05 | Clicking a data step node broadcasts a `step-selected` message (target: `*`) with `{ projectId, workflowId, stepId }` | Must |
| FR-06 | Provide a search input that filters the tree by name, matching across all node types | Must |
| FR-07 | When filtering, show matching nodes along with their ancestor nodes to preserve hierarchy context | Must |
| FR-08 | When filtering, auto-expand ancestor nodes of matching results | Must |
| FR-09 | Clearing the search restores the tree to its previous expand/collapse state | Should |
| FR-10 | Lazy-load children when a node is first expanded (not on app load) | Must |
| FR-11 | Show a loading indicator on a node while its children are being fetched | Must |
| FR-12 | Visually highlight the currently selected data step | Must |
| FR-13 | Collapse an expanded node by clicking its expand/collapse control | Must |
| FR-14 | Send `app-ready` message to the orchestrator when initialization is complete | Must |

---

## 4. User Interface Components

### 4.1 App Structure

The project navigator is a **tool window webapp** — it runs inside the orchestrator's left tool window panel. It uses a single-column layout (no internal left panel / main content split) because the app itself occupies a tool window that is already the left side of the workbench.

```
┌──────────────────────────┐
│ SEARCH                   │
│ ┌──────────────────────┐ │
│ │ 🔍 Search...         │ │
│ └──────────────────────┘ │
│                          │
│ PROJECTS                 │
│                          │
│ ▶ Project Alpha          │
│ ▼ Project Beta           │
│   ▶ Workflow 1           │
│   ▼ Workflow 2           │
│     ◆ Data Step A        │
│     ◆ Data Step B  [sel] │
│ ▶ Project Gamma          │
│                          │
│                          │
│                          │
│ INFO                     │
│ ┌──────────────────────┐ │
│ │ GitHub link           │ │
│ └──────────────────────┘ │
└──────────────────────────┘
```

### 4.2 Sections

#### Section 1: SEARCH
Icon: magnifying-glass

| Control | Type | Default | Notes |
|---------|------|---------|-------|
| Search | Text input | Empty | Filters tree by name as user types. Matches case-insensitive across projects, workflows, and data steps. |

#### Section 2: PROJECTS
Icon: folder

The tree view. No controls — this is the browsable, interactive tree.

**Tree node structure:**

| Level | Icon | Label | Expand/collapse | Selectable |
|-------|------|-------|----------------|------------|
| Project | folder (FontAwesome) | Project name | Yes (shows workflows) | No |
| Workflow | tercen-Workflow (Tercen custom) | Workflow name | Yes (shows data steps) | No |
| Data Step | tercen-Data-Step (Tercen custom) | Data step name | No (leaf node) | Yes |

**Indentation:** Each child level is indented one step from its parent.

**Expand/collapse indicator:** Collapsed nodes show a right-pointing chevron; expanded nodes show a down-pointing chevron. Leaf nodes (data steps) show no chevron.

**Selection:** Clicking a data step highlights it and broadcasts the `step-selected` message. Only one data step can be selected at a time.

**Loading state:** When a node is being expanded for the first time, a small spinner replaces its children area until data arrives.

**Empty state:** If a project has no workflows, or a workflow has no data steps, show a muted text label: "No workflows" or "No data steps."

#### Section 3: INFO
Icon: circle-info

| Control | Type | Notes |
|---------|------|-------|
| GitHub link | Icon + link | Links to the repository |

### 4.3 Main Panel

This app has no separate main panel. The entire app is a single-column tool window (see 4.1).

### 4.4 Search/Filter Behavior

When the user types in the search field:

1. The tree is filtered to show only nodes whose **name** contains the search text (case-insensitive)
2. Matching is across all node types — a search can match projects, workflows, and data steps simultaneously
3. Ancestor nodes of any match are always shown (to preserve hierarchy context)
4. Ancestor nodes of matches are auto-expanded
5. If a project name matches, all its children are shown (the project itself is the match)
6. If a workflow name matches, its parent project and all the workflow's children are shown
7. If a data step name matches, its parent workflow and grandparent project are shown

When the search field is cleared, the tree returns to its previous state.

---

## 5. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | Project list loads within 2 seconds of app initialization |
| NFR-02 | Expanding a node loads children within 1 second |
| NFR-03 | Search filtering responds as the user types (debounced, no submit button) |
| NFR-04 | Tree handles 50+ projects without performance degradation |
| NFR-05 | The app fits within the orchestrator's tool window panel (typical width 200–400px) |

---

## 6. Feature Summary

### Must Have

| Feature | Status |
|---------|--------|
| Hierarchical tree: Projects → Workflows → Data Steps | Planned |
| Expand/collapse tree nodes with lazy loading | Planned |
| Icons per node type (folder, tercen-Workflow, tercen-Data-Step) | Planned |
| Click data step → broadcast `step-selected` | Planned |
| Search/filter by name across all node types | Planned |
| Loading indicator during child fetch | Planned |
| Selected data step highlighting | Planned |

### Should Have

| Feature | Status |
|---------|--------|
| Restore expand/collapse state after clearing search | Planned |

### Could Have

| Feature | Status |
|---------|--------|
| Keyboard navigation (arrow keys to move, Enter to select/expand) | Planned |

---

## 7. Assumptions

### 7.1 Data Assumptions

- The authenticated user has access to one or more projects
- Each project contains zero or more workflows
- Each workflow contains zero or more data steps
- The Tercen API provides endpoints to list projects for a user, workflows for a project, and data steps for a workflow
- Object names are non-empty strings

### 7.2 Environment Assumptions

- Runs as an iframe inside the orchestrator's left tool window panel
- Receives authentication credentials from the orchestrator via postMessage
- Communicates with other webapps only via postMessage through the orchestrator
- Panel width is typically 200–400px (resizable by the user via the orchestrator's splitter)

### 7.3 Mock Data

For Phase 2 (mock build), the tree uses hardcoded data:

- **3 projects:** "Immunology Study", "Gene Expression Analysis", "Clinical Trial 2024"
- **2–3 workflows per project** with descriptive names (e.g., "Baseline Analysis", "Dose Response", "Quality Control")
- **2–4 data steps per workflow** with descriptive names (e.g., "PCA", "Normalize", "Scatter Plot", "Heatmap")
- Total: ~30 tree nodes
- Data is hardcoded in a service class (no network calls in Phase 2)

### 7.4 Inter-App Messages

**Outgoing:**

| Message type | Target | Payload | When |
|-------------|--------|---------|------|
| `step-selected` | `*` (broadcast) | `{ projectId, workflowId, stepId }` | User clicks a data step |
| `app-ready` | orchestrator | `{}` | App initialization complete |

**Incoming:**

| Message type | From | Payload | Effect |
|-------------|------|---------|--------|
| `auth-credentials` | orchestrator | `{ token, baseUrl }` | Store credentials for API calls |

---

## 8. Glossary

| Term | Definition |
|------|------------|
| Project | A top-level container in Tercen that groups related workflows |
| Workflow | A pipeline of connected data steps within a project |
| Data Step | A single processing unit in a workflow where an operator is applied to data |
| Tool window | A side panel in the orchestrator, toggled via the icon strip |
| `step-selected` | The broadcast message sent when the user clicks a data step, carrying the project, workflow, and step identifiers |
| Factor selector | A separate webapp (not part of this spec) that listens for `step-selected` to configure plot axis/color/facet mappings |
