# Tercen Layout Principles

These layout rules are mandatory for all UI work. Source: Tercen Layout Principles v2.0.

---

## C.R.A.P. Design Principles

Every layout decision must satisfy:

- **Contrast** — If elements differ, make them *obviously* different. No subtle differences.
- **Repetition** — Reuse consistent spacing, colors, fonts, component styles across all views.
- **Alignment** — Every element visually connects to something else. Nothing placed arbitrarily. Prefer left-alignment.
- **Proximity** — Group related items together. Separate unrelated elements with space.

---

## Structural Layout Rules

1. **Corner-out design** — All layouts anchor from top-left (0,0).
2. **Nested origins** — Frame, panel, and content each have their own top-left origin.
3. **Left-out approach** — NO right sidebars. All persistent panels on the left.
4. **Top bars are exceptions** — Toolbars only when essential (Save, Run). Ask: can this live in the left panel or a popover?
5. **Left-out, no stretch** — Elements have natural widths. Do NOT stretch to fill. Empty space on the right is fine. No `justify-content: space-between` pushing items to opposite edges. No full-width buttons that stretch with the container.
6. **Two-direction canvas** — Content grows right and down only, never up or left.
7. **Layered left panel** — Persistent expandable sections + contextual popovers (not more panels).
8. **No hidden elements** — Every feature has a visible, clickable affordance. Hover is for enhancement only (tooltips, color change). No hover-to-reveal actions. No hotkey-only features. Tablet test: can a user with no keyboard and no hover discover every feature?

---

## Component Sizing

- Size components for their **content**, not available space.
- Form control heights: Small 28px, Default 36px, Large 44px.
- Width should reflect expected content length, not stretch to fill.
- Fixed width when content has predictable bounded length (status dropdowns).
- Full width when content length is unpredictable (search, free text) and the control is alone in its row.

---

## Anti-Patterns (NEVER do these)

- Unequal grid gaps (e.g., 4px horizontal, 12px vertical)
- `Expanded` / `flex: 1` on dropdowns/controls
- Arbitrary spacing values (10px, 15px, 22px)
- Right sidebars
- Centering content that should be left-aligned
- Stretched/justified layouts (`justify-content: space-between`)
- Hover-to-reveal UI elements
- Hotkey-only features
- Four-direction infinite canvas (always top-left origin, grow right/down)
