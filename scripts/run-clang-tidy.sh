#!/bin/bash
set -e
cd "/Users/jack/Software/garazyk"
echo "Running clang-tidy static analysis..."
find ATProtoPDS/Sources -name "*.m" -o -name "*.c" | head -50 | xargs -I{} clang-tidy -p . --config-file=.clang-tidy {} 2>&1 | grep -E "(warning|error)" | head -100 || true
echo "Clang-tidy analysis complete."
