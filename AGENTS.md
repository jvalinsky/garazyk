# Agent Instructions

## Project Status

### Phase 1: Repository & MST Protocol Compliance - COMPLETED
- **MST Interop**: Implemented `MSTInteropTests` verifying Merkle Search Tree compliance with reference implementations. Fixed MST fan-out calculation, CBOR key ordering, and prefix calculation bugs.
- **CAR v1 Interop**: Implemented `CARInteropTests` and fixed binary CID parsing in `CAR.m`.
- **Repo Commit**: Implemented signature verification and proper commit structure in `RepoCommit`.

### Phase 2: Authentication & JWT Transition - COMPLETED
- **JWT Transition**: Migrated from opaque UUID tokens to signed JWT access tokens with `JWTMinter` and `JWTVerifier`.
- **Key Rotation**: Integrated `KeyRotationManager` for secure token signing and verification.
- **Token Refresh**: Implemented proper token refresh logic in `OAuth2.m`.
- **Service Auth**: Added `com.atproto.server.getServiceAuth` endpoint.
- **DPoP Signing**: Implemented `OAuth2 DPoP` signature generation and verification using `SecKeyCreateSignature` (ECDSA P-256).

### Phase 3: The Firehose & Sync - COMPLETED
- **Repo Sync**: Implemented `subscribeRepos` commit broadcasting with operation extraction in `SubscribeReposHandler.m`.
- **WebSocket**: Full WebSocket server implementation in `WebSocketServer.m` supporting multiple connections and event broadcasting.

### Phase 4: macOS Build & Test - COMPLETED (REPAIRED Feb 2026)
- **macOS Build**: All targets build successfully with CMake (out-of-source) and xcodebuild.
- **Build System Repair (Feb 2026)**: Fixed root directory pollution and resolved a circular proxy invocation issue with the `swiftly` compiler wrapper on macOS by implementing robust compiler discovery using `xcrun` in `CMakeLists.txt`.
- **Test Suite**: `./build/tests/AllTests` passing with 0 failures.
- **Bug Fixes**:
  - Fixed HandleResolver.skipSSRFCheck property accessibility (ATProtoPDS/Sources/Identity/HandleResolver.h:23)
  - Fixed CBOR boolean encoding bug where all NSNumbers were treated as booleans (ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m:47-54)
- **CLI Verification**: Application runs successfully with all commands functional.

### Phase 5: Linux Support & Reliability Improvements - COMPLETED
- **Linux Porting**: `PDSNetworkTransportLinux` implements non-blocking connect + read/write and uses `getaddrinfo()` for hostname + IPv4/IPv6 resolution.
- **CLI Enhancements**: Added unit tests for CLI commands.
- **Handle Resolution**: Full implementation in `HandleResolver.m` including HTTPS resolution, DNS TXT fallback, caching, and rate limiting.
- **Moderation**: Implemented `admin.disableAccount`, `admin.enableAccount`, `createLabel`, and `getLabels` logic in `PDSController` and `PDSDatabase`.
- **Explore**: Implemented Base58BTC decoding in `Base58` and `CID` classes to support `z`-prefixed CIDs.
- **Linux Client Connections**: Implemented non-blocking `connect()` with `DISPATCH_SOURCE_TYPE_WRITE` for async completion notification.
- **Handle Verification**: `resolveIdentity` validates the requested handle against the DID document `alsoKnownAs` list.
- **Follower Counts**: `ActorService` uses a SQL count query for followers.
- **PLC `did:key` Parsing**: `PLCDIDKey.parseFromString:` implements base58btc multibase decoding and multicodec parsing for secp256k1 + P-256 keys.

### Phase 6: Professional Script Development - COMPLETED
- **Professional Bash Scripting Standards**: Core repository scripts follow structured error handling, input validation, and maintainable shell scripting practices.
- **Script Quality Improvements**: Upgraded core shell scripts following professional bash scripting standards.
- **New E2E Test Scripts**: End-to-end tests for social (6 scenarios) and moderation (4 scenarios) workflows.
- **Script Validation**: All scripts pass ShellCheck linting with zero warnings.

### Phase 7: PLC Directory Interaction - COMPLETED
- **PLCRotationKeyManager**: Server-level signing key for PLC operations with persistent storage (`ATProtoPDS/Sources/PLC/PLCRotationKeyManager.m`).
- **DID Resolution Protocol Compliance**:
  - Added `Accept: application/did+ld+json,application/json` header
  - Implemented redirect rejection via `NSURLSessionTaskDelegate` for security
- **signPlcOperation**:
  - Fetches last PLC operation from audit log
  - Detects and rejects tombstoned accounts
  - Calculates correct `prev` CID from last operation
  - Signs with server rotation key (not actor signing key)
  - Removed `did` field from operation body (spec compliance)
- **submitPlcOperation**:
  - Validates server rotation key is in `rotationKeys`
  - Validates `services.atproto_pds.type` is `AtprotoPersonalDataServer`
  - Validates `services.atproto_pds.endpoint` matches server URL
  - Validates `alsoKnownAs` contains account's handle
  - Validates `prev` matches last operation CID (prevents replay attacks)
  - Actually forwards operations to PLC directory via POST
- **requestPlcOperationSignature**: Email-based token flow with testing fallback
- **PLC Server**: Returns correct `Content-Type: application/did+ld+json` for DID documents
- **Bug Fixes**:
  - Fixed `DIDPLCResolver executeRawRequest` never calling completion on success (line 271-273)
  - Removed `sig = hash` fallback that returned invalid signatures
  - Removed `did:key:placeholder` fallback, now returns proper error

### Database Layer
- **Actor Store**: `PDSActorStore` provides SQLite-based persistence for actor data, employing WAL mode and prepared statements for performance.

### Development Tools
- **PLC Server**: The standalone PLC server binary is `campagnola` (CMake target: `atproto-plc`), located at `./build/bin/campagnola`.

## Build & Test Instructions

### Primary Build Workflow (Recommended)
Always use out-of-source builds to keep the repository clean. See [BUILD.md](file:///Users/jack/Software/garazyk/BUILD.md) for detailed instructions.

```bash
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)
```

### Xcode Project Generation
The project use **XcodeGen** to wrap the CMake-based build system.

```bash
xcodegen generate
```

### Building Targets via xcodebuild

**CLI Tool:**
```bash
xcodebuild -scheme ATProtoPDS-CLI build
# Binary at: ./build/bin/kaszlak
```

**Unit Tests:**
```bash
xcodebuild -scheme AllTests build
# Binary at: ./build/tests/AllTests
```

### Running Tests
```bash
./build/tests/AllTests
# Expected output includes: 1017 tests, Failures: 0
```

**Fuzzers:**
```bash
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/xrpc_valid_create.txt
```

### Security Testing

**Static Analysis:**
```bash
# Generate compilation database for clang-tidy
cd build
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cd ..
clang-tidy -p build ATProtoPDS/Sources/Repository/CBOR.m
```

## Repository Skills

- `scripts/stub_find.sh` provides the repository-level stub scan for `TODO`/`FIXME`/`not implemented` markers. Run `./scripts/stub_find.sh .` before code reviews to catch placeholder logic and follow-up work.
- `skills/atproto-endpoint-stub-finder/SKILL.md` documents endpoint-stub auditing with repo-native XRPC coverage integration and endpoint mapping that supports both typed registrations and `registerMethod:@"<nsid>"` string registrations.
- `skills/xrpc-schema-sync/SKILL.md` documents schema-sync and coverage drift checks using repo-native generators (`scripts/generate_xrpc_coverage_report.js` and `scripts/generate_xrpc_next_steps.js`) with parser fallback tooling.
- `skills/objc-reentrancy-audit/SKILL.md` audits Objective-C re-entrancy hazards (callbacks under lock, recursive notification/KVO paths, sync queue re-entry).
- `skills/objc-concurrency-bug-audit/SKILL.md` audits Objective-C concurrency defects (race conditions, deadlock signals, shared mutable state without clear synchronization).
- `skills/objc-locking-queue-audit/SKILL.md` audits lock and dispatch queue contracts (lock/unlock imbalance, queue assertions, lock plus sync-dispatch risk).
- `skills/objc-sqlite-invariant-audit/SKILL.md` audits SQLite invariants in Objective-C persistence code (transaction correctness, statement lifecycle, pragma assumptions).
- `skills/objc-xrpc-contract-audit/SKILL.md` audits XRPC contract conformance (registration, auth enforcement signals, validation and error-shape consistency).
- `skills/objc-firehose-ordering-backpressure-audit/SKILL.md` audits firehose and WebSocket flow-control correctness (ordering, cursor monotonicity, buffering/backpressure behavior).
- `skills/objc-oauth-dpop-conformance-audit/SKILL.md` audits OAuth2 and DPoP conformance/security paths (proof validation, nonce/replay, token lifecycle, key handling).
- `skills/objc-gnustep-regression-audit/SKILL.md` audits Linux/GNUstep portability regressions (platform-sensitive APIs, missing guards, compat-layer bypasses).
- `skills/objc-network-timeout-retry-audit/SKILL.md` audits network timeout/retry/cancellation reliability in transport code.
- `skills/objc-parser-hardening-audit/SKILL.md` audits parser hardening needs (bounds checks, risky memory operations, integer conversion safety).
- `skills/objc-log-redaction-audit/SKILL.md` audits sensitive logging and redaction gaps (tokens, auth headers, secrets).
- `skills/objc-test-gap-mapper/SKILL.md` maps Objective-C source files to likely test coverage gaps and module risk hotspots.
- `skills/objc-service-boundary-audit/SKILL.md` audits service-layer authorization and trust-boundary enforcement for privileged operations.
- `skills/rewrite-dev-docs-comments/SKILL.md` rewrites docs and code comments to remove low-signal LLM-style phrasing and produce concise, technically precise language for experienced developers.

## CI/CD Pipeline

The project uses GitHub Actions for continuous integration.

### Workflows

| Workflow | File | Purpose |
|----------|------|---------|
| **CI** | `.github/workflows/ci.yml` | macOS/Linux build, test, PLC integration |
| **Security** | `.github/workflows/security.yml` | Static analysis, fuzzing, dependency scan, PLC module clang-tidy |
| **Static Analysis** | `.github/workflows/static-analysis.yml` | Code quality, ShellCheck, secrets scan |
| **Linux Release** | `.github/workflows/linux.yml` | Docker image builds for tagged releases |

### CI Workflow Jobs

| Job | Trigger | Purpose |
|-----|---------|---------|
| `macos-build-and-test` | Every PR/push | Build and run tests on macOS |
| `linux-gnustep-build-and-test` | After macOS passes | Build and run tests on Linux/GNUstep |
| `linux-docker-build` | After macOS passes | Build Docker image |
| `plc-integration-tests` | After macOS passes | Run PLC-specific integration tests |

### Security Workflow Jobs

| Job | Trigger | Purpose |
|-----|---------|---------|
| `clang-tidy` | Every PR/push | Static analysis (core + PLC modules) |
| `fuzzing` | Every PR/push + weekly | LibFuzzer tests |
| `dependency-scan` | Every PR/push | OSV vulnerability scan |
| `secret-scan` | Every PR/push | TruffleHog secret detection |

### Quality Gates

Before pushing, ensure:
1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes (0 failures)
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds (binary: `kaszlak`)
5. Fuzzers build successfully

## Linux/GNUstep Compatibility

### Key Findings

| Feature | macOS | Linux (GNUstep) | Compat Layer Needed? |
|---------|-------|-----------------|---------------------|
| **NSLog** | Native | Native | No |
| **os/log.h** | Native | Not implemented | Yes - see `Sources/Compat/os/log.h` |
| **Security framework** | Native | Not implemented | Yes - see `Sources/Compat/Security/` |
| **CommonCrypto** | Native | Not implemented | Yes - see `Sources/Compat/CommonCrypto/` |
| **NSURLConnection** | Native | Native | No |
| **NSURLSession** | Native | Declarations only | Use NSURLConnection |
| **dispatch_queue_t** | Native | Native (via libdispatch) | No |

### Common Patterns

**os_log_t property declaration:**
```objc
#if TARGET_OS_LINUX
@property (nonatomic, assign) os_log_t log;
#else
@property (nonatomic, strong) os_log_t log;
#endif
```

**Importing platform-specific headers:**
```objc
#import <os/log.h>   // Uses compat layer on Linux, system on macOS
#import <Security/Security.h>  // Same pattern
```

### Building on Linux

```bash
# On VM with GNUstep installed
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Production Deployment (pds.garazyk.xyz)

### Secure Defaults — MANDATORY

When generating, modifying, or reviewing PDS configuration for production deployment, enforce these security defaults. Agents MUST NOT weaken these without explicit user approval.

| Setting | Secure Default | Rationale |
|---------|---------------|-----------|
| `session.invite_code_required` | `true` | Prevent open registration spam/abuse |
| `nodeinfo.open_registrations` | `false` | Consistent with invite-only policy |
| `plc.url` | `"https://plc.directory"` | Never use `"mock"` in production |
| `debug.skip_plc_operations` | `false` | Must register DIDs with real PLC directory |
| `debug.verbose_logging` | `false` | Avoid leaking sensitive data in logs |
| `debug.in_memory_databases` | `false` | Data must persist across restarts |
| `debug.reset_on_startup` | `false` | Never destroy production data |
| `server.host` | `"0.0.0.0"` | Bind address (nginx handles TLS) |
| `server.issuer` | `"https://pds.garazyk.xyz"` | Public-facing origin for DIDs/JWTs |
| `rate_limit.enabled` | `true` | Protect against abuse |

### Production Config Location

- **Docker**: `docker/pds/config.json` (mounted read-only into container)
- **Docker Compose**: `docker/pds/docker-compose.yml`
- **VM**: `DEPLOY_HOST` (exe.dev)
- **Architecture**: `exe.dev HTTPS → nginx:3000 → PDS:2583`

### Required Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `PDS_TRUST_PROXY_HEADERS` | `1` | Trust `X-Real-IP`/`X-Forwarded-For` from nginx for proper rate limiting per-client |

### Deployment Commands

**CRITICAL**: Always run `docker compose` from `docker/pds/`, NEVER from the repo root. The repo root has a separate `docker-compose.yml` for local dev/testing that mounts the dev `config.json` (localhost, mock PLC). Running from the wrong directory will cause the PDS to serve `did:web:localhost%3A2583` instead of `did:web:pds.garazyk.xyz`.

```bash
# On the VM (DEPLOY_HOST):
cd DEPLOY_DIR/objpds/docker/pds   # <-- MUST be this directory, NOT repo root
docker compose up -d        # Start
docker compose logs -f pds  # Monitor
docker compose restart pds  # Restart after config change

# Create invite codes (required for account creation):
docker exec nspds kaszlak invite create

# Verify correct config is loaded after any restart:
curl -s http://localhost:2583/xrpc/com.atproto.server.describeServer
# MUST show: "did":"did:web:pds.garazyk.xyz" and "availableUserDomains":["garazyk.xyz"]
```

### Production Volume Backup

- **Backup directory on VM**: `DEPLOY_DIR/backup`
- **Current backup artifact pattern**: `DEPLOY_DIR/backup/pds_pds_data-YYYYMMDD-HHMMSS.tar.gz`
- **Latest known backup (Feb 25, 2026)**: `DEPLOY_DIR/backup/pds_pds_data-20260225-195508.tar.gz`
- **Volume name to protect**: `pds_pds_data` (Docker external volume mounted at `/var/lib/atprotopds` in `nspds`)

```bash
# Create a non-destructive backup tarball of the production volume:
mkdir -p DEPLOY_DIR/backup
TS=$(date +%Y%m%d-%H%M%S)
docker run --rm \
  -v pds_pds_data:/data \
  -v DEPLOY_DIR/backup:/backup \
  busybox sh -c "cd /data && tar -czf /backup/pds_pds_data-$TS.tar.gz ."
```

### What Agents Must NEVER Do

- Set `invite_code_required` to `false` in production configs
- Use `plc.url: "mock"` outside of test/dev configs
- Enable any `debug.*` flags in production
- Expose the PDS port (2583) directly to the internet (nginx handles this)
- Store secrets or keys in config files committed to git
- Run `docker compose` from the repo root on the production VM (use `docker/pds/` only)

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   # Sync Deciduous decision graph state:
   deciduous sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
