# Static Analysis Engine

The Static Analysis Engine provides Objective-C AST (Abstract Syntax Tree) parsing capabilities using libclang. It is the foundation for extracting assertions, variables, method calls, and control flow information from test code.

## Overview

The engine uses the official Clang library (libclang) to parse Objective-C source files and provide access to their AST. This enables robust analysis of test code structure without relying on fragile regex-based parsing.

## Key Components

### StaticAnalysisEngine

The main engine struct that manages the clang index and provides parsing capabilities.

```go
engine := analysis.NewStaticAnalysisEngine()
defer engine.Close()

tu, err := engine.ParseFile("path/to/test.m")
if err != nil {
    // Handle error - note that TU may still be valid for partial analysis
}
defer tu.Dispose()
```

### Features

1. **Objective-C with ARC Support**: Configured to parse modern Objective-C code with Automatic Reference Counting
2. **Blocks Support**: Handles Objective-C blocks syntax
3. **Graceful Error Handling**: Continues parsing even with syntax errors, enabling partial analysis
4. **Fallback Strategies**: Multiple parsing strategies for maximum compatibility
5. **Resource Management**: Proper cleanup of clang resources

## Usage Examples

### Basic Parsing

```go
engine := analysis.NewStaticAnalysisEngine()
defer engine.Close()

tu, err := engine.ParseFile("MyTests.m")
if err != nil {
    log.Printf("Parse error: %v", err)
    // TU may still be usable for partial analysis
}
defer tu.Dispose()

cursor := engine.GetCursor(tu)
// Use cursor for AST traversal
```

### Visiting AST Nodes

```go
cursor := engine.GetCursor(tu)

engine.VisitChildren(cursor, func(cursor, parent clang.Cursor) bool {
    if cursor.Kind() == clang.Cursor_ObjCInterfaceDecl {
        fmt.Printf("Found class: %s\n", cursor.Spelling())
    }
    return true // Continue visiting
})
```

### Fallback Parsing

```go
// Try standard parsing first, fall back to lenient mode if needed
tu, err := engine.ParseFileWithFallback("problematic.m")
if err != nil {
    log.Fatalf("Failed even with fallback: %v", err)
}
defer tu.Dispose()
```

## Clang Arguments

The engine configures clang with the following arguments for Objective-C parsing:

- `-x objective-c`: Treat input as Objective-C
- `-fobjc-arc`: Enable Automatic Reference Counting
- `-fblocks`: Enable blocks extension
- `-fmodules`: Enable modules
- `-isysroot <path>`: System root for headers (macOS)
- `-Wno-everything`: Suppress warnings for cleaner output

## Error Handling

The engine implements graceful error handling:

1. **Validation Errors**: Empty paths and invalid extensions are caught early
2. **Parse Errors**: Syntax errors are reported but don't prevent TU creation
3. **Fallback Strategy**: If standard parsing fails, tries with more lenient options
4. **Partial Analysis**: Even with errors, the TU may be usable for partial analysis

## Platform Support

### macOS

Uses Xcode SDK for system headers. The engine automatically configures the SDK path.

### Linux

Uses system default headers. The SDK path is empty and clang uses standard system paths.

## Testing

The engine includes comprehensive unit tests covering:

- Engine creation and cleanup
- File path validation
- Extension validation
- Valid Objective-C parsing
- Header file parsing
- Syntax error handling
- ARC code parsing
- Blocks parsing
- Fallback strategies
- Cursor operations
- AST traversal

Run tests with:

```bash
go test ./internal/analysis
```

## Future Enhancements

The following features will be added in subsequent tasks:

- **Assertion Extraction** (Task 3.2): Extract XCTest assertion calls
- **Variable Extraction** (Task 3.3): Extract variable declarations and assignments
- **Method Call Extraction** (Task 3.3): Extract method invocations
- **Control Flow Analysis** (Task 3.4): Build control flow graphs

## Dependencies

- `github.com/go-clang/clang-v14/clang`: Official Go bindings for libclang

## Related Documentation

- [libclang Documentation](https://clang.llvm.org/doxygen/group__CINDEX.html)
- [Clang AST Introduction](https://clang.llvm.org/docs/IntroductionToTheClangAST.html)
- [Test Audit Validation Design](../../../.kiro/specs/test-audit-validation/design.md)
