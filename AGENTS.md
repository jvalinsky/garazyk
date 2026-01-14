# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

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

### Phase 3: The Firehose & Sync - COMPLETED
- **Repo Sync**: Implemented `subscribeRepos` commit broadcasting with operation extraction in `SubscribeReposHandler.m`.
- **WebSocket**: Full WebSocket server implementation in `WebSocketServer.m` supporting multiple connections and event broadcasting.

### Phase 4: macOS Build & Test - COMPLETED
- **macOS Build**: All targets build successfully with xcodebuild
  - ATProtoPDS-CLI: Builds without errors
  - AllTests: Builds without errors
  - Fuzzers: Available
- **Test Suite**: All 168 tests passing (0 failures)
- **Bug Fixes**:
  - Fixed HandleResolver.skipSSRFCheck property accessibility (ATProtoPDS/Sources/Identity/HandleResolver.h:23)
  - Fixed CBOR boolean encoding bug where all NSNumbers were treated as booleans (ATProtoPDS/Sources/Core/ATProtoCBORSerialization.m:47-54)
- **CLI Verification**: Application runs successfully with all commands functional

### Phase 5: Linux Support & Reliability Improvements - IN PROGRESS
- **Linux Porting**: `PDSNetworkTransportLinux` structure in place using BSD sockets/libdispatch, but read logic is pending implementation.
- **CLI Enhancements**: Added unit tests for CLI commands.
- **Handle Resolution**: COMPLETED. Full implementation in `HandleResolver.m` including HTTPS resolution, DNS TXT fallback, caching, and rate limiting.

### Database Layer
- **Actor Store**: `PDSActorStore` provides SQLite-based persistence for actor data, employing WAL mode and prepared statements for performance.

### Development Tools
- **PLC Server**: `tool-plc` contains a local PLC server for ATProto development/testing.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
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
   bd sync
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
# Expected output: Tests run: 168, Failures: 0
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

- `skills/stub-finder/SKILL.md` documents the repository-level stub-finder skill that uses `scripts/stub_find.sh` to scan for `TODO`/`FIXME`/`not implemented` markers. Run `./scripts/stub_find.sh .` before code reviews to catch placeholder logic and report/find follow-up work.

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
3. `./build/tests/AllTests` passes (168 tests, 0 failures)
4. `xcodebuild -scheme ATProtoPDS-CLI build` succeeds
5. Fuzzers build successfully

## Linux/GNUstep Compatibility

This project targets both macOS and Linux (via GNUstep). See [docs/GNUSTEP_COMPATIBILITY.md](docs/GNUSTEP_COMPATIBILITY.md) for detailed compatibility information.

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
