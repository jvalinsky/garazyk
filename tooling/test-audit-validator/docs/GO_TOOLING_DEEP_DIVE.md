# Go tooling deep dive

## What problem this tool solves

`test-audit-validator` exists because "does this test file compile?" is not the
same question as "does this test validate the behavior it claims to cover?"

The repository already has Objective-C test code and Objective-C build tooling.
This tool adds a second layer: static audit logic that inspects test structure,
assertions, and naming patterns without executing the tests.

That audit logic lives outside the Objective-C build for practical reasons:

- it should run quickly against a whole test tree
- it should emit structured findings and CI-friendly exit codes
- it should support several output formats from one analysis pass
- it should be easy to extend with new heuristics

Go is a good fit for that orchestration layer. It is not being used because Go
parses Objective-C better than Clang. It is being used because the surrounding
tooling problem is a classic Go problem: CLI management, config layering,
parallel workers, caching, and report generation.

The parser still needs libclang because Objective-C syntax and build context are
the hard part. Regex alone is not enough for categories, blocks, selectors,
message sends, line-accurate findings, or AST-aware control-flow checks.

## The end-to-end execution path

The execution path starts in `cmd/test-audit-validator/main.go`:

1. Cobra parses the command and flags.
2. `internal/config` loads config defaults, optional config file values,
   environment variables, and validates the merged result.
3. The CLI discovers `.m` files under the target root.
4. The CLI constructs a simple parser and, when enabled, a clang-backed parser.
5. `parser_selector.go` wraps those analyzers into one mode-aware function.
6. `internal/runner` distributes files across workers and enforces per-file
   limits.
7. The chosen analyzer returns a `models.TestFile`.
8. `internal/validation` runs all rules against the parsed model.
9. `internal/config` filters findings by domain, severity, class, and test type.
10. `internal/report` renders markdown, JSON, or HTML.
11. The CLI writes the report and applies strict clang or `--fail-on` exit
    behavior.

That sequence is important because it explains the package split:

- parser setup happens before the runner
- rules operate on models, not AST cursors
- reporting happens after filtering
- exit behavior lives at the CLI boundary, not inside the rules

## Why the CLI uses Cobra

Cobra is the right choice here because this tool needs a stable human-facing and
automation-facing interface.

What Cobra is doing for this project:

- defining `analyze` and `version`
- centralizing flag parsing
- making defaults and help text explicit
- keeping future subcommands possible without rewriting the entrypoint

That matters because this tool is used in multiple contexts:

- ad hoc local analysis
- scripted local workflows via `make`
- CI gates
- parser debugging

A small, stable CLI surface reduces accidental drift between those workflows.

## Why configuration uses Viper

The config package uses Viper because the tool needs layered configuration
without hand-rolled precedence code in the CLI.

Current behavior:

- built-in defaults come from `DefaultConfig()`
- `.test_audit_config.json` is loaded when present
- `TAV_` environment variables override config-file values
- explicit CLI flags override everything else

This reduces friction in practice:

- local one-off runs can stay flag-driven
- CI can inject environment variables
- teams can check in sample config files for repeatable workflows

Viper is not a deep architectural choice here. It is a practical one. The real
design choice is that configuration resolution lives in one package, so the rest
of the tool can depend on a validated `Config` rather than re-reading flags or
environment variables on its own.

## Why the runner is separate from parsing

The runner package owns execution, not interpretation.

That is why it works with this narrow interface:

```go
type FileAnalyzer func(filePath string) (*models.TestFile, error)
```

This design buys several useful properties:

- the worker pool does not need to know whether the parser is regex-based or
  libclang-backed
- per-file timeout handling is centralized
- file-size checks happen before expensive parsing
- cache lookup and cache write-through stay in one place

The separation also makes failure modes easier to reason about. If a file times
out, that is runner behavior. If a file cannot be parsed because the SDK path is
wrong, that is analyzer behavior. Those are different problems and should stay
in different packages.

## Why parser selection is its own layer

The parser selector exists because parser mode is a policy choice, not a parser
implementation detail.

The project supports three policies:

- always simple
- always clang
- clang with per-file fallback

If that policy were spread across the runner, the CLI, and the clang parser, it
would be hard to answer basic questions like:

- how many files actually used clang?
- how many fell back?
- which mode should fail the process?

Keeping parser selection in its own file makes the behavior explicit and keeps
telemetry accurate.

## Why reports are a dedicated package

The report package exists because findings and rendering are not the same thing.

One validation run can support three consumers:

- markdown for direct reading
- JSON for scripts and gates
- HTML for browsing larger result sets

If the CLI generated all of those outputs directly, every output change would
touch command code. By isolating reporting:

- the validation engine stays output-agnostic
- new renderers can be added without changing rule logic
- JSON shape can stay stable for automation consumers

The report package also centralizes metadata such as parser mode, duration, and
clang fallback counts, which would otherwise be easy to format inconsistently.

## Why the data model sits between parsing and validation

The parser does not give rules raw clang cursors. It builds intermediate Go
models first.

That is a deliberate design decision.

The model layer provides a stable contract:

- `TestFile`
- `TestClass`
- `TestMethod`
- `Assertion`
- `MethodCall`
- `Variable`

Rules work against those types because rule authors should think in test
semantics, not libclang API calls. This also makes it possible for the simple
parser and clang parser to feed the same validation engine.

Without that model layer, every rule would need parser-specific logic and the
whole tool would become harder to extend.

## Why Makefile and flake.nix both exist

These files solve different problems.

The Makefile is the task runner. It encodes repeatable repository workflows:

- build the binary
- run tests
- generate coverage
- run parser matrices
- enforce parser gates

`flake.nix` is the environment description. It encodes the shell state required
to run those workflows reliably:

- Go toolchain
- libclang
- `CLANG_EXECUTABLE`
- `LIBCLANG_PATH`
- `CLANG_RESOURCE_DIR`
- cache directories

This split is useful because not every contributor uses Nix, but every
contributor still benefits from stable Make targets. Likewise, a Nix user may
want the shell without adopting every Make target.

## Why the libclang wrapper lives in the CLI tree

`clang_parser.go` is in `cmd/test-audit-validator/`, not `internal/analysis/`.

That is intentional.

`internal/analysis/` should stay focused on AST operations:

- creating and disposing of translation units
- visiting cursors
- extracting assertions, variables, and method calls
- simple control-flow signals

`clang_parser.go` solves a different problem:

- resolve `compile_commands.json`
- sanitize compile commands for parse-only use
- patch XCTest framework paths when needed
- normalize compiler argv for runtime compatibility
- combine AST extraction with source-text fallbacks into repository models

That logic is closer to command execution strategy than to generic AST analysis,
so it belongs near the CLI path.

## Practical extension points

If you want to extend the tool, these are the main seams:

### Add a new rule

- file: `internal/validation/`
- reason: rule logic should remain parser-agnostic

### Improve AST extraction

- file: `internal/analysis/engine.go`
- reason: cursor walking and extraction heuristics live there

### Improve compile-argument handling

- file: `cmd/test-audit-validator/clang_parser.go`
- reason: command-resolution quirks are isolated there

### Add a new output format

- file: `internal/report/`
- reason: rendering stays separate from validation

### Change execution policy

- files: `main.go`, `parser_selector.go`, `runner/`
- reason: mode selection, worker behavior, and exit codes belong in the control
  plane

## What this structure buys the project

The current split makes the tool easier to change without destabilizing it.

Examples:

- You can add a new validation rule without touching parser setup.
- You can improve libclang fallback logic without changing report generation.
- You can add JSON metadata without rewriting the runner.
- You can compare parser modes because selection and telemetry are explicit.

That is the real reason the Go tooling matters here. It is not just glue. It is
the part that makes the Objective-C analysis operationally useful.

## Related documents

- [../README.md](../README.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [LIBCLANG_AST_PARSING.md](LIBCLANG_AST_PARSING.md)
- [../LIBCLANG_SETUP.md](../LIBCLANG_SETUP.md)
