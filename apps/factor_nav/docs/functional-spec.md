# Factor Navigator — Functional Specification

**Version:** 1.0.0
**Status:** Draft
**Last Updated:** 2026-02-17
**Reference:** docs/plan-overview.md, apps/project_nav/docs/functional-spec.md

---

## 1. Overview

### 1.1 Purpose

The factor navigator displays available data factors (columns) from previously executed workflow steps. Users drag factors from this list onto the plot viewer canvas to assign them to plot roles (X axis, Y axis, color, facet, etc.). It is the bridge between selecting a data step (in project_nav) and configuring a plot (in plot_viewer).

### 1.2 Users

Tercen platform users who need to browse and select data factors for plot configuration.

### 1.3 Scope

**In Scope:**
- Display factors grouped by namespace in a collapsible tree
- Search/filter factors by name
- Drag factor nodes onto the plot viewer
- Listen for `step-selected` messages to load the relevant factors
- Show factor data type

**Out of Scope:**
- Creating, editing, or deleting factors (read-only)
- Handling drop targets (plot_viewer's responsibility)
- Displaying factor values or data previews
- Writing data back to Tercen
- Factor assignment to specific plot roles (plot_viewer manages this)

### 1.4 App Type

**Type 1 (Read-only navigation).** Data flows from Tercen to the app for display. The app writes nothing back. User interaction (dragging a factor) is handled by the browser's native drag-and-drop — the factor navigator is the drag source only.

---

## 2. Domain Context

### 2.1 Background

In Tercen, a workflow contains multiple connected steps. Each step processes data through an operator, producing output columns (factors). When configuring a plot at a given data step, the available factors come from all **previously executed ancestor steps** in the workflow — not just the current step.

Factor names follow the convention `namespace.column_name`, where the namespace (text before the first dot) typically corresponds to the ancestor step that produced the factor. For example, a PCA step might produce factors named `PCA.PC1`, `PCA.PC2`, and `PCA.variance_explained`.

System columns (names starting with `.`, ending with `._rids` or `.tlbId`) are internal to Tercen and are filtered out before display.

### 2.2 Data Source

The factor navigator receives factors from the Tercen backend via `sci_tercen_client` (Phase 3). Factors are loaded when a `step-selected` message is received.

**Factor data:**

| Field | Description | Example |
|-------|-------------|---------|
| name | Full factor name (namespaced) | `PCA.PC1` |
| type | Data type | `double`, `string`, `int` |

**Data retrieval chain:**
1. Receive `step-selected` with `{ projectId, workflowId, stepId }`
2. Fetch the workflow and locate the step
3. Get the step's ancestor chain via `RelationStep.getFactorTree()`
4. Each ancestor step contributes a group of factors (its output columns)
5. Factor names are namespaced by the producing step

### 2.3 Typical Workflow

1. User selects a data step in the project navigator
2. Factor navigator receives the `step-selected` broadcast
3. Factor navigator loads factors for the selected step's ancestor chain
4. Factors appear grouped by namespace, sorted alphabetically
5. User searches or browses to find the desired factor
6. User drags a factor from the list onto the plot viewer canvas
7. Plot viewer receives the drop and assigns the factor to the appropriate role

---

## 3. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Listen for `step-selected` messages and load factors for the selected step | Must |
| FR-02 | Display factors grouped by namespace (text before first dot) in a collapsible tree | Must |
| FR-03 | Sort namespace groups alphabetically; sort factors within each group alphabetically | Must |
| FR-04 | Each factor leaf node displays a type-indicating icon and the factor's short name (text after last dot) | Must |
| FR-05 | Each namespace group node displays a group icon and the namespace name | Must |
| FR-06 | Provide a search input that filters factors by name (case-insensitive substring match against full name) | Must |
| FR-07 | When filtering, show matching factors along with their namespace group | Must |
| FR-08 | When filtering, auto-expand namespace groups that contain matches | Must |
| FR-09 | Factor leaf nodes are draggable via native HTML5 drag-and-drop | Must |
| FR-10 | Drag data includes the factor name and type as serialized JSON | Must |
| FR-11 | Clicking a factor has no effect (no selection state, no broadcast) | Must |
| FR-12 | Show empty state when no step has been selected | Must |
| FR-13 | Show empty state when the selected step has no available factors | Must |
| FR-14 | Show empty state when search matches no factors | Must |
| FR-15 | Filter out system columns (names starting with `.`, ending with `._rids` or `.tlbId`) | Must |
| FR-16 | Send `app-ready` message to orchestrator when initialization is complete | Must |
| FR-17 | Clear search filter when a new step is selected | Should |
| FR-18 | All namespace groups expanded by default | Should |

---

## 4. User Interface Components

### 4.1 App Structure

The factor navigator is a tool window webapp. It runs inside the orchestrator as the **second left tool window**, positioned to the right of the project navigator. Both panels are visible simultaneously. It uses a single-column layout — the entire app is the panel.

```
┌──────────────────────────┐
│ SEARCH                   │
│ ┌──────────────────────┐ │
│ │ 🔍 Filter factors... │ │
│ └──────────────────────┘ │
│                          │
│ FACTORS                  │
│                          │
│ ▼ Import                 │
│   [A] gene_id     string │
│   [#] expression  double │
│   [A] sample_name string │
│ ▼ Normalize              │
│   [#] mean        double │
│   [#] sd          double │
│ ▼ PCA                    │
│   [#] PC1         double │
│   [#] PC2         double │
│   [#] PC3         double │
│                          │
│                          │
│ INFO                     │
│ ┌──────────────────────┐ │
│ │ GitHub link          │ │
│ └──────────────────────┘ │
└──────────────────────────┘
```

### 4.2 Sections

#### Section 1: SEARCH
Icon: magnifying-glass

| Control | Type | Default | Notes |
|---------|------|---------|-------|
| Filter | Text input | Empty | Filters factor list by name as user types. Case-insensitive substring match against full factor name (including namespace). Clear button when non-empty. |

#### Section 2: FACTORS
Icon: layer-group

The factor tree. No controls — this is the browsable, draggable factor list.

**Tree node structure:**

| Level | Icon | Label | Expand/collapse | Draggable |
|-------|------|-------|----------------|-----------|
| Namespace group | layer-group | Namespace name | Yes | No |
| Factor (numeric: double, int) | hashtag | Short name (after last dot) | No (leaf) | Yes |
| Factor (string) | font | Short name (after last dot) | No (leaf) | Yes |

**Indentation:** Factors are indented one level from their namespace group.

**Expand/collapse indicator:** Collapsed groups show a right-pointing chevron; expanded groups show a down-pointing chevron.

**Factor type label:** The factor's data type is shown as muted text to the right of the factor name.

**Drag behavior:** Factor leaf nodes are draggable. A drag ghost (small chip showing the factor name) follows the cursor. Drag data carries `{ "name": "PCA.PC1", "type": "double" }` as JSON via `dataTransfer.setData()`.

**Default state:** All namespace groups expanded.

**Empty states:**
- No step selected: "Select a data step in the project navigator"
- No factors available: "No factors available for this step"
- No search matches: "No matching factors"

#### Section 3: INFO
Icon: circle-info

| Control | Type | Notes |
|---------|------|-------|
| GitHub link | Icon + link | Links to the repository |

### 4.3 Main Panel

This app has no separate main panel. The entire app is a single-column tool window (see 4.1).

### 4.4 Search/Filter Behavior

When the user types in the search field:
1. The tree filters to show only factors whose full name (including namespace) contains the search text (case-insensitive)
2. Matching factors are shown within their namespace group (group header always visible for context)
3. Namespace groups that contain matching factors are auto-expanded
4. Namespace groups with no matching factors are hidden

When the search field is cleared, the full factor list returns with all groups expanded.

---

## 5. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | Factor list loads within 1 second of receiving a `step-selected` message |
| NFR-02 | Search filtering responds as the user types (no submit button) |
| NFR-03 | Factor list handles 200+ factors without performance degradation |
| NFR-04 | The app fits within the orchestrator's tool window panel (typical width 200–400px) |
| NFR-05 | Drag gesture initiates within 100ms of pointer down + move |

---

## 6. Feature Summary

### Must Have

| Feature | Status |
|---------|--------|
| Listen for `step-selected` and display factors | Planned |
| Group factors by namespace in collapsible tree | Planned |
| Alphabetical sorting (groups and factors) | Planned |
| Type-indicating icons (hashtag for numeric, font for string) | Planned |
| Search/filter by name | Planned |
| Draggable factor nodes with JSON drag data | Planned |
| System column filtering | Planned |
| Empty states (no step, no factors, no matches) | Planned |

### Should Have

| Feature | Status |
|---------|--------|
| Clear search on new step selection | Planned |
| All groups expanded by default | Planned |

### Could Have

| Feature | Status |
|---------|--------|
| Keyboard navigation (arrow keys to browse, Enter to start drag) | Planned |

---

## 7. Assumptions

### 7.1 Data Assumptions

- Factors are available only for steps that have been previously executed
- Factor names follow the `namespace.column_name` convention
- System columns (starting with `.`, ending with `._rids` or `.tlbId`) are filtered out before display
- Factor types include: double, string, int (may include others)
- A step typically has 5–50 available factors; some steps may have up to 200

### 7.2 Environment Assumptions

- Runs as an iframe in the orchestrator's second left tool window position
- Appears alongside (not instead of) the project navigator — both panels visible simultaneously
- Receives authentication credentials from the orchestrator via postMessage (`init-context`)
- Panel width is typically 200–400px (resizable via orchestrator splitter)

### 7.3 Mock Data

For Phase 2 (mock build), the factor list uses hardcoded data:

- **3 namespaces:** "Import" (5 factors), "Normalize" (3 factors), "PCA" (4 factors)
- **Factors with realistic bioinformatics names:**
  - Import: gene_id (string), sample_name (string), expression_value (double), batch_id (int), tissue_type (string)
  - Normalize: mean (double), sd (double), method (string)
  - PCA: PC1 (double), PC2 (double), PC3 (double), variance_explained (double)
- **Total:** 12 mock factors
- Mock data is hardcoded in a service class — no network calls in Phase 2
- On receiving a mock `step-selected` message, the same factor list is shown regardless of step ID

### 7.4 Inter-App Messages

**Outgoing:**

| Message type | Target | Payload | When |
|-------------|--------|---------|------|
| `request-context` | orchestrator | `{}` | App requests credentials on load |
| `app-ready` | orchestrator | `{}` | App initialization complete |

**Incoming:**

| Message type | From | Payload | Effect |
|-------------|------|---------|--------|
| `init-context` | orchestrator | `{ token, teamId, serviceUri?, themeMode }` | Initialize with credentials |
| `step-selected` | project_nav (broadcast) | `{ projectId, workflowId, stepId }` | Load factors for this step |
| `theme-changed` | orchestrator | `{ mode }` | Switch light/dark theme |

---

## 8. Glossary

| Term | Definition |
|------|------------|
| Factor | A data column available from a previously executed workflow step. Has a name and a type. |
| Namespace | The prefix of a factor name (text before the first dot). Typically corresponds to the ancestor step that produced the factor. |
| System column | Internal Tercen columns (names starting with `.`, ending with `._rids` or `.tlbId`) that are filtered out. |
| Drag source | The factor navigator acts as a drag source — factor nodes can be dragged out of the panel. |
| Drop zone | An area in the plot viewer where factors are dropped to assign them to roles. Not part of this app. |
| Tool window | A side panel in the orchestrator, toggled via the icon strip. |
