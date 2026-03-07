---
title: Test Audit Validator Documentation Expansion Plan
---

# Test Audit Validator Documentation Expansion Plan

**Generated:** 2026-03-07
**Scope:** `tools/test-audit-validator/`

## Goal

Expand the tool documentation so a contributor can answer four questions without
reading the full codebase:

1. What the Go tooling does end to end.
2. Why the tool is structured this way.
3. How the libclang-backed AST path works.
4. What libclang enables for Objective-C analysis in this repository.

## Current gaps

The current docs explain setup and usage, but they do not yet give a strong
mental model of the system:

- [`tools/test-audit-validator/README.md`](../../../tools/test-audit-validator/README.md) is command-focused and feature-focused, but light on architecture and rationale.
- [`tools/test-audit-validator/docs/ARCHITECTURE.md`](../../../tools/test-audit-validator/docs/ARCHITECTURE.md) describes the pipeline at a high level, but not why the Go packages are split the way they are.
- [`tools/test-audit-validator/LIBCLANG_SETUP.md`](../../../tools/test-audit-validator/LIBCLANG_SETUP.md) explains environment setup, but not why `CGO_*`, `LIBCLANG_PATH`, SDK headers, and `compile_commands.json` matter.
- [`tools/test-audit-validator/internal/analysis/README.md`](../../../tools/test-audit-validator/internal/analysis/README.md) documents the engine, but it is too isolated from the CLI, parser selector, and overall workflow.
- There is no dedicated document that explains libclang AST terminology in practical Objective-C terms.

## Documentation deliverables

### 1. Expand the top-level README

Update [`tools/test-audit-validator/README.md`](../../../tools/test-audit-validator/README.md) so it does more than list commands.

Add these sections:

- `How the tool works at a glance`
- `Why the tool is written in Go`
- `How parser selection works`
- `When to use simple, auto, or clang mode`
- `How compile_commands.json changes parsing quality`
- `How the runner, cache, and reports fit together`
- `Where to read deeper`

This page should stay contributor-oriented and operational. It should explain
the high-level flow without turning into package-by-package reference material.

### 2. Expand the architecture document into an actual subsystem map

Restructure [`tools/test-audit-validator/docs/ARCHITECTURE.md`](../../../tools/test-audit-validator/docs/ARCHITECTURE.md) into a narrative architecture page.

Add these subsections:

- `CLI entrypoint and command model`
- `Configuration precedence and validation`
- `Discovery pipeline`
- `Parser selection and fallback behavior`
- `libclang translation-unit pipeline`
- `Model building from AST + source text`
- `Validation engine and rule execution`
- `Runner concurrency, timeouts, and file limits`
- `Incremental caching`
- `Report generation and parser telemetry`
- `Build and workflow helpers`

For each subsection, explain both:

- what the package does
- why that responsibility lives there instead of elsewhere

### 3. Add a Go tooling deep-dive document

Create a new page:

- [`tools/test-audit-validator/docs/GO_TOOLING_DEEP_DIVE.md`](../../../tools/test-audit-validator/docs/GO_TOOLING_DEEP_DIVE.md)

Purpose:

- give a package-by-package explanation of the Go code
- explain design decisions, not just APIs
- make extension points obvious for future contributors

Recommended outline:

#### `What problem this tool solves`

- Why static analysis lives outside the Objective-C build.
- Why Go is a good fit for orchestration, filtering, reporting, and parallelism.
- Why the tool still needs libclang instead of regex alone.

#### `The end-to-end execution path`

- `cmd/test-audit-validator/main.go`
- config loading via `internal/config`
- file discovery
- parser selection
- runner execution
- validation rules
- report generation
- exit status / CI gating

#### `Why the CLI uses Cobra`

- command layout
- flags as contributor-facing interface
- stable automation surface for CI and Make targets

#### `Why configuration uses Viper`

- default values
- config file support
- `TAV_` environment variables
- CLI override precedence
- why this reduces friction in local and CI use

#### `Why the runner is separate from parsing`

- parser independence via `FileAnalyzer`
- parallel worker model
- per-file timeout handling
- cache integration
- easier testing of orchestration logic

#### `Why reports are a dedicated package`

- same core findings, multiple renderers
- markdown for humans
- JSON for gates and scripts
- HTML for exploratory review

#### `Why Makefile and flake.nix both exist`

- Makefile as task runner
- Nix shell as repeatable environment
- practical difference between build workflow and environment provisioning

### 4. Add a dedicated libclang AST parsing document

Create a new page:

- [`tools/test-audit-validator/docs/LIBCLANG_AST_PARSING.md`](../../../tools/test-audit-validator/docs/LIBCLANG_AST_PARSING.md)

This is the missing piece the current docs do not cover.

Recommended outline:

#### `What libclang gives you`

- `Index`
- `TranslationUnit`
- diagnostics
- source locations and ranges
- cursors and cursor kinds

Explain these in plain language first, then map them to actual code in:

- [`tools/test-audit-validator/internal/analysis/engine.go`](../../../tools/test-audit-validator/internal/analysis/engine.go)
- [`tools/test-audit-validator/cmd/test-audit-validator/clang_parser.go`](../../../tools/test-audit-validator/cmd/test-audit-validator/clang_parser.go)

#### `How parsing works in this tool`

- resolve parse arguments from `compile_commands.json` when available
- normalize compiler invocation when full argv is unsafe
- fall back to default Objective-C parse args
- create translation unit
- inspect diagnostics
- walk the AST
- build `models.TestFile`, `models.TestClass`, and `models.TestMethod`

#### `Why compile_commands.json matters`

- Objective-C parsing is only as good as the headers, defines, SDK path, and
  language flags you provide.
- libclang needs the same world view the real compiler had.
- this is why strict clang mode can fail while simple mode still works.

#### `How Objective-C shows up in the AST`

Include a table that maps common Objective-C constructs to cursor kinds and what
the tool does with them:

| Objective-C construct | Clang cursor kind | Current use in tool |
| --- | --- | --- |
| `@implementation` | `ObjCImplementationDecl` | Identify test classes |
| `-testSomething` | `ObjCInstanceMethodDecl` | Identify XCTest methods |
| `XCTAssert...` call | `CallExpr` | Extract assertions |
| `[object method]` | `ObjCMessageExpr` | Extract method calls |
| `if` / `switch` | `IfStmt` / `SwitchStmt` | Track conditional assertions |
| categories | `ObjCCategoryImplDecl` | Preserve test methods defined in categories |

#### `What you can do with libclang for Objective-C`

Add a contributor-facing section focused on capability, not implementation
detail. Cover at least:

- class and method discovery that respects actual syntax
- assertion extraction without brittle regex
- selector and receiver extraction from message sends
- better handling of categories, protocols, blocks, and ARC-era syntax
- line-number and source-location aware findings
- future checks such as registration audits, fixture usage validation, control
  flow improvements, and richer method behavior analysis

#### `What libclang does not solve automatically`

- parser accuracy still depends on correct compiler arguments
- macros can obscure intent
- semantic analysis is not full symbolic execution
- source text extraction is still needed for comments and some fallback cases
- cross-file or interprocedural reasoning remains limited

### 5. Upgrade the libclang setup guide from setup-only to setup-plus-explanation

Extend [`tools/test-audit-validator/LIBCLANG_SETUP.md`](../../../tools/test-audit-validator/LIBCLANG_SETUP.md) with short explanatory subsections:

- `Why CGO is required`
- `Why Xcode headers and libraries must match`
- `Why the Makefile exports CGO_CFLAGS and CGO_LDFLAGS`
- `Why the Nix shell sets CLANG_EXECUTABLE and CLANG_RESOURCE_DIR`
- `Why parse failures often mean argument mismatch, not broken code`

This page should remain practical, but it should stop being only a checklist.

## Source-to-section mapping

Use the code itself as the source of truth for each new section:

| Topic | Primary source files |
| --- | --- |
| CLI and flags | `cmd/test-audit-validator/main.go` |
| parser selection | `cmd/test-audit-validator/parser_selector.go` |
| libclang command resolution | `cmd/test-audit-validator/clang_parser.go` |
| AST engine concepts | `internal/analysis/engine.go` |
| config precedence | `internal/config/config.go` |
| concurrency and timeouts | `internal/runner/runner.go` |
| incremental caching | `internal/cache/*.go` |
| findings and reports | `internal/report/*.go`, `internal/validation/*.go` |
| local workflow and env wiring | `Makefile`, `flake.nix` |

## Proposed writing order

### Phase 1: reader-facing orientation

1. Expand the top-level README.
2. Expand `docs/ARCHITECTURE.md`.
3. Add cross-links between those two pages.

### Phase 2: deep technical pages

1. Add `GO_TOOLING_DEEP_DIVE.md`.
2. Add `LIBCLANG_AST_PARSING.md`.
3. Link both from the README and architecture page.

### Phase 3: setup and maintenance polish

1. Extend `LIBCLANG_SETUP.md`.
2. Add a short `Further reading` section to `internal/analysis/README.md`.
3. Ensure page titles and section names follow the docs style guide.

## Recommended diagrams and tables

Add a small number of high-signal visuals:

- `CLI -> config -> discovery -> parser selector -> runner -> validation -> report`
- `compile_commands.json present?` decision tree for parser argument resolution
- `Objective-C construct -> clang cursor kind -> extracted model data` table
- parser mode comparison table: `simple` vs `auto` vs `clang`

## Acceptance criteria

This work is complete when a new contributor can read the docs and answer these
questions correctly:

- Why does the tool use Go for orchestration but libclang for parsing?
- What is the difference between `simple`, `auto`, and `clang` parser modes?
- Why can `compile_commands.json` change AST quality or failure rate?
- How does an Objective-C test method become a `models.TestMethod` and then a
  set of findings?
- What kinds of Objective-C analysis are practical with libclang in this tool?
- What are the real limits of the current AST-based approach?

## Non-goals

This documentation expansion should not:

- duplicate every exported symbol as API reference
- promise interprocedural or semantic analysis the tool does not implement
- over-explain generic Go basics that are not specific to this tool
- turn the setup guide into a compiler theory document

## Immediate next step

Start with the README and architecture page. Those two pages should establish
the core mental model before adding the deeper Go tooling and libclang AST
documents.
