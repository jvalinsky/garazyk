# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Project Status

### ✅ Phase 1: Repository & MST Protocol Compliance - COMPLETED
- **MST Interop**: Implemented `MSTInteropTests` verifying Merkle Search Tree compliance with reference implementations. Fixed critical bugs in fan-out, CBOR key ordering, and prefix calculation.
- **CAR v1 Interop**: Implemented `CARInteropTests` and fixed binary CID parsing in `CAR.m`.
- **Repo Commit**: Implemented signature verification and proper commit structure in `RepoCommit`.

### ✅ Phase 2: Authentication & JWT Transition - COMPLETED
- **JWT Transition**: Migrated from opaque UUID tokens to signed JWT access tokens with `JWTMinter` and `JWTVerifier`.
- **Key Rotation**: Integrated `KeyRotationManager` for secure token signing and verification.
- **Token Refresh**: Implemented proper token refresh logic in `OAuth2.m`.
- **Service Auth**: Added `com.atproto.server.getServiceAuth` endpoint.

### ✅ Phase 2.5: did:plc Account Creation - COMPLETED
- **DIDKey**: Implemented `DIDKey.h/.m` for parsing/generating did:key identifiers with secp256k1 support.
- **DIDKeyEncoder**: Implemented `DIDKeyEncoder.h/.m` for multicodec/multibase encoding per W3C spec.
- **PLCOperation**: Implemented `PLCOperation.h/.m` data model for genesis/update/tombstone operations.
- **PLCOperationSigner**: Implemented `PLCOperationSigner.h/.m` for DAG-CBOR signing with base64url output.
- **PLCOperationBuilder**: Implemented `PLCOperationBuilder.h/.m` for building/signing PLC operations.
- **PLCClient**: Implemented `PLCClient.h/.m` HTTP client for plc.directory operations.
- **PLCAccountCreator**: Implemented `PLCAccountCreator.h/.m` orchestrating full account creation flow.
- **PDSAccountService Integration**: Integrated PLC account creation into `createAccountForEmail()`.
- **Fix Duplicate Symbols**: Resolved linker errors from duplicate `DIDKeyErrorDomain` and `PLCOperationErrorDomain` definitions across files.

### 🏗️ Phase 3: The Firehose & Sync - IN PROGRESS
- **Repo Sync**: Implemented `subscribeRepos` commit broadcasting with operation extraction.
- **WebSocket**: WebSocket handler is implemented but needs robust testing.

### 🏗️ Phase 4: Linux Support & Robustness - IN PROGRESS
- **Linux Porting**: Implemented `PDSNetworkTransportLinux` using BSD sockets and libdispatch. Added unit tests.
- **CLI Enhancements**: Added unit tests for CLI commands.
- **Handle Resolution**: Implemented DNS TXT fallback for handle resolution.

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
1. ✅ `xcodegen generate` succeeds
2. ✅ `xcodebuild -scheme AllTests build` succeeds
3. ✅ `./build/tests/AllTests` passes (zero failures)
4. ✅ Fuzzers build successfully
