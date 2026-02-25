# All Styling From Tercen Design System Only

ALL theme colors, spacing, typography, icons, component styles, and visual tokens **must** come from the Tercen Design System.

Source of truth: https://github.com/tercen/tercen-style

## What this means

- Do not invent colors. Use the palette defined in `04-tercen-style-reference.md`.
- Do not invent spacing values. Use the 8px grid: 4, 8, 16, 24, 32, 48. Nothing else.
- Do not invent icon choices. Use FontAwesome 6 Solid or the 6 Tercen custom icons.
- Do not invent component styles. Follow the component specs in the style reference.
- Do not invent typography. Use the Fira Sans type scale.

## When something is not covered

If a visual decision is not covered by the design system, **ask the user**. Do not improvise, guess, or "pick something close." Flag it and wait for direction.

## Applies to all apps

This rule applies to every app in the monorepo: orchestrator, toolbar, project_nav, and plot_viewer. The shared theme in `packages/tercen_shared/` is the single source of truth for all apps.
