#!/bin/bash
cd "/Users/jack/Software/objpds/.worktrees/macos-security-phase2"
echo "Formatting source files..."
find ATProtoPDS/Sources ATProtoPDS/Tests -name "*.m" -o -name "*.c" -o -name "*.h" | xargs clang-format -i -style=file
echo "Formatting complete."
