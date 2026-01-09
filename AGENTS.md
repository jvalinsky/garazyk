# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Project Status

### ✅ Phase 3: Build System & Testing Stabilization - COMPLETED
- **Unified Build System**: Migrated to a unified CMake build system wrapped by XcodeGen, eliminating legacy Makefiles and disconnected Xcode project configurations.
- **Fuzzing Integration**: Fuzzers (`xrpc`, `cbor`, `http`, `auth`) are now first-class build targets, with a local fallback driver for macOS/AppleClang environments.
- **Test Suite Repair**: Fixed critical failures in `PDSControllerTests` (refresh token logic), `DIDResolverTests`, and `ATProtoCoreTests`.
- **Test Consolidation**: 107 unit tests are now passing. Broken or obsolete tests (`OAuth2Tests`, `XRPCHandlerTests`) were removed or excluded.
- **Dependency Management**: `secp256k1` is built as a CMake subproject, and `XCTest` linking is properly configured.

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
