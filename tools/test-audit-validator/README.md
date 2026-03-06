# Test Audit Validator

A static analysis tool that validates Objective-C XCTest test code to ensure tests actually test what they claim to test. Designed for the September PDS codebase (1017+ tests across 155+ test classes).

## Features

- **Name-Assertion Alignment**: Detects tests whose assertions don't match what the test name claims to verify
- **False Positive Detection**: Identifies tests that always pass regardless of code correctness
- **Security Test Validation**: Verifies OAuth/DPoP/JWT/SSRF tests actually validate security properties
- **Async Test Validation**: Ensures async tests properly create, fulfill, and wait for expectations
- **Property-Based Test Detection**: Identifies and validates round-trip, invariant, and idempotence patterns
- **Coverage Gap Analysis**: Detects missing error handling, state transition, and concurrency testing
- **Mock/Stub Validation**: Flags over-mocking, under-mocking, and unverified mock interactions
- **Integration Test Validation**: Checks multi-component setup, resource cleanup, and outcome assertions
- **Interop Test Validation**: Verifies tests compare against reference implementation outputs
- **Parser/Serializer Validation**: Detects missing round-trip and pretty-printer companion tests
- **Test Dependency Analysis**: Identifies external dependencies, execution order coupling, and shared mutable state
- **Test Organization**: Validates directory structure and base class usage
- **Assertion Quality Analysis**: Evaluates assertion count and quality (value vs existence assertions)
- **Characterization Test Validation**: Ensures characterization tests capture specific values for regression detection
- **Test Documentation**: Flags complex tests lacking explanatory comments
- **Test Fixture Validation**: Verifies fixture files exist and are used in assertions
- **Incremental Analysis**: SQLite-based caching for fast re-analysis of changed files
- **Multiple Report Formats**: Markdown, JSON, and interactive HTML reports
- **CI Integration**: Configurable fail-on severity for quality gates

## Installation

### Prerequisites

- Go 1.23+
- libclang 14+ (for AST parsing)

### Installing libclang

**macOS (Xcode — recommended):**
```bash
# libclang is included with Xcode Command Line Tools
xcode-select --install

# Set environment variables for Go
export CGO_CFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib -Wl,-rpath,/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
```

**macOS (Homebrew):**
```bash
brew install llvm@14
export CGO_CFLAGS="-I$(brew --prefix llvm@14)/include"
export CGO_LDFLAGS="-L$(brew --prefix llvm@14)/lib -Wl,-rpath,$(brew --prefix llvm@14)/lib"
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install libclang-14-dev clang-14
export CGO_CFLAGS="-I/usr/lib/llvm-14/include"
export CGO_LDFLAGS="-L/usr/lib/llvm-14/lib"
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install clang-devel clang
```

See [LIBCLANG_SETUP.md](LIBCLANG_SETUP.md) for detailed setup instructions and troubleshooting.

### Building

```bash
cd tools/test-audit-validator

# Using Make (handles CGO flags automatically)
make build

# Or manually
go build -o bin/test-audit-validator ./cmd/test-audit-validator
```

## Usage

### Basic Analysis

```bash
# Analyze tests in current directory
./bin/test-audit-validator analyze

# Analyze tests in specific directory
./bin/test-audit-validator analyze ../../ATProtoPDS/Tests

# Output to file
./bin/test-audit-validator analyze -o report.md ../../ATProtoPDS/Tests

# JSON output for CI
./bin/test-audit-validator analyze -f json -o report.json ../../ATProtoPDS/Tests

# HTML report
./bin/test-audit-validator analyze -f html -o report.html ../../ATProtoPDS/Tests
```

### Filtering

```bash
# Only critical and high findings
./bin/test-audit-validator analyze --severity critical,high ../../ATProtoPDS/Tests

# Only Auth domain tests
./bin/test-audit-validator analyze --domain Auth ../../ATProtoPDS/Tests

# Specific test class
./bin/test-audit-validator analyze --class OAuthDPoPTests ../../ATProtoPDS/Tests

# Filter by test type
./bin/test-audit-validator analyze --test-type property ../../ATProtoPDS/Tests
```

### Parser Modes

```bash
# Auto (default): try libclang per file, fallback to simple parser on parse/setup errors
./bin/test-audit-validator analyze --parser auto ../../ATProtoPDS/Tests

# Strict clang: no fallback, exits non-zero on parse/setup errors
./bin/test-audit-validator analyze --parser clang ../../ATProtoPDS/Tests

# Force simple regex parser only
./bin/test-audit-validator analyze --parser simple ../../ATProtoPDS/Tests

# Prefer compile_commands.json from an out-of-source build directory
./bin/test-audit-validator analyze --parser auto --compile-commands-dir ../../build ../../ATProtoPDS/Tests
```

In strict clang mode with `-f json`, parse/setup failures are included in a machine-readable `errors` array and the process exits non-zero.
JSON reports also include parser telemetry metadata:
- `metadata.parser_mode`
- `metadata.clang_attempted_count`
- `metadata.clang_success_count`
- `metadata.clang_fallback_count`

### Planned Analysis Workflow (Make Targets)

Use the Make targets to run the full local workflow consistently:

```bash
# Build tool
make build

# Run parser matrix against ATProtoPDS/Tests
make audit-matrix-json

# Enforce local parser gate in auto mode (no parser errors/fallbacks)
make audit-gate

# Enforce strict clang gate (no parser errors/fallbacks)
make audit-clang-gate

# Print one-line summary for simple/auto/clang outputs
make audit-summary
```

Generated artifacts:

- `tools/test-audit-validator/.artifacts/test-audit/audit-simple.json`
- `tools/test-audit-validator/.artifacts/test-audit/audit-auto.json`
- `tools/test-audit-validator/.artifacts/test-audit/audit-clang.json`

Useful overrides:

```bash
# Analyze a different tests root
make audit-matrix-json TEST_ROOT=../../ATProtoPDS/Tests/Auth

# Point auto/clang modes at a specific compile_commands.json directory
make audit-matrix-json COMPILE_COMMANDS_DIR=../../build
```

### CI Integration

```bash
# Fail if critical findings exist (exit code 1)
./bin/test-audit-validator analyze --fail-on critical -f json -o report.json ../../ATProtoPDS/Tests

# Fail on high or above
./bin/test-audit-validator analyze --fail-on high ../../ATProtoPDS/Tests
```

### Incremental Analysis

```bash
# First run: full analysis (cache is created)
./bin/test-audit-validator analyze --incremental --cache .test_audit_cache.db ../../ATProtoPDS/Tests

# Subsequent runs: only re-analyze changed files
./bin/test-audit-validator analyze --incremental --cache .test_audit_cache.db ../../ATProtoPDS/Tests
```

### Parallel Processing

```bash
# Use 8 workers for analysis
./bin/test-audit-validator analyze --workers 8 ../../ATProtoPDS/Tests
```

### Quiet Mode

```bash
# Suppress progress output (useful in scripts)
./bin/test-audit-validator analyze -q -f json -o report.json ../../ATProtoPDS/Tests
```

## Configuration

Create a `.test_audit_config.json` file in your project root:

```json
{
    "root_directory": "ATProtoPDS/Tests",
    "cache_path": ".test_audit_cache.db",
    "parser": "auto",
    "compile_commands_dir": "",
    "clang_args": [],
    "output_format": "markdown",
    "output_file": "",
    "quiet": false,
    "incremental": true,
    "fail_on": "critical",
    "max_file_size": 1048576,
    "file_timeout": 30,
    "workers": 4,
    "domains": [],
    "severities": [],
    "test_types": [],
    "test_classes": []
}
```

See [examples/.test_audit_config.json](examples/.test_audit_config.json) for a complete example.

Configuration is loaded from (in order of precedence):

1. **CLI flags** — highest priority
2. **Environment variables** — prefix `TAV_` (e.g., `TAV_ROOT_DIRECTORY`, `TAV_OUTPUT_FORMAT`, `TAV_FAIL_ON`)
3. **Config file** — `.test_audit_config.json` in the current directory, or specified with `--config`
4. **Defaults** — sensible defaults for all values

### Configuration Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root_directory` | string | `"."` | Root directory containing test files |
| `cache_path` | string | `".test_audit_cache.db"` | Path to SQLite cache database |
| `parser` | string | `"auto"` | Parser mode: `auto`, `clang`, `simple` |
| `compile_commands_dir` | string | `""` | Directory containing `compile_commands.json` |
| `clang_args` | []string | `[]` | Extra clang arguments appended to resolved args |
| `output_format` | string | `"markdown"` | Output format: `markdown`, `json`, `html` |
| `output_file` | string | `""` | Output file path (empty = stdout) |
| `quiet` | bool | `false` | Suppress progress output |
| `incremental` | bool | `false` | Only analyze files changed since last run |
| `fail_on` | string | `""` | Exit with error if findings at this severity or above |
| `max_file_size` | int | `1048576` | Maximum file size in bytes (1MB) |
| `file_timeout` | int | `30` | Per-file analysis timeout in seconds |
| `workers` | int | `NumCPU()` | Number of parallel analysis workers |
| `domains` | []string | `[]` | Filter by domain (Auth, Core, Network, etc.) |
| `severities` | []string | `[]` | Filter by severity (critical, high, medium, low) |
| `test_types` | []string | `[]` | Filter by test type |
| `test_classes` | []string | `[]` | Filter by test class name |

## Validation Rules

The tool includes 16 validation rules, each targeting a specific class of test quality issue:

| # | Rule | Default Severity | Description |
|---|------|-----------------|-------------|
| 1 | `NameAssertionAlignmentRule` | High | Detects tests whose assertions don't match what the test name claims to verify |
| 2 | `FalsePositiveDetectionRule` | Critical | Identifies tests that pass without validating behavior (only non-null checks, trivial assertions, unreachable assertions, setup without verification) |
| 3 | `SecurityTestRule` | Critical | Validates that OAuth/DPoP/JWT/SSRF/input-validation/rate-limit tests verify security properties |
| 4 | `AsyncTestRule` | High | Ensures async tests create expectations, fulfill them, and wait with reasonable timeouts |
| 5 | `MockStubRule` | Medium | Detects over-mocking (>3 mocks), under-mocking (unmocked external deps), and unverified mock interactions |
| 6 | `PropertyBasedTestRule` | High | Validates that property-based tests check recognized correctness properties (round-trip, invariant, idempotence, metamorphic, model-based, confluence, error-condition) |
| 7 | `CoverageGapRule` | Medium | Detects gaps: multiple claims with single validation, error handling without exceptions, state transitions without before/after checks, concurrency without race testing, performance without timing |
| 8 | `IntegrationTestRule` | Medium | Validates integration tests exercise multiple components, use realistic environments, clean up resources, and assert on final outcomes |
| 9 | `InteropTestRule` | High | Validates interop tests load fixtures and compare against reference implementation outputs |
| 10 | `ParserSerializerRule` | Medium | Detects parser tests missing round-trip companions and serializer tests missing pretty-printer companions |
| 11 | `AssertionQualityRule` | Medium | Analyzes assertion count (too few/too many) and quality (value vs existence assertions) |
| 12 | `CharacterizationTestRule` | Medium | Ensures characterization tests assert specific values for regression detection, not just existence |
| 13 | `TestDependencyRule` | High | Identifies external service dependencies, execution order coupling, shared mutable state, and isolation issues |
| 14 | `TestDocumentationRule` | Low | Flags complex tests (>20 lines, >5 assertions) lacking explanatory comments |
| 15 | `TestFixtureRule` | Medium | Validates fixture paths exist and fixture data is used in assertions |
| 16 | `TestOrganizationRule` | Medium | Validates test files are in appropriate directories and use correct base classes |

For detailed descriptions, examples, and remediation guidance for each rule, see [docs/FINDINGS_GUIDE.md](docs/FINDINGS_GUIDE.md).

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **Critical** | Test provides false confidence — it passes without validating correctness | Fix immediately |
| **High** | Test likely doesn't test what it claims — significant gaps or mismatches | Review and fix |
| **Medium** | Test has potential gaps — incomplete coverage or structural issues | Consider improving |
| **Low** | Minor quality issues — documentation, organization, formatting | Improve when convenient |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (no findings at or above fail-on level) |
| 1 | Critical findings found |
| 2 | High findings found |
| 3 | Medium findings found |
| 4 | Low findings found |

## Architecture

```
cmd/test-audit-validator/    CLI entry point (cobra commands)
internal/
  analysis/                  libclang-based AST parsing of Objective-C test files
  cache/                     SQLite-based incremental analysis cache
  config/                    Configuration loading (file, env, CLI flags via viper)
  discovery/                 Test file/class/method discovery and registration validation
  models/                    Data model types (TestFile, TestClass, TestMethod, Assertion)
  report/                    Report generation (Markdown, JSON, HTML)
  runner/                    Parallel test file processing orchestrator
  validation/                Validation engine and 16 rule implementations
```

Data flow: **discovery → analysis → validation → reporting**

1. **Discovery**: Recursively find `.m` test files; parse `test_main.m` for registration
2. **Analysis**: Parse each file with libclang to extract classes, methods, assertions, and method calls
3. **Validation**: Run all enabled rules against each test method/class/file
4. **Reporting**: Aggregate findings into a structured report with statistics

For detailed architecture documentation, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

### Running Tests

```bash
# Using Make (handles CGO flags)
make test

# With coverage
make test-coverage

# Specific package
make test-analysis
make test-discovery
make test-models

# Run audit against ATProtoPDS/Tests (fails on critical findings)
make audit

# Generate full markdown report
make audit-report

# Cross-compile for macOS/Linux
make build-all
```

### Current Performance

Against the ATProtoPDS test suite (1,662 tests, 406 classes):

| Metric | Value |
|--------|-------|
| **Findings** | 1,796 |
| **Pass rate** | 68.7% |
| **Critical** | 288 |
| **High** | 305 |
| **Analysis time** | ~300ms |

### Adding New Validation Rules

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for step-by-step instructions.

## License

Same as September PDS project.
