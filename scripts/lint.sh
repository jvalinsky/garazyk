#!/bin/bash
set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

MODE="${1:-all}"
BUILD_DIR="$ROOT_DIR/build"

if [[ "$MODE" == "format" || "$MODE" == "all" ]]; then
    echo ">>> Formatting..."
    find "$ROOT_DIR/ATProtoPDS/Sources" "$ROOT_DIR/ATProtoPDS/Tests" -name "*.m" -o -name "*.c" -o -name "*.h" | xargs clang-format -i -style=file
fi

if [[ "$MODE" == "tidy" || "$MODE" == "all" ]]; then
    echo ">>> Running clang-tidy..."
    # Ensure compile_commands.json exists
    if [ ! -f "$BUILD_DIR/compile_commands.json" ]; then
        echo "compile_commands.json not found. Running build configuration..."
        "$SCRIPT_DIR/build.sh"
    fi
    find "$ROOT_DIR/ATProtoPDS/Sources" -name "*.m" -o -name "*.c" | head -50 | xargs -I{} clang-tidy -p "$BUILD_DIR" --config-file="$ROOT_DIR/.clang-tidy" {} 2>&1 | grep -E "(warning|error)" | head -100 || true
fi

if [[ "$MODE" == "scan" ]]; then
    echo ">>> Running scan-build..."
    SCAN_BUILD_DIR="$ROOT_DIR/build_scan"
    if [ -d "$SCAN_BUILD_DIR" ]; then rm -rf "$SCAN_BUILD_DIR"; fi
    mkdir -p "$SCAN_BUILD_DIR"
    scan-build -o "$SCAN_BUILD_DIR/report" cmake -S "$ROOT_DIR" -B "$SCAN_BUILD_DIR" -DCMAKE_BUILD_TYPE=Debug
    scan-build -o "$SCAN_BUILD_DIR/report" cmake --build "$SCAN_BUILD_DIR" -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    echo "Scan build report generated in $SCAN_BUILD_DIR/report"
fi

echo "Lint/format complete."
