# Contributing to Garazyk

This is a thin entrypoint. Contributor workflow details are canonical in `docs/`.

## Canonical Contributor Path

- [Contributor Guide](docs/index.md)
- [Setup](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Testing Map](docs/11-reference/testing-map.md)
- [Documentation Map](docs/11-reference/documentation-map.md)

## Minimum Expectations

1. Build using canonical platform commands.
2. Run focused tests first, then broader suites.
3. Update docs for any contributor-facing behavior change.
4. Keep internal links valid across repository markdown.

## Quality Gates

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
xcodebuild -scheme kaszlak build
```

If fuzzers were touched, rebuild affected fuzz targets.
