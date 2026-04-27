# Test Audit Validator

`test-audit-validator` is a static analysis tool for Objective-C XCTest code. It verifies that tests validate the behaviors they claim to cover by inspecting AST structure and assertions.

## Execution Flow

1. **Discovery**: Recursively scans the target tree for `.m` files.
2. **Parsing**: Selects a parser (`simple`, `auto`, or `clang`) to build a model of the test file.
3. **Analysis**: Inspects classes, methods, assertions, and message sends.
4. **Validation**: Applies rules to the model and generates findings.
5. **Reporting**: Renders findings in Markdown, JSON, or HTML.

## Implementation Detail

### Control Plane (Go)
The orchestration layer uses Go to manage CLI flags, configuration, parallel workers, and caching. Go is used for:
- Worker-pool execution for concurrent file analysis.
- JSON, HTML, and Markdown report generation.
- Incremental analysis via a SQLite-backed cache.
- CLI management using Cobra and Viper.

### Parser (libclang)
The tool uses libclang to provide Objective-C-aware parsing. This enables the tool to resolve:
- Method ownership within `@implementation` blocks.
- Objective-C message sends and selectors.
- Source locations for findings.
- Control-flow signals (if/switch statements).

## Parser Modes

| Mode | Behavior | Use Case |
| --- | --- | --- |
| `simple` | Regex and source-text parsing only | Fast scans or environments without libclang |
| `auto` | Try libclang per file, fall back to simple parser | Default local development |
| `clang` | Require libclang for all files | CI gates and parser quality checks |

## Usage

### Basic Analysis
```bash
# Analyze tests in a specific directory
./bin/test-audit-validator analyze ../../Garazyk/Tests

# JSON output for automation
./bin/test-audit-validator analyze -f json -o report.json ../../Garazyk/Tests
```

### Filtering
```bash
# Filter by severity and domain
./bin/test-audit-validator analyze --severity critical,high --domain Auth
```

### Integration with compile_commands.json
Providing a `compile_commands.json` directory improves libclang accuracy by reusing the original compiler arguments:
```bash
./bin/test-audit-validator analyze --compile-commands-dir ../../build ../../Garazyk/Tests
```

## Installation

### Prerequisites
- Go 1.23+
- libclang 14+

### Building
```bash
cd tools/test-audit-validator
make build
```

Refer to `docs/ARCHITECTURE.md` and `docs/FINDINGS_GUIDE.md` for technical details and remediation guidance.
