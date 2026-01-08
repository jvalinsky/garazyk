# Agent Instructions

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

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

## Security Testing

This project includes comprehensive security testing infrastructure.

### Available Security Targets

```bash
make clang-tidy              # Run clang-tidy static analysis
make scan-build             # Run Clang Static Analyzer
make fuzz-asan              # Build with AddressSanitizer
make fuzz-ubsan             # Build with UBSAN
make fuzz-tsan              # Build with ThreadSanitizer
make fuzz-all               # Build with all sanitizers
make fuzz-xrpc              # Build XRPC fuzzer
make fuzz-cbor              # Build CBOR/CAR fuzzer
make fuzz-http              # Build HTTP parser fuzzer
make run-fuzzers            # Run all fuzzers (limited run)
```

### Running Fuzzers

For extended fuzzing sessions:

```bash
# XRPC endpoint fuzzing
./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -max_len=65536 -jobs=8 -timeout=30

# CBOR/CAR parsing fuzzing
./fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -max_len=65536 -jobs=8 -timeout=30

# HTTP request parsing fuzzing
./fuzzing/fuzz_http fuzzing/corpus_http/ -max_len=65536 -jobs=8 -timeout=30
```

### Clang-Tidy Configuration

Static analysis is configured in `.clang-tidy`. Key checks enabled:
- `bugprone-*` - Bug-prone code patterns
- `cert-*` - CERT C++ guidelines
- `objc-*` - Objective-C specific issues
- `clang-analyzer-*` - Clang static analyzer checks

To run on specific files:
```bash
clang-tidy -p . --config-file=.clang-tidy ATProtoPDS/Sources/Repository/CBOR.m
```

### Security Results

**Static Analysis Findings:**
- CBOR.m: Multiple `bugprone-branch-clone` warnings (code duplication in switch statements)
- PDSDatabase.m: `cert-dcl51-cpp` warning about reserved identifier `_iso8601Formatter`
- Header include issues resolved for Foundation framework

**Fuzzing Status:**
- All 3 fuzzers (XRPC, CBOR, HTTP) build successfully
- Corpus seeded with sample HTTP requests
- Initial test runs completed without crashes

### GitHub Actions Security Workflow

A comprehensive security testing workflow runs automatically:

```yaml
# .github/workflows/security.yml
name: Security Testing
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday
  workflow_dispatch:
    inputs:
      fuzzing_duration:
        description: 'Fuzzing duration in minutes'
        default: '30'

jobs:
  static-analysis:    # Clang-tidy
  codeql-analysis:    # GitHub CodeQL
  fuzzing:            # libFuzzer with corpus
  dependency-check:   # OSV Scanner
  secret-scanning:    # TruffleHog
  security-report:    # Combined report
```

**Features:**
- Automatic execution on push/PR/schedule
- Configurable fuzzing duration
- CodeQL security analysis
- Dependency vulnerability scanning
- Secret detection
- Sanitizer build verification
- Comprehensive security report

**View Results:**
- GitHub Security tab → Vulnerability alerts
- Artifacts attached to workflow runs
- SECURITY_REPORT.md in workflow artifacts

### Adding Fuzzing Corpus

Add valid inputs to improve fuzzing effectiveness:

```bash
# HTTP requests
cp samples/http_valid.txt fuzzing/corpus_http/

# CBOR data
cp samples/cbor_valid.bin fuzzing/corpus_cbor/

# XRPC calls
cp samples/xrpc_valid.txt fuzzing/corpus_xrpc/
```

### Crash Analysis

Crashes are written to `fuzzing/crashers/`. To triage:
```bash
# Reproduce crash
./fuzzing/fuzz_xrpc fuzzing/crashers/crash_id

# Minimize test case
./fuzzing/fuzz_xrpc fuzzing/crashers/crash_id -minimize_crash=1
```

### Related Files

- `.clang-tidy` - Static analysis configuration
- `SECURITY_PLAN.md` - Comprehensive security strategy
- `fuzzing/` - Fuzzing harnesses and corpus
- `Makefile` - Build targets (search for "Security Targets")

---

## CI/CD Pipeline

This project uses GitHub Actions for continuous integration.

### Workflows

| Workflow | File | Purpose |
|----------|------|---------|
| **CI** | `.github/workflows/ci.yml` | Build, test, coverage, lint |
| **Security** | `.github/workflows/security.yml` | Static analysis, fuzzing, dependency scan |
| **Deploy Pages** | `.github/workflows/deploy-pages.yml` | Deploy docs to GitHub Pages |
| **Cleanup** | `.github/workflows/cleanup-decision-graphs.yml` | Clean up PR assets |

### CI Workflow Jobs

| Job | Trigger | Purpose |
|-----|---------|---------|
| `build-and-test` | Every PR/push | Build project and run tests |
| `coverage` | After build | Generate code coverage report |
| `lint` | Every PR/push | Code formatting and linting |
| `dependencies` | Every PR/push | Dependency verification |
| `docs` | After build | Validate documentation builds |
| `summary` | After all jobs | Create PR comment with results |

### Running CI Locally

```bash
# Build project
xcodebuild -project ATProtoPDS.xcodeproj -scheme ATProtoPDS build

# Run tests
"/Users/jack/Library/Developer/Xcode/DerivedData/ATProtoPDS-gxvfspcaobaihodzeszdnsruddhc/Build/Products/Debug/AllTests"

# Run static analysis
make clang-tidy

# Run fuzzers
./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/
./fuzzing/fuzz_cbor fuzzing/corpus_cbor/
./fuzzing/fuzz_http fuzzing/corpus_http/
```

### CI Status

View CI status at: **Actions** tab on GitHub

- Green checkmark: All checks passed
- Red X: Some checks failed
- Yellow dot: Checks in progress

### Quality Gates

Before pushing, ensure:
1. ✅ All tests pass (`./AllTests`)
2. ✅ Project builds (`xcodebuild build`)
3. ✅ No new clang-tidy errors
4. ✅ Fuzzers still pass
