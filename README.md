# September PDS

Standards-oriented AT Protocol Personal Data Server implementation in Objective-C for macOS and Linux/GNUstep.

September is a production-style repository, not a toy protocol demo. The fastest way to understand it is to treat the codebase as a set of layers:

- transport and route registration
- XRPC dispatch and auth
- application services
- shared and per-actor storage
- sync, relay, and contributor tooling surfaces

## Start Here

The canonical contributor docs live in [`docs/`](docs/index.md).

- [Contributor Guide](docs/index.md)
- [Setup Guide](docs/01-getting-started/setup.md)
- [Codebase Map](docs/01-getting-started/codebase-map.md)
- [Request Lifecycle](docs/01-getting-started/request-lifecycle.md)
- [Tutorials Overview](docs/10-tutorials/index.md)
- [CLI Reference](docs/11-reference/cli-reference.md)

Older collections such as [`docs/guides/`](docs/guides/README.md), [`docs/architecture/`](docs/architecture/README.md), [`docs/security/`](docs/security/README.md), and [`docs/tests/`](docs/tests/README.md) remain useful, but they are deep reference rather than the main onboarding path.

## Quick Start

### macOS contributor path

```bash
git clone https://github.com/jvalinsky/September.git
cd September
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build
./build/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

### Linux and GNUstep contributor path

```bash
git clone https://github.com/jvalinsky/September.git
cd September
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Debug
cmake --build build-linux -j
./build-linux/bin/kaszlak serve --config ./config.json --data-dir ./pds-data --foreground
```

### First verification

After the server starts:

```bash
curl -sS http://127.0.0.1:2583/xrpc/com.atproto.server.describeServer | jq .
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/api/pds/docs
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2583/ui/Info.plist
```

Use the explicit `/ui` and `/api/pds/*` routes for contributor verification even though the root UI may also be wired as the default entrypoint.

## Runtime Surfaces

The server exposes several distinct surfaces with different ownership rules:

| Surface | Purpose | Primary owner |
| --- | --- | --- |
| `/xrpc/*` | AT Protocol and application protocol methods | `XrpcDispatcher`, `XrpcMethodRegistry`, domain method modules |
| `/api/pds/*` | Explorer, inspection endpoints, and generated OpenAPI | `PDSHttpServerBuilder`, `ExploreHandler` |
| `/ui` | Contributor-facing Objective-J and Cappuccino UI | `PDSHttpServerBuilder`, `CappuccinoUIHandler` |
| `/api/mst/*` | MST viewer and repository inspection helpers | MST viewer handlers |
| `/metrics` | Runtime metrics for monitoring | metrics registration in server builder |
| `/oauth/*` and `/.well-known/*` | OAuth and discovery routes | OAuth handlers and server builder |

Keeping those roles separate is the main documentation and debugging habit this repo expects.

## Repository Layout

The runtime code lives under `ATProtoPDS/Sources/`. The most important areas for new contributors are:

- `App/` for application composition, configuration, and browser tooling
- `Network/` for HTTP routing, XRPC dispatch, and route registration
- `Database/` for service databases, actor stores, migrations, and pools
- `Repository/` and `Core/` for MST, CAR, CID, and repository invariants
- `Auth/`, `AuthCrypto/`, `AuthVerifier/`, `OAuthProvider/`, and `PDSAuth/` for auth flows
- `Sync/` and `Federation/` for firehose and cross-server behavior
- `CLI/` for the `kaszlak` command-line surface

Tests live under `ATProtoPDS/Tests/` and broadly mirror the runtime structure. New test classes must be added to `ATProtoPDS/Tests/test_main.m` or they will compile without running.

## Build and Test Workflow

Canonical build rules:

- use out-of-source builds
- run `xcodegen generate` before macOS builds
- treat [`docs/index.md`](docs/index.md) and [`docs/01-getting-started/setup.md`](docs/01-getting-started/setup.md) as the contributor workflow source of truth

Core contributor loop:

```bash
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
xcodebuild -scheme ATProtoPDS-CLI build
```

If you touch fuzzers, build them too. If you change docs, update the relevant contributor pages rather than leaving behavior and docs to drift apart.

More detail:

- [Build Guide](BUILD.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Testing Map](docs/11-reference/testing-map.md)
- [Explorer, OpenAPI, and UI](docs/11-reference/explorer-openapi-ui.md)

## Binaries

The repository currently produces these primary executables:

| Binary | Purpose |
| --- | --- |
| `kaszlak` | main PDS CLI and server binary |
| `campagnola` | standalone PLC server |
| `AllTests` | shared Objective-C test runner |

See [CLI Reference](docs/11-reference/cli-reference.md) for the current command families and contributor usage patterns.

## Deployment Notes

For production-like Docker workflows, always run Compose from `docker/pds/`, not from the repo root.

```bash
cd docker/pds
docker compose up -d
docker compose logs -f pds
```

Deployment walkthrough:

- [Tutorial 6: Deployment](docs/10-tutorials/tutorial-6-deployment.md)
- [Config Reference](docs/11-reference/config-reference.md)

## How To Change Behavior Safely

When you modify a feature:

1. identify the surface you are changing
2. confirm the route registration point
3. change the owning service or domain logic, not just the route
4. run the smallest useful test surface first
5. update contributor tooling and docs if the behavior is inspectable there

Useful starting pages:

- [Tutorial 8: Endpoint Workflow](docs/10-tutorials/tutorial-8-endpoint-workflow.md)
- [Troubleshooting](docs/11-reference/troubleshooting.md)
- [Test Selection Workflow](docs/11-reference/test-selection-workflow.md)

## Deep Reference

These areas are still useful when you need extra detail, historical context, or specialized operational reference:

- [Guides](docs/guides/README.md)
- [Architecture Notes and Diagrams](docs/architecture/README.md)
- [Security Documentation](docs/security/README.md)
- [Test Catalog](docs/tests/README.md)

They are intentionally secondary to the numbered contributor docs in `docs/`.
