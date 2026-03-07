# Static analysis engine

## Role in the system

`internal/analysis` is the AST-focused package behind the clang-backed parser.
It does not own CLI behavior, parser-mode policy, or report generation. Its job
is narrower:

- create and dispose libclang indexes and translation units
- walk Objective-C AST cursors
- extract assertions, variables, and method calls
- apply simple reachability heuristics to assertions

That boundary matters because AST extraction is hard enough on its own. Keeping
environment setup, parser fallback policy, and report logic outside this package
makes the analysis code easier to reason about.

## What the engine does

The main entrypoint is `StaticAnalysisEngine`.

```go
engine := analysis.NewStaticAnalysisEngine()
defer engine.Close()

tu, err := engine.ParseFile("MyTests.m")
if err != nil {
    // A valid translation unit may still be returned for partial analysis.
}
defer tu.Dispose()
```

Core responsibilities:

- configure clang for Objective-C parsing
- create translation units with `KeepGoing` enabled
- surface parse diagnostics
- expose helper traversal APIs
- extract test-relevant syntax from method bodies

## Current extraction capabilities

### Assertions

`ExtractAssertions()` walks a method subtree looking for XCTest-style call
expressions and records:

- assertion type
- arguments
- line number
- whether the assertion is nested under `if` or `switch`

The engine then runs `AnalyzeControlFlow()` to mark assertions that appear in
obviously unreachable regions, such as top-level code after `return`.

### Variables

`ExtractVariables()` finds `VarDecl` cursors and records:

- variable name
- type spelling
- initial value when a simple textual representation can be recovered
- line number

### Method calls

`ExtractMethodCalls()` walks `ObjCMessageExpr` cursors and records:

- receiver
- selector
- arguments
- line number

This is one of the main reasons the AST path exists. Objective-C message sends
are much harder to recover reliably with regex alone.

## Error handling model

The engine is designed for best-effort analysis.

- empty paths and invalid extensions fail early
- parse failures are reported from diagnostics
- a translation unit may still be returned even when diagnostics contain errors
- callers decide whether a parse error should trigger fallback or process
  failure

That is why strict/non-strict behavior is not implemented here. The engine
reports parse reality. Higher layers decide policy.

## Platform behavior

On macOS, the engine's default parse arguments assume Xcode SDK paths when they
exist. On Linux, clang usually falls back to system include paths.

For real repository analysis, the more important source of truth is usually
`compile_commands.json`, which is resolved in the higher-level clang parser.

## Current limitations

The engine is useful, but it is intentionally not pretending to be a full
semantic verifier.

- parser quality still depends on correct compiler arguments
- some literal/text recovery uses simplified placeholders
- reachability analysis is heuristic, not full control-flow analysis
- comments and exact source snippets are still better recovered from source text
- cross-file reasoning is outside this package's scope

## When to change this package

Change `internal/analysis` when you need to improve AST extraction itself:

- support a new cursor pattern
- improve assertion or method-call extraction
- improve reachability heuristics
- add richer variable or selector recovery

Do not change this package just to alter:

- parser mode policy
- compile-command resolution
- configuration behavior
- report formatting

Those concerns live elsewhere.

## Related documents

- [../../README.md](../../README.md)
- [../../docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)
- [../../docs/GO_TOOLING_DEEP_DIVE.md](../../docs/GO_TOOLING_DEEP_DIVE.md)
- [../../docs/LIBCLANG_AST_PARSING.md](../../docs/LIBCLANG_AST_PARSING.md)
- [../../LIBCLANG_SETUP.md](../../LIBCLANG_SETUP.md)
