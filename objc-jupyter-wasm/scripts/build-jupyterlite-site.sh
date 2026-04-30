#!/bin/bash
set -euo pipefail

# build-jupyterlite-site.sh: build a full JupyterLite site with the Objective-C kernel.
#
# Prerequisites:
#   - npm install (for TypeScript compilation and labextension build)
#   - kernel.wasm built (via Nix or scripts/build-all.sh)
#   - jupyterlab and jupyterlite-core pip-installed
#
# Usage:
#   bash scripts/build-jupyterlite-site.sh [--kernel-wasm PATH]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_DIR="$PROJECT_ROOT/dist/jupyterlite"

echo "=== Building Objective-C JupyterLite site ==="

# Step 1: Build TypeScript
echo "[1/5] Compiling TypeScript..."
npm run build:lib --prefix "$PROJECT_ROOT" --silent 2>/dev/null

# Step 2: Build JupyterLab federated extension
echo "[2/5] Building JupyterLab federated extension..."
jupyter labextension build "$PROJECT_ROOT" 2>/dev/null

# Step 3: Copy WASM assets into the labextension static dir
echo "[3/5] Copying WASM assets into labextension..."
ASSET_ARGS=()
if [ "${1:-}" = "--kernel-wasm" ] && [ -n "${2:-}" ]; then
    ASSET_ARGS+=(--kernel-wasm "$2")
    shift 2
fi
node "$PROJECT_ROOT/scripts/copy-static-assets.mjs" "${ASSET_ARGS[@]}"

# Step 4: Install the Python package (so jupyter lite build can find the extension)
echo "[4/5] Installing Python package..."
pip install --force-reinstall --no-deps "$PROJECT_ROOT" -q 2>/dev/null

# Step 5: Build the JupyterLite site
echo "[5/5] Building JupyterLite site..."
rm -rf "$SITE_DIR"
jupyter lite build --config "$PROJECT_ROOT/jupyterlite_config.py" 2>/dev/null

echo ""
echo "=== Build Complete ==="
echo "Site: $SITE_DIR"
echo ""
echo "To serve:"
echo "  python -m http.server 8080 --directory $SITE_DIR"
echo "  open http://localhost:8080/lab"
