---
title: Setup Guide
---

# Setup Guide

## Overview

This page describes the contributor setup for the repository:

- macOS contributors use `xcodegen` and `xcodebuild`
- builds are out-of-source
- Docker workflows are run from `docker/pds/`

## Local Workflow

The goal is to get a contributor to a local workflow:

1. generate the project,
2. build the main targets,
3. run the test binary,
4. start the server with a config,
5. verify the routes.

## Build Rules That Matter

### Use out-of-source builds

Never run `cmake` in the repository root. Keep build artifacts in a separate directory.

### Use XcodeGen on macOS

On macOS, regenerate the Xcode project before building:

```bash
xcodegen generate
xcodebuild -scheme kaszlak build
```

### Treat `docs/` as the canonical docs site

There is an experimental docs site elsewhere in the repo. Ignore it for this contributor flow.

## Prerequisites

### macOS

You **must** install XcodeGen to generate the project structure. If it is missing, the build will fail.

```bash
xcode-select --install
brew install cmake xcodegen
```

- macOS 14 or later
- Xcode 16.1 or later
- Xcode Command Line Tools
- CMake 3.28 or later
- XcodeGen
- Git

### Linux and GNUstep

You **must** have clang and the GNUstep runtime development libraries installed.

```bash
sudo apt-get update
sudo apt-get install clang libblocksruntime-dev cmake libsqlite3-dev libssl-dev gnustep-devel
```

- recent Linux distribution with GNUstep development packages
- clang
- CMake 3.28 or later
- SQLite and OpenSSL development headers
- Git

## Recommended macOS Workflow

macOS is the primary contributor path for this repository.

### Step 1: install the toolchain

```bash
xcode-select --install
brew install cmake xcodegen
```

### Step 2: generate the Xcode project

```bash
xcodegen generate
```

This step is required because:

- the repo expects XcodeGen to materialize the current project structure,
- the documented quality gates use Xcode schemes,
- and test execution depends on the generated project matching the source tree.

### Step 3: build the main targets

```bash
xcodebuild -scheme kaszlak build
xcodebuild -scheme syrena build
xcodebuild -scheme zuk build
xcodebuild -scheme campagnola build
xcodebuild -scheme AllTests build
```

### Step 4: run the shared tests

```bash
./build/tests/AllTests
```

### Step 5: start the server explicitly

```bash
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

The CLI grammar is `kaszlak <command> [flags]`, and the built binary you will usually invoke directly is `./build/bin/kaszlak`.

### Step 6: start the Admin UI when you need operator workflows

The Admin UI now runs as its own service:

```bash
xcodebuild -scheme garazyk-ui build
GARAZYK_UI_ADMIN_PASSWORD=dev-admin ./build/bin/garazyk-ui serve
```

It listens on `http://127.0.0.1:2590/admin` by default. Use `GARAZYK_UI_PDS_URL`, `GARAZYK_UI_PLC_URL`, `GARAZYK_UI_RELAY_URL`, `GARAZYK_UI_APPVIEW_URL`, and `GARAZYK_UI_CHAT_URL` when your backing services are not on their default local ports.

## Recommended Linux Workflow

Linux is supported, but the contributor ergonomics are different because the GNUstep toolchain is closer to the raw build system.

### Step 1: create an out-of-source build directory

```bash
mkdir -p build-linux
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=ON
cmake --build build-linux -j 8
```

### Step 2: run tests if the build generated them

```bash
./build-linux/tests/AllTests
```

### Step 3: start the server with explicit paths

```bash
./build-linux/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

## Minimal Local Config Shape

The config loader reads snake_case keys. Use this shape as the baseline mental model:

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

Two important subtleties:

- `PDSConfiguration` has development-oriented defaults when instantiated without a config file.
- `kaszlak serve` has its own CLI defaults and can override config values such as port and data directory.

Do not infer production guidance from bare runtime defaults.

## First Verification Pass

After the server starts, verify the discovery and contributor surfaces rather than assuming the process is healthy just because it is running.

```bash
./build/bin/kaszlak account list
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq '.did'
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2590/admin
```


These checks confirm:

- protocol discovery,
- Explorer and OpenAPI docs routing,
- and the standalone Admin UI service, when it is running.

## Docker Workflow

The compose workflow is rooted in `docker/pds/`.

Run compose commands from that directory, not from the repo root:

```bash
cd docker/pds
docker compose build
docker compose up -d
```

## Implementation Notes

### macOS Build Path

Use XcodeGen on macOS. Raw `cmake ..` commands are not supported for the macOS contributor path.

### Configuration Keys

Use snake_case keys as documented in [Config Reference](../11-reference/config-reference). Older camelCase examples are stale.

### Defaults

Development defaults and deployment defaults differ. Deployment guidance lives in [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment).

## Related Reading

- [Codebase Map](./codebase-map)
- [Request Lifecycle](./request-lifecycle)
- [Config Reference](../11-reference/config-reference)
- [CLI Reference](../11-reference/cli-reference)
- [Testing Map](../11-reference/testing-map)
- [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment)
