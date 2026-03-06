# Architecture

## Overview

The Test Audit Validator is a static analysis tool that validates Objective-C XCTest code. It uses a pipeline architecture:

```
Discovery → Analysis → Validation → Reporting
```

## Package Structure

```
cmd/test-audit-validator/    CLI entry point
internal/
  analysis/                  libclang-based AST parsing (optional)
  cache/                     SQLite incremental analysis cache
  config/                    Configuration loading & filtering
  discovery/                 Test file/class/method discovery
  models/                    Data model types
  report/                    Report generation (MD, JSON, HTML)
  runner/                    Parallel file processing orchestrator
  validation/                Validation engine + 16 rule implementations
tests/
  integration/               End-to-end integration tests
testdata/
  fixtures/                  Test fixture files by domain
```

## Data Flow

1. **File Discovery**: Walk directory tree, find `.m` files matching test patterns
2. **Parsing**: Parse each file to extract `TestFile` → `TestClass` → `TestMethod` → `Assertion` hierarchy
3. **Validation**: Run all enabled `ValidationRule` implementations against each test method/class/file
4. **Filtering**: Apply domain/severity/class filters per configuration
5. **Reporting**: Generate structured report in requested format with statistics
6. **Caching**: Store/retrieve results in SQLite for incremental re-analysis

## Key Interfaces

### ValidationRule

```go
type ValidationRule interface {
    Name() string
    Description() string
    Validate(ctx ValidationContext) []Finding
}
```

All 16 rules implement this interface. Rules receive a `ValidationContext` containing the current test method, class, and file being validated. Rules return zero or more `Finding` structs.

### FileAnalyzer

```go
type FileAnalyzer func(filePath string) (*models.TestFile, error)
```

The runner accepts any function matching this signature. The CLI provides a built-in regex-based parser. The `analysis` package provides a libclang-based parser for deeper AST analysis.

### Report Generator

Each report format (Markdown, JSON, HTML) implements:
```go
func Generate(report *Report) (string, error)
```

## Adding New Validation Rules

1. Create `internal/validation/my_new_rule.go`
2. Define a struct implementing `ValidationRule`
3. Add to `DefaultRules()` in `internal/validation/rules.go`
4. Create `internal/validation/my_new_rule_test.go`
5. Run `go test ./internal/validation/`

## Concurrency Model

The `runner` package distributes files across a configurable worker pool. Each worker:
1. Checks file size limits
2. Checks incremental cache
3. Parses the file (with configurable timeout)
4. Runs all validation rules
5. Caches results
6. Reports progress

Workers communicate via Go channels. Results are collected and aggregated after all workers finish.
