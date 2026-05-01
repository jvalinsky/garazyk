#!/usr/bin/env bash
set -euo pipefail

# ── objc-jupyter-wasm JupyterLite demo builder + server ──────────
#
# Prerequisites (one-time):
#   pip3 install jupyterlite==0.6.4 jupyterlab==4.4.5
#   cd objc-jupyter-wasm && npm install
#   nix build "path:objc-jupyter-wasm#kernel-wasm" -L
#
# Usage:
#   bash scripts/serve-demo.sh          # build + serve on port 8765
#   bash scripts/serve-demo.sh 9000     # custom port

PORT="${1:-8765}"
PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$PROJ_ROOT/dist/jupyterlite"
EXT_NAME="objc-jupyter-wasm"

# ── 1. Build TypeScript lib ──────────────────────────────────────
echo ">> Building TypeScript lib..."
npm --prefix "$PROJ_ROOT" run build:lib --silent

# ── 2. Build labextension (webpack federated extension) ──────────
echo ">> Building labextension..."
# jupyter labextension build is a thin wrapper around @jupyterlab/builder
# The pip-installed binary lives in ~/Library/Python/3.9/bin/ on macOS
JUPYTER_BIN=""
for candidate in \
  "$HOME/Library/Python/3.9/bin/jupyter" \
  "$HOME/Library/Python/3.10/bin/jupyter" \
  "$HOME/Library/Python/3.11/bin/jupyter" \
  "$HOME/Library/Python/3.12/bin/jupyter" \
  "$(which jupyter 2>/dev/null)"; do
  if [ -x "$candidate" ] 2>/dev/null; then
    JUPYTER_BIN="$candidate"
    break
  fi
done

if [ -z "$JUPYTER_BIN" ]; then
  echo "ERROR: jupyter not found. Install with: pip3 install jupyterlab==4.4.5" >&2
  exit 1
fi

PATH="$(dirname "$JUPYTER_BIN"):$PATH" jupyter labextension build "$PROJ_ROOT"

# ── 3. Copy WASM assets into labextension ─────────────────────────
echo ">> Copying WASM assets..."
npm --prefix "$PROJ_ROOT" run build:assets --silent

# ── 4. Build JupyterLite site ────────────────────────────────────
echo ">> Building JupyterLite site..."
rm -rf "$DIST"
cd "$PROJ_ROOT"
PATH="$(dirname "$JUPYTER_BIN"):$PATH" python3 -m jupyterlite build \
  --config jupyterlite_config.py \
  --lite-dir . \
  || true  # JupyterLite 0.6.4 bug: _output/tree/ merge fails — non-fatal

# ── 5. Patch jupyter-lite.json with federated extension ─────────
# The build fails to populate federated_extensions due to the
# _output merge bug. We patch it manually.
echo ">> Patching jupyter-lite.json with kernel extension..."

# Find the remoteEntry.js path from the extension's _build metadata
REMOTE_ENTRY=""
PKG_JSON="$DIST/extensions/$EXT_NAME/package.json"
if [ -f "$PKG_JSON" ]; then
  REMOTE_ENTRY=$(python3 -c "
import json, sys
pkg = json.load(open('$PKG_JSON'))
build = pkg.get('jupyterlab', {}).get('_build', {})
load = build.get('load', '')
if not load:
    sys.exit(1)
print(load)
" 2>/dev/null || true)
fi

if [ -z "$REMOTE_ENTRY" ]; then
  echo "ERROR: Could not find remoteEntry.js in extension" >&2
  exit 1
fi

python3 -c "
import json, glob, os

ext_name = '$EXT_NAME'
remote_entry = '$REMOTE_ENTRY'
dist_dir = '$DIST'
load_path = f'extensions/{ext_name}/{remote_entry}'

ext_entry = {
    'name': ext_name,
    'extension': True,
    'load': load_path,
}

for f in glob.glob(os.path.join(dist_dir, '**/jupyter-lite.json'), recursive=True):
    if 'extensions' in f:
        continue
    try:
        config = json.load(open(f))
    except Exception:
        continue
    jcd = config.setdefault('jupyter-config-data', {})
    fe = jcd.get('federated_extensions', None)
    if fe is not None:
        # Replace or append
        existing = [e for e in fe if e.get('name') != ext_name]
        existing.append(ext_entry)
        jcd['federated_extensions'] = existing
    else:
        jcd['federated_extensions'] = [ext_entry]

    # Set default kernel
    if 'defaultKernelName' not in jcd or jcd['defaultKernelName'] == 'python':
        jcd['defaultKernelName'] = 'objective-c'

    with open(f, 'w') as fh:
        json.dump(config, fh, indent=2)

print(f'  Patched jupyter-lite.json files with {ext_name} extension')
"

# ── 6. Verify ────────────────────────────────────────────────────
echo ">> Verifying built site..."
python3 -c "
import json, os
config = json.load(open('$DIST/jupyter-lite.json'))
fe = config.get('jupyter-config-data', {}).get('federated_extensions', [])
kernel = config.get('jupyter-config-data', {}).get('defaultKernelName', '')
wasm = os.path.exists('$DIST/extensions/$EXT_NAME/static/kernel/kernel.wasm')
print(f'  federated_extensions: {len(fe)} registered')
print(f'  defaultKernelName: {kernel}')
print(f'  kernel.wasm: {\"found\" if wasm else \"MISSING\"}')
if not fe or not wasm:
    raise SystemExit('ERROR: Site is incomplete')
"

# ── 7. Serve ─────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Objective-C JupyterLite Demo"
echo "  http://localhost:$PORT/lab"
echo ""
echo "  Demo notebooks are in Files/:"
echo "    hello.ipynb"
echo "    foundation.ipynb"
echo "    interactive.ipynb"
echo "    algorithms.ipynb"
echo "========================================="
echo ""

cd "$DIST"
python3 -m http.server "$PORT"
