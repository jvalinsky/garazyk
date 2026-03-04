# Test Audit Validator

A comprehensive static analysis tool that validates whether test code in the September PDS codebase actually tests what it claims to test.

## Overview

The Test Audit Validator analyzes 1017 tests across 155+ test classes to identify:

- **Name-Assertion Mismatches**: Tests that don't validate what their names claim
- **False Positives**: Tests that pass without validating behavior
- **Coverage Gaps**: Functionality claimed but not validated
- **Security Test Issues**: Security tests that don't verify security properties
- **Property Test Issues**: Property-based tests that don't validate correctness properties
- **Interop Test Issues**: AT Protocol compliance tests missing reference comparisons

## Features

- Static analysis using libclang for Objective-C AST parsing
- Test registration validation (detects unregistered test classes)
- Incremental analysis with SQLite caching
- Multiple output formats (Markdown, JSON, HTML)
- Configurable validation rules
- CI/CD integration support
- Parallel file processing for performance

## Installation

### Prerequisites

The Test Audit Validator requires **libclang 14** for parsing Objective-C code. This is the official Clang library that provides AST (Abstract Syntax Tree) access.

#### macOS

libclang is included with Xcode Command Line Tools:

```bash
# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Verify installation
clang --version  # Should show Apple clang version 14.0 or higher
```

**Setting up environment for Go:**

When building or testing, you need to tell Go where to find libclang:

```bash
# For Xcode's libclang (recommended on macOS)
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib -Wl,-rpath,/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
export CGO_CFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"

# Then build or test
go build ./cmd/test-audit-validator
go test ./...
```

Alternatively, install via Homebrew for a specific LLVM version:

```bash
# Install LLVM 14 (includes libclang)
brew install llvm@14

# Set environment variables for Go to find libclang
export CGO_CFLAGS="-I$(brew --prefix llvm@14)/include"
export CGO_LDFLAGS="-L$(brew --prefix llvm@14)/lib -Wl,-rpath,$(brew --prefix llvm@14)/lib"
```

#### Linux

**Ubuntu/Debian:**

```bash
# Install libclang-14 development files
sudo apt-get update
sudo apt-get install libclang-14-dev clang-14

# Verify installation
clang-14 --version
```

**Fedora/RHEL:**

```bash
# Install clang development files
sudo dnf install clang-devel clang

# Verify installation
clang --version
```

**Arch Linux:**

```bash
# Install clang
sudo pacman -S clang

# Verify installation
clang --version
```

#### Verifying libclang Installation

After installation, verify that Go can find libclang:

```bash
cd tools/test-audit-validator
go build ./cmd/test-audit-validator

# If you see errors about missing libclang, you may need to set:
export CGO_CFLAGS="-I/usr/lib/llvm-14/include"
export CGO_LDFLAGS="-L/usr/lib/llvm-14/lib"
```

### Build from Source

```bash
cd tools/test-audit-validator
go build -o bin/test-audit-validator ./cmd/test-audit-validator
```

## Usage

### Basic Analysis

```bash
# Analyze all tests
./bin/test-audit-validator --root ../../ATProtoPDS/Tests

# Analyze specific directory
./bin/test-audit-validator --root ../../ATProtoPDS/Tests/Auth

# Analyze specific test class
./bin/test-audit-validator --class OAuthDPoPTests

# Check for unregistered test classes
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --check-registration --test-main ../../ATProtoPDS/Tests/test_main.m
```

### Filtering

```bash
# Filter by severity
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --severity critical,high

# Filter by domain
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --domain Auth,Network

# Filter by test type
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --test-type property
```

### Output Formats

```bash
# Generate Markdown report
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --format markdown --output report.md

# Generate JSON report
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --format json --output report.json

# Generate HTML report
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --format html --output report.html
```

### Incremental Analysis

```bash
# First run (full analysis)
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --cache .audit_cache

# Subsequent runs (only analyze changed files)
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --cache .audit_cache --incremental
```

### CI Integration

```bash
# Fail CI if critical issues found
./bin/test-audit-validator --root ../../ATProtoPDS/Tests --fail-on critical --format json > audit.json

# Exit codes:
# 0 = success (no issues at fail-on severity)
# 1 = critical issues found
# 2 = high severity issues found
# 3 = analysis error
```

## Configuration

Create `.test_audit_config.json` in your project root:

```json
{
  "root_path": "ATProtoPDS/Tests",
  "cache_path": ".audit_cache",
  "exclude_patterns": [
    "*/fixtures/*",
    "*/plc_e2e/*"
  ],
  "severity_thresholds": {
    "name_assertion_alignment": 0.5,
    "false_positive_confidence": 0.7
  },
  "rules": {
    "NameAssertionAlignmentRule": {
      "enabled": true,
      "min_score": 0.5
    },
    "PropertyBasedTestRule": {
      "enabled": true,
      "require_varied_inputs": true
    },
    "FalsePositiveDetectionRule": {
      "enabled": true,
      "check_trivial_assertions": true
    }
  },
  "report": {
    "format": "markdown",
    "output": "audit_report.md",
    "include_recommendations": true,
    "group_by": "severity"
  }
}
```

## Architecture

The system consists of four primary components:

1. **Test Discovery Engine**: Discovers test classes and methods using ObjC runtime reflection patterns
   - Discovers test files recursively in directory trees
   - Identifies test classes inheriting from XCTestCase or test base classes
   - Extracts test methods (methods starting with "test")
   - Parses test_main.m to extract registered test classes
   - Validates test class registration and reports unregistered classes
2. **Static Analysis Engine**: Parses Objective-C test code using libclang to extract structure and assertions
3. **Validation Engine**: Applies validation rules to detect mismatches, false positives, and gaps
4. **Report Generator**: Produces actionable reports with severity rankings and recommendations

### Test Registration Validation

The September PDS test runner uses runtime reflection to discover test methods, but test classes must be explicitly registered in the `testClasses` array in `ATProtoPDS/Tests/test_main.m`. The Test Discovery Engine validates this registration:

- **ParseTestMainRegistration**: Parses test_main.m to extract the testClasses array
- **CheckTestRegistration**: Verifies if a specific test class is registered
- **FindUnregisteredTestClasses**: Identifies test classes that exist but aren't registered

Unregistered test classes won't be executed by the test runner, leading to silent test coverage gaps. The validator detects these issues and reports them as HIGH severity findings.

## Development

### Running Tests

```bash
# Run all tests
go test ./...

# Run tests with coverage
go test -cover ./...

# Generate coverage report
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
```

### Adding New Validation Rules

See [CONTRIBUTING.md](CONTRIBUTING.md) for details on adding new validation rules.

## License

Same as September PDS project.

## Status

🚧 **Under Development** - This tool is currently being implemented as part of the test-audit-validation spec.
