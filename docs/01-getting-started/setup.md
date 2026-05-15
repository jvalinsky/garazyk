---
title: Setup Guide
---

# Setup Guide

## Overview

This guide walks through setting up your local environment for Garazyk development.

- **macOS** contributors use `xcodegen` and `xcodebuild`.
- **Linux** contributors use `cmake` and the GNUstep runtime.
- **Docker** workflows are available in `docker/pds/`.

## Prerequisites

### macOS

- macOS 14 or later
- Xcode 16.1 or later with Command Line Tools
- [CMake](https://cmake.org/) 3.28 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# Install dependencies via Homebrew
brew install cmake xcodegen
xcode-select --install
```

### Linux (GNUstep)

- Recent Linux distribution (e.g., Ubuntu 22.04+)
- Clang
- CMake 3.28 or later
- GNUstep development libraries
- SQLite and OpenSSL development headers

```bash
sudo apt-get update
sudo apt-get install clang libblocksruntime-dev cmake libsqlite3-dev libssl-dev gnustep-devel
```

## Recommended macOS Workflow

macOS is the primary development platform for Garazyk.

### 1. Generate the Xcode Project

Garazyk uses XcodeGen to manage its project structure. You must regenerate the project whenever files are added or removed.

```bash
xcodegen generate
```

### 2. Build the Targets

Use `xcodebuild` or open `Garazyk.xcodeproj` in Xcode.

```bash
# Build the primary PDS binary
xcodebuild -scheme kaszlak build

# Build other specialized binaries
xcodebuild -scheme syrena build      # AppView
xcodebuild -scheme zuk build         # Relay
xcodebuild -scheme campagnola build  # PLC
xcodebuild -scheme garazyk-ui build  # Admin UI

# Build all tests
xcodebuild -scheme AllTests build
```

### 3. Run Tests

Verify your build by running the test suite:

```bash
./build/tests/AllTests
```

### 4. Start the Server

Start the PDS with a local configuration:

```bash
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

The server will be available at `http://localhost:2583`.

### 5. Start the Admin UI (Optional)

The Admin UI runs as a standalone service:

```bash
GARAZYK_UI_ADMIN_PASSWORD=dev-admin ./build/bin/garazyk-ui serve
```

Access it at `http://localhost:2590/admin`.

## Recommended Linux Workflow

On Linux, use a standard CMake out-of-source build.

```bash
mkdir -p build-linux
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=ON
cmake --build build-linux -j $(nproc)

# Run tests
./build-linux/tests/AllTests

# Start the server
./build-linux/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

## Configuration

Garazyk uses JSON configuration files with `snake_case` keys.

### Minimal Local Config

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 2583,
    "data_dir": "./pds-data",
    "issuer": "http://localhost:2583"
  },
  "plc": { "url": "mock" },
  "session": { "invite_code_required": false }
}
```

- **Issuer**: Must match the public-facing URL of your PDS.
- **PLC**: Set to `"mock"` for isolated local development.

See the [Config Reference](../11-reference/config-reference) for more details.

## Verification

After starting the server, verify it is healthy:

```bash
# Check protocol discovery
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq

# List accounts (should be empty initially)
./build/bin/kaszlak account list

# Verify Admin UI (if running)
curl -I http://127.0.0.1:2590/admin
```

## Docker Workflow

For a fully containerized environment, use Docker Compose:

```bash
cd docker/pds
docker compose build
docker compose up -d
```

## Related Reading

- [Codebase Map](./codebase-map) — Understand the directory structure.
- [CLI Reference](../11-reference/cli-reference) — Explore `kaszlak` commands.
- [Testing Map](../11-reference/testing-map) — Guide to the test suite.
- [Deployment Guide](../docs/DEPLOYMENT_GUIDE.md) — Production setup.
