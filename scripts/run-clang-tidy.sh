#!/bin/bash
set -e
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"
echo "Running clang-tidy static analysis..."
find ATProtoPDS/Sources -name "*.m" -o -name "*.c" | head -50 | xargs -I{} clang-tidy -p . --config-file=.clang-tidy {} 2>&1 | grep -E "(warning|error)" | head -100 || true
echo "Clang-tidy analysis complete."
