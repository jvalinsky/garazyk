# Garazyk

Standards-oriented AT Protocol implementation in Objective-C for macOS and Linux/GNUstep.

`docs/` is the canonical source of truth for contributor and operator documentation.

## Start Here

- [Contributor Guide](docs/index.md)
- [Documentation Map](docs/11-reference/documentation-map.md)
- [Setup](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Request Lifecycle](docs/01-getting-started/request-lifecycle.md)
- [Context Map](docs/01-getting-started/context-map.md)
- [Services Setup](docs/guides/services-setup.md)
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

## Contributing

1. Build using the platform commands above.
2. Run focused tests first, then broader suites.
3. Update docs for any contributor-facing behavior change.
4. Keep internal links valid across repository markdown.

### Quality Gates

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
xcodebuild -scheme kaszlak build
```

If fuzzers were touched, rebuild affected fuzz targets.
Register new test classes in `Garazyk/Tests/test_main.m`.

## Documentation Governance

- `docs/` is the canonical contributor documentation path.
- Root files should remain entrypoints, not duplicate long-form content.
- Internal markdown links must stay valid across the repository scope.
- Historical material should be archived and indexed, not silently dropped.

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
- [Spec Version & Lexicon Compliance](docs/11-reference/spec-version.md)

## Related Entrypoints

- [Agent Instructions](AGENTS.md)
- [Agent Quick Reference](AGENTS_QUICKREF.md)
