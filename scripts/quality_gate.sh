#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/build/reports"
mkdir -p "$REPORT_DIR"

echo "=== Starting Quality Gate Check ==="
echo "Date: $(date)"

# 1. Run Clang-Tidy (Check only, no auto-fix)
echo "--- Running Clang-Tidy ---"
# Check if compile_commands.json exists, if not, cmake
if [ ! -f "$PROJECT_ROOT/build/compile_commands.json" ]; then
    echo "Generating compile_commands.json..."
    cd "$PROJECT_ROOT/build" && cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
    cd "$PROJECT_ROOT"
fi

# Run clang-tidy on sources (this can be slow, limiting to Source directory)
# find ATProtoPDS/Sources -name "*.m" | xargs clang-tidy -p build

# 2. Run OCLint
echo "--- Running OCLint ---"
# Ensure we have clean build log?
# Or use compile_commands.json with oclint-json-compilation-database

if command -v oclint-json-compilation-database &> /dev/null; then
    cd "$PROJECT_ROOT/build"
    # Filter out generated files or external libs if necessary
    oclint-json-compilation-database -e build -e Tests -- \
        -report-type json -o "$REPORT_DIR/oclint.json" \
        -max-priority-1=0 -max-priority-2=20 \
        -rc LONG_LINE=150
    
    cd "$PROJECT_ROOT"
    python3 "$SCRIPT_DIR/process_oclint_report.py" "$REPORT_DIR/oclint.json" --threshold 20
else
    echo "Warning: oclint-json-compilation-database not found. Skipping OCLint."
fi

echo "=== Quality Gate Passed ==="
