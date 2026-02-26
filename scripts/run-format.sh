#!/bin/bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"
echo "Formatting source files..."
find ATProtoPDS/Sources ATProtoPDS/Tests -name "*.m" -o -name "*.c" -o -name "*.h" | xargs clang-format -i -style=file
echo "Formatting complete."
