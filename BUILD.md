# Build Guide

This is a thin entrypoint. Canonical build instructions live in `docs/`.

## Canonical Build Docs

- [Setup](docs/01-getting-started/setup.md)
- [Testing Map](docs/11-reference/testing-map.md)
- [Test Selection Workflow](docs/11-reference/test-selection-workflow.md)
- [Documentation Map](docs/11-reference/documentation-map.md)

## Core Commands

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

## Notes

- Use out-of-source builds.
- Register new test classes in `Garazyk/Tests/test_main.m`.
- If build behavior changes, update canonical docs in `docs/` first.
