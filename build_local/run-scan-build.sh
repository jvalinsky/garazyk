#!/bin/bash
set -e
cd "/Users/jack/Software/garazyk"
echo "Running Clang Static Analyzer (scan-build)..."
rm -rf build-analyzed
mkdir build-analyzed
cd build-analyzed
scan-build -use-cc=$(which clang) cmake .. -DCMAKE_BUILD_TYPE=Debug
scan-build -use-cc=$(which clang) make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo "Static analysis complete."
