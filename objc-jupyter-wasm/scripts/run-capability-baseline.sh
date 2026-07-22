#!/usr/bin/env bash
# Rebuild and verify the Objective-C WASM support boundary, then regenerate its matrix.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
repository_dir=$(cd -- "$project_dir/.." && pwd)
baseline_dir=$(mktemp -d "${TMPDIR:-/tmp}/objc-jupyter-wasm-baseline.XXXXXX")

cleanup() {
  rm -rf -- "$baseline_dir"
}
trap cleanup EXIT

cd -- "$repository_dir"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  printf '%s\n' 'Refusing to generate a capability baseline from a dirty checkout.' >&2
  printf '%s\n' 'Commit or stash local changes, then rerun this command.' >&2
  exit 1
fi

nix build ./objc-jupyter-wasm#kernel-wasm --out-link "$baseline_dir/kernel-first"
first_store_path=$(readlink "$baseline_dir/kernel-first")
second_store_path=$(nix build ./objc-jupyter-wasm#kernel-wasm --no-link --print-out-paths | tail -n 1)

if [[ "$first_store_path" != "$second_store_path" ]]; then
  printf 'kernel-wasm builds resolved to different store paths:\n  %s\n  %s\n' \
    "$first_store_path" "$second_store_path" >&2
  exit 1
fi

current_system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build "./objc-jupyter-wasm#checks.${current_system}.smoke-site-assets" --no-link
nix build ./objc-jupyter-wasm#jupyterlite-smoke-site --out-link "$baseline_dir/smoke-site"

matrix_args=(
  --kernel "$baseline_dir/kernel-first/wasm/kernel.wasm"
  --output "$project_dir/docs/capability-matrix.md"
)

if [[ -n "${PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH:-}" ]]; then
  matrix_args+=(--smoke-site "$baseline_dir/smoke-site")
fi

node "$script_dir/generate-capability-matrix.mjs" "${matrix_args[@]}"
