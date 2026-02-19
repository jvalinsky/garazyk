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

### Phase 4: macOS Build & Test - COMPLETED
- **macOS Build**: All targets build successfully with xcodebuild
  - ATProtoPDS-CLI: Builds without errors
  - AllTests: Builds without errors
  - Fuzzers: Available
- **Test Suite**: `./build/tests/AllTests` passing with 0 failures (suite count varies by build/config)
- **Bug Fixes**:
  - Fixed HandleResolver.skipSSRFCheck property accessibility (ATProtoPDS/Sources/Identity/HandleResolver.h:23)
  - Fixed CBOR boolean encoding bug where all NSNumbers were treated as booleans (ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m:47-54)
- **CLI Verification**: Application runs successfully with all commands functional

### Phase 5: Linux Support & Reliability Improvements - IN PROGRESS
- **Linux Porting**: `PDSNetworkTransportLinux` implements non-blocking connect + read/write and uses `getaddrinfo()` for hostname + IPv4/IPv6 resolution; remaining work is Linux/GNUstep validation, fallback behavior, and additional hardening.
- **CLI Enhancements**: Added unit tests for CLI commands.
- **Handle Resolution**: COMPLETED. Full implementation in `HandleResolver.m` including HTTPS resolution, DNS TXT fallback, caching, and rate limiting.
- **Moderation**: COMPLETED. Implemented `admin.disableAccount`, `admin.enableAccount`, `createLabel`, and `getLabels` logic in `PDSController` and `PDSDatabase`.
- **Explore**: COMPLETED. Implemented Base58BTC decoding in `Base58` and `CID` classes to support `z`-prefixed CIDs.

- **Linux Client Connections**: COMPLETED. Implemented non-blocking `connect()` with `DISPATCH_SOURCE_TYPE_WRITE` for async completion notification (`ATProtoPDS/Sources/Network/PDSNetworkTransportLinux.m`).
- **Handle Verification**: `resolveIdentity` validates the requested handle against the DID document `alsoKnownAs` list and returns a `HandleMismatch` error when they disagree (ATProtoPDS/Sources/Network/XrpcMethodRegistry.m:1069-1092).
- **Follower Counts**: `ActorService` uses a SQL count query for followers; remaining work is correctness/perf hardening (ensuring `subject_did` is populated and indexed) (ATProtoPDS/Sources/AppView/ActorService.m:183-195).
- **PLC `did:key` Parsing**: COMPLETED. `PLCDIDKey.parseFromString:` implements base58btc multibase decoding and multicodec parsing for secp256k1 + P-256 keys (ATProtoPDS/Sources/PLC/PLCDIDKey.m:27-141).

### Phase 6: Professional Script Development - COMPLETED
- **Professional Bash Scripting Standards**: Core repository scripts follow structured error handling, input validation, and maintainable shell scripting practices.
- **Script Quality Improvements**: Upgraded core shell scripts following professional bash scripting standards:
  - `simple_test.sh`: Complete overhaul with proper error handling, structured logging, input validation, and dependency checking
  - `start_server.sh`: Signal handling, PID file management, graceful shutdown with 10s timeout
  - `quality_gate.sh`: Improved error handling, validation, and structured logging
  - `run-tests.sh`: Added professional structure with proper validation and logging
- **New E2E Test Scripts**: End-to-end tests for social (6 scenarios) and moderation (4 scenarios) workflows:
  - `test_social_features.sh`: Complete social features testing (feeds, follows, likes, profiles, search, timelines)
  - `test_moderation.sh`: Full moderation testing (reports, account moderation, content labeling)
- **Script Ecosystem Enhancement**: Shell scripts use `set -euo pipefail`, colored output via `log_info`/`log_error` functions, and pass ShellCheck with zero warnings.
- **Script Validation**: All scripts (existing and new) pass ShellCheck linting with zero warnings and follow SC2155 best practices for variable declaration.

### Database Layer
- **Actor Store**: `PDSActorStore` provides SQLite-based persistence for actor data, employing WAL mode and prepared statements for performance.

### Development Tools
- **PLC Server**: `tool-plc` contains a local PLC server for ATProto development/testing.

## Build & Test Instructions

### Generating the Project
The project uses **XcodeGen** to wrap a CMake-based build system. You must regenerate the project if `project.yml` or `CMakeLists.txt` changes.

```bash
xcodegen generate
```

### Building Targets

**CLI Tool:**
```bash
xcodebuild -scheme ATProtoPDS-CLI build
# Binary at: ./build/bin/atprotopds-cli
```

**Unit Tests:**
```bash
xcodebuild -scheme AllTests build
# Binary at: ./build/tests/AllTests
```

**Fuzzers:**
```bash
xcodebuild -scheme Fuzzers build
# Binaries at: ./build/fuzzing/
```

### Running Tests

**Unit Tests:**
```bash
./build/tests/AllTests
# Expected output includes: Failures: 0
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

The project uses GitHub Actions for continuous integration, defined in `.github/workflows/ci.yml`.

### Workflows

| Workflow | File | Purpose |
|----------|------|---------|
| **CI** | `.github/workflows/ci.yml` | Build, test, coverage, lint |
| **Security** | `.github/workflows/security.yml` | Static analysis, fuzzing, dependency scan |

### CI Workflow Jobs

| Job | Trigger | Purpose |
|-----|---------|---------|
| `build-and-test` | Every PR/push | Build project and run tests |
| `coverage` | After build | Generate code coverage report |
| `lint` | Every PR/push | Code formatting and linting |
| `dependencies` | Every PR/push | Dependency verification |

### Quality Gates

Before pushing, ensure:
1. `xcodegen generate` succeeds
2. `xcodebuild -scheme AllTests build` succeeds
3. `./build/tests/AllTests` passes (0 failures)
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
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
