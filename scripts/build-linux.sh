#!/bin/bash
# Linux Build Script for ATProto PDS
# Run this on a Linux VM with GNUstep installed

set -e

echo "=== ATProto PDS Linux Build Script ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
command -v gnustep-config >/dev/null 2>&1 || { echo "ERROR: GNUstep not installed" >&2; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake not installed" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git not installed" >&2; exit 1; }
command -v pkg-config >/dev/null 2>&1 || { echo "ERROR: pkg-config not installed" >&2; exit 1; }

# Check for blocks_runtime.h (required for blocks/ARC support)
if [ ! -f "/usr/include/objc/blocks_runtime.h" ] && [ ! -f "/usr/lib/gcc/x86_64-linux-gnu/*/include/objc/blocks_runtime.h" ]; then
    echo "WARNING: Objective-C blocks_runtime.h not found."
    echo "This is required for blocks and ARC support."
    echo ""
    echo "Ubuntu 22.04 does not include this header in standard repositories."
    echo ""
    echo "Options to fix this:"
    echo "1. Use Ubuntu 24.04 or later which has libobjc4 with blocks support"
    echo "2. Build libobjc4 from source: https://github.com/gnustep/libobjc2"
    echo "3. Use Arch Linux or Fedora which have better GNUstep support"
    echo ""
    echo "For a quick test, you can try installing from GNUstep's PPA:"
    echo "  sudo add-apt-repository ppa:gnustep/packages"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install libobjc4-dev gnustep-devel"
    echo ""
    echo "Continuing anyway (build may fail if blocks/ARC are used)..."
    echo ""
fi

echo "GNUstep flags: $(gnustep-config --objc-flags)"
echo ""

# Clone repo if not present
if [ ! -d "NSPds" ]; then
    echo "Cloning repository..."
    if [ -n "$GITHUB_TOKEN" ]; then
        git clone https://$GITHUB_TOKEN@github.com/jvalinsky/NSPds.git
    elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        git clone git@github.com:jvalinsky/NSPds.git
    else
        echo "ERROR: No GitHub access configured. Set up SSH keys or GitHub token."
        exit 1
    fi
fi

cd NSPds

# Initialize submodules
echo "Initializing submodules..."
git submodule update --init --recursive

# Create build directory
echo "Configuring build..."
mkdir -p build-linux
cd build-linux

cmake -DCMAKE_BUILD_TYPE=Debug ..

# Build
echo "Building..."
make -j$(nproc)

echo ""
echo "=== Build Complete ==="
echo "Binaries in: $(pwd)/bin/"
ls -la bin/

echo ""
echo "To run tests:"
echo "  cd build-linux && ./tests/AllTests"
