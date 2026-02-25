# Tercen Icon System

Two-tier system. Same concept = same icon, always, no exceptions.

---

## Tier 1: Tercen Custom Icons (ONLY for these 6 concepts)

| Icon | Class | Concept |
|------|-------|---------|
| Data Step | `tercen-Data-Step` | Data processing step in a workflow |
| Workflow | `tercen-Workflow` | Complete analysis pipeline |
| Submodule | `tercen-Submodule` | Nested/reusable workflow module |
| Gather | `tercen-Gather` | Data aggregation operation |
| Join | `tercen-Join` | Data merge operation |
| Clone | `tercen-clone` | Git-style repository clone (NOT file copy) |

Do NOT use these for generic concepts. For "copy file" use FontAwesome copy, not `tercen-clone`.

## Tier 2: FontAwesome 6 Solid (everything else)

### Actions
plus (add), pen (edit), trash (delete), floppy-disk (save), copy, play (run), stop, pause, rotate (refresh), rotate-left (undo), rotate-right (redo)

### Transfer
upload, download, file-import, file-export, share-nodes

### Navigation
house (home), arrow-left (back), arrow-right (forward), bars (menu), ellipsis (more), chevron-down (expand), chevron-up (collapse)

### Data Operations
magnifying-glass (search), filter, sort, layer-group (group)

### Status
circle-check (success, green), circle-xmark (error, red), triangle-exclamation (warning, amber), circle-info (info, primary), circle-question (help), spinner fa-spin (loading)

### User & Access
user, users (team), lock (private), lock-open (public), right-to-bracket (sign in), right-from-bracket (sign out)

### Documents & Data
file, folder, folder-open, table, database

### Charts
chart-bar, chart-line, chart-pie, chart-area

### Settings
gear (settings), sliders (options), wrench (tools)

### View
eye (show), eye-slash (hide), grip (grid view), list (list view), expand (fullscreen), compress (exit fullscreen), magnifying-glass-plus (zoom in), magnifying-glass-minus (zoom out)

## Decision Flow

```
Is this a Tercen platform concept (Data Step, Workflow, Submodule, Gather, Join, Clone)?
├── YES -> Use tercen-* class
└── NO  -> Use FontAwesome fa-solid class
```

## Rules
- Same concept = same icon, always
- Tercen icons exclusive to the 6 defined concepts
- Never create custom icons for generic concepts
- State variants use same base (lock/lock-open, not different icons)
- When uncertain, ask — do not improvise
