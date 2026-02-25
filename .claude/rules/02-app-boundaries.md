# App Boundaries — No Cross-App Imports

This is a monorepo with multiple apps in `apps/` and shared packages in `packages/`.

## The rule

Apps must **never** import from each other. All shared code lives in `packages/widget_library/`.

```
apps/orchestrator/  ──depends on──>  packages/widget_library/  <──depends on──  apps/step_viewer/
apps/factor_nav/    ──depends on──>  packages/widget_library/  <──depends on──  apps/project_nav/

apps/step_viewer/ ──X── apps/factor_nav/     (NEVER)
apps/project_nav/ ──X── apps/orchestrator/   (NEVER)
```

## When something needs to be shared

If app A needs a class, function, model, or service that currently lives in app B:

1. Move it to `packages/widget_library/`
2. Export it from the shared package
3. Both apps depend on the shared package

Do NOT copy code between apps. Do NOT create "convenience" imports across app boundaries.

## Why

This rule exists so each app can be split into its own repository later. The split is mechanical: publish `widget_library` as a Git dependency, move the app folder, change `path:` to `git:` in pubspec.yaml. No code changes needed.

## Monorepo structure

```
plot_viewer_operator/
├── apps/
│   ├── orchestrator/      # Thin shell: layout, routing, inter-app messaging
│   ├── project_nav/       # Left panel: project -> workflow -> step tree
│   ├── factor_nav/        # Left panel: factor navigation via link graph
│   └── step_viewer/       # Center content: plot visualization + GGRS WASM
├── packages/
│   └── widget_library/    # Shared: models, services, theme, message contracts
```
