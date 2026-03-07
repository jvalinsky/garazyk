# libclang AST parsing

## Why this document exists

The repository already had setup instructions for libclang, but it did not have
one place that explained what libclang is doing for the tool and what practical
Objective-C analysis it unlocks.

This page fills that gap.

## What libclang gives you

libclang is the C interface to Clang's parsing and indexing machinery. In this
tool, it provides five core things:

### `Index`

An `Index` is the top-level clang context used to create translation units. The
analysis engine creates one in `NewStaticAnalysisEngine()` and reuses it for the
life of that engine instance.

Why it matters:

- it is the starting point for all parsing work
- it centralizes clang-side state
- it gives the tool a clean lifetime boundary for setup and disposal

### `TranslationUnit`

A `TranslationUnit` is clang's parsed representation of one source file plus
the headers, framework context, and compiler arguments needed to understand it.

Why it matters:

- the AST is attached to the translation unit
- diagnostics are attached to the translation unit
- source locations and extents are resolved through the translation unit

The tool parses translation units in
[`internal/analysis/engine.go`](../internal/analysis/engine.go) and feeds them
through the model builder in
[`cmd/test-audit-validator/clang_parser.go`](../cmd/test-audit-validator/clang_parser.go).

### diagnostics

Diagnostics are parse errors, fatal errors, and other clang messages emitted
during translation-unit construction.

Why they matter:

- they explain why strict clang mode failed
- they allow partial analysis when clang produced a usable translation unit
- they help distinguish real syntax problems from environment problems

The engine currently treats error and fatal diagnostics as parse failures while
still returning a valid translation unit when clang made one available.

### source locations and ranges

Every meaningful cursor can point back to file, line, column, and source extent
information.

Why they matter:

- findings need useful line numbers
- comment and source extraction need cursor extents
- file ownership checks need to distinguish the current `.m` file from imported
  headers

### cursors and cursor kinds

Cursors are libclang's AST nodes. Cursor kinds describe what a node represents:

- interface declaration
- implementation declaration
- Objective-C method
- function call
- Objective-C message send
- `if` statement
- `switch` statement

Why they matter:

- the tool identifies test classes from Objective-C implementation cursors
- it identifies test methods from Objective-C method cursors
- it finds `XCTAssert...` calls from call-expression cursors
- it finds Objective-C message sends from `ObjCMessageExpr` cursors

## How parsing works in this tool

The clang-backed path is more than "parse file with libclang." It is a small
pipeline that tries to recreate enough of the real compile environment for AST
analysis to work.

### Step 1: resolve parser arguments

The clang parser first tries to load compile commands from
`compile_commands.json`.

If a matching entry exists for a file, the tool:

1. loads the recorded compiler argv
2. strips flags that do not make sense for AST-only parsing
3. ensures XCTest framework paths are present when needed
4. adds runtime support flags such as resource directory and module cache path

If no compile database is available, the tool falls back to a default Objective-C
argument set plus some project-relative include guesses.

### Step 2: normalize full argv when needed

Some environments mix compiler executables and libclang runtimes from different
origins. One example is using Xcode's compiler with a Nix-provided libclang.

When that mismatch is detected, the tool swaps argv[0] to a compatible clang
executable before asking libclang to parse the full command line.

Why this exists:

- libclang can fail with `ASTReadError` when the compiler/runtime combination is
  inconsistent
- the fix is often not "change the source file"
- the fix is "make the parsing executable and runtime agree"

### Step 3: create a translation unit

The engine calls `ParseTranslationUnit2` or `ParseTranslationUnit2FullArgv`
depending on whether it is using full compiler argv or parse-only args.

Important parse options:

- `DetailedPreprocessingRecord`
- `KeepGoing`

The tool does not skip function bodies because it needs method bodies for:

- assertion extraction
- method-call extraction
- control-flow checks

### Step 4: inspect diagnostics

After parsing, the engine inspects translation-unit diagnostics.

This is important because a valid translation unit does not always mean a clean
parse. The tool keeps partial analysis possible, but it still reports parse
errors so strict clang mode can fail correctly.

### Step 5: walk the AST

Once the translation unit exists, `clang_parser.go` walks the root cursor and
extracts repository-specific meaning:

- which Objective-C declarations belong to the current file
- which implementations look like test classes
- which methods are XCTest-style `test...` methods
- which calls are XCTest assertions
- which message sends are interesting method invocations

### Step 6: build `models.*` types

The AST layer does not talk directly to validation rules. It turns the parse
tree into Go models:

- `TestFile`
- `TestClass`
- `TestMethod`
- `Assertion`
- `MethodCall`

That conversion keeps libclang APIs out of the rule layer.

### Step 7: fall back to source text where needed

The clang-backed path still uses source text for some jobs:

- extracting inline comments
- recovering method source slices
- filling in assertions when AST extraction returns nothing but the source
  clearly contains `XCTAssert`

This is not a weakness in the design. It is a pragmatic combination of AST
structure plus text recovery.

## Why `compile_commands.json` matters

Objective-C parsing is unusually sensitive to build context. A source file is
not fully meaningful without the same flags the compiler had.

`compile_commands.json` matters because it carries:

- include directories
- framework search paths
- preprocessor defines
- SDK choice
- language flags

Without that information, libclang may:

- fail to find headers
- fail to resolve XCTest
- parse the file under the wrong language assumptions
- emit many diagnostics that are really environment problems

That is why the tool prefers compile commands when they are available and only
uses fallback args as a best-effort path.

## How Objective-C shows up in the AST

The table below maps common Objective-C constructs to the cursor kinds this tool
cares about.

| Objective-C construct | Clang cursor kind | Current use in tool |
| --- | --- | --- |
| `@interface MyTests : XCTestCase` | `ObjCInterfaceDecl` | Secondary signal for class discovery |
| `@implementation MyTests` | `ObjCImplementationDecl` | Primary signal for test class discovery |
| `@implementation MyTests (Category)` | `ObjCCategoryImplDecl` | Preserve category-defined test methods |
| `- (void)testExample` | `ObjCInstanceMethodDecl` | Identify XCTest methods |
| `+ (void)testFactory` | `ObjCClassMethodDecl` | Support class-method discovery when present |
| `XCTAssertEqual(...)` | `CallExpr` | Assertion extraction |
| `[parser parse:input]` | `ObjCMessageExpr` | Method-call extraction |
| `if (...) { ... }` | `IfStmt` | Conditional assertion tracking |
| `switch (...) { ... }` | `SwitchStmt` | Conditional assertion tracking |
| local variable declaration | `VarDecl` | Variable extraction |
| `return` | `ReturnStmt` | Reachability heuristics |

## A practical Objective-C example

Take this simplified method:

```objc
- (void)testTokenParsing {
    NSString *token = [parser parse:input];
    if (token != nil) {
        XCTAssertEqualObjects(token, @"abc");
    }
}
```

The tool can map it roughly like this:

- `ObjCInstanceMethodDecl`
  -> `testTokenParsing`
- `VarDecl`
  -> local variable `token`
- `ObjCMessageExpr`
  -> receiver `parser`, selector `parse:`
- `IfStmt`
  -> conditional depth increases
- `CallExpr`
  -> `XCTAssertEqualObjects`

That information becomes a `TestMethod` with method calls and assertions, and
the assertion is marked as conditional.

## What you can do with libclang for Objective-C

In this tool, libclang makes several useful kinds of Objective-C analysis
practical.

### Accurate class and method discovery

The tool can discover test classes and methods from actual Objective-C syntax
instead of guessing from line-oriented regex only.

That matters for:

- categories
- class methods
- methods whose formatting is unusual
- files containing multiple implementations

### Assertion extraction without brittle regex

The AST path can detect real call expressions and inspect their location and
arguments. That is more robust than searching for `XCTAssert` strings alone.

### Selector and receiver extraction from message sends

Objective-C method calls are message expressions, not ordinary function calls.
libclang lets the tool walk those message-send nodes and recover:

- receiver
- selector
- arguments

That is useful for rules that care about what behavior a test is actually
invoking.

### Better handling of ARC-era Objective-C syntax

The engine is configured for:

- Objective-C mode
- ARC
- blocks
- modules

That makes it more resilient around modern Objective-C constructs than a
regex-only path.

### Line-aware findings

Source locations make findings more actionable. Instead of only naming a test
method, the tool can point at the assertion or declaration line involved.

### Future analysis opportunities

The current implementation already extracts enough structure to support richer
checks later, such as:

- registration audits using `test_main.m`
- stronger fixture-usage checks
- better unreachable-code detection
- more detailed method-behavior summaries
- class inheritance and helper/test classification improvements

## What libclang does not solve automatically

libclang is powerful, but it does not remove the hard parts of static analysis.

### It still depends on correct arguments

If the SDK path, framework path, or defines are wrong, the AST will be degraded
or unavailable.

### Macros still obscure intent

Clang can parse macro expansions, but understanding what a macro means for test
semantics is still a tool-level problem.

### AST is not symbolic execution

The tool can see syntax shape and some local control-flow signals. It does not
prove what code paths are feasible in all cases.

### Source text still matters

Comments, inline notes, and some exact textual recoveries are easier to obtain
from the file itself than from cursor metadata alone.

### Cross-file reasoning is still limited

The tool is mainly a per-file analyzer. It can parse a translation unit with
headers, but it does not perform deep interprocedural reasoning across the
entire codebase.

## When to prefer each parser mode

| Goal | Recommended mode |
| --- | --- |
| fast baseline scan | `simple` |
| everyday local work | `auto` |
| parser correctness gate | `clang` |
| investigate environment/setup issues | `clang` with JSON output and explicit `--compile-commands-dir` |

## Related code paths

- [`../cmd/test-audit-validator/clang_parser.go`](../cmd/test-audit-validator/clang_parser.go)
- [`../internal/analysis/engine.go`](../internal/analysis/engine.go)
- [`../cmd/test-audit-validator/parser_selector.go`](../cmd/test-audit-validator/parser_selector.go)
- [`../LIBCLANG_SETUP.md`](../LIBCLANG_SETUP.md)
- [`GO_TOOLING_DEEP_DIVE.md`](GO_TOOLING_DEEP_DIVE.md)
