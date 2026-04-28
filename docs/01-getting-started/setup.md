---
title: Setup Guide
---

# Setup Guide

## Overview

This page is the contributor setup path for the current repository. It is intentionally opinionated:

- macOS contributors should use `xcodegen` and `xcodebuild`
- all builds should be out-of-source
- production-style Docker workflows should be run from `docker/pds/`

If another page suggests a different default, treat this page as the canonical contributor guide for this docs pass.

## What This Setup Optimizes For

The goal is not to teach every possible build permutation. The goal is to get a new contributor to a trustworthy local workflow quickly:

1. generate the project correctly,
2. build the main targets,
3. run the shared test binary,
4. start the server with an explicit config,
5. verify the exposed routes.

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

- macOS 14 or later
- Xcode 16.1 or later
- Xcode Command Line Tools
- CMake 3.28 or later
- XcodeGen
- Git

### Linux and GNUstep

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

Why this matters:

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
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/ui/index.html
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2590/admin
```


These checks confirm:

- protocol discovery,
- Explorer and OpenAPI docs routing,
- and the newer `/ui` asset path.
- the standalone Admin UI service, when it is running.

## Production-Like Docker Workflow

Contributor docs often drift when they ignore the deployment path. This repository’s compose workflow is rooted in `docker/pds/`.

Run compose commands from that directory, not from the repo root:

```bash
cd docker/pds
docker compose build
docker compose up -d
```

That is the only compose workflow this docs pass treats as canonical.

## Common Mistakes

### Using the wrong macOS build path

If you are on macOS and start with raw `cmake ..` commands, you are not following the repository’s preferred contributor path.

### Copying stale config keys

Several older docs used camelCase or renamed fields that `PDSConfiguration` no longer reads. Prefer [Config Reference](../11-reference/config-reference) over older examples.

### Assuming the process default is the production default

Development defaults and secure deployment defaults are not the same thing. Production guidance lives in [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment).

## Related Reading

- [Codebase Map](./codebase-map)
- [Request Lifecycle](./request-lifecycle)
- [Build Guide](../../BUILD.md)
- [Contributing Guide](../../CONTRIBUTING.md)
- [Config Reference](../11-reference/config-reference)
- [CLI Reference](../11-reference/cli-reference)
- [Testing Map](../11-reference/testing-map)
- [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
