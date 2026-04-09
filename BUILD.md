# Build Guide

This file is the short build reference for contributors. The canonical onboarding path still starts in [`docs/index.md`](docs/index.md) and [`docs/01-getting-started/setup.md`](docs/01-getting-started/setup.md).

## Build Rules

- Always use out-of-source builds.
- On macOS, run `xcodegen generate` before building.
- Treat `docker/pds/` as the only supported Compose root for deployment-style runs.

## macOS

```bash
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

Primary outputs:

- `./build/bin/kaszlak`
- `./build/bin/campagnola`
- `./build/tests/AllTests`

## Linux and GNUstep

Choose an explicit build directory and keep using it consistently.

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

Primary outputs:

- `./build-linux/bin/kaszlak`
- `./build-linux/bin/campagnola`
- `./build-linux/tests/AllTests`

The output location follows the build directory you pass to CMake. Do not mix `build-linux` configuration with `./build/...` runtime paths.

## Quality Gates

Before pushing work that changes code or build-sensitive behavior, verify:

1. `xcodegen generate`
2. `xcodebuild -scheme AllTests build`
3. `./build/tests/AllTests`
4. `xcodebuild -scheme ATProtoPDS-CLI build`
5. fuzzer builds if you modified fuzzing-related code

## Related Docs

- [Setup Guide](docs/01-getting-started/setup.md)
- [Testing Map](docs/11-reference/testing-map.md)
- [Contributing Guide](CONTRIBUTING.md)
