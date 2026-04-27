# Architecture

`test-audit-validator` uses a Go control plane to manage file discovery, orchestration, and reporting, combined with a libclang-backed parsing layer for Objective-C analysis.

## Execution Flow

```text
config + flags
  -> file discovery
  -> parser selector
  -> test model construction
  -> validation rules
  -> filtering
  -> report generation
```

## Package Responsibilities

### CLI and Control Plane (`cmd/test-audit-validator/`)
- **main.go**: Entry point, flag definitions, and report emission.
- **parser_selector.go**: Manages fallback logic between `simple` and `clang` modes.
- **clang_parser.go**: Handles `compile_commands.json` resolution and libclang integration.

### Internal Libraries (`internal/`)
- **analysis/**: libclang helpers and AST extraction logic.
- **cache/**: SQLite-backed incremental analysis cache.
- **config/**: Configuration loading, validation, and finding filters.
- **discovery/**: Utilities for discovering test files and registrations.
- **models/**: The intermediate data model (TestFile, TestClass, TestMethod).
- **report/**: Renderers for Markdown, JSON, and HTML.
- **runner/**: Worker-pool orchestration and timeout management.
- **validation/**: Rule definitions and the validation engine.

## Configuration and Precedence

Configuration is resolved in `internal/config` using the following precedence:
1. CLI flags.
2. `TAV_` environment variables.
3. `.test_audit_config.json`.
4. Built-in defaults.

## Parser Selection

`parser_selector.go` abstracts the parser implementation from the runner. It supports three modes:
- **simple**: Regex and source-text analysis.
- **auto**: Attempts libclang first, falling back to simple per file.
- **clang**: Requires libclang and fails on any parse error.

## Model Layer

The tool builds intermediate models (`models.*`) from either the AST or source text. This allows validation rules to focus on test semantics rather than parser-specific APIs. The builder combines AST structure with source-text recovery for comments and method slices.

## Validation Engine

The `internal/validation` package executes rules against the parsed models. Each rule implements the `ValidationRule` interface, receiving a context that includes the test classes and methods found in a file.

## Execution and Concurrency

The `internal/runner` package manages the worker pool. It accepts a `FileAnalyzer` function, allowing it to remain agnostic of the specific parser implementation. The runner also handles per-file timeouts and file-size constraints.

## Caching

Incremental analysis is handled by `internal/cache`. It hashes file content and stores previous results in a SQLite database to skip re-analysis of unchanged files.
