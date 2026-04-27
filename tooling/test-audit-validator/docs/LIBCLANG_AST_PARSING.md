# libclang AST Analysis

`test-audit-validator` uses libclang to extract the AST (Abstract Syntax Tree) from Objective-C test files. This document details the specific libclang constructs used and the parsing pipeline.

## Core libclang Constructs

### Index and Translation Unit
An `Index` provides the context for creating `TranslationUnit` objects. A `TranslationUnit` contains the parsed representation of a source file, including headers and framework context. The tool uses these to resolve source locations, extents, and diagnostic messages.

### Diagnostics
The tool monitors clang diagnostics during translation unit construction to distinguish between real syntax errors and environment configuration problems (e.g., missing SDKs).

### Cursors and Cursor Kinds
Cursors represent AST nodes. The tool uses specific cursor kinds to identify test structures:
- `ObjCImplementationDecl`: Identifies test classes.
- `ObjCInstanceMethodDecl`: Identifies XCTest methods.
- `CallExpr`: Identifies `XCTAssert` and other function calls.
- `ObjCMessageExpr`: Identifies Objective-C message sends (selectors and receivers).
- `IfStmt` / `SwitchStmt`: Tracks conditional logic surrounding assertions.

## Parsing Pipeline

### 1. Argument Resolution
The parser attempts to load `compile_commands.json` for each file. If found, it:
1. Loads the compiler arguments.
2. Strips flags irrelevant to AST analysis.
3. Injects XCTest framework paths and runtime support flags.

If missing, the tool uses default Objective-C arguments and include guesses.

### 2. Normalization
The tool can normalize the compiler path (`argv[0]`) to ensure compatibility between the compiler environment and the libclang runtime, preventing `ASTReadError` failures.

### 3. Translation Unit Construction
The engine parses the file with `DetailedPreprocessingRecord` enabled. It retains function bodies to extract assertions and method calls.

### 4. Model Conversion
The AST walker converts cursors into Go models (`TestFile`, `TestClass`, `TestMethod`). This isolates libclang-specific logic from the validation engine.

### 5. Source Text Fallbacks
The tool uses source text scanning for:
- Extracting inline comments.
- Recovering exact method source slices.
- Verifying `XCTAssert` calls that the AST extraction might miss due to macro expansion.

## Mapping Objective-C to the AST

| Construct | Clang Cursor Kind |
| --- | --- |
| `@implementation` | `ObjCImplementationDecl` |
| `- (void)test...` | `ObjCInstanceMethodDecl` |
| `XCTAssert...` | `CallExpr` |
| `[receiver selector]` | `ObjCMessageExpr` |
| `if (...)` | `IfStmt` |
| `return` | `ReturnStmt` |

## Analysis Capabilities

- **Accurate Discovery**: Detects test methods in categories and files with multiple implementations.
- **Robust Extraction**: Identifies assertions and message sends without relying on line-based regex.
- **Selector Awareness**: Resolves selectors and receivers for message sends to identify tested behaviors.
- **Location Precision**: Points findings to specific lines and columns.
