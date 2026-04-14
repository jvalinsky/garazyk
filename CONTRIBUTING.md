# Contributing to September PDS

This repository expects contributors to work from the current contributor docs, not from stale copied examples.

Start here:

- [Contributor Guide](docs/index.md)
- [Setup Guide](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Testing Map](docs/11-reference/testing-map.md)

## Development Workflow

1. Create a branch from your current base.
2. Build using the canonical platform path:
   - macOS: `xcodegen generate`, then `xcodebuild`
   - Linux: `cmake -S . -B <build-dir>`, then `cmake --build <build-dir>`
3. Make the smallest coherent change.
4. Run the narrowest useful tests first, then broader coverage as needed.
5. Update docs whenever the behavior, workflow, or contributor-facing surface changes.
6. Run the repository quality gates before you push.

## Build and Test Expectations

macOS is the primary contributor path. Use:

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
xcodebuild -scheme ATProtoPDS-CLI build
```

Linux and GNUstep contributors should keep their chosen out-of-source build directory consistent:

```bash
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/tests/AllTests
```

## Documentation Requirements

Documentation updates are required when you change:

- build or setup workflows
- XRPC endpoints or contributor tooling routes
- service boundaries or application behavior that contributors need to understand
- configuration keys or operational defaults
- CLI commands or flags
- testing workflows or required verification steps

For contributor-facing docs, prefer the numbered pages under `docs/` first. The older `docs/guides/`, `docs/architecture/`, `docs/security/`, and `docs/tests/` collections remain useful, but they are secondary reference material.

## Testing Rules That Commonly Get Missed

- New test classes must be added to `Garazyk/Tests/test_main.m`.
- Route or service changes should start with targeted tests, not an immediate full-suite run.
- If you change fuzzers or fuzzing-sensitive code, rebuild the relevant fuzz targets.

## Review Expectations

Good contributions make it easy to answer:

- which runtime surface changed
- which layer owns the new behavior
- which tests prove it
- which docs explain it now

That is more useful than a large diff with weak verification.

## Quality Gates

Before pushing:

1. `xcodegen generate`
2. `xcodebuild -scheme AllTests build`
3. `./build/tests/AllTests`
4. `xcodebuild -scheme ATProtoPDS-CLI build`
5. fuzzer builds if modified

## Related Docs

- [Build Guide](BUILD.md)
- [CLI Reference](docs/11-reference/cli-reference.md)
- [Config Reference](docs/11-reference/config-reference.md)
- [Troubleshooting](docs/11-reference/troubleshooting.md)
