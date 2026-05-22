---
title: Setup Guide
---

# Setup Guide

## Prerequisites

### macOS

```bash
brew install cmake xcodegen deno
```

### Linux (GNUstep)

```bash
apt install clang cmake libsqlite3-dev libssl-dev gnustep-devel
# Install Deno: https://deno.land/manual/getting_started/installation
```

## Clone & Build

```bash
git clone https://github.com/jack/garazyk.git
cd garazyk
```

### macOS

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

### Linux

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

## Run a Scenario

```bash
# Start Docker services via the local network script
./scripts/scenarios/setup_local_network.sh

# Run the scenario suite
deno task hamownia

# Or a single scenario
deno run -A packages/hamownia/cli.ts run --scenario account_lifecycle
```

## Next Steps

- [Codebase Map](codebase-map.md) — understand the directory layout
- [Tutorials](../10-tutorials/index.md) — learn by doing
- [Architecture Overview](../20-explanation/architecture/atproto_pds_architecture.md)
