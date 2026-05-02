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
PATH="$(dirname "$JUPYTER_BIN"):$PATH" jupyter lite build \
  --config jupyterlite_config.py \
  --lite-dir . \
  || true  # JupyterLite 0.6.4 bug: _output/tree/ merge fails — non-fatal

# ── 5. Patch jupyter-lite.json with federated extension ─────────
# When the JupyterLite build succeeds (with --lite-dir .), the
# federated_extensions:patch step already populates the extension list.
# Our patch is only needed when the build's patch step fails (the
# _output merge bug). We check first and only patch if missing.
#
# CRITICAL: We must also deduplicate — JupyterLite merges configs from
# root + subdirectory jupyter-lite.json files. If the extension appears
# in both root and a subdirectory, it gets loaded twice, causing
# "Plugin 'objc-jupyter-wasm:kernel' is already registered".
echo ">> Checking federated extension registration..."

python3 -c "
import json, glob, os

ext_name = '$EXT_NAME'
dist_dir = '$DIST'

# Read the _build metadata from the extension's package.json
pkg_json = os.path.join(dist_dir, 'extensions', ext_name, 'package.json')
pkg = json.load(open(pkg_json))
build = pkg.get('jupyterlab', {}).get('_build', {})

ext_entry = {
    'name': ext_name,
    **build,
}

# Collect all jupyter-lite.json files (root + subdirectories)
all_configs = []
for f in sorted(glob.glob(os.path.join(dist_dir, '**/jupyter-lite.json'), recursive=True)):
    if 'extensions' in f:
        continue
    all_configs.append(f)

# Check if root config already has the extension
root_config = os.path.join(dist_dir, 'jupyter-lite.json')
root_data = json.load(open(root_config))
root_fe = root_data.get('jupyter-config-data', {}).get('federated_extensions', [])
already_registered = any(e.get('name') == ext_name for e in root_fe)

if already_registered:
    # Build succeeded — deduplicate: keep extension ONLY in root config,
    # remove from subdirectory configs to prevent double-loading.
    patched = 0
    for f in all_configs:
        if f == root_config:
            continue  # keep root as-is
        try:
            config = json.load(open(f))
        except Exception:
            continue
        jcd = config.get('jupyter-config-data', {})
        fe = jcd.get('federated_extensions', None)
        if fe is not None and any(e.get('name') == ext_name for e in fe):
            jcd['federated_extensions'] = [e for e in fe if e.get('name') != ext_name]
            with open(f, 'w') as fh:
                json.dump(config, fh, indent=2)
            patched += 1
    if patched > 0:
        print(f'  Deduplicated: removed extension from {patched} subdirectory configs')
    else:
        print(f'  Already registered (no duplicates)')
else:
    # Build failed to register — patch all configs
    patched = 0
    for f in all_configs:
        try:
            config = json.load(open(f))
        except Exception:
            continue
        jcd = config.setdefault('jupyter-config-data', {})
        fe = jcd.get('federated_extensions', None)
        if fe is not None:
            existing = [e for e in fe if e.get('name') != ext_name]
            existing.append(ext_entry)
            jcd['federated_extensions'] = existing
        else:
            jcd['federated_extensions'] = [ext_entry]

        if 'defaultKernelName' not in jcd or jcd['defaultKernelName'] == 'python':
            jcd['defaultKernelName'] = 'objective-c'

        with open(f, 'w') as fh:
            json.dump(config, fh, indent=2)
        patched += 1
    print(f'  Patched {patched} jupyter-lite.json files with {ext_name} extension')

# Always ensure defaultKernelName is set on root
root_data = json.load(open(root_config))
jcd = root_data.setdefault('jupyter-config-data', {})
if 'defaultKernelName' not in jcd or jcd['defaultKernelName'] == 'python':
    jcd['defaultKernelName'] = 'objective-c'
    with open(root_config, 'w') as fh:
        json.dump(root_data, fh, indent=2)
    print(f'  Set defaultKernelName to objective-c')
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
