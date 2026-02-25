# Step Viewer — Functional Specification

**Version:** 1.0.0
**Status:** Draft
**Last Updated:** 2026-02-20
**Reference:** docs/architecture-webapp.md, docs/architecture-ggrs-interactive.md, docs/architecture-pwa.md, docs/plan-overview.md

---

## 1. Overview

### 1.1 Purpose

The step viewer is the core visualization app in the Tercen PWA suite. When a user selects a data step in the project navigator, the step viewer renders an interactive plot using the GGRS rendering engine. Users configure the plot by dragging factors from the factor navigator onto spatial drop zones positioned directly on the plot — X axis below the grid, Y axis to the left, column facet on the top strip, row facet on the left strip. The plot builds incrementally, showing meaningful output at every stage from an empty skeleton to a fully bound visualization.

### 1.2 Users

Tercen platform users who need to visualize data at a workflow step. Typical users are bioinformaticians and data scientists exploring experimental results.

### 1.3 Scope

**In Scope:**
- Receive `step-selected` messages and initialize with step context
- Spatial drop zones on the plot for four roles: X axis, Y axis, Row facet, Column facet
- Small top toolbar with geom type and plot theme selectors
- Incremental GGRS rendering at every binding stage (empty, facets-only, partial axis, full)
- GGRS WASM 5-layer DOM rendering (canvas data, SVG chrome, DOM text, SVG annotations, interaction)
- Resize handling (re-layout on container size change)
- Light/dark theme switching via orchestrator broadcast

**Out of Scope:**
- Color binding (deferred to future right-side collapsible menu)
- Right-side collapsible configuration menu
- Annotations (text, arrows, polygons, rectangles)
- Export (PNG, SVG, high-resolution)
- Multi-layer plots (multiple CubeAxisQueries)
- CubeQuery construction and task submission
- Data selection (lasso, box select)
- Filter configuration
- Operator settings
- Scroll/zoom/pan viewport interaction
- Server-side GGRS rendering path
- Left panel / AppShell layout

### 1.4 App Type

**Type 2 (Interactive).** Data flows from Tercen to the app. The user interacts by dropping factors onto the plot. The app does not write data back to Tercen in this version, but it accepts drag-and-drop input from another app (factor_nav), making it interactive rather than display-only.

---

## 2. Domain Context

### 2.1 Background

In Tercen, a **data step** is a processing node in a workflow. Each data step has a **cross-tab model** (Crosstab) that defines how data is visualized: which factors map to X, Y, color, and faceting roles. The GGRS rendering engine takes this configuration (as a JSON payload) and produces a layered plot.

GGRS supports **incremental binding** — the plot renders at every stage of configuration:

| Stage | Bindings present | What GGRS renders |
|-------|-----------------|-------------------|
| 0 — Empty | Nothing | 3x2 skeleton grid with blank strip labels, white panels, gray borders |
| 1 — Facets only | Row and/or column facet | Actual facet grid with strip labels, themed panels, no axes or data |
| 2–3 — Partial axis | X only or Y only | Falls through to empty layout (no data rendering possible) |
| 4 — Full axes | X + Y | Full layout with axes, ticks, grid lines, axis mappings, data points |
| 5 — Complete | X + Y + facets | Complete faceted visualization |

This incremental behavior means the step viewer always shows something useful — there is no blank screen while the user builds up the plot configuration.

### 2.2 Data Source

The step viewer receives its context from the orchestrator via `step-selected` messages. In Phase 3 (Tercen integration), it will load the step's computed data and available factors from the Tercen backend. In Phase 2 (mock), data is hardcoded.

**GGRS Input: TercenDataPayload**

The GGRS WASM API consumes a JSON payload with this structure:

| Field | Description | Example |
|-------|-------------|---------|
| `version` | Payload format version | `"1.0"` |
| `geom_type` | Chart type | `"point"`, `"line"`, `"bar"`, `"heatmap"` |
| `theme` | Plot theme | `"gray"`, `"bw"`, `"minimal"` |
| `title` | Plot title | `"Iris Dataset"` |
| `labels` | Axis/legend labels | `{ "x": "Sepal Length", "y": "Petal Width" }` |
| `bindings` | Aesthetic role assignments | Each role: `{ "status": "bound", "column": "name" }` or `{ "status": "unbound" }` |
| `qt_stream.data` | Data points | `[{ "xs": 32768, "ys": 49152, "x": 5.1, "y": 3.5, "ci": 0, "ri": 0, "colorhash": 4294967040 }]` |
| `column_stream.labels` | Column facet labels | `[{ "index": 0, "label": "setosa" }]` |
| `row_stream.labels` | Row facet labels | `[{ "index": 0, "label": "male" }]` |

**GGRS Output: LayoutInfo**

GGRS returns comprehensive geometry for rendering: panel bounds, grid lines, axis lines, tick marks, text placements (with position, font, anchor, baseline), strip backgrounds, strip labels, panel backgrounds, panel borders, and axis mappings (for coordinate conversion).

**Binding roles (this version):**

| Role | Binding field | Effect on plot | Drop zone position |
|------|--------------|----------------|--------------------|
| X axis | `bindings.x` | Horizontal axis variable | Below the panel grid |
| Y axis | `bindings.y` | Vertical axis variable | Left of the panel grid |
| Row facet | `bindings.row_facet` | Vertical facet grid (strips on LEFT, Tercen-specific) | On the left strip area |
| Column facet | `bindings.col_facet` | Horizontal facet grid (strips on TOP) | On the top strip area |

**Deferred roles (future right-side menu):**

| Role | Binding field | Effect on plot |
|------|--------------|----------------|
| Color | `bindings.color` | Point/bar color encoding |

### 2.3 Typical Workflow

1. User selects a data step in the project navigator
2. Step viewer receives the `step-selected` message and shows an empty skeleton plot with visible drop zones
3. Factor navigator loads available factors for the selected step
4. User drags a factor from the factor navigator onto the Y axis drop zone (left of grid)
5. Plot remains at skeleton stage (Y-only does not produce axes)
6. User drags another factor onto the X axis drop zone (below grid)
7. Plot renders with full axes, grid lines, tick labels, and data points
8. User drags a factor onto the Column facet drop zone (top strip)
9. Plot re-renders as a faceted grid with column strip labels
10. User changes geom type from "Point" to "Bar" in the top toolbar
11. Plot re-renders as a bar chart

---

## 3. Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Listen for `step-selected` messages and initialize with the selected step's context (projectId, workflowId, stepId) | Must |
| FR-02 | Show an empty skeleton plot (3x2 grid) immediately when a step is selected and no bindings are configured | Must |
| FR-03 | Provide four spatial drop zones positioned on the plot: X axis (below grid), Y axis (left of grid), Row facet (left strip area), Column facet (top strip area) | Must |
| FR-04 | Drop zones remain at constant positions relative to the plot edges; the GGRS grid resizes dynamically within them | Must |
| FR-05 | Accept HTML5 drag-and-drop from factor_nav; parse the drag data JSON (`{ "name": "PCA.PC1", "type": "double" }`) | Must |
| FR-06 | When a factor is dropped on a drop zone, assign the factor to that role and show the factor's short name in the drop zone | Must |
| FR-07 | Provide a clear button (✕) on each assigned drop zone to remove the binding | Must |
| FR-08 | Render the GGRS plot incrementally after every binding change — the plot always reflects the current binding state | Must |
| FR-09 | When only facets are bound (no X or Y), render a facet grid with strip labels and themed panels but no axes or data | Must |
| FR-10 | When X and Y are both bound, render the full plot with axes, ticks, grid lines, and data points | Must |
| FR-11 | Provide a top toolbar with a geom type selector: Point, Line, Bar, Heatmap | Must |
| FR-12 | Provide a top toolbar with a plot theme selector: Gray, Black & White, Minimal | Must |
| FR-13 | Re-render the plot when geom type or theme changes | Must |
| FR-14 | Re-layout and re-render the plot when the container is resized | Must |
| FR-15 | Send `app-ready` message to the orchestrator when initialization is complete | Must |
| FR-16 | Respond to `theme-changed` broadcast by switching light/dark app theme | Must |
| FR-17 | Show a visual drag-over highlight when a factor is dragged over a valid drop zone | Must |
| FR-18 | Use the factor's short name (text after last dot) as the drop zone label and as the axis label passed to GGRS | Must |
| FR-19 | Clear all bindings when a new step is selected | Should |
| FR-20 | Show the full factor name (with namespace) as a tooltip on hover over an assigned drop zone | Should |

---

## 4. User Interface Components

### 4.1 App Structure

The step viewer is a **center-panel app** with no left panel. The entire content area is the plot with spatial drop zones around it and a compact toolbar above. There is no AppShell — the app is full-width.

```
┌──────────────────────────────────────────────────────────────────┐
│ [Point ▾]  [Gray ▾]                                    toolbar  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│             [Column facet: Drop factor here]                     │
│         ┌────────┬────────┬────────┐                             │
│  [Row]  │        │        │        │                             │
│  [fac]  │        │        │        │                             │
│  [et:]  │ panel  │ panel  │ panel  │                             │
│  [Dro]  │        │        │        │                             │
│  [p  ]  ├────────┼────────┼────────┤                             │
│  [fac]  │        │        │        │                             │
│  [tor]  │        │        │        │                             │
│  [her]  │ panel  │ panel  │ panel  │                             │
│  [e  ]  │        │        │        │                             │
│         └────────┴────────┴────────┘                             │
│  [Y axis:                                                        │
│   Drop       [X axis: Drop factor here]                          │
│   factor                                                         │
│   here]                                                          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Layout zones (fixed positions, dynamic content):**

| Zone | Position | Content when empty | Content when bound |
|------|----------|-------------------|-------------------|
| Top toolbar | Top edge, full width | Geom + theme dropdowns | Same |
| Column facet drop | Above the panel grid | "Drop factor here" | Factor short name + ✕ |
| Row facet drop | Left of the panel grid | "Drop factor here" (vertical) | Factor short name + ✕ |
| Y axis drop | Below row facet, left of grid | "Drop factor here" (vertical) | Factor short name + ✕ |
| X axis drop | Below the panel grid | "Drop factor here" | Factor short name + ✕ |
| GGRS plot | Center, fills remaining space | Skeleton 3x2 grid | Rendered plot |

The drop zones occupy the same spatial positions where GGRS renders axis labels and facet strip labels. When a binding is assigned, the GGRS-rendered labels replace the drop zone placeholder text — but the drop zone remains active (re-droppable) and retains its clear (✕) button.

### 4.2 Top Toolbar

A compact control strip above the plot area. Minimum height, left-aligned controls.

| Control | Type | Default | Options |
|---------|------|---------|---------|
| Geom type | Dropdown | Point | Point, Line, Bar, Heatmap |
| Plot theme | Dropdown | Gray | Gray, Black & White, Minimal |

### 4.3 Drop Zones

Four spatial drop zones positioned around the GGRS plot grid. Each drop zone has constant dimensions — the GGRS grid resizes dynamically within the space bounded by the drop zones.

**Drop zone states:**

| State | Appearance |
|-------|------------|
| Empty | Dashed border, muted placeholder text (e.g., "Drop factor here") |
| Drag-over (valid) | Highlighted border (primary color), slightly elevated background |
| Assigned | Factor short name displayed, clear (✕) button visible. GGRS renders axis labels/strip labels in the same space. |

**Drop zone interaction:**
- Accepts drag data containing JSON `{ "name": "...", "type": "..." }` from factor_nav
- Any factor type is accepted for any role (no validation at the step viewer level)
- On drop: assigns the factor, updates the binding, triggers plot re-render
- On clear (✕ click): removes the binding, triggers plot re-render
- Tooltip on hover (when assigned): shows full factor name including namespace

**Spatial relationship to GGRS:**

The drop zones and GGRS rendering share the same spatial areas:
- The **column facet drop zone** occupies the same region as the GGRS column strip labels (top of grid)
- The **row facet drop zone** occupies the same region as the GGRS row strip labels (left of grid)
- The **X axis drop zone** occupies the same region as the GGRS X axis label (below grid)
- The **Y axis drop zone** occupies the same region as the GGRS Y axis label (left of grid, below row facet)

When a binding is assigned, GGRS produces axis labels or strip labels in these positions. The drop zone remains interactive (the user can still drop a different factor or click ✕ to clear).

### 4.4 Main Panel (GGRS Plot)

The GGRS plot fills the space between the drop zones. It is rendered using the 5-layer DOM structure.

**Rendering layers (composited via CSS z-ordering):**
1. **Data layer** — Canvas element for data points
2. **Chrome layer** — SVG for grid lines, axis lines, panel borders, panel backgrounds
3. **Text layer** — DOM div with absolutely positioned spans for tick labels, axis labels, strip labels
4. **Annotation layer** — SVG (empty in this version, reserved for future)
5. **Interaction layer** — DOM div (empty in this version, reserved for future)

**Rendering behavior by binding stage:**

| Binding state | What renders |
|---------------|-------------|
| No bindings | 3x2 skeleton grid: white panels, gray borders, blank strip positions, no axes |
| Facets only (row and/or column) | Facet grid sized to actual facet count, strip labels, themed panels, no axes or data |
| X only or Y only | Falls through to empty/facets layout (single axis cannot produce a meaningful plot) |
| X + Y | Full plot: axes with ticks and labels, grid lines, data points rendered on canvas |
| X + Y + facets | Full faceted plot with per-panel axes and strip labels |

**Resize:** When the container dimensions change, the app re-calls the GGRS layout computation with new width/height and re-renders all layers. Drop zone positions adapt automatically since they are anchored to fixed edges.

### 4.5 Empty States

| Condition | Display |
|-----------|---------|
| No step selected | Centered message: "Select a data step in the project navigator" with a chart icon |
| Step selected, no bindings | GGRS skeleton plot (3x2 grid) with visible drop zones — this IS the empty state for a selected step |
| Error loading step data | Centered error message with the error text |

---

## 5. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | Stateless layout computation completes within 500ms of a binding change |
| NFR-02 | Drop zone drag-over visual feedback appears within 100ms |
| NFR-03 | Resize re-renders without visible flicker (debounced at 100ms) |
| NFR-04 | Works both inside the orchestrator iframe and in standalone mode |
| NFR-05 | GGRS text measurement uses browser Canvas2D for pixel-accurate positioning |
| NFR-06 | Plot area uses the full available width and height minus toolbar |
| NFR-07 | Drop zones have constant dimensions; the GGRS grid adapts to remaining space |

---

## 6. Feature Summary

### Must Have

| Feature | Status |
|---------|--------|
| Spatial drop zones for X, Y, Row facet, Column facet on the plot | Planned |
| Accept factor drag-and-drop from factor_nav | Planned |
| Clear binding via ✕ button on each drop zone | Planned |
| Top toolbar with geom type selector (point, line, bar, heatmap) | Planned |
| Top toolbar with plot theme selector (gray, bw, minimal) | Planned |
| GGRS incremental rendering at every binding stage | Planned |
| Skeleton plot (3x2 grid) when no bindings set | Planned |
| Re-render on binding, geom, or theme change | Planned |
| Resize handling with debounce | Planned |
| `step-selected` message handling | Planned |
| `app-ready` and `theme-changed` message handling | Planned |
| Drop zone visual states (empty, drag-over, assigned) | Planned |

### Should Have

| Feature | Status |
|---------|--------|
| Clear all bindings on new step selection | Planned |
| Full factor name tooltip on assigned drop zones | Planned |

### Could Have

| Feature | Status |
|---------|--------|
| Loading indicator during GGRS WASM initialization | Planned |
| Right-side collapsible menu for color and additional config | Future |

---

## 7. Assumptions

### 7.1 Data Assumptions

- Factor data arrives from the factor_nav app via HTML5 drag-and-drop as JSON: `{ "name": "namespace.column", "type": "double" }`
- Any factor can be dropped on any role (no type validation at the step viewer level)
- The GGRS WASM module is loaded once and reused across re-renders
- Data points use quantized coordinates (u16, 0-65535) for x/y positions plus original float values for axis scale training

### 7.2 Environment Assumptions

- Runs as an iframe in the orchestrator's center content area
- Shares the page with factor_nav (in the orchestrator's left tool window) which provides the drag source
- HTML5 drag-and-drop works across iframe boundaries (orchestrator must not intercept drag events targeting the step viewer iframe)
- GGRS WASM module is available at a known path relative to the app
- Browser supports WebAssembly and Canvas2D
- Receives authentication credentials from the orchestrator via `init-context` message

### 7.3 Mock Data

For Phase 2 (mock build), the app uses hardcoded data simulating an Iris-like dataset:

- **150 data points** across 3 column facets (setosa, versicolor, virginica) and 2 row facets (female, male)
- **Numeric factors:** Sepal.Length (4.3–7.9), Sepal.Width (2.0–4.4), Petal.Length (1.0–6.9), Petal.Width (0.1–2.5)
- **String factors:** Species (setosa, versicolor, virginica), Gender (female, male)
- **Quantized coordinates:** Pre-computed xs/ys values (u16) for each data point
- **Color hashes:** Pre-computed RGBA u32 values (single color, since color binding is not in scope)
- Mock data is hardcoded — no network calls in Phase 2
- On receiving a mock `step-selected` message, the same dataset is used regardless of step ID
- Factors for the drop zones come from factor_nav (separate app); the step viewer does not maintain its own factor list

### 7.4 Inter-App Messages

**Incoming:**

| Message type | From | Payload | Effect |
|-------------|------|---------|--------|
| `init-context` | orchestrator | `{ token, teamId, serviceUri?, themeMode }` | Initialize with credentials and theme |
| `step-selected` | project_nav (broadcast) | `{ projectId, workflowId, stepId }` | Clear bindings, show skeleton plot, prepare for factor drops |
| `theme-changed` | orchestrator (broadcast) | `{ mode }` | Switch light/dark app theme |

**Outgoing:**

| Message type | Target | Payload | When |
|-------------|--------|---------|------|
| `request-context` | orchestrator | `{}` | App requests credentials on load |
| `app-ready` | orchestrator | `{}` | App initialization complete |
| `render-progress` | orchestrator | `{ progress: 0.0–1.0 }` | During data rendering (stateful API path) |

### 7.5 Cross-Iframe Drag-and-Drop

Factor drag-and-drop originates in the factor_nav iframe and targets the step viewer iframe. HTML5 drag-and-drop supports cross-iframe interaction natively when both iframes share the same origin. The orchestrator hosts both iframes and must not consume or block drag events that pass between them. If same-origin is not guaranteed, the orchestrator may need to relay drag data via postMessage (Phase 2 will validate this assumption).

---

## 8. Glossary

| Term | Definition |
|------|------------|
| Aesthetic binding | Mapping a data factor to a visual role (X axis, Y axis, Row facet, Column facet). Color binding is deferred. |
| Binding stage | The current level of plot configuration, from empty (no bindings) to complete (all roles assigned) |
| Drop zone | A spatial target area positioned on the plot where users drop factors dragged from the factor navigator. Four zones: X (below grid), Y (left of grid), Row facet (left strip), Column facet (top strip). |
| Factor | A data column from a workflow step, with a name and type. Delivered via drag-and-drop from factor_nav. |
| GGRS | The Rust-based rendering engine compiled to WASM. Computes layout geometry and maps data to pixel coordinates. |
| Incremental rendering | The ability of GGRS to produce meaningful plot output at every binding stage, from empty skeleton to full visualization |
| LayoutInfo | The JSON output of GGRS containing all geometry needed to render the plot: panel bounds, grid lines, text placements, axis mappings |
| TercenDataPayload | The JSON input format that GGRS expects, containing bindings, data streams, and plot configuration |
| Skeleton plot | The default empty state: a 3x2 grid of blank panels with gray borders, shown when no aesthetic bindings are configured |
| Strip label | Text label on a facet strip (row or column). Row strips appear on the LEFT of panels; column strips on TOP. |
| 5-layer DOM | The composited rendering structure: canvas (data), SVG (chrome), div (text), SVG (annotations), div (interaction) |
| Right-side menu | Future collapsible overlay menu on the right edge for color binding and additional configuration. Not in this version. |
