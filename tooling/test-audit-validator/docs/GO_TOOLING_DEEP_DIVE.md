# Go Orchestration and Architecture

`test-audit-validator` uses Go to coordinate the analysis process, manage configuration, and generate reports. While libclang handles Objective-C parsing, Go provides the operational infrastructure.

## Execution Pipeline

The execution sequence follows these steps in `cmd/test-audit-validator/main.go`:

1. **CLI and Config**: Cobra and Viper load and merge configuration from flags, environment variables, and `.test_audit_config.json`.
2. **Discovery**: Recursively identifies `.m` files in the target root.
3. **Parser Selection**: `parser_selector.go` determines whether to use the `simple` (regex) or `clang` analyzer.
4. **Concurrent Execution**: `internal/runner` distributes files across a worker pool with per-file timeouts.
5. **Validation**: The validation engine runs rules against the intermediate `models.TestFile`.
6. **Reporting**: Renderers in `internal/report` generate Markdown, JSON, or HTML output.

## Core Package Responsibilities

### CLI and Configuration (`internal/config`)
Manages configuration precedence:
1. CLI flags.
2. `TAV_` environment variables.
3. `.test_audit_config.json`.
4. Defaults.

The config package also handles finding filters (domain, severity, etc.) to keep the validation engine focused solely on detection.

### Runner and Concurrency (`internal/runner`)
Coordinates file analysis using a worker pool. It abstracts the specific parser implementation behind a `FileAnalyzer` interface. This package also handles file-size limits and progress reporting.

### Caching (`internal/cache`)
Uses SQLite to store analysis results keyed by file content hash. This allows the tool to skip re-analyzing unchanged files in incremental mode.

### Validation Engine (`internal/validation`)
Contains the logic for identifying test quality issues. Rules are implemented against the `models` package, making them agnostic to the underlying parser (regex or libclang).

### Reporting (`internal/report`)
Transforms findings into structured output. By isolating rendering logic, the tool can support multiple formats from a single analysis pass.

## Repository Tooling

- **Makefile**: Defines repeatable tasks for building, testing, and running audit gates.
- **flake.nix**: Defines the environment, including the Go toolchain and libclang dependencies.

## Extension Points

- **New Rules**: Implement the `ValidationRule` interface in `internal/validation/`.
- **AST Extraction**: Update `internal/analysis/engine.go` to extract more information from libclang cursors.
- **Output Formats**: Add new renderers to `internal/report/`.
