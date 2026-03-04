# Models Package

This package defines the core data structures for representing parsed Objective-C test code in the Test Audit Validation System.

## Overview

The models package provides the foundation for all subsequent analysis and validation. These structures are populated by the Static Analysis Engine during AST parsing and consumed by the Validation Engine to detect test quality issues.

## Data Structures

### TestFile

Represents a test file containing test classes.

```go
type TestFile struct {
    Path    string       // Path to the test file
    Classes []TestClass  // Test classes defined in this file
    Imports []string     // Import statements in the file
}
```

**Example:**
```go
testFile := TestFile{
    Path:    "ATProtoPDS/Tests/Auth/OAuthTests.m",
    Classes: []TestClass{...},
    Imports: []string{"<XCTest/XCTest.h>", "\"OAuth.h\""},
}
```

### TestClass

Represents a test class (typically inheriting from XCTestCase).

```go
type TestClass struct {
    Name      string       // Name of the test class
    FilePath  string       // Path to the file containing this class
    Methods   []TestMethod // Test methods in this class
    BaseClass *string      // Base class name (e.g., "XCTestCase"), nil if none
    IsHelper  bool         // True for test utility classes, false for actual test classes
}
```

**Example:**
```go
baseClass := "XCTestCase"
testClass := TestClass{
    Name:      "OAuthTests",
    FilePath:  "ATProtoPDS/Tests/Auth/OAuthTests.m",
    Methods:   []TestMethod{...},
    BaseClass: &baseClass,
    IsHelper:  false,
}
```

### TestMethod

Represents a single test method within a test class.

```go
type TestMethod struct {
    Name       string      // Name of the test method (e.g., "testOAuthTokenValidation")
    ClassName  string      // Name of the class containing this method
    LineNumber int         // Line number where the method is defined
    SourceCode string      // Full source code of the method
    Assertions []Assertion // Assertions found in this method
    Comments   []string    // Comments and documentation for this method
}
```

**Example:**
```go
testMethod := TestMethod{
    Name:       "testOAuthTokenValidation",
    ClassName:  "OAuthTests",
    LineNumber: 42,
    SourceCode: "- (void)testOAuthTokenValidation { ... }",
    Assertions: []Assertion{...},
    Comments:   []string{"// Test OAuth token validation"},
}
```

### Assertion

Represents an XCTest assertion call in test code.

```go
type Assertion struct {
    Type          string   // Assertion type (e.g., "XCTAssertEqual", "XCTAssertTrue")
    Arguments     []string // Raw argument expressions passed to the assertion
    LineNumber    int      // Line number where the assertion appears
    IsConditional bool     // True if assertion is inside an if/else block
    IsReachable   bool     // False if assertion is in unreachable code path
}
```

**Supported Assertion Types:**
- `XCTAssertEqual` - value equality
- `XCTAssertTrue` - boolean true
- `XCTAssertFalse` - boolean false
- `XCTAssertNil` - null check
- `XCTAssertNotNil` - non-null check
- `XCTAssertThrows` - exception expected
- `XCTAssertNoThrow` - no exception expected
- `XCTAssertEqualObjects` - object equality
- `XCTAssertGreaterThan` - comparison
- `XCTFail` - explicit failure

**Example:**
```go
assertion := Assertion{
    Type:          "XCTAssertEqual",
    Arguments:     []string{"token.type", "@\"Bearer\""},
    LineNumber:    45,
    IsConditional: false,
    IsReachable:   true,
}
```

### Variable

Represents a variable declaration in test code.

```go
type Variable struct {
    Name         string  // Variable name
    Type         string  // Variable type (e.g., "NSString*", "BOOL", "int")
    InitialValue *string // Initial value expression, nil if not initialized
    LineNumber   int     // Line number where the variable is declared
}
```

**Example:**
```go
initialValue := "@\"test\""
variable := Variable{
    Name:         "token",
    Type:         "NSString*",
    InitialValue: &initialValue,
    LineNumber:   10,
}
```

### MethodCall

Represents a method invocation in test code.

```go
type MethodCall struct {
    Receiver   string   // Receiver object or class name (e.g., "parser", "NSString")
    Selector   string   // Method selector (e.g., "parse:", "stringWithFormat:")
    Arguments  []string // Argument expressions passed to the method
    LineNumber int      // Line number where the method call appears
}
```

**Example:**
```go
methodCall := MethodCall{
    Receiver:   "parser",
    Selector:   "parse:",
    Arguments:  []string{"input"},
    LineNumber: 20,
}
```

## Usage

These models are used throughout the Test Audit Validation System:

1. **Test Discovery Engine**: Populates `TestFile` and `TestClass` structures
2. **Static Analysis Engine**: Populates `TestMethod`, `Assertion`, `Variable`, and `MethodCall` structures
3. **Validation Engine**: Consumes all models to detect test quality issues
4. **Report Generator**: Uses models to generate detailed findings reports

## Design Principles

- **Immutability**: Models are designed to be populated once during parsing and then read-only
- **Nullable Fields**: Use pointers for optional fields (e.g., `BaseClass`, `InitialValue`)
- **Simplicity**: Keep models simple and focused on representing parsed code structure
- **Extensibility**: Easy to add new fields as analysis requirements evolve

## Testing

Run the test suite:

```bash
go test ./internal/models -v
```

All tests should pass, verifying that the models can be instantiated and used correctly.
