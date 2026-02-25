#!/usr/bin/env bash
set -euo pipefail

# Ensure asdf shims (flutter, dart) are on PATH for non-interactive shells (IDE run configs)
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATOR_DIR="$REPO_ROOT/apps/orchestrator"
ORCHESTRATOR_WEB="$ORCHESTRATOR_DIR/web"

# Map from app directory name to registry ID used in webapp_registry.dart
declare -A APP_REGISTRY_IDS=(
  [project_nav]="project-nav"
  [toolbar]="toolbar"
  [step_viewer]="step-viewer"
)

# Build GGRS WASM and copy assets into step_viewer
GGRS_ROOT="/home/thiago/workspaces/tercen/main/ggrs"
GGRS_TARGET="$REPO_ROOT/apps/step_viewer/web/ggrs/pkg"
echo "=== Building GGRS WASM ==="
(cd "$GGRS_ROOT" && wasm-pack build crates/ggrs-wasm --target web)
echo ""
echo "=== Copying GGRS WASM assets ==="
mkdir -p "$GGRS_TARGET"
cp "$GGRS_ROOT/crates/ggrs-wasm/pkg/ggrs_wasm.js" "$GGRS_TARGET/"
cp "$GGRS_ROOT/crates/ggrs-wasm/pkg/ggrs_wasm_bg.wasm" "$GGRS_TARGET/"
echo "GGRS assets copied to $GGRS_TARGET"
echo ""

echo "=== Building all apps ==="
echo "Repo root: $REPO_ROOT"
echo ""

built_apps=()

# Build only step_viewer (add other apps here as needed)
ONLY_APPS=(step_viewer)

for app_name in "${ONLY_APPS[@]}"; do
  app_dir="$REPO_ROOT/apps/$app_name"

  if [ ! -f "$app_dir/pubspec.yaml" ]; then
    echo "[$app_name] Skipping — no pubspec.yaml"
    echo ""
    continue
  fi

  echo "[$app_name] Cleaning & building..."
  cd "$app_dir"
  flutter clean
  flutter pub get --no-example
  flutter build web --profile --source-maps

  # Copy build output into orchestrator's web directory
  target_dir="$ORCHESTRATOR_WEB/$app_name"
  rm -rf "$target_dir"
  cp -r "$app_dir/build/web" "$target_dir"

  echo "[$app_name] Copied to orchestrator/web/$app_name/"
  built_apps+=("$app_name")
  echo ""
done

# Build orchestrator
echo "[orchestrator] Cleaning & building..."
cd "$ORCHESTRATOR_DIR"
flutter clean
flutter pub get --no-example
flutter build web --profile --source-maps

echo ""
echo "=== Done ==="
echo "Built apps: ${built_apps[*]:-none}"
echo ""
echo "Run the orchestrator:"
echo "  cd apps/orchestrator && flutter run -d chrome --web-port 8080"
