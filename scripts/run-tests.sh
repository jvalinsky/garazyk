#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Running all tests..."
"$SCRIPT_DIR/../build/tests/AllTests"
echo "Tests complete."
