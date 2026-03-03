# Project Structure

## Source Organization

```
ATProtoPDS/Sources/
  Admin/          - Admin endpoints & moderation
  App/            - PDSApplication, PDSController, PDSConfiguration
  Auth/           - OAuth 2.0, DPoP, JWT, TOTP, WebAuthn
  CLI/            - CLI commands (kaszlak entrypoint)
  Compat/         - Linux/GNUstep compatibility layer
  Core/           - CBOR, CAR, CID, MST, DID, ATProtoError
  Database/       - SQLite pools, service databases, actor store, migrations
  Identity/       - DID & handle resolution, PLC client
  Network/        - HttpServer, XrpcDispatcher, XrpcMethodRegistry, rate limiting
  PLC/            - PLC directory interaction (campagnola entrypoint)
  Repository/     - Repository operations, blob storage
  Services/       - Service layer (account, record, blob, repository, relay)
  Sync/           - Firehose, WebSocket server, subscribeRepos
```

## Test Organization

```
ATProtoPDS/Tests/
```

Tests mirror the source structure. Test runner at `ATProtoPDS/Tests/test_main.m` discovers test methods via ObjC runtime reflection. To add a new test class, add its name to the `testClasses` array in `test_main.m`.

## Key Entry Points

- `ATProtoPDS/Sources/CLI/main.m` - CLI entrypoint (kaszlak)
- `ATProtoPDS/Sources/PLC/main.m` - PLC server entrypoint (campagnola)

## Application Architecture

### Core Facade

`PDSApplication` (in `App/`) is the primary application facade. It composes all services and manages server lifecycle. `PDSController` is a legacy facade that delegates to `PDSApplication`; new code should use `PDSApplication` directly.

### Key Services

All services are accessed via `PDSApplication`:

- `PDSAccountService` - account creation, auth, token refresh
- `PDSRecordService` - record CRUD within repositories
- `PDSBlobService` - blob upload/retrieval/deletion
- `PDSRepositoryService` - MST management, commit processing, repo sync
- `PDSAdminController` - takedowns, moderation, labeling
- `PDSRelayService` - notifies external relays of updates

### HTTP & XRPC

- `HttpServer` (in `Network/`) - custom HTTP server with route registration
- `PDSHttpServerBuilder` - configures all routes (XRPC, OAuth, Explore UI, NodeInfo, MST Viewer)
- `XrpcDispatcher` - routes ATProto RPC calls by NSID
- `XrpcMethodRegistry` - orchestrates registration by delegating to domain modules:
  - `XrpcServerMethods` - `com.atproto.server.*`
  - `XrpcRepoMethods` - `com.atproto.repo.*`
  - `XrpcSyncMethods` - `com.atproto.sync.*`
  - `XrpcIdentityMethods` - `com.atproto.identity.*`
  - `XrpcAdminMethods` - `com.atproto.admin.*`
  - `XrpcLabelMethods` - `com.atproto.label.*`
  - `XrpcAppBskyMethods` - `app.bsky.*`

### Helper Modules

- `XrpcAuthHelper` - JWT/DPoP authentication
- `XrpcIdentityHelper` - handle/DID resolution
- `XrpcErrorHelper` - standardized error responses

## Database Architecture

SQLite-based with separate databases per concern:

- `PDSServiceDatabases` - shared service DB, DID cache, sequencer
- `PDSDatabasePool` - per-user actor databases (each user's repo data in separate DB)
- WAL mode and prepared statements throughout

## Configuration

- `PDSConfiguration` - loaded from `config.json`
- Default server port: 2583

## Supporting Directories

```
docs/                - Documentation (mdBook format)
docker/              - Docker configs & deployment
scripts/             - ~55 utility shell scripts
skills/              - Audit skills for code analysis
lexicons/            - AT Protocol lexicons
fuzzing/             - Fuzz testing infrastructure
examples/            - Tutorial examples
Tests/e2e/           - End-to-end tests (Node.js/Playwright)
```

## Deployment

Production Docker Compose: `docker/pds/docker-compose.yml` (NOT repo root)

## Utility Scripts

- `scripts/stub_find.sh` - scan for TODO/FIXME markers
- `scripts/wipe_and_rebuild.sh` - clean rebuild
- `scripts/backup_pds.sh` - SQLite-safe production backup
- `scripts/db_dump.sh` - inspect PDS database contents
- `scripts/run-tests.sh` - run all tests
