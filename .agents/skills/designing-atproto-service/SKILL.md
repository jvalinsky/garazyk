---
name: designing-atproto-service
description: "Guide and scaffold a new AT Protocol service binary in Garazyk. Covers project scaffolding, build system integration (CMake + XcodeGen + Docker), XRPC/lexicon wiring, and database layer. Use when adding a new service binary, creating a route pack, adding XRPC handlers, or scaffolding a new service module."
---

# Designing an AT Protocol Service

Workflow and scaffolding for adding a new service binary to Garazyk (alongside kaszlak, syrena, zuk, campagnola, jelcz, garazyk-ui, syrena-chat, germ).

## When to Use

- "Add a new service binary to Garazyk"
- "Create a new ATProto service"
- "Scaffold a new route pack"
- "Add XRPC handlers for a new service"
- "I need a new service module"

## Quick Start

1. **Define the service** — name, purpose, which static libs it needs, whether it has a database
2. **Run the scaffold script** — generates entry point, runtime class, route pack, and build integration
3. **Wire up XRPC methods** — add handlers to the route pack
4. **Add database migrations** (if needed) — conform to `PDSMigration` protocol
5. **Update build files** — CMake, project.yml, Docker
6. **Write tests** — register in `test_main.m`

```bash
# Generate scaffolding
.agents/skills/designing-atproto-service/scripts/scaffold-service.sh <service-name> <class-prefix> <port>
# Example:
.agents/skills/designing-atproto-service/scripts/scaffold-service.sh labeler PDSLabeler 2591
```

## Architecture Overview

Every Garazyk service follows the same pattern:

```
Garazyk/Binaries/<name>/main.m          ← thin CLI entry point
Garazyk/Sources/<Module>/                ← runtime class + domain logic
Garazyk/Sources/Network/<Name>XrpcRoutePack.{h,m}  ← XRPC route registration
```

The `main.m` is a thin wrapper that:
1. Installs crash/signal handlers
2. Parses CLI flags (port, data-dir, config)
3. Instantiates the runtime/application object
4. Creates an `HttpServer`, registers routes via the route pack
5. Starts the server and runs the run loop

### Existing Service Patterns

| Service | Binary | Runtime Class | Route Pack | Database |
|---------|--------|---------------|------------|----------|
| PDS | `kaszlak` | `PDSApplication` | `ATProtoHttpXrpcRoutePack` | Service DB + Actor Stores |
| AppView | `syrena` | `AppViewRuntime` | `AppViewXRpcRoutePack` | `AppViewDatabase` |
| Relay | `zuk` | (inline in main.m) | `RelayXrpcRoutePack` | None (event buffer) |
| PLC | `campagnola` | `PLCServer` | (direct HTTP routes) | `PLCPersistentStore` |
| Video | `jelcz` | (inline in main.m) | None | None |
| Chat | `syrena-chat` | (inline in main.m) | None | None |
| E2EE | `germ` | (inline in main.m) | None | None |
| Admin UI | `garazyk-ui` | `UIServerRuntime` | None | None |

## Step-by-Step Checklist

### 1. Create the Entry Point

Create `Garazyk/Binaries/<name>/main.m` following the zuk pattern:

- SPDX headers
- `print_usage()` / `print_version()`
- CLI flag parsing (`--port`, `--data-dir`, `--config`, `--verbose`)
- Instantiate runtime objects
- Create `HttpServer`, register routes
- Start server, run `NSRunLoop`
- On Linux: `curl_global_init()`, category link verification

### 2. Create the Runtime Class

Create `Garazyk/Sources/<Module>/<Prefix>Runtime.{h,m}`:

- Owns service lifecycle (start/stop)
- Holds references to all dependencies (database, handlers, etc.)
- Provides `startWithError:` and `stop` methods

### 3. Create the Route Pack

Create `Garazyk/Sources/Network/<Name>XrpcRoutePack.{h,m}`:

- Conforms to the pattern: `initWith...` + `registerRoutesWithServer:`
- For XRPC methods: register on `XrpcDispatcher` via `registerMethod:handler:`
- For HTTP routes: register on `HttpServer` via `addRoute:path:handler:`
- For WebSocket: register via `addWebSocketRoute:handler:`

### 4. Add XRPC Handlers

Two approaches depending on service type:

**PDS-style (XrpcMethodRegistry):** Add a new domain module (e.g., `XrpcLabelMethods`) that registers handlers on the `XrpcDispatcher`. See [references/xrpc-wiring.md](references/xrpc-wiring.md).

**Standalone service (Route Pack):** Register methods directly on the dispatcher in the route pack's `registerRoutesWithServer:`. See [references/xrpc-wiring.md](references/xrpc-wiring.md).

### 5. Add Database Layer (if needed)

**Service DB:** Create migration classes conforming to `PDSMigration`:

```objc
@interface PDSMigrationNNN : NSObject <PDSMigration>
- (NSInteger)version;           // sequential number
- (NSString *)description;       // human-readable
- (BOOL)applyToDatabase:(PDSDatabase *)database error:(NSError **)error;
@end
```

Register in `PDSMigrationManager`. See [references/database-layer.md](references/database-layer.md).

**Actor Store:** If the service manages per-user data, follow the `PDSActorStore` / `PDSDatabasePool` pattern.

### 6. Update Build System

See [references/build-integration.md](references/build-integration.md) for exact CMake, XcodeGen, and Docker edits.

Key files to update:
- `CMakeLists.txt` — add `add_executable`, link static libs, set output dir
- `project.yml` — add XcodeGen tool target
- `docker/Dockerfile.gnustep` — add to build targets and COPY
- `scripts/stage-docker-binaries.sh` — add to `BINARIES` array
- `docker/local-network/Dockerfile.local` — add COPY
- `docker/local-network/docker-compose.yml` — add service container (if used locally)

### 7. Write Tests

- Create test file in `Garazyk/Tests/`
- Register in `Garazyk/Tests/test_main.m`
- Follow `garazyk-testing` skill for patterns

### 8. Add Scenario Test (optional)

- Create `scripts/scenarios/scenarios/NN_<name>.ts`
- Follow `atproto-scenario-testing` skill

## Static Library Selection

Choose which static libs to link based on what the service needs:

| Need | Link |
|------|------|
| Base types, logging, compat | `ATProtoCore` |
| SQLite database, repositories | `ATProtoStorage` |
| Account, blob, identity, services | `ATProtoServices` |
| HTTP server, network transport | `ATProtoTransport` |
| XRPC dispatch, route packs | `ATProtoXRPC` |
| Firehose, relay, WebSocket | `ATProtoSync` |
| PLC directory | `ATProtoPLC` |
| PDSApplication, CLI, server builder | `ATProtoRuntime` |
| Video transcoding | `ATProtoVideoService` |
| AppView server | `ATProtoAppViewServer` |

Minimal service (HTTP + XRPC, no DB): `ATProtoTransport ATProtoXRPC ATProtoCore`
Full PDS-like service: all libs (see kaszlak CMake target)

## References

- [references/xrpc-wiring.md](references/xrpc-wiring.md) — XRPC handler protocol, dispatcher registration, route pack patterns
- [references/database-layer.md](references/database-layer.md) — migration protocol, service DB, actor store, connection pool
- [references/build-integration.md](references/build-integration.md) — CMake, XcodeGen, Docker exact edit patterns
