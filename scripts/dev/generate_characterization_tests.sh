#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
SOURCE_DIR="$REPO_ROOT/Garazyk/Sources"
GENERATOR_SCRIPT="$SCRIPT_DIR/generate_characterization_tests.py"

if [ $# -eq 0 ]; then
    echo "Usage: $0 ClassName1 [ClassName2 ...]"
    exit 1
fi

for CLASS_NAME in "$@"; do
    echo "Searching for $CLASS_NAME.h in $SOURCE_DIR..."
    
    # Find the header file
    HEADER_FILE=$(find "$SOURCE_DIR" -name "${CLASS_NAME}.h" | head -n 1)
    
    if [ -z "$HEADER_FILE" ]; then
        echo "Error: Header file for $CLASS_NAME not found."
        continue
    fi
    
    echo "Found header: $HEADER_FILE"
    echo "Generating tests..."
    
    python3 "$GENERATOR_SCRIPT" "$HEADER_FILE"
    
    echo "Done for $CLASS_NAME."
    echo "-----------------------------------"
done

echo "Test generation complete."
echo "Don't forget to run 'cmake ..' to register new test files and update 'test_main.m'!"
