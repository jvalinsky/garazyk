# Architecture

## Overview

`test-audit-validator` is split into a thin CLI layer, a parsing layer, a
validation layer, and a rendering layer.

```text
config + flags
  -> file discovery
  -> parser selector
  -> test model construction
  -> validation rules
  -> filtering
  -> report generation
```

This split exists for one reason: the tool needs two very different kinds of
logic.

- It needs language-aware Objective-C parsing, which comes from libclang.
- It needs reliable orchestration, filtering, caching, concurrency, and output
  generation, which are easier to express in Go.

The result is a Go control plane wrapped around an Objective-C-aware AST path.

## Package map

```text
cmd/test-audit-validator/
  main.go             CLI, config overlay, discovery, report emission
  parser_selector.go  simple/auto/clang behavior and telemetry
  clang_parser.go     compile_commands-aware libclang parsing

internal/
  analysis/           libclang translation-unit helpers and AST extraction
  cache/              SQLite-backed incremental cache
  config/             defaults, config loading, validation, finding filters
  discovery/          richer discovery helpers and registration checks
  models/             TestFile/TestClass/TestMethod/Assertion data model
  report/             markdown, JSON, HTML renderers
  runner/             worker-pool execution, timeouts, progress
  validation/         rule engine and finding definitions

tests/
  integration/        end-to-end CLI integration tests
```

## CLI entrypoint and command model

The CLI lives in `cmd/test-audit-validator/main.go`. It currently exposes two
commands:

- `analyze`
- `version`

That command model is intentionally small. The project treats the CLI as a
stable automation surface for local scripts, CI, and the repository Makefile.
Keeping the command surface tight makes it easier to add flags without creating
multiple overlapping workflows.

The CLI owns:

- command and flag definitions
- configuration overlay rules
- parser-mode selection
- runner setup
- report generation choice
- exit behavior for strict clang and `--fail-on`

The CLI does not own AST walking or validation details. Those are delegated to
specialized packages so the entrypoint stays readable.

## Configuration precedence and validation

`internal/config` is responsible for turning defaults, config files,
environment variables, and CLI values into one validated `Config`.

Current precedence is:

1. CLI flags
2. `TAV_` environment variables
3. `.test_audit_config.json`
4. built-in defaults

This responsibility lives in one package because configuration has to stay
consistent across local use, CI use, and `make` targets. If validation rules,
the runner, or the CLI each interpreted config differently, the same analysis
would behave differently depending on how it was launched.

The config package also owns finding filters. That keeps domain/severity/class
selection out of the validation engine, which should only answer "what did we
find?" rather than "what should we hide?"

## Discovery pipeline

The current default CLI path uses `discoverTestFiles()` in `main.go`. That
function does a simple recursive walk and keeps `.m` files whose names look like
test files.

This is deliberately lightweight:

- it is fast
- it has no libclang dependency
- it keeps discovery available even when clang parsing is unavailable

There is also a richer `internal/discovery` package that can discover test
files, classes, methods, and `test_main.m` registration information. That
package exists because those capabilities are useful, but they are not yet the
default hot path for the CLI.

This separation matters:

- simple file collection is an execution concern
- class/method/registration discovery is a deeper analysis concern

The CLI only needs the first one to start work.

## Parser selection and fallback behavior

`parser_selector.go` exists so parser choice does not leak into the runner or
the validation engine.

The selector exposes one `analyze(filePath)` function and hides the mode logic:

- `simple`: always use the regex/source parser
- `clang`: always use libclang and fail on any parse/setup problem
- `auto`: try libclang first, then fall back per file

The selector also records parser telemetry:

- clang attempted count
- clang success count
- clang fallback count

That telemetry is surfaced in JSON metadata and is critical when you are using
the tool as a parser-quality gate rather than only a findings generator.

Keeping this logic in one place avoids two common problems:

- parser fallback scattered across unrelated packages
- inconsistent success/failure accounting between modes

## libclang translation-unit pipeline

The clang-backed path lives in `clang_parser.go` and `internal/analysis`.

The flow is:

1. Resolve parser arguments.
2. Prefer `compile_commands.json` when available.
3. Sanitize compile commands for parse-only use.
4. Add XCTest framework arguments when the compile database does not provide
   them.
5. Add runtime arguments such as module cache path and resource directory.
6. Normalize full argv when the compiler executable and libclang runtime are
   from incompatible worlds.
7. Parse a translation unit.
8. Retry with parse-only arguments on specific AST read failures.

This logic is separate from the AST extraction code because command resolution
is not the same problem as tree walking. It deals with SDK paths, frameworks,
compiler executables, and clang runtime quirks. The analysis package should not
need to know about any of that.

See [LIBCLANG_AST_PARSING.md](LIBCLANG_AST_PARSING.md) for the deep dive.

## Model building from AST and source text

The clang parser does not hand raw cursors to the validation engine. Instead it
builds stable Go models:

- `models.TestFile`
- `models.TestClass`
- `models.TestMethod`
- `models.Assertion`
- `models.MethodCall`

This conversion layer exists because validation rules should reason about test
behavior, not about libclang cursor APIs.

The model builder intentionally mixes AST data and source-text data:

- AST traversal identifies implementations, methods, assertions, and message
  sends.
- raw comment text and source slices recover human-facing context that AST nodes
  do not preserve well.
- source scanning acts as a fallback when AST extraction finds no assertions in
  a method that clearly contains `XCTAssert`.

That hybrid approach is not accidental. Objective-C analysis is more reliable
when syntax structure comes from the AST, but comments and exact source slices
are often easier to recover from the file itself.

## Validation engine and rule execution

`internal/validation` owns findings, severity levels, rule definitions, and the
rule engine.

Its core interface is intentionally small:

```go
type ValidationRule interface {
    Validate(ctx ValidationContext) []Finding
    Severity() Severity
    Description() string
    Name() string
}
```

Rules receive parsed models, not parser internals. That design keeps rules
focused on questions like:

- Does this test name match its assertions?
- Does this security test reject invalid input?
- Does this async test manage expectations correctly?

The engine runs rules at file, class, and method levels. That lets structural
checks and fine-grained assertion checks coexist without duplicating traversal
logic in every rule.

## Runner concurrency, timeouts, and file limits

`internal/runner` is the execution coordinator. It owns:

- worker count selection
- file-size checks
- per-file timeout handling
- progress reporting
- optional cache lookup/write-through

The runner accepts a `FileAnalyzer` function rather than embedding parser logic
directly:

```go
type FileAnalyzer func(filePath string) (*models.TestFile, error)
```

That boundary exists so the runner can stay parser-agnostic. The same worker
pool can process the regex parser, the clang parser, or any future parser
variant without changing the concurrency code.

This separation also makes the runner easier to test in isolation.

## Incremental caching

`internal/cache` stores findings keyed by file content hash in SQLite.

This package exists because caching is an operational concern, not a validation
concern:

- the parser should not know about cache persistence
- rules should not know about cache invalidation
- the runner should only ask whether results are reusable

The cache layer hashes the current file, checks for a matching stored result,
and either returns cached findings or lets the runner proceed with analysis.

The choice of SQLite keeps the cache local, deterministic, and easy to inspect.

## Report generation and parser telemetry

`internal/report` renders one logical report into multiple output formats:

- markdown for humans
- JSON for CI and scripts
- HTML for exploratory review

This responsibility lives outside the CLI because output shape should be stable
even if command wiring changes. The CLI chooses a generator. The report package
defines how the report is rendered.

The report metadata includes more than a timestamp. It can include:

- parser mode
- clang attempt/success/fallback counts
- configuration snapshot values such as worker count and compile-commands path
- file-level parse/setup errors in JSON mode

One useful implementation detail: summary totals are counted in a second pass
using the simple parser. That keeps top-level counts available even when strict
clang mode fails on some files.

## Build and workflow helpers

Two files support local workflows:

- `Makefile`
- `flake.nix`

They solve different problems.

The Makefile is the task runner. It standardizes commands such as:

- `make build`
- `make test`
- `make audit-matrix-json`
- `make audit-gate`

The Nix flake is the environment definition. It standardizes:

- Go toolchain availability
- libclang availability
- `CLANG_EXECUTABLE`
- `LIBCLANG_PATH`
- `CLANG_RESOURCE_DIR`
- cache directories for Go and clang modules

Keeping those separate is useful because a developer may want the Make targets
without Nix, or the Nix shell without the Make-based workflow.

## Why Go and libclang are split this way

This architecture is driven by failure modes.

If the entire tool were regex-based, it would be fast but brittle around
Objective-C syntax, categories, blocks, ARC, and source locations.

If the entire tool were a thin wrapper around libclang, it would be harder to:

- run robustly in CI
- provide layered configuration
- manage concurrency and caching cleanly
- emit several report formats from one model

The current split keeps the expensive, language-aware work narrow and keeps the
operational logic explicit.

## Extension points

The main extension seams are:

- add new findings by implementing `ValidationRule`
- add new output formats in `internal/report`
- strengthen AST extraction in `internal/analysis`
- improve compile-argument handling in `clang_parser.go`
- eventually promote richer `internal/discovery` helpers into the CLI hot path

When you extend the tool, keep the existing boundaries intact. The package
split is doing real work, not only organizing files.

## Related documents

- [../README.md](../README.md)
- [GO_TOOLING_DEEP_DIVE.md](GO_TOOLING_DEEP_DIVE.md)
- [LIBCLANG_AST_PARSING.md](LIBCLANG_AST_PARSING.md)
- [../LIBCLANG_SETUP.md](../LIBCLANG_SETUP.md)
- [../internal/analysis/README.md](../internal/analysis/README.md)
