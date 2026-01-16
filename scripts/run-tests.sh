#!/bin/bash
set -e
cd "/Users/jack/Software/objpds/.worktrees/macos-xnu-integration"
echo "Running all tests..."
/Users/jack/Software/objpds/.worktrees/macos-xnu-integration/build/tests/AllTests
echo "Tests complete."
