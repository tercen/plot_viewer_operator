# Tercen Style Reference

Complete visual specification from the Tercen Design System (https://github.com/tercen/tercen-style).

---

## Colors

### Primary
| Token | Value | Usage |
|-------|-------|-------|
| `--primary` | `#1E40AF` | Primary actions, active states, links |
| `--primary-dark` | `#1E3A8A` | Hover states, dark emphasis |
| `--primary-light` | `#2563EB` | Light emphasis, secondary active |
| `--primary-surface` | `#DBEAFE` | Selected backgrounds, focus rings |
| `--primary-bg` | `#EFF6FF` | Subtle background tints |

### Accent / Functional (dual-purpose: status AND data viz)
| Token | Value | Usage |
|-------|-------|-------|
| `--green` / `--green-light` | `#047857` / `#D1FAE5` | Success, positive values |
| `--teal` / `--teal-light` | `#0E7490` / `#CFFAFE` | Info, secondary data |
| `--amber` / `--amber-light` | `#B45309` / `#FEF3C7` | Warning, caution |
| `--red` / `--red-light` | `#B91C1C` / `#FEE2E2` | Error, danger, negative values |
| `--violet` / `--violet-light` | `#6D28D9` / `#EDE9FE` | New, special labels |

### Neutrals
| Token | Value | Usage |
|-------|-------|-------|
| `--neutral-900` | `#111827` | Primary text |
| `--neutral-800` | `#1F2937` | Dark backgrounds (tooltips, code) |
| `--neutral-700` | `#374151` | Secondary text, body text |
| `--neutral-600` | `#4B5563` | Subtle headings, labels |
| `--neutral-500` | `#6B7280` | Placeholder text, muted text |
| `--neutral-400` | `#9CA3AF` | Disabled text, icons |
| `--neutral-300` | `#D1D5DB` | Borders, dividers |
| `--neutral-200` | `#E5E7EB` | Light borders, table lines |
| `--neutral-100` | `#F3F4F6` | Subtle backgrounds, hover |
| `--neutral-50` | `#F9FAFB` | Row hover, lightest bg |
| `--white` | `#FFFFFF` | Card backgrounds, content areas |

---

## Typography

- **Font family:** `'Fira Sans', -apple-system, BlinkMacSystemFont, sans-serif`
- **Monospace:** `'SF Mono', 'Consolas', 'Monaco', monospace`
- **Base size:** 16px, weight 400, line-height 1.5
- **Antialiasing:** `-webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale`

### Type Scale
| Role | Size | Weight | Notes |
|------|------|--------|-------|
| Page title | 36px | 700 | |
| Section title | 24px | 600 | |
| Subsection title | 14px | 600 | Uppercase, 0.5px letter-spacing |
| Body | 16px | 400 | line-height 1.5 |
| Small body / UI text | 14px | 400-500 | |
| Caption / helper | 12px | 400-500 | |
| Label (form) | 11-12px | 500-600 | Uppercase for section headers |
| Code | 13px | 400 | Monospace font |

---

## Spacing (8px base grid)

**Only these values. Never 10px, 15px, 18px, 22px, or any other arbitrary value.**

| Token | Value | Usage |
|-------|-------|-------|
| `--space-xs` | 4px | Tight: grid gaps, icon-to-text, inline elements |
| `--space-sm` | 8px | Related elements: label to field, list items |
| `--space-md` | 16px | Standard: component padding, between form fields |
| `--space-lg` | 24px | Section spacing: between card groups |
| `--space-xl` | 32px | Large gaps: page margins, major sections |
| `--space-2xl` | 48px | Extra large: between major page regions |

### Equal Gap Rule
Within a single component (image grid, card grid), horizontal and vertical spacing **must be equal**.

---

## Border Radius
| Token | Value | Usage |
|-------|-------|-------|
| `--radius-sm` | 4px | Badges, small elements, code |
| `--radius-md` | 8px | Buttons, inputs, cards |
| `--radius-lg` | 12px | Sections, panels, modals |
| `--radius-xl` | 16px | Large containers |
| `--radius-full` | 9999px | Pills, toggles, progress bars |

## Shadows
| Token | Value | Usage |
|-------|-------|-------|
| `--shadow-sm` | `0 1px 2px rgba(0,0,0,0.05)` | Cards, subtle lift |
| `--shadow-md` | `0 4px 6px rgba(0,0,0,0.07)` | Hover states, thumbnails |
| `--shadow-lg` | `0 10px 15px rgba(0,0,0,0.1)` | Popovers, dropdowns, toasts |
| `--shadow-xl` | `0 20px 25px rgba(0,0,0,0.15)` | Modals |

---

## Components

### Buttons
| Variant | Background | Text | Border |
|---------|-----------|------|--------|
| Primary | `--primary` | white | none |
| Secondary | transparent | `--primary` | 1.5px solid `--primary` |
| Ghost | transparent | `--primary` | none |
| Subtle | `--neutral-100` | `--neutral-700` | none |
| Danger | `--red` | white | none |
| Disabled | `--neutral-200` | `--neutral-400` | none |

Padding: default `10px 20px`, small `6px 12px`, large `14px 28px`. Font: 14px, weight 500, radius `--radius-md`.

### Form Inputs
- Padding: `10px 14px`, border: `1px solid --neutral-300`, radius `--radius-md`
- Focus: border `--primary`, box-shadow `0 0 0 3px --primary-surface`
- Error: border `--red`, focus shadow `0 0 0 3px --red-light`
- Disabled: bg `--neutral-100`, color `--neutral-400`
- Placeholder: `--neutral-400`

### Badges
- Padding `4px 10px`, radius `--radius-sm`, font 12px weight 500, 6px dot indicator
- Variants: success (green), info (teal), warning (amber), error (red), primary, neutral

### Alerts (inline, bordered)
- Left border 4px, padding `16px 18px`, 32px round icon
- Variants: success, info, warning, error

### Toasts (bold/inverted)
- Full-color bg, white text, max-width 380px, `--shadow-lg`
- Variants: success, info, warning, error

### Tabs
- Container: bg `--neutral-100`, 4px padding, 4px gap, radius `--radius-md`
- Tab: padding `10px 20px`, 14px font, 1px border
- Active tab: bg `--primary`, white text, weight 600

### Data Tables
- Font 14px, th bg `--neutral-50`, border-bottom `--neutral-200`, cell padding 12px, row hover `--neutral-50`

### Modals
- Overlay `rgba(0,0,0,0.5)` centered, white bg, radius `--radius-lg`, shadow `--shadow-xl`, max-width 480px

### Tooltips
- bg `--neutral-800`, white text, 12px font, `6px 12px` padding, radius `--radius-sm`

### Breadcrumbs
- bg `--primary-bg`, border `--primary-surface`, 15px font, links `--primary`, current `--primary-dark` weight 700

### Left Panel
- Width 280px (min 200px, max 400px), white bg, right border `1px solid --neutral-200`
- Sections: collapsible, header 12px uppercase 0.5px letter-spacing, bg `--neutral-50`

### Popovers
- White bg, `1px solid --neutral-200`, radius `--radius-md`, shadow `--shadow-lg`
- Min-width 240px, max-width 360px

### Toolbar
- Min-height 48px, gap `--space-sm`, padding `--space-sm --space-md`, white bg, bottom border `--neutral-200`
- Buttons: 13px, `6px 12px` padding, transparent bg, radius `--radius-sm`

### Spinners
- Default 24px/3px, Small 16px/2px, Large 32px/4px. Track `--neutral-200`, indicator `--primary`.

### Chips/Tags
- Pill shape (`--radius-full`), 13px, `4px 12px` padding, bg `--neutral-100`

---

## Application States

### Empty State
- Centered column, 64px icon (0.5 opacity), 16px title (neutral-700), 14px message (neutral-500), optional CTA

### Error State
- Centered, bg `--red-light`, border `--red`, 48px icon, 16px title in red, 14px message, retry button

### Loading State
- Centered spinner + 14px text (neutral-600)
- Skeleton: animated gradient pulse (`neutral-200` -> `neutral-100` -> `neutral-200`)

### Disabled State
- `opacity: 0.5; pointer-events: none; user-select: none`

### Selection States
- Hover: bg `--neutral-50`
- Selected: bg `--primary-surface`, border `--primary`
- List selected: bg `--primary-surface`, left border 3px `--primary`
- Card selected: border 2px `--primary`, bg `--primary-bg`
- Focus: `box-shadow: 0 0 0 3px --primary-surface`
- Focus-visible: `outline: 2px solid --primary`, offset 2px

---

## Data Display
- Numeric values: monospace font
- Null: `--neutral-400`, italic
- Positive: `--green`
- Negative: `--red`
- Truncation: `overflow: hidden; text-overflow: ellipsis; white-space: nowrap`

---

## Density Levels
| Level | Gaps | Controls | When |
|-------|------|----------|------|
| Compact | 4px | 28px | Image grids, file lists, table cells, sidebars |
| Standard | 8-16px | 36px | Forms, settings, dashboards (DEFAULT) |
| Spacious | 24-32px | 44px | Hero areas, onboarding, emphasis |

## Data Grid / Table Sizing
| Element | Value |
|---------|-------|
| Row height (compact) | 32px |
| Row height (default) | 40px |
| Row height (comfortable) | 48px |
| Cell horizontal padding | 12px (16px comfortable) |
| Header background | `#F3F4F6` |
| Row hover | `#F9FAFB` |

## Image & Grid Rules
- Grid gap: `--space-sm` (8px) standard, `--space-xs` (4px) compact. Gaps must be equal both directions.
- Container padding: 16px around grid
- Image containers: bg `--neutral-100`, border `1px solid --neutral-200`, radius `--radius-md`, overflow hidden
- Aspect ratios: square (1:1), video (16:9). object-fit: cover.
- Columns: <400px 2-3, 400-600px 3-4, 600-900px 4-6, >900px 6-8
