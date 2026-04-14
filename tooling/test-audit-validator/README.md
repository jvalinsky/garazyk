# Test Audit Validator

`test-audit-validator` is a static analysis tool for Objective-C XCTest code.
It checks whether tests actually validate the behavior they claim to cover.

The tool is designed for the September PDS codebase, but the architecture is
general: Go handles orchestration, filtering, reporting, and parallelism, while
libclang handles Objective-C parsing when you need real AST structure.

## How the tool works at a glance

The default execution path looks like this:

```text
CLI flags/config
  -> test file discovery
  -> parser selection (simple, auto, or clang)
  -> per-file analysis
  -> validation rules
  -> report generation
  -> optional CI failure based on severity
```

At a finer level:

1. The CLI loads defaults, optional config file values, environment variables,
   and explicit flags.
2. It walks the target tree and collects `.m` files whose names look like test
   files.
3. It chooses a parser mode:
   `simple` for regex-only parsing, `auto` for libclang with per-file fallback,
   or `clang` for strict libclang.
4. Each file becomes a `models.TestFile` with classes, methods, assertions,
   comments, and method calls.
5. Validation rules inspect those models and emit findings.
6. The report package renders markdown, JSON, or HTML output.

## Why the tool is written in Go

Go is a good fit for the control plane of this tool:

- It makes CLI construction straightforward with Cobra.
- It makes configuration layering straightforward with Viper.
- Goroutines and channels make the worker-pool runner simple and explicit.
- JSON, HTML, and markdown generation are easy to keep deterministic.
- The tool remains easy to run in CI and easy to package with a small binary.

Go is not the parser because Objective-C syntax and Apple-specific build
context are the hard part. That is why the tool still uses libclang for the
AST-backed path.

## Why the tool still needs libclang

Regex is fast and resilient, but it cannot reliably answer questions like:

- Which `@implementation` actually owns this test method?
- Is this selector a real Objective-C message send?
- Is this assertion inside a conditional or unreachable region?
- Does this file use categories, blocks, or ARC-era syntax that changes shape?

libclang gives the tool Objective-C-aware parsing, source locations,
diagnostics, and cursor kinds. That enables more precise extraction of test
classes, XCTest methods, assertion calls, message sends, and control-flow
signals.

See [docs/LIBCLANG_AST_PARSING.md](docs/LIBCLANG_AST_PARSING.md) for the full
AST-focused explanation.

## Parser selection and when to use each mode

| Mode | Behavior | When to use it | Failure behavior |
| --- | --- | --- | --- |
| `simple` | Regex and source-text parsing only | Fast local scans, environments without libclang, baseline comparison | Never attempts libclang |
| `auto` | Try libclang per file, then fall back to simple parser | Default local workflow | Per-file fallback with warning |
| `clang` | Require libclang for every file | Parser quality gates, CI, libclang debugging | Any parse/setup failure fails the run |

Examples:

```bash
# Default: libclang when possible, simple parser when needed
./bin/test-audit-validator analyze --parser auto ../../Garazyk/Tests

# Strict parser gate
./bin/test-audit-validator analyze --parser clang ../../Garazyk/Tests

# Fast regex-only scan
./bin/test-audit-validator analyze --parser simple ../../Garazyk/Tests
```

In strict clang mode with JSON output, parser failures are emitted in the
top-level `errors` array and the process exits non-zero. JSON metadata also
includes:

- `metadata.parser_mode`
- `metadata.clang_attempted_count`
- `metadata.clang_success_count`
- `metadata.clang_fallback_count`

## How `compile_commands.json` changes parsing quality

The libclang path is only as good as the compiler arguments it sees. Objective-C
parsing depends on the same world view the real compiler had:

- SDK path
- framework search paths
- preprocessor defines
- include directories
- module and resource configuration

If `compile_commands.json` is present, the tool tries to reuse those arguments
and then patches them into a parse-friendly form. That is usually the most
accurate way to parse Objective-C tests.

If it is missing, the tool falls back to repository-agnostic Objective-C parse
arguments and some project-relative include guesses. That often works, but it
is more likely to miss framework context or fail in strict clang mode.

This is why the recommended clang-backed invocation points at an out-of-source
build directory:

```bash
./bin/test-audit-validator analyze \
  --parser auto \
  --compile-commands-dir ../../build \
  ../../Garazyk/Tests
```

## How the runner, cache, and reports fit together

The runtime responsibilities are deliberately split:

- The runner owns concurrency, per-file timeouts, file-size limits, and
  progress reporting.
- The cache package stores findings keyed by file hash so unchanged files can
  skip re-analysis.
- The report package turns one set of findings into markdown, JSON, or HTML
  without changing validation logic.

That split keeps parsing logic out of the worker pool, keeps rendering logic
out of the rules, and keeps CI output stable across parser modes.

## Installation

### Prerequisites

- Go 1.23+
- libclang 14+ for AST-backed parsing

### Installing libclang

**macOS (Xcode, recommended):**

```bash
xcode-select --install

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
export CGO_LDFLAGS="-L/usr/lib/llvm-14/lib -Wl,-rpath,/usr/lib/llvm-14/lib"
```

**Linux (Fedora/RHEL):**

```bash
sudo dnf install clang-devel clang
```

For setup rationale and failure modes, see
[LIBCLANG_SETUP.md](LIBCLANG_SETUP.md).

### Building

```bash
cd tools/test-audit-validator

# Recommended: repository Makefile wrapper
make build

# Direct build
go build -o bin/test-audit-validator ./cmd/test-audit-validator
```

## Usage

### Basic analysis

```bash
# Analyze tests in current directory
./bin/test-audit-validator analyze

# Analyze a specific tree
./bin/test-audit-validator analyze ../../Garazyk/Tests

# Write markdown output to a file
./bin/test-audit-validator analyze -o report.md ../../Garazyk/Tests

# JSON for CI or scripts
./bin/test-audit-validator analyze -f json -o report.json ../../Garazyk/Tests

# Interactive HTML report
./bin/test-audit-validator analyze -f html -o report.html ../../Garazyk/Tests
```

### Filtering

```bash
# Only critical and high findings
./bin/test-audit-validator analyze --severity critical,high ../../Garazyk/Tests

# Only Auth domain tests
./bin/test-audit-validator analyze --domain Auth ../../Garazyk/Tests

# Specific test class
./bin/test-audit-validator analyze --class OAuthDPoPTests ../../Garazyk/Tests

# Filter by test type
./bin/test-audit-validator analyze --test-type property ../../Garazyk/Tests
```

### Incremental analysis

```bash
# First run creates the cache
./bin/test-audit-validator analyze --incremental --cache .test_audit_cache.db ../../Garazyk/Tests

# Later runs only re-analyze changed files
./bin/test-audit-validator analyze --incremental --cache .test_audit_cache.db ../../Garazyk/Tests
```

### Parallel processing

```bash
./bin/test-audit-validator analyze --workers 8 ../../Garazyk/Tests
```

### Quiet mode

```bash
./bin/test-audit-validator analyze -q -f json -o report.json ../../Garazyk/Tests
```

## Planned analysis workflow via `make`

Use the Make targets when you want reproducible local parser checks:

```bash
# Build the tool
make build

# Produce simple/auto/clang JSON artifacts
make audit-matrix-json

# Enforce the auto-mode parser gate
make audit-gate

# Enforce strict clang
make audit-clang-gate

# Print one-line summaries for the generated artifacts
make audit-summary
```

Generated artifacts:

- `.artifacts/test-audit/audit-simple.json`
- `.artifacts/test-audit/audit-auto.json`
- `.artifacts/test-audit/audit-clang.json`

Useful overrides:

```bash
# Analyze a different tests root
make audit-matrix-json TEST_ROOT=../../Garazyk/Tests/Auth

# Point clang-backed modes at a specific compile_commands.json directory
make audit-matrix-json COMPILE_COMMANDS_DIR=../../build
```

## Configuration

Create a `.test_audit_config.json` file in your project root:

```json
{
  "root_directory": "Garazyk/Tests",
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

See [examples/.test_audit_config.json](examples/.test_audit_config.json) for a
complete example.

Configuration precedence:

1. CLI flags
2. `TAV_` environment variables
3. `.test_audit_config.json`
4. built-in defaults

### Configuration reference

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `root_directory` | string | `"."` | Root directory containing test files |
| `cache_path` | string | `".test_audit_cache.db"` | Path to SQLite cache database |
| `parser` | string | `"auto"` | Parser mode: `auto`, `clang`, `simple` |
| `compile_commands_dir` | string | `""` | Directory containing `compile_commands.json` |
| `clang_args` | `[]string` | `[]` | Extra clang arguments appended after resolved args |
| `output_format` | string | `"markdown"` | Output format: `markdown`, `json`, `html` |
| `output_file` | string | `""` | Output file path (empty means stdout) |
| `quiet` | bool | `false` | Suppress progress output |
| `incremental` | bool | `false` | Only analyze files changed since last run |
| `fail_on` | string | `""` | Exit with error if findings at this severity or above |
| `max_file_size` | int | `1048576` | Maximum file size in bytes |
| `file_timeout` | int | `30` | Per-file analysis timeout in seconds |
| `workers` | int | `NumCPU()` | Number of parallel workers |
| `domains` | `[]string` | `[]` | Filter by domain |
| `severities` | `[]string` | `[]` | Filter by severity |
| `test_types` | `[]string` | `[]` | Filter by test type |
| `test_classes` | `[]string` | `[]` | Filter by test class name |

## Validation rules

The tool includes 16 validation rules, each targeting a different class of test
quality problem:

| # | Rule | Default severity | Purpose |
| --- | --- | --- | --- |
| 1 | `NameAssertionAlignmentRule` | High | Test name vs actual assertions |
| 2 | `FalsePositiveDetectionRule` | Critical | Tests that pass without validating behavior |
| 3 | `SecurityTestRule` | Critical | Security tests that do not verify rejection behavior |
| 4 | `AsyncTestRule` | High | Async tests with weak expectation handling |
| 5 | `MockStubRule` | Medium | Over-mocking, under-mocking, or unverified mocks |
| 6 | `PropertyBasedTestRule` | High | Property-style tests missing real properties |
| 7 | `CoverageGapRule` | Medium | Claimed behavior with incomplete validation |
| 8 | `IntegrationTestRule` | Medium | Integration tests missing multi-component realism or cleanup |
| 9 | `InteropTestRule` | High | Interop tests missing fixture/reference checks |
| 10 | `ParserSerializerRule` | Medium | Parser or serializer tests missing companions |
| 11 | `AssertionQualityRule` | Medium | Weak assertion mix or suspicious assertion counts |
| 12 | `CharacterizationTestRule` | Medium | Characterization tests without specific-value checks |
| 13 | `TestDependencyRule` | High | Order coupling, shared state, or external dependency issues |
| 14 | `TestDocumentationRule` | Low | Complex tests lacking explanation |
| 15 | `TestFixtureRule` | Medium | Fixture path and usage validation |
| 16 | `TestOrganizationRule` | Medium | Structural organization and base-class checks |

For detailed rule descriptions and remediation guidance, see
[docs/FINDINGS_GUIDE.md](docs/FINDINGS_GUIDE.md).

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success, or no findings at or above the selected `--fail-on` level |
| 1 | Critical findings found |
| 2 | High findings found |
| 3 | Medium findings found |
| 4 | Low findings found |

## Architecture summary

```text
cmd/test-audit-validator/
  main.go             CLI, config overlay, parser choice, report emission
  parser_selector.go  simple/auto/clang mode behavior
  clang_parser.go     compile_commands + libclang-backed model building

internal/
  analysis/           Objective-C AST helpers built on libclang
  cache/              SQLite-backed incremental cache
  config/             config loading, validation, and finding filters
  discovery/          richer discovery helpers and registration checks
  models/             parsed test model types
  report/             markdown, JSON, HTML renderers
  runner/             worker-pool orchestration
  validation/         finding rules and validation engine
```

Important current detail: the CLI currently performs its own filename-based
file discovery in `main.go`. The `internal/discovery` package contains richer
discovery and registration utilities, but it is not the default execution path
yet.

For the full subsystem walkthrough, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

### Running tests

```bash
# Full test suite
make test

# Coverage report
make test-coverage

# Specific packages
make test-analysis
make test-discovery
make test-models
```

### Adding a new validation rule

1. Create `internal/validation/my_new_rule.go`.
2. Implement the `ValidationRule` interface.
3. Add the rule to `DefaultRules()` in `internal/validation/rules.go`.
4. Add focused tests in `internal/validation/my_new_rule_test.go`.
5. Run `go test ./internal/validation/...`.

See [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the surrounding workflow.

## Where to read deeper

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): subsystem map and execution flow
- [docs/GO_TOOLING_DEEP_DIVE.md](docs/GO_TOOLING_DEEP_DIVE.md): why the Go
  packages are split the way they are
- [docs/LIBCLANG_AST_PARSING.md](docs/LIBCLANG_AST_PARSING.md): how libclang
  parses Objective-C and what the AST path enables
- [LIBCLANG_SETUP.md](LIBCLANG_SETUP.md): environment setup and parse failure
  troubleshooting
- [internal/analysis/README.md](internal/analysis/README.md): analysis package
  responsibilities and limits
