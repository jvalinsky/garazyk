# Garazyk

AT Protocol stack in portable Objective-C — PDS, AppView, Relay, PLC Server, and Admin UI. Runs on macOS (Apple frameworks) and Linux (GNUstep).

## Architecture

Garazyk implements the ATProto service topology in an Objective-C codebase:

- **PDS** — Personal Data Server: repo hosting, XRPC endpoints, blob storage, account management
- **AppView** — indexing, backfill, profile/feed/notification queries
- **Relay** (BGS) — firehose aggregation, crawl dispatch, event stream
- **PLC Server** — DID PLC directory: rotation key management, operation log, export
- **Admin UI** — Standalone HTMX service for live monitoring and administration.
- **Scenario Dashboard** — Deno Fresh application for orchestrating narrative integration tests.

The stack uses a sans-I/O HTTP architecture (`HttpProtocolDriver`, `HttpConnectionIOCoordinator`, `HttpResponseSender`) with WebSocket firehose support, `GZLogger` with PII redaction, OAuth2 provider (PKCE, DPoP, refresh token rotation, passkey), AVFoundation video transcoding (H.264/H.265, FFmpeg on Linux), and MST/CAR repository encoding.

26 source modules, 33 test directories, 2676+ tests. See [Codebase Map](docs/01-getting-started/codebase-map.md) for the layout.

### Prerequisites

- **macOS**: `brew install cmake xcodegen deno`
- **Linux**: `apt install clang cmake libsqlite3-dev libssl-dev gnustep-devel` (and [install Deno](https://deno.land/manual/getting_started/installation))

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

- **2676+ tests** across 33 test directories
- **Deno Scenarios** — TypeScript integration tests in `scripts/scenarios/` orchestrating the local Docker network
- **Scenario Dashboard** — Browser-based UI for running tests and viewing historical results via SQLite
- **Fuzzing** — corpus, harnesses, crashers, and mutators in `fuzzing/`
- **Coverage builds** — `cmake -DENABLE_COVERAGE=ON` with LLVM profraw

See [Test Organization](docs/11-reference/test-organization.md), [Test Selection Workflow](docs/11-reference/test-selection-workflow.md), and [Deno Scenario Framework](docs/11-reference/deno-scenario-framework.md).

## Docker

Local-network stack for development and testing:

```bash
docker compose up
```

Includes PDS, Admin UI, and supporting services. See [Docs Site Deployment Guide](docs/DEPLOYMENT_GUIDE.md) and [Service Orchestration](docs/guides/SERVICE_ORCHESTRATION_GUIDE.md).

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
- [Deno Scenario Framework](docs/11-reference/deno-scenario-framework.md)
- [Spec Version & Lexicon Compliance](docs/11-reference/spec-version.md)

## Contributing

1. Build using the platform commands above.
2. Run focused tests first, then broader suites. Register new test classes in `Garazyk/Tests/test_main.m`.
3. Update `docs/` for any contributor-facing behavior change.
4. Keep internal markdown links valid across the repository.

## Licensing

Original code in this repository is released to the public domain under the
**Unlicense OR CC0-1.0** dual dedication. Per-file SPDX headers are
authoritative. Full license texts are in `UNLICENSE` and `LICENSES/`.

### Original code (`Garazyk/Sources/`, `Garazyk/Tests/`, `Garazyk/Binaries/`)

Licensed under `Unlicense OR CC0-1.0` — your choice. Each file carries:

```
SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
SPDX-License-Identifier: Unlicense OR CC0-1.0
```

### Compat/ platform shims (`Garazyk/Sources/Compat/`)

These files are **original** API-compatible reimplementations of Apple
framework APIs (CommonCrypto, Security, CoreFoundation, LocalAuthentication,
os/log, XCTest). They are not derived from Apple or GNUstep source code — they
merely provide the same API surface, backed by OpenSSL, SQLite, and other
open-source libraries on Linux. They are released under the same
`Unlicense OR CC0-1.0` terms as the rest of the project.

**Note**: On Linux, the runtime links against GNUstepBase (LGPL-2.1+). This is
a library dependency, not a code provenance issue — the Compat/ shims are
original work that calls into GNUstepBase, not derived from it.

### Vendored third-party code

| Path | License | Copyright |
|---|---|---|
| `secp256k1/` | MIT | Pieter Wuille |
| `vendor/secp256k1/` | MIT | Pieter Wuille |
| `vendor/reference/did-method-plc/` | MIT OR Apache-2.0 | Bluesky Social PBC |
| `vendor/reference/Allegedly/` | Apache-2.0 | Bluesky Social PBC |

These directories retain their original licenses and are **not** covered by
the Unlicense/CC0 dedication. See their respective `LICENSE`/`COPYING` files.

### Attribution

- `Garazyk/Sources/Repository/MSTWalker.h/.m` — based on the
  [atproto MST walker](https://github.com/bluesky-social/atproto/blob/main/packages/repo/src/mst/walker.ts)
  (MIT OR Apache-2.0, Bluesky Social PBC). The Objective-C implementation is
  original; the algorithm and data structures follow the reference.

## Agent Tools

AI assistants use `deciduous` decision tracking. See [AGENTS.md](AGENTS.md) for operational guidance and [AGENTS_QUICKREF.md](AGENTS_QUICKREF.md) for build commands.
