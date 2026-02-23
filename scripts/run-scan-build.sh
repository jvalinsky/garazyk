#!/bin/bash
set -e
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "$repo_root"

if ! command -v scan-build &> /dev/null; then
    echo "Error: scan-build not found. Install with 'brew install llvm' or use nix shell."
    exit 1
fi

echo "Running Clang Static Analyzer (scan-build)..."
rm -rf build-analyzed
mkdir -p build-analyzed
cd build-analyzed

# Use clang from nix/system
CC=$(which clang)
scan-build -use-cc="$CC" cmake .. -DCMAKE_BUILD_TYPE=Debug
scan-build -use-cc="$CC" make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "Static analysis complete. Reports in build-analyzed/tmp/scan-build-*"
