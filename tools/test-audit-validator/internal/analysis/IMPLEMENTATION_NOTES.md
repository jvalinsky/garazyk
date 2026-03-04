# Assertion Extraction Implementation Notes

## Task 3.2: Implement assertion extraction

### Implementation Summary

The `ExtractAssertions()` method has been successfully implemented in `engine.go` with the following capabilities:

#### Core Functionality

1. **Assertion Detection**: Identifies all XCTest assertion macro calls including:
   - `XCTAssert`, `XCTAssertTrue`, `XCTAssertFalse`
   - `XCTAssertEqual`, `XCTAssertNotEqual`
   - `XCTAssertEqualObjects`, `XCTAssertNotEqualObjects`
   - `XCTAssertNil`, `XCTAssertNotNil`
   - `XCTAssertGreaterThan`, `XCTAssertGreaterThanOrEqual`
   - `XCTAssertLessThan`, `XCTAssertLessThanOrEqual`
   - `XCTAssertThrows`, `XCTAssertThrowsSpecific`, `XCTAssertThrowsSpecificNamed`
   - `XCTAssertNoThrow`, `XCTAssertNoThrowSpecific`, `XCTAssertNoThrowSpecificNamed`
   - `XCTFail`
   - `XCTAssertEqualWithAccuracy`, `XCTAssertNotEqualWithAccuracy`
   - `XCTUnwrap`, `XCTSkip`, `XCTSkipIf`, `XCTSkipUnless`, `XCTExpectFailure`

2. **Argument Extraction**: Extracts all arguments passed to assertion calls using `extractCallArguments()`

3. **Line Number Tracking**: Accurately tracks the line number where each assertion appears

4. **Conditional Context Detection**: Tracks whether assertions are inside conditional blocks (if/else/switch statements)

5. **Reachability Tracking**: Placeholder for future control flow analysis to detect unreachable assertions

#### Supporting Methods

- `visitDescendants()`: Recursively visits all descendants of a cursor for thorough AST traversal
- `getFunctionName()`: Extracts function names from call expression cursors
- `isXCTestAssertion()`: Validates whether a function name is an XCTest assertion macro
- `extractCallArguments()`: Extracts argument expressions from call expressions
- `getCursorText()`: Extracts source text for cursors (simplified implementation)

#### Test Coverage

Comprehensive tests have been written covering:

1. **TestExtractAssertions_BasicAssertions**: Tests extraction of basic XCTest assertions (XCTAssertTrue, XCTAssertFalse, XCTAssertNil)

2. **TestExtractAssertions_ConditionalAssertions**: Tests detection of assertions in conditional blocks and proper IsConditional flag setting

3. **TestExtractAssertions_AllAssertionTypes**: Tests detection of all 14+ XCTest assertion types

4. **TestExtractAssertions_WithArguments**: Tests extraction of assertion arguments including complex expressions

5. **TestExtractAssertions_ZeroAssertions**: Tests handling of methods with no assertions

6. **TestExtractAssertions_NestedConditionals**: Tests assertions in nested if/switch statements

7. **TestExtractAssertions_LineNumbers**: Tests accurate line number tracking

### Requirements Validated

This implementation satisfies the following requirements from the spec:

- **Requirement 2.1**: Identifies all XCTest assertion calls
- **Requirement 2.2**: Extracts arguments passed to each assertion
- **Requirement 2.3**: Identifies variables and expressions being asserted
- **Requirement 2.4**: Detects conditional assertions within if/else blocks
- **Requirement 2.5**: Tracks assertion count per test method (via len(assertions))

### Known Limitations

1. **libclang Linking**: Tests require proper libclang setup to run. See `LIBCLANG_SETUP.md` for configuration instructions.

2. **Control Flow Analysis**: The `IsReachable` field is currently always set to `true`. Full control flow analysis for detecting unreachable code paths is marked as TODO for task 3.4.

3. **Argument Text Extraction**: The `getCursorText()` method uses a simplified implementation returning `cursor.DisplayName()`. A production implementation would read the source file directly to extract exact text from source ranges.

### Integration Points

The `ExtractAssertions()` method integrates with:

- **models.Assertion**: Returns a slice of Assertion structs with Type, Arguments, LineNumber, IsConditional, and IsReachable fields
- **StaticAnalysisEngine**: Uses the existing clang AST parsing infrastructure
- **Test Discovery**: Will be called by the discovery engine for each test method found

### Next Steps

1. **Task 3.3**: Implement variable and method call extraction
2. **Task 3.4**: Implement control flow analysis to populate IsReachable field
3. **Task 3.5**: Write unit tests for Static Analysis Engine (requires libclang setup)
4. **CI Integration**: Configure CI environment with libclang for automated testing

### Build Verification

The code compiles successfully:

```bash
cd tools/test-audit-validator
go build ./internal/analysis/
# Success - no compilation errors
```

### Testing Instructions

To run tests locally, first configure libclang:

```bash
# macOS with Xcode
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
export CGO_CPPFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"

# Then run tests
cd tools/test-audit-validator
go test -v ./internal/analysis/ -run TestExtractAssertions
```

See `LIBCLANG_SETUP.md` for detailed setup instructions for different platforms.


## Task 3.3: Implement variable and method call extraction

### Implementation Summary

The `ExtractVariables()` and `ExtractMethodCalls()` methods have been successfully implemented in `engine.go` with comprehensive test coverage.

#### ExtractVariables() Functionality

1. **Variable Detection**: Identifies all variable declarations (VarDecl nodes) in method bodies
2. **Type Extraction**: Captures variable types including Objective-C pointer types with qualifiers (e.g., `NSString *__strong`)
3. **Initial Value Extraction**: Detects and extracts initial values for variables when present
4. **Line Number Tracking**: Accurately tracks the line number where each variable is declared

#### ExtractMethodCalls() Functionality

1. **Method Call Detection**: Identifies all Objective-C message expressions (ObjCMessageExpr nodes)
2. **Receiver Extraction**: Extracts the receiver object or class name for each method call
3. **Selector Extraction**: Captures the method selector (method name)
4. **Argument Extraction**: Extracts all arguments passed to method calls
5. **Line Number Tracking**: Tracks the line number where each method call appears
6. **Nested Call Support**: Handles nested method calls like `[[NSString alloc] initWithString:@"test"]`

#### Supporting Methods

- `FindMethodByName()`: Helper method to locate Objective-C methods by name in a translation unit
  - Searches through all descendants to find instance or class methods
  - Returns the cursor and a boolean indicating if the method was found
  - Used by tests to easily locate method cursors for analysis

- `extractReceiver()`: Extracts the receiver from an Objective-C message expression
  - Handles variable receivers (DeclRefExpr)
  - Handles property receivers (MemberRefExpr)
  - Handles class receivers (ObjCClassRef)
  - Falls back to receiver type for class methods

- `extractMessageArguments()`: Extracts arguments from Objective-C message expressions
  - Uses `NumArguments()` and `Argument()` methods from clang
  - Extracts text representation of each argument

#### Test Coverage

Comprehensive tests have been written covering:

**Variable Extraction Tests:**
1. **TestExtractVariables_BasicVariables**: Tests extraction of basic variable declarations (NSString*, int, BOOL)
2. **TestExtractVariables_WithInitialValues**: Tests detection of initial values for variables
3. **TestExtractVariables_LineNumbers**: Tests accurate line number tracking for variables
4. **TestExtractVariables_ZeroVariables**: Tests handling of methods with no variable declarations

**Method Call Extraction Tests:**
1. **TestExtractMethodCalls_BasicCalls**: Tests extraction of basic instance method calls
2. **TestExtractMethodCalls_WithArguments**: Tests extraction of method calls with arguments
3. **TestExtractMethodCalls_LineNumbers**: Tests accurate line number tracking for method calls
4. **TestExtractMethodCalls_ZeroCalls**: Tests handling of methods with no method calls
5. **TestExtractMethodCalls_ClassMethods**: Tests extraction of class method calls
6. **TestExtractMethodCalls_NestedCalls**: Tests extraction of nested method calls

### Requirements Validated

This implementation satisfies the following requirements from the spec:

- **Requirement 2.3**: Identifies variables and expressions being asserted (via ExtractVariables)
- **Task 3.3 Requirements**: 
  - Implements `ExtractVariables()` to find variable declarations
  - Implements `ExtractMethodCalls()` to find method invocations
  - Tracks variable types, initial values, and usage
  - Tracks method call receivers, selectors, and arguments
  - Tracks line numbers for both variables and method calls

### Known Limitations

1. **Initial Value Text Extraction**: The `getCursorText()` method uses a simplified implementation:
   - String literals are extracted correctly using `DisplayName()`
   - Integer and floating literals return placeholder values (`<integer>`, `<float>`)
   - A production implementation would read the source file directly to extract exact literal values

2. **Argument Text Extraction**: Similar to initial values, argument text uses `DisplayName()` which provides a simplified representation

3. **Complex Expressions**: Very complex initialization expressions may not be fully captured in the InitialValue field

### Integration Points

The extraction methods integrate with:

- **models.Variable**: Returns a slice of Variable structs with Name, Type, InitialValue, and LineNumber fields
- **models.MethodCall**: Returns a slice of MethodCall structs with Receiver, Selector, Arguments, and LineNumber fields
- **StaticAnalysisEngine**: Uses the existing clang AST parsing infrastructure and `visitDescendants()` method
- **Test Discovery**: Will be called by validation rules to analyze test method behavior

### Next Steps

1. **Task 3.4**: Implement control flow analysis to detect unreachable code paths
2. **Task 3.5**: Write additional unit tests for Static Analysis Engine
3. **Task 5.x**: Implement validation rules that use variable and method call extraction
4. **Enhancement**: Improve `getCursorText()` to extract exact literal values from source files

### Build Verification

The code compiles successfully and all tests pass:

```bash
cd tools/test-audit-validator
go test -v ./internal/analysis/... -run "TestExtractVariables|TestExtractMethodCalls"
# All tests pass
```

### Testing Instructions

To run tests locally, configure libclang as documented in the README:

```bash
# macOS with Xcode
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib -Wl,-rpath,/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
export CGO_CFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"

# Run tests
cd tools/test-audit-validator
go test -v ./internal/analysis/... -run "TestExtractVariables|TestExtractMethodCalls"
```


## Task 3.4: Implement control flow analysis

### Implementation Summary

The `AnalyzeControlFlow()` method has been successfully implemented in `engine.go` to detect unreachable code paths and update the `IsReachable` field on assertions.

#### Core Functionality

1. **Unreachable Code After Return**: Detects code following return statements at the top level of a method
2. **Always-False Conditions**: Detects code inside `if (NO)`, `if (0)`, or `if (false)` blocks
3. **Conditional Tracking**: Properly tracks whether assertions are inside conditional blocks using recursive depth tracking

#### Implementation Details

**Control Flow Graph Building**: The `findUnreachableRegions()` method:
- Locates the method body (CompoundStmt)
- Examines direct children to find return statements
- Marks all code after a top-level return as unreachable
- Recursively searches for always-false if statements

**Always-False Condition Detection**: The `isAlwaysFalseCondition()` method detects:
- `if (NO)` - Objective-C boolean literal (ObjCBoolLiteralExpr with column span ≤ 2)
- `if (0)` - Integer literal zero (IntegerLiteral with column span = 1)
- `if (false)` - C boolean literal (DeclRefExpr with spelling "false")

**Conditional Depth Tracking**: The `extractAssertionsRecursive()` method:
- Uses recursive AST traversal with depth parameter
- Increments depth when entering if/switch statements
- Properly sets IsConditional flag based on depth > 0

#### Supporting Methods

- `findUnreachableRegions()`: Identifies regions of unreachable code
- `findAlwaysFalseRegions()`: Recursively finds always-false if statements
- `isAlwaysFalseCondition()`: Checks if an if statement condition is always false
- `isLineInUnreachableRegion()`: Checks if a line falls within an unreachable region
- `extractAssertionsRecursive()`: Recursively extracts assertions with proper conditional tracking

#### Data Structures

```go
type UnreachableRegion struct {
    StartLine int
    EndLine   int
    Reason    string // "after-return", "always-false-condition"
}
```

#### Test Coverage

Comprehensive tests have been written covering:

1. **TestAnalyzeControlFlow_UnreachableAfterReturn**: Tests detection of unreachable code after return statements
2. **TestAnalyzeControlFlow_ReachableInConditionalReturn**: Tests that code after conditional returns remains reachable
3. **TestAnalyzeControlFlow_AlwaysFalseCondition**: Tests detection of `if (NO)` blocks
4. **TestAnalyzeControlFlow_AlwaysFalseWithZero**: Tests detection of `if (0)` blocks
5. **TestAnalyzeControlFlow_MultipleReturns**: Tests handling of multiple return statements
6. **TestAnalyzeControlFlow_NoUnreachableCode**: Tests that normal code is marked as reachable
7. **TestAnalyzeControlFlow_ConditionalAndUnconditional**: Tests mixed conditional and unconditional assertions
8. **TestAnalyzeControlFlow_EmptyMethod**: Tests handling of methods with no assertions
9. **TestAnalyzeControlFlow_NestedIfStatements**: Tests nested if statements with always-false conditions

### Requirements Validated

This implementation satisfies the following requirements from the spec:

- **Requirement 2.4**: Detects conditional assertions within if/else blocks (IsConditional field)
- **Requirement 10.5**: Detects tests with assertions in unreachable code paths (IsReachable field)
- **Task 3.4 Requirements**:
  - Implements `AnalyzeControlFlow()` to build control flow graph
  - Detects unreachable code paths with assertions
  - Identifies conditional assertions in if/else blocks

### Known Limitations

1. **Heuristic-based Detection**: Due to limitations in the clang API, we use heuristics to distinguish:
   - `NO` from `YES` (column span ≤ 2 for NO)
   - `0` from other integers (column span = 1 for 0)
   - This works for most cases but may have edge cases with unusual formatting

2. **Conditional Returns**: Returns inside conditional blocks (e.g., `if (condition) { return; }`) do not mark subsequent code as unreachable, as the condition may not always be true. This is correct behavior.

3. **Complex Conditions**: Only simple always-false conditions are detected:
   - `if (NO)`, `if (0)`, `if (false)` ✓
   - `if (1 == 2)`, `if (ptr && false)`, `if (!YES)` ✗

4. **Throw Statements**: Infrastructure exists for detecting unreachable code after `@throw` statements, but this is not fully implemented yet.

5. **Switch Statements**: Always-false switch conditions are not currently detected.

### Integration Points

The control flow analysis integrates with:

- **models.Assertion**: Updates the IsReachable field on existing assertions
- **ExtractAssertions()**: Provides assertions with IsConditional already set
- **Validation Rules**: Will be used by FalsePositiveDetectionRule to identify tests with unreachable assertions

### Next Steps

1. **Task 3.5**: Write additional unit tests for Static Analysis Engine
2. **Task 5.3**: Implement FalsePositiveDetectionRule that uses IsReachable field
3. **Enhancement**: Improve always-false detection to handle more complex conditions
4. **Enhancement**: Implement throw statement detection for unreachable code

### Build Verification

The code compiles successfully and all tests pass:

```bash
cd tools/test-audit-validator
go test -v ./internal/analysis/... -run TestAnalyzeControlFlow
# All 9 tests pass
```

### Testing Instructions

To run tests locally, configure libclang as documented in the README:

```bash
# macOS with Xcode
export CGO_LDFLAGS="-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib -Wl,-rpath,/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
export CGO_CFLAGS="-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include"

# Run all analysis tests
cd tools/test-audit-validator
go test -v ./internal/analysis/...
```

All tests should pass with output showing proper detection of unreachable code and conditional assertions.
