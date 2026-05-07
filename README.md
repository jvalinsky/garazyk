# Garazyk

Full AT Protocol stack in portable Objective-C — PDS, AppView, Relay, PLC Server, and Admin UI. Runs on macOS (Apple frameworks) and Linux (GNUstep).

## Architecture

Garazyk implements the complete ATProto service topology in a single Objective-C codebase:

- **PDS** — Personal Data Server: repo hosting, XRPC endpoints, blob storage, account management
- **AppView** — indexing, backfill, profile/feed/notification queries
- **Relay** (BGS) — firehose aggregation, crawl dispatch, event stream
- **PLC Server** — DID PLC directory: rotation key management, operation log, export
- **Admin UI** — HTMX server with AppKit aesthetics, 18 XRPC client methods, tabbed admin shell

The stack is built on a sans-I/O HTTP architecture (`HttpProtocolDriver`, `HttpConnectionIOCoordinator`, `HttpResponseSender`) with WebSocket firehose support, full OAuth2 provider (PKCE, DPoP, refresh token rotation, passkey), AVFoundation video transcoding (H.264/H.265, FFmpeg on Linux), and MST/CAR repository encoding.

26 source modules, 33 test directories, 2676+ tests. See [Codebase Map](docs/01-getting-started/codebase-map.md) for the full layout.

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

### Nix (WASM kernel)

```bash
cd objc-jupyter-wasm && nix build .#kernel-wasm
```

## WASM Kernel

`objc-jupyter-wasm/` — a C interpreter compiled to WASM via wasi-sdk, capable of running Objective-C in the browser. Node.js test scripts load the WASM and execute ObjC through a JSON bridge. Host bridges provide SHA-256, CBOR, base32/base58, and random bytes that WASM can't do natively. 20 ATProto tutorial notebooks cover identifiers, CID, DAG-CBOR, CAR, MST, XRPC dispatch, and more.

## Testing

- **2676+ tests** across 33 test directories — core suite passes with 0 failures
- **Scenario tests** — `scripts/scenarios/` and `scripts/seed_*.py` for full-stack simulation
- **Fuzzing** — corpus, harnesses, crashers, and mutators in `fuzzing/`
- **Coverage builds** — `cmake -DENABLE_COVERAGE=ON` with LLVM profraw

See [Test Organization](docs/11-reference/test-organization.md) and [Test Selection Workflow](docs/11-reference/test-selection-workflow.md).

## Docker

Local-network stack for development and testing:

```bash
docker compose up
```

Includes PDS, Admin UI, and supporting services. See [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) and [Service Orchestration](docs/guides/SERVICE_ORCHESTRATION_GUIDE.md).

## Documentation

`docs/` is the canonical source of truth for contributor and operator documentation. Root files are entrypoints — long-form content lives in `docs/`.

- [Contributor Guide](docs/index.md)
- [Documentation Map](docs/11-reference/documentation-map.md)
- [Setup](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Request Lifecycle](docs/01-getting-started/request-lifecycle.md)
- [Context Map](docs/01-getting-started/context-map.md)
- [Services Setup](docs/guides/services-setup.md)
- [Tutorials](docs/10-tutorials/index.md)
- [CLI Reference](docs/11-reference/cli-reference.md)
- [Admin UI Documentation](docs/11-reference/admin-ui-documentation.md)
- [Spec Version & Lexicon Compliance](docs/11-reference/spec-version.md)

## Contributing

1. Build using the platform commands above.
2. Run focused tests first, then broader suites. Register new test classes in `Garazyk/Tests/test_main.m`.
3. Update `docs/` for any contributor-facing behavior change.
4. Keep internal markdown links valid across the repository.

## Agent Tools

AI assistants use `deciduous` decision tracking. See [AGENTS.md](AGENTS.md) for operational guidance and [AGENTS_QUICKREF.md](AGENTS_QUICKREF.md) for build commands.
