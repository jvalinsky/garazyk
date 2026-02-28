# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

ATProto Personal Data Server (PDS) written in Objective-C, targeting macOS (Xcode/clang) and Linux (GNUstep). The CLI binary is `kaszlak`; the standalone PLC server is `campagnola`.

## Build Commands

Always use out-of-source builds. Never run `cmake` in the repo root.

```bash
# macOS: CMake build
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)

# macOS: Xcode build
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build    # binary: ./build/bin/kaszlak
xcodebuild -scheme AllTests build          # binary: ./build/tests/AllTests

# Linux (GNUstep)
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)

# Full wipe and rebuild
./scripts/wipe_and_rebuild.sh
```

## Running Tests

```bash
# Run all tests (~1017 tests)
./build/tests/AllTests

# Run a specific test class (filter by class name)
./build/tests/AllTests -XCTest MSTInteropTests

# Run multiple test classes (comma-separated)
./build/tests/AllTests -XCTest MSTInteropTests,CARInteropTests
```

Tests use XCTest. The test runner at `ATProtoPDS/Tests/test_main.m` discovers test methods via ObjC runtime reflection and registers them in a hardcoded class list. To add a new test class, add its name to the `testClasses` array in `test_main.m`.

## Static Analysis & Fuzzing

```bash
# clang-tidy (requires compilation database)
cd build && cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cd ..
clang-tidy -p build ATProtoPDS/Sources/Repository/CBOR.m

# Build fuzzers
mkdir -p build && cd build && cmake .. -DBUILD_FUZZERS=ON && make -j$(sysctl -n hw.ncpu)

# Run a single fuzzer
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/xrpc_valid_create.txt

# ShellCheck all scripts
shellcheck scripts/*.sh
```

## Quality Gates (Pre-Push)

1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes with 0 failures
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
5. Fuzzers build successfully

## Architecture

### Entrypoints

- `ATProtoPDS/Sources/CLI/main.m` — CLI entrypoint. Parses global options (`--data-dir`, `--config`, `--verbose`, `--json`) and dispatches to `PDSCLIDispatcher`.
- `ATProtoPDS/Sources/PLC/main.m` — PLC server entrypoint (`campagnola`).

### Application Layer

`PDSApplication` (in `App/`) is the primary application facade. It composes all services and manages server lifecycle. `PDSController` is a legacy facade that delegates to `PDSApplication`; new code should use `PDSApplication` and its services directly.

Key services (all on `PDSApplication`):
- `PDSAccountService` — account creation, auth, token refresh
- `PDSRecordService` — record CRUD within repositories
- `PDSBlobService` — blob upload/retrieval/deletion
- `PDSRepositoryService` — MST management, commit processing, repo sync
- `PDSAdminController` — takedowns, moderation, labeling
- `PDSRelayService` — notifies external relays of updates

Configuration lives in `PDSConfiguration` (loaded from `config.json`). The server host defaults to port 2583.

### HTTP & XRPC

`HttpServer` (in `Network/`) is a custom HTTP server with route registration. `PDSHttpServerBuilder` configures all routes: XRPC, OAuth, Explore UI, NodeInfo, MST Viewer.

XRPC dispatch: `XrpcDispatcher` routes ATProto RPC calls by NSID. `XrpcMethodRegistry` orchestrates registration by delegating to domain modules:
- `XrpcServerMethods` — `com.atproto.server.*`
- `XrpcRepoMethods` — `com.atproto.repo.*`
- `XrpcSyncMethods` — `com.atproto.sync.*`
- `XrpcIdentityMethods` — `com.atproto.identity.*`
- `XrpcAdminMethods` — `com.atproto.admin.*`
- `XrpcLabelMethods` — `com.atproto.label.*`
- `XrpcAppBskyMethods` — `app.bsky.*`

Helper modules: `XrpcAuthHelper` (JWT/DPoP), `XrpcIdentityHelper` (handle/DID resolution), `XrpcErrorHelper` (standardized error responses).

### Database

SQLite-based, with separate databases per concern:
- `PDSServiceDatabases` — shared service DB, DID cache, sequencer
- `PDSDatabasePool` — per-user actor databases (each user's repo data in a separate DB)
- WAL mode and prepared statements throughout

### Authentication

- JWT access/refresh tokens via `JWTMinter`/`JWTVerifier`
- OAuth 2.0 with DPoP (ECDSA P-256) in `Auth/` and `OAuthProvider/`
- Key rotation via `KeyRotationManager`

### Repository & Protocol

Core AT Protocol types in `Core/`: DAG-CBOR (`ATProtoCBORSerialization`), CAR v1 (`CAR`), CID, MST (Merkle Search Tree).

The firehose (`subscribeRepos`) is served via WebSocket upgrade on the HTTP port. `SubscribeReposHandler` in `Sync/` handles commit broadcasting.

### Platform Compatibility

The codebase targets both macOS and Linux/GNUstep. Platform-specific code uses:
- `ATProtoPDS/Sources/Compat/` — compatibility shims for `os/log.h`, `Security.framework`, `CommonCrypto`
- `PDSNetworkTransportMac.m` / `PDSNetworkTransportLinux.m` — platform-specific network I/O
- `#if TARGET_OS_LINUX` / `#if __APPLE__` guards for conditional compilation
- ARC is enabled on both platforms (GNUstep 2.2 runtime)
- `NSURLSession` is declarations-only on GNUstep; use `NSURLConnection` or the custom transport layer

### Source Layout

```
ATProtoPDS/Sources/
  Admin/          — Admin endpoints & middleware
  App/            — PDSApplication, PDSController, PDSConfiguration
  Auth/           — OAuth 2.0, DPoP, JWT, TOTP, WebAuthn
  CLI/            — CLI commands (kaszlak)
  Compat/         — Linux/GNUstep compatibility layer
  Core/           — CBOR, CAR, CID, MST, DID, ATProtoError
  Database/       — SQLite pools, service databases, actor store, migrations
  Identity/       — DID & handle resolution, PLC client
  Network/        — HttpServer, XrpcDispatcher, XrpcMethodRegistry, rate limiting
  PLC/            — PLC directory interaction, rotation key manager
  Repository/     — Repository operations, blob storage
  Services/       — Service layer (account, record, blob, repository, relay)
  Sync/           — Firehose, WebSocket server, subscribeRepos
```

Test mirrors live under `ATProtoPDS/Tests/` with matching directory names.

## CI/CD

GitHub Actions workflows:
- `ci.yml` — macOS build+test → Linux/GNUstep build+test → Docker build → PLC integration tests
- `security.yml` — clang-tidy, fuzzing, OSV dependency scan, TruffleHog secret scan
- `static-analysis.yml` — code quality, ShellCheck, secrets scan
- `linux.yml` — Docker image builds for tagged releases

## Repository Skills

- `scripts/stub_find.sh` — stub scan for `TODO`/`FIXME`/`not implemented` markers
- `skills/atproto-endpoint-stub-finder/SKILL.md` — endpoint-stub auditing with XRPC coverage
- `skills/xrpc-schema-sync/SKILL.md` — schema-sync and coverage drift checks
- Audit skills in `skills/objc-*/SKILL.md` — reentrancy, concurrency, locking, SQLite invariants, XRPC contracts, firehose ordering, OAuth/DPoP conformance, GNUstep regression, network reliability, parser hardening, log redaction, test gap mapping, service boundary enforcement
- `skills/rewrite-dev-docs-comments/SKILL.md` — rewrite docs/comments to remove LLM-style phrasing

## Production Deployment (pds.garazyk.xyz)

**CRITICAL**: Always run `docker compose` from `docker/pds/`, NEVER from the repo root. The repo root `docker-compose.yml` is for local dev with mock PLC.

### Secure Defaults — MANDATORY

Never weaken these without explicit user approval:
- `session.invite_code_required`: `true`
- `plc.url`: `"https://plc.directory"` (never `"mock"` in production)
- All `debug.*` flags: `false`
- `rate_limit.enabled`: `true`
- `server.issuer`: `"https://pds.garazyk.xyz"`

Production config: `docker/pds/config.json` (read-only mount). VM: `DEPLOY_HOST`. Architecture: `exe.dev HTTPS → nginx:3000 → PDS:2583`.

Required env: `PDS_TRUST_PROXY_HEADERS=1` (trust proxy headers for rate limiting).

### Never Do In Production

- Set `invite_code_required` to `false`
- Use `plc.url: "mock"` outside test/dev
- Enable any `debug.*` flags
- Expose port 2583 directly (nginx handles TLS)
- Store secrets in committed config files
- Run `docker compose` from repo root on the production VM

### Deployment Commands

```bash
# On VM (DEPLOY_HOST):
cd DEPLOY_DIR/objpds/docker/pds
docker compose up -d
docker compose logs -f pds
docker exec nspds kaszlak invite create

# Verify correct config:
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer
# Must show: "did":"did:web:pds.garazyk.xyz"
```

### Volume Backup

```bash
mkdir -p DEPLOY_DIR/backup
TS=$(date +%Y%m%d-%H%M%S)
docker run --rm \
  -v pds_pds_data:/data \
  -v DEPLOY_DIR/backup:/backup \
  busybox sh -c "cd /data && tar -czf /backup/pds_pds_data-$TS.tar.gz ."
```

## Session Completion

When ending a work session, you MUST:
1. Run quality gates (if code changed)
2. Push to remote — work is NOT complete until `git push` succeeds
3. File issues for remaining work

```bash
git pull --rebase
deciduous sync
git push
git status  # Must show "up to date with origin"
```

Never stop before pushing. Never say "ready to push when you are" — YOU must push.

## Utility Scripts

- `scripts/stub_find.sh .` — scan for `TODO`/`FIXME`/`not implemented` markers
- `scripts/wipe_and_rebuild.sh` — clean rebuild from scratch
- `scripts/backup_pds.sh` — SQLite-safe production backup
- `scripts/db_dump.sh` — inspect PDS database contents
- `scripts/run-tests.sh` — run all tests
