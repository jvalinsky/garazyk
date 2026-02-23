#!/bin/bash
cd "/Users/jack/Software/garazyk"
echo "Formatting source files..."
find ATProtoPDS/Sources ATProtoPDS/Tests -name "*.m" -o -name "*.c" -o -name "*.h" | xargs clang-format -i -style=file
echo "Formatting complete."
