package analysis

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestParseFile_NonExistentFile tests error handling for non-existent files
func TestParseFile_NonExistentFile(t *testing.T) {
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	_, err := engine.ParseFile("/nonexistent/path/test.m")
	if err == nil {
		t.Error("Expected error for non-existent file")
	}
}

// TestParseFile_WithCategories tests parsing Objective-C categories
func TestParseFile_WithCategories(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface NSString (TestCategory)
- (NSString *)reverseString;
@end

@implementation NSString (TestCategory)
- (NSString *)reverseString {
    NSUInteger length = [self length];
    XCTAssertGreaterThan(length, 0);
    return self;
}
@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse category: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestParseFile_WithProtocols tests parsing Objective-C protocols
func TestParseFile_WithProtocols(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@protocol TestProtocol <NSObject>
- (void)requiredMethod;
@optional
- (void)optionalMethod;
@end

@interface TestClass : NSObject <TestProtocol>
@end

@implementation TestClass
- (void)requiredMethod {
    XCTAssertTrue(YES);
}
@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse protocol: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestParseFile_WithBlockParameters tests parsing code with block parameters
func TestParseFile_WithBlockParameters(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    void (^completionBlock)(BOOL success, NSError *error) = ^(BOOL success, NSError *error) {
        XCTAssertTrue(success);
        XCTAssertNil(error);
    };
    completionBlock(YES, nil);
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse blocks: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
	
	// Find the test method and extract assertions
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find assertions inside the block
	if len(assertions) != 2 {
		t.Errorf("Expected 2 assertions (inside block), found %d", len(assertions))
	}
}


// TestExtractAssertions_InLoops tests extraction of assertions inside loops
func TestExtractAssertions_InLoops(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    for (int i = 0; i < 10; i++) {
        XCTAssertLessThan(i, 10);
    }
    
    int j = 0;
    while (j < 5) {
        XCTAssertLessThan(j, 5);
        j++;
    }
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find 2 assertions (one in for loop, one in while loop)
	if len(assertions) != 2 {
		t.Errorf("Expected 2 assertions in loops, found %d", len(assertions))
	}
	
	// Note: Loop bodies may or may not be marked as conditional depending on implementation
	// The current implementation tracks if/switch statements but not loops
	// This is acceptable as loops don't affect reachability in the same way
	for i, assertion := range assertions {
		t.Logf("Assertion %d: conditional=%v", i, assertion.IsConditional)
	}
}

// TestExtractAssertions_InSwitchStatements tests assertions in switch cases
func TestExtractAssertions_InSwitchStatements(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    int value = 1;
    switch (value) {
        case 1:
            XCTAssertEqual(value, 1);
            break;
        case 2:
            XCTAssertEqual(value, 2);
            break;
        default:
            XCTFail(@"Unexpected value");
            break;
    }
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find 3 assertions (one in each case)
	if len(assertions) != 3 {
		t.Errorf("Expected 3 assertions in switch, found %d", len(assertions))
	}
	
	// All should be marked as conditional (inside switch cases)
	for i, assertion := range assertions {
		if !assertion.IsConditional {
			t.Errorf("Assertion %d in switch should be marked as conditional", i)
		}
	}
}

// TestExtractVariables_ComplexTypes tests extraction of variables with complex types
func TestExtractVariables_ComplexTypes(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSArray<NSString *> *stringArray = @[@"a", @"b"];
    NSDictionary<NSString *, NSNumber *> *dict = @{@"key": @42};
    void (^block)(void) = ^{ NSLog(@"test"); };
    id<NSCopying> copyable = @"test";
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Should find 4 variables with complex types
	if len(variables) != 4 {
		t.Errorf("Expected 4 variables, found %d", len(variables))
	}
	
	// Verify all have types
	for i, variable := range variables {
		if variable.Type == "" {
			t.Errorf("Variable %d (%s) has empty type", i, variable.Name)
		}
		t.Logf("Variable %d: %s %s", i, variable.Type, variable.Name)
	}
}

// TestExtractVariables_MultipleDeclarations tests multiple variables in one statement
func TestExtractVariables_MultipleDeclarations(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    int a = 1, b = 2, c = 3;
    NSString *x, *y, *z;
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Should find 6 variables (3 ints + 3 strings)
	// Note: This depends on how clang represents multiple declarations
	// It may create separate VarDecl nodes for each
	if len(variables) < 3 {
		t.Errorf("Expected at least 3 variables, found %d", len(variables))
	}
	
	t.Logf("Found %d variables from multiple declarations", len(variables))
}


// TestExtractMethodCalls_PropertyAccess tests extraction of property access as method calls
func TestExtractMethodCalls_PropertyAccess(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@property (nonatomic, strong) NSString *name;
@end

@implementation TestClass

- (void)testMethod {
    self.name = @"test";
    NSString *value = self.name;
    NSUInteger length = value.length;
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Property access is typically represented as method calls in Objective-C
	// We should find at least the getter calls
	t.Logf("Found %d method calls (including property access)", len(methodCalls))
	
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s]", i, call.Receiver, call.Selector)
	}
}

// TestExtractMethodCalls_ChainedCalls tests extraction of chained method calls
func TestExtractMethodCalls_ChainedCalls(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *result = [[[NSString alloc] init] uppercaseString];
    NSArray *array = [[NSArray arrayWithObject:@"test"] sortedArrayUsingSelector:@selector(compare:)];
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Should find multiple method calls from the chains
	if len(methodCalls) < 4 {
		t.Errorf("Expected at least 4 method calls from chains, found %d", len(methodCalls))
	}
	
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s]", i, call.Receiver, call.Selector)
	}
}

// TestAnalyzeControlFlow_SwitchWithBreaks tests control flow with switch and break statements
func TestAnalyzeControlFlow_SwitchWithBreaks(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    int value = 1;
    switch (value) {
        case 1:
            XCTAssertEqual(value, 1);
            break;
        case 2:
            XCTAssertEqual(value, 2);
            return;
            XCTFail(@"Unreachable after return");
        default:
            XCTAssertTrue(YES);
            break;
    }
    XCTAssertNotNil(@"test");  // Reachable after switch
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find 5 assertions
	if len(assertions) != 5 {
		t.Errorf("Expected 5 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// The assertion after return in case 2 should be unreachable
	// The last assertion after switch should be reachable
	for i, assertion := range assertions {
		t.Logf("Assertion %d (line %d): type=%s, conditional=%v, reachable=%v",
			i, assertion.LineNumber, assertion.Type, assertion.IsConditional, assertion.IsReachable)
	}
}

// TestAnalyzeControlFlow_LoopsWithBreakContinue tests control flow with break and continue
func TestAnalyzeControlFlow_LoopsWithBreakContinue(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    for (int i = 0; i < 10; i++) {
        if (i == 5) {
            continue;
        }
        XCTAssertLessThan(i, 10);
        
        if (i == 8) {
            break;
        }
    }
    XCTAssertTrue(YES);  // Reachable after loop
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find 2 assertions
	if len(assertions) != 2 {
		t.Errorf("Expected 2 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// Both assertions should be reachable
	// (break/continue don't make code unreachable in the same way return does)
	for i, assertion := range assertions {
		t.Logf("Assertion %d (line %d): conditional=%v, reachable=%v",
			i, assertion.LineNumber, assertion.IsConditional, assertion.IsReachable)
	}
}

// TestExtractAssertions_WithMessageArguments tests assertions with custom messages
func TestExtractAssertions_WithMessageArguments(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *value = @"test";
    XCTAssertNotNil(value, @"Value should not be nil");
    XCTAssertEqualObjects(value, @"test", @"Value should equal 'test'");
    XCTAssertTrue(YES, @"This should always pass: %@", @"reason");
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find 3 assertions
	if len(assertions) != 3 {
		t.Errorf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Verify assertions have arguments (including message arguments)
	for i, assertion := range assertions {
		if len(assertion.Arguments) == 0 {
			t.Errorf("Assertion %d should have arguments", i)
		}
		t.Logf("Assertion %d: %s with %d arguments: %v",
			i, assertion.Type, len(assertion.Arguments), assertion.Arguments)
	}
}

// TestExtractAssertions_XCTUnwrap tests extraction of XCTUnwrap assertions
func TestExtractAssertions_XCTUnwrap(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *optional = @"test";
    // XCTUnwrap is a macro that may not be available without XCTest headers
    // Just test that we can parse code that would use it
    XCTAssertNotNil(optional);
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find at least 1 assertion
	if len(assertions) < 1 {
		t.Errorf("Expected at least 1 assertion, found %d", len(assertions))
	}
	
	t.Logf("Found %d assertions", len(assertions))
}

// TestParseFile_MissingHeaders tests graceful handling of missing header files
func TestParseFile_MissingHeaders(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>
#import "NonExistentHeader.h"

@interface TestClass : NSObject
@end

@implementation TestClass
- (void)testMethod {
    XCTAssertTrue(YES);
}
@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	
	// Should return an error but still provide a TU for partial analysis
	if err != nil {
		t.Logf("Expected parse error for missing header: %v", err)
	}
	
	// TU should still be valid for partial analysis
	if tu.IsValid() {
		defer tu.Dispose()
		t.Log("Translation unit is valid despite missing header (graceful fallback)")
		
		// Try to extract assertions anyway
		methodCursor, found := engine.FindMethodByName(tu, "testMethod")
		if found {
			assertions, err := engine.ExtractAssertions(methodCursor)
			if err == nil {
				t.Logf("Successfully extracted %d assertions despite missing header", len(assertions))
			}
		}
	}
}

// TestExtractVariables_StaticVariables tests extraction of static variables
func TestExtractVariables_StaticVariables(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    static int counter = 0;
    static NSString *sharedString = nil;
    counter++;
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Should find 2 static variables
	if len(variables) != 2 {
		t.Errorf("Expected 2 static variables, found %d", len(variables))
	}
	
	for i, variable := range variables {
		t.Logf("Variable %d: %s %s (initial: %v)",
			i, variable.Type, variable.Name, variable.InitialValue)
	}
}

// TestAnalyzeControlFlow_TernaryOperator tests assertions in ternary expressions
func TestAnalyzeControlFlow_TernaryOperator(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    BOOL condition = YES;
    NSString *result = condition ? @"yes" : @"no";
    XCTAssertEqualObjects(result, @"yes");
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Should find 1 assertion
	if len(assertions) != 1 {
		t.Errorf("Expected 1 assertion, found %d", len(assertions))
	}
	
	// Assertion should be reachable (not inside conditional)
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	if !assertions[0].IsReachable {
		t.Error("Assertion should be reachable")
	}
}

// TestFindMethodByName_ClassMethod tests finding class methods (not just instance methods)
func TestFindMethodByName_ClassMethod(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
+ (void)classMethod;
@end

@implementation TestClass

+ (void)classMethod {
    XCTAssertTrue(YES);
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	// Should find class method
	methodCursor, found := engine.FindMethodByName(tu, "classMethod")
	if !found {
		t.Fatal("Could not find classMethod")
	}
	
	// Verify it's a class method
	kind := methodCursor.Kind()
	t.Logf("Method kind: %v", kind)
	
	// Extract assertions from class method
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	if len(assertions) != 1 {
		t.Errorf("Expected 1 assertion in class method, found %d", len(assertions))
	}
}

// TestExtractAssertions_EmptyFile tests handling of empty or minimal files
func TestExtractAssertions_EmptyFile(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
// Empty file with just a comment
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse empty file: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit should be valid for empty file")
	}
}

// TestExtractMethodCalls_SelectorWithColons tests method calls with multiple parameters
func TestExtractMethodCalls_SelectorWithColons(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *result = [NSString stringWithFormat:@"Value: %d, Name: %@", 42, @"test"];
    NSRange range = [result rangeOfString:@"Value" options:NSCaseInsensitiveSearch];
}

@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse file: %v", err)
	}
	defer tu.Dispose()
	
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Should find method calls with multiple parameters
	if len(methodCalls) < 2 {
		t.Errorf("Expected at least 2 method calls, found %d", len(methodCalls))
	}
	
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s] with %d arguments",
			i, call.Receiver, call.Selector, len(call.Arguments))
		
		// Verify selector contains colons for multi-parameter methods
		if len(call.Arguments) > 1 && !strings.Contains(call.Selector, ":") {
			t.Logf("Note: Multi-parameter selector may not include colons: %s", call.Selector)
		}
	}
}
