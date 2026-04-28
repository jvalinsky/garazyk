# Garazyk

Standards-oriented AT Protocol implementation in Objective-C for macOS and Linux/GNUstep.

`docs/` is the canonical source of truth for contributor and operator documentation.

## Start Here

- [Contributor Guide](docs/index.md)
- [Documentation Map](docs/11-reference/documentation-map.md)
- [Setup](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Request Lifecycle](docs/01-getting-started/request-lifecycle.md)
- [Tutorials](docs/10-tutorials/index.md)
- [CLI Reference](docs/11-reference/cli-reference.md)

## Prerequisites

Before building, ensure you have the necessary toolchains installed.

**macOS:**
```bash
xcode-select --install
brew install cmake xcodegen
```

**Linux/GNUstep:**
```bash
sudo apt-get update
sudo apt-get install clang libblocksruntime-dev cmake libsqlite3-dev libssl-dev
```

## Quick Build

### macOS

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
xcodebuild -scheme kaszlak build
```

### Linux/GNUstep

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

## Runtime Surfaces

- `/xrpc/*` protocol endpoints
- `/api/pds/*` explorer/openapi utilities
- `/ui` contributor UI surface
- `/metrics` metrics and monitoring
- `/oauth/*` and `/.well-known/*` auth/discovery surfaces

See [Explorer, OpenAPI & UI](docs/11-reference/explorer-openapi-ui.md) for surface-specific behavior.

## Deep Reference Hubs

- [Admin UI Documentation](docs/11-reference/admin-ui-documentation.md)
- [Source-Adjacent Documentation](docs/11-reference/source-adjacent-documentation.md)
- [Tooling and Skills Documentation](docs/11-reference/tooling-and-skills-documentation.md)
- [Repository Documentation Index](docs/repo-index/index.md)

## Related Entrypoints

- [Build Guide](BUILD.md)
- [Contributing](CONTRIBUTING.md)
- [Documentation Conventions](DOCUMENTATION.md)
- [Agent Instructions](AGENTS.md)
