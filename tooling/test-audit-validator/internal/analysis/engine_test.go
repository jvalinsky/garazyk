package analysis

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/go-clang/clang-v14/clang"
)

// TestNewStaticAnalysisEngine tests engine creation
func TestNewStaticAnalysisEngine(t *testing.T) {
	engine := NewStaticAnalysisEngine()
	if engine == nil {
		t.Fatal("NewStaticAnalysisEngine returned nil")
	}
	defer engine.Close()
	
	// Verify index is initialized
	if engine.index == (clang.Index{}) {
		t.Error("Engine index not initialized")
	}
}

// TestEngineClose tests resource cleanup
func TestEngineClose(t *testing.T) {
	engine := NewStaticAnalysisEngine()
	if engine == nil {
		t.Fatal("NewStaticAnalysisEngine returned nil")
	}
	
	// Close should not panic
	engine.Close()
	
	// Multiple closes should be safe
	engine.Close()
}

// TestParseFile_EmptyPath tests error handling for empty file path
func TestParseFile_EmptyPath(t *testing.T) {
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	_, err := engine.ParseFile("")
	if err == nil {
		t.Error("Expected error for empty file path")
	}
	if !strings.Contains(err.Error(), "cannot be empty") {
		t.Errorf("Expected 'cannot be empty' error, got: %v", err)
	}
}

// TestParseFile_InvalidExtension tests error handling for invalid file extensions
func TestParseFile_InvalidExtension(t *testing.T) {
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	testCases := []string{
		"test.txt",
		"test.c",
		"test.cpp",
		"test.swift",
		"test",
	}
	
	for _, tc := range testCases {
		_, err := engine.ParseFile(tc)
		if err == nil {
			t.Errorf("Expected error for file extension: %s", tc)
		}
		if !strings.Contains(err.Error(), "must have .m or .h extension") {
			t.Errorf("Expected extension error for %s, got: %v", tc, err)
		}
	}
}

// TestParseFile_ValidObjCFile tests parsing a valid Objective-C file
func TestParseFile_ValidObjCFile(t *testing.T) {
	// Create a temporary test file
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
- (void)testMethod;
@end

@implementation TestClass
- (void)testMethod {
    NSLog(@"Hello");
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
		t.Fatalf("Failed to parse valid Objective-C file: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestParseFile_HeaderFile tests parsing an Objective-C header file
func TestParseFile_HeaderFile(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.h")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
- (void)testMethod;
@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFile(testFile)
	if err != nil {
		t.Fatalf("Failed to parse header file: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestParseFile_WithSyntaxErrors tests graceful handling of syntax errors
func TestParseFile_WithSyntaxErrors(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	// Code with syntax errors
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
- (void)testMethod  // Missing semicolon
@end

@implementation TestClass
- (void)testMethod {
    NSLog(@"Hello"  // Missing closing paren and semicolon
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
	if err == nil {
		t.Log("Warning: Expected parse error for syntax errors, but got none")
	}
	
	// TU should still be valid for partial analysis
	if tu.IsValid() {
		defer tu.Dispose()
		t.Log("Translation unit is valid despite syntax errors (graceful fallback)")
	}
}

// TestParseFile_WithARCCode tests parsing code that uses ARC features
func TestParseFile_WithARCCode(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@property (strong, nonatomic) NSString *name;
@end

@implementation TestClass
- (void)testMethod {
    self.name = @"Test";
    __weak typeof(self) weakSelf = self;
    NSLog(@"%@", weakSelf.name);
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
		t.Fatalf("Failed to parse ARC code: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestParseFile_WithBlocks tests parsing code that uses blocks
func TestParseFile_WithBlocks(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass
- (void)testMethod {
    void (^block)(void) = ^{
        NSLog(@"Block executed");
    };
    block();
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
		t.Fatalf("Failed to parse blocks code: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestParseFileWithFallback tests the fallback parsing strategy
func TestParseFileWithFallback(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	// Simple valid code
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass
@end
`
	
	if err := os.WriteFile(testFile, []byte(testCode), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}
	
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	tu, err := engine.ParseFileWithFallback(testFile)
	if err != nil {
		t.Fatalf("Failed to parse with fallback: %v", err)
	}
	defer tu.Dispose()
	
	if !tu.IsValid() {
		t.Error("Translation unit is not valid")
	}
}

// TestGetCursor tests getting the root cursor from a translation unit
func TestGetCursor(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
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
	
	cursor := engine.GetCursor(tu)
	if cursor.IsNull() {
		t.Error("Root cursor is null")
	}
	
	// Root cursor should be a translation unit cursor
	kind := cursor.Kind()
	t.Logf("Cursor kind: %v", kind)
	// The cursor kind should be TranslationUnit (value 300)
	// We just verify it's not null and is valid
	if kind == clang.Cursor_InvalidFile {
		t.Error("Cursor kind is InvalidFile")
	}
}

// TestVisitChildren tests visiting child cursors
func TestVisitChildren(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
- (void)method1;
- (void)method2;
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
	
	cursor := engine.GetCursor(tu)
	
	// Count children
	childCount := 0
	engine.VisitChildren(cursor, func(cursor, parent clang.Cursor) bool {
		childCount++
		return true // Continue visiting
	})
	
	if childCount == 0 {
		t.Error("Expected to find child cursors")
	}
	
	t.Logf("Found %d child cursors", childCount)
}

// TestVisitChildren_EarlyTermination tests stopping visitor early
func TestVisitChildren_EarlyTermination(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
- (void)method1;
- (void)method2;
- (void)method3;
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
	
	cursor := engine.GetCursor(tu)
	
	// Visit only first 2 children - return false on the second visit
	visitCount := 0
	engine.VisitChildren(cursor, func(cursor, parent clang.Cursor) bool {
		visitCount++
		if visitCount >= 2 {
			return false // Stop after 2nd visit
		}
		return true // Continue
	})
	
	if visitCount < 2 {
		t.Errorf("Expected to visit at least 2 children, visited: %d", visitCount)
	}
	
	t.Logf("Visited %d children before stopping", visitCount)
}

// TestGetClangArguments tests the clang arguments configuration
func TestGetClangArguments(t *testing.T) {
	engine := NewStaticAnalysisEngine()
	defer engine.Close()
	
	args := engine.getClangArguments()
	
	// Verify essential arguments are present
	requiredArgs := []string{
		"-x", "objective-c",
		"-fobjc-arc",
		"-fblocks",
	}
	
	argsStr := strings.Join(args, " ")
	for _, req := range requiredArgs {
		if !strings.Contains(argsStr, req) {
			t.Errorf("Missing required argument: %s", req)
		}
	}
}

// TestParseFile_XCTestFile tests parsing a real XCTest file structure
func TestParseFile_XCTestFile(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <XCTest/XCTest.h>

@interface MyTests : XCTestCase
@end

@implementation MyTests

- (void)testExample {
    XCTAssertTrue(YES, @"This should pass");
}

- (void)testAnotherExample {
    NSString *result = @"test";
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result, @"test");
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
		// XCTest headers might not be available, so we allow parse errors
		t.Logf("Parse error (expected if XCTest not available): %v", err)
	}
	
	if tu.IsValid() {
		defer tu.Dispose()
		
		// Try to find the test class
		cursor := engine.GetCursor(tu)
		foundTestClass := false
		
		engine.VisitChildren(cursor, func(cursor, parent clang.Cursor) bool {
			if cursor.Kind() == clang.Cursor_ObjCInterfaceDecl {
				name := cursor.Spelling()
				if name == "MyTests" {
					foundTestClass = true
					t.Logf("Found test class: %s", name)
				}
			}
			return true
		})
		
		if !foundTestClass {
			t.Log("Note: Test class not found in AST (may be due to missing XCTest headers)")
		}
	}
}

// TestExtractAssertions_BasicAssertions tests extraction of basic XCTest assertions
func TestExtractAssertions_BasicAssertions(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    XCTAssertFalse(NO);
    XCTAssertNil(nil);
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 3 assertions
	if len(assertions) != 3 {
		t.Errorf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Verify assertion types
	expectedTypes := []string{"XCTAssertTrue", "XCTAssertFalse", "XCTAssertNil"}
	for i, expected := range expectedTypes {
		if i >= len(assertions) {
			break
		}
		if assertions[i].Type != expected {
			t.Errorf("Assertion %d: expected type %s, got %s", i, expected, assertions[i].Type)
		}
	}
}

// TestExtractAssertions_ConditionalAssertions tests detection of assertions in conditional blocks
func TestExtractAssertions_ConditionalAssertions(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    
    if (YES) {
        XCTAssertEqual(1, 1);
    }
    
    XCTAssertNotNil(@"test");
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 3 assertions
	if len(assertions) != 3 {
		t.Errorf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Verify conditional flags
	// First assertion: not conditional
	if assertions[0].IsConditional {
		t.Error("First assertion should not be conditional")
	}
	
	// Second assertion: conditional (inside if block)
	if !assertions[1].IsConditional {
		t.Error("Second assertion should be conditional")
	}
	
	// Third assertion: not conditional
	if assertions[2].IsConditional {
		t.Error("Third assertion should not be conditional")
	}
}

// TestExtractAssertions_AllAssertionTypes tests detection of all XCTest assertion types
func TestExtractAssertions_AllAssertionTypes(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssert(YES);
    XCTAssertTrue(YES);
    XCTAssertFalse(NO);
    XCTAssertEqual(1, 1);
    XCTAssertNotEqual(1, 2);
    XCTAssertEqualObjects(@"a", @"a");
    XCTAssertNotEqualObjects(@"a", @"b");
    XCTAssertNil(nil);
    XCTAssertNotNil(@"test");
    XCTAssertGreaterThan(2, 1);
    XCTAssertGreaterThanOrEqual(2, 2);
    XCTAssertLessThan(1, 2);
    XCTAssertLessThanOrEqual(1, 1);
    XCTFail(@"Failed");
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found all assertions
	expectedCount := 14
	if len(assertions) != expectedCount {
		t.Errorf("Expected %d assertions, found %d", expectedCount, len(assertions))
	}
	
	// Verify all assertions have types
	for i, assertion := range assertions {
		if assertion.Type == "" {
			t.Errorf("Assertion %d has empty type", i)
		}
		if !strings.HasPrefix(assertion.Type, "XCT") {
			t.Errorf("Assertion %d has invalid type: %s", i, assertion.Type)
		}
	}
}

// TestExtractAssertions_WithArguments tests extraction of assertion arguments
func TestExtractAssertions_WithArguments(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *result = @"test";
    XCTAssertEqualObjects(result, @"test", @"Result should be 'test'");
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 1 assertion
	if len(assertions) != 1 {
		t.Fatalf("Expected 1 assertion, found %d", len(assertions))
	}
	
	// Verify assertion has arguments
	assertion := assertions[0]
	if len(assertion.Arguments) == 0 {
		t.Error("Assertion should have arguments")
	}
	
	t.Logf("Assertion type: %s", assertion.Type)
	t.Logf("Assertion arguments: %v", assertion.Arguments)
}

// TestExtractAssertions_ZeroAssertions tests handling of methods with no assertions
func TestExtractAssertions_ZeroAssertions(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *result = @"test";
    NSLog(@"%@", result);
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 0 assertions
	if len(assertions) != 0 {
		t.Errorf("Expected 0 assertions, found %d", len(assertions))
	}
}

// TestExtractAssertions_NestedConditionals tests assertions in nested if/switch statements
func TestExtractAssertions_NestedConditionals(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    if (YES) {
        if (YES) {
            XCTAssertTrue(YES);
        }
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 1 assertion
	if len(assertions) != 1 {
		t.Fatalf("Expected 1 assertion, found %d", len(assertions))
	}
	
	// Verify it's marked as conditional
	if !assertions[0].IsConditional {
		t.Error("Assertion in nested if should be marked as conditional")
	}
}

// TestExtractAssertions_LineNumbers tests that line numbers are correctly tracked
func TestExtractAssertions_LineNumbers(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    
    XCTAssertFalse(NO);
    
    
    XCTAssertNil(nil);
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 3 assertions
	if len(assertions) != 3 {
		t.Fatalf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Verify line numbers are set and increasing
	for i, assertion := range assertions {
		if assertion.LineNumber == 0 {
			t.Errorf("Assertion %d has line number 0", i)
		}
		if i > 0 && assertion.LineNumber <= assertions[i-1].LineNumber {
			t.Errorf("Assertion %d line number (%d) should be greater than previous (%d)", 
				i, assertion.LineNumber, assertions[i-1].LineNumber)
		}
		t.Logf("Assertion %d at line %d: %s", i, assertion.LineNumber, assertion.Type)
	}
}

// TestExtractVariables_BasicVariables tests extraction of basic variable declarations
func TestExtractVariables_BasicVariables(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *name = @"test";
    int count = 42;
    BOOL flag = YES;
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract variables
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Verify we found 3 variables
	if len(variables) != 3 {
		t.Errorf("Expected 3 variables, found %d", len(variables))
	}
	
	// Verify variable names
	expectedNames := []string{"name", "count", "flag"}
	for i, expected := range expectedNames {
		if i >= len(variables) {
			break
		}
		if variables[i].Name != expected {
			t.Errorf("Variable %d: expected name %s, got %s", i, expected, variables[i].Name)
		}
	}
	
	// Verify all variables have types
	for i, variable := range variables {
		if variable.Type == "" {
			t.Errorf("Variable %d (%s) has empty type", i, variable.Name)
		}
		t.Logf("Variable %d: %s %s", i, variable.Type, variable.Name)
	}
}

// TestExtractVariables_WithInitialValues tests extraction of variable initial values
func TestExtractVariables_WithInitialValues(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *name = @"test";
    int count = 42;
    BOOL flag;
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract variables
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Verify we found 3 variables
	if len(variables) != 3 {
		t.Fatalf("Expected 3 variables, found %d", len(variables))
	}
	
	// First two variables should have initial values
	if variables[0].InitialValue == nil {
		t.Error("Variable 'name' should have initial value")
	}
	
	if variables[1].InitialValue == nil {
		t.Error("Variable 'count' should have initial value")
	}
	
	// Third variable should not have initial value
	if variables[2].InitialValue != nil {
		t.Error("Variable 'flag' should not have initial value")
	}
	
	// Log the initial values
	for i, variable := range variables {
		if variable.InitialValue != nil {
			t.Logf("Variable %d (%s) initial value: %s", i, variable.Name, *variable.InitialValue)
		} else {
			t.Logf("Variable %d (%s) has no initial value", i, variable.Name)
		}
	}
}

// TestExtractVariables_LineNumbers tests that line numbers are correctly tracked
func TestExtractVariables_LineNumbers(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *first = @"test";
    
    int second = 42;
    
    
    BOOL third = YES;
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract variables
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Verify we found 3 variables
	if len(variables) != 3 {
		t.Fatalf("Expected 3 variables, found %d", len(variables))
	}
	
	// Verify line numbers are set and increasing
	for i, variable := range variables {
		if variable.LineNumber == 0 {
			t.Errorf("Variable %d (%s) has line number 0", i, variable.Name)
		}
		if i > 0 && variable.LineNumber <= variables[i-1].LineNumber {
			t.Errorf("Variable %d (%s) line number (%d) should be greater than previous (%d)", 
				i, variable.Name, variable.LineNumber, variables[i-1].LineNumber)
		}
		t.Logf("Variable %d (%s) at line %d", i, variable.Name, variable.LineNumber)
	}
}

// TestExtractVariables_ZeroVariables tests handling of methods with no variables
func TestExtractVariables_ZeroVariables(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSLog(@"No variables here");
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract variables
	variables, err := engine.ExtractVariables(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract variables: %v", err)
	}
	
	// Verify we found 0 variables
	if len(variables) != 0 {
		t.Errorf("Expected 0 variables, found %d", len(variables))
	}
}

// TestExtractMethodCalls_BasicCalls tests extraction of basic method calls
func TestExtractMethodCalls_BasicCalls(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *str = @"test";
    NSString *upper = [str uppercaseString];
    NSLog(@"%@", upper);
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract method calls
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Verify we found at least 1 method call (uppercaseString)
	if len(methodCalls) == 0 {
		t.Error("Expected to find method calls")
	}
	
	// Log all method calls found
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s] with %d arguments at line %d", 
			i, call.Receiver, call.Selector, len(call.Arguments), call.LineNumber)
	}
}

// TestExtractMethodCalls_WithArguments tests extraction of method call arguments
func TestExtractMethodCalls_WithArguments(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *result = [NSString stringWithFormat:@"Value: %d", 42];
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract method calls
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Verify we found at least 1 method call
	if len(methodCalls) == 0 {
		t.Fatal("Expected to find method calls")
	}
	
	// Log method calls with arguments
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s]", i, call.Receiver, call.Selector)
		if len(call.Arguments) > 0 {
			t.Logf("  Arguments: %v", call.Arguments)
		}
	}
}

// TestExtractMethodCalls_LineNumbers tests that line numbers are correctly tracked
func TestExtractMethodCalls_LineNumbers(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *str = @"test";
    [str uppercaseString];
    
    [str lowercaseString];
    
    
    [str length];
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract method calls
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Verify we found at least 3 method calls
	if len(methodCalls) < 3 {
		t.Errorf("Expected at least 3 method calls, found %d", len(methodCalls))
	}
	
	// Verify line numbers are set
	for i, call := range methodCalls {
		if call.LineNumber == 0 {
			t.Errorf("Method call %d has line number 0", i)
		}
		t.Logf("Method call %d at line %d: [%s %s]", i, call.LineNumber, call.Receiver, call.Selector)
	}
}

// TestExtractMethodCalls_ZeroCalls tests handling of methods with no method calls
func TestExtractMethodCalls_ZeroCalls(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    int x = 42;
    int y = x + 1;
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract method calls
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Verify we found 0 method calls
	if len(methodCalls) != 0 {
		t.Errorf("Expected 0 method calls, found %d", len(methodCalls))
		for i, call := range methodCalls {
			t.Logf("Unexpected method call %d: [%s %s]", i, call.Receiver, call.Selector)
		}
	}
}

// TestExtractMethodCalls_ClassMethods tests extraction of class method calls
func TestExtractMethodCalls_ClassMethods(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *str = [NSString stringWithString:@"test"];
    NSArray *arr = [NSArray arrayWithObject:str];
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract method calls
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Verify we found at least 2 method calls
	if len(methodCalls) < 2 {
		t.Errorf("Expected at least 2 method calls, found %d", len(methodCalls))
	}
	
	// Log method calls
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s] with %d arguments", 
			i, call.Receiver, call.Selector, len(call.Arguments))
	}
}

// TestExtractMethodCalls_NestedCalls tests extraction of nested method calls
func TestExtractMethodCalls_NestedCalls(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSString *result = [[NSString alloc] initWithString:@"test"];
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract method calls
	methodCalls, err := engine.ExtractMethodCalls(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract method calls: %v", err)
	}
	
	// Verify we found at least 2 method calls (alloc and initWithString)
	if len(methodCalls) < 2 {
		t.Errorf("Expected at least 2 method calls (nested), found %d", len(methodCalls))
	}
	
	// Log method calls
	for i, call := range methodCalls {
		t.Logf("Method call %d: [%s %s]", i, call.Receiver, call.Selector)
	}
}

// TestAnalyzeControlFlow_UnreachableAfterReturn tests detection of unreachable code after return
func TestAnalyzeControlFlow_UnreachableAfterReturn(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    return;
    XCTAssertFalse(NO);  // Unreachable
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 2 assertions
	if len(assertions) != 2 {
		t.Fatalf("Expected 2 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// First assertion should be reachable
	if !assertions[0].IsReachable {
		t.Error("First assertion (before return) should be reachable")
	}
	
	// Second assertion should be unreachable
	if assertions[1].IsReachable {
		t.Error("Second assertion (after return) should be unreachable")
	}
	
	t.Logf("Assertion 1 (line %d): reachable=%v", assertions[0].LineNumber, assertions[0].IsReachable)
	t.Logf("Assertion 2 (line %d): reachable=%v", assertions[1].LineNumber, assertions[1].IsReachable)
}

// TestAnalyzeControlFlow_ReachableInConditionalReturn tests that assertions after conditional returns are reachable
func TestAnalyzeControlFlow_ReachableInConditionalReturn(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    if (YES) {
        return;
    }
    XCTAssertTrue(YES);  // Reachable (return is in conditional)
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 1 assertion
	if len(assertions) != 1 {
		t.Fatalf("Expected 1 assertion, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// Assertion should be reachable (return is in conditional block)
	if !assertions[0].IsReachable {
		t.Error("Assertion after conditional return should be reachable")
	}
	
	t.Logf("Assertion (line %d): reachable=%v", assertions[0].LineNumber, assertions[0].IsReachable)
}

// TestAnalyzeControlFlow_AlwaysFalseCondition tests detection of unreachable code in always-false conditions
func TestAnalyzeControlFlow_AlwaysFalseCondition(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    
    if (NO) {
        XCTAssertFalse(NO);  // Unreachable
    }
    
    XCTAssertNotNil(@"test");  // Reachable
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 3 assertions
	if len(assertions) != 3 {
		t.Fatalf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// First assertion should be reachable
	if !assertions[0].IsReachable {
		t.Error("First assertion should be reachable")
	}
	
	// Second assertion (inside if (NO)) should be unreachable
	if assertions[1].IsReachable {
		t.Error("Assertion inside if (NO) should be unreachable")
	}
	
	// Third assertion should be reachable
	if !assertions[2].IsReachable {
		t.Error("Third assertion (after if block) should be reachable")
	}
	
	for i, assertion := range assertions {
		t.Logf("Assertion %d (line %d): reachable=%v", i+1, assertion.LineNumber, assertion.IsReachable)
	}
}

// TestAnalyzeControlFlow_AlwaysFalseWithZero tests detection of if (0) as always false
func TestAnalyzeControlFlow_AlwaysFalseWithZero(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    if (0) {
        XCTAssertTrue(YES);  // Unreachable
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 1 assertion
	if len(assertions) != 1 {
		t.Fatalf("Expected 1 assertion, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// Assertion should be unreachable
	if assertions[0].IsReachable {
		t.Error("Assertion inside if (0) should be unreachable")
	}
	
	t.Logf("Assertion (line %d): reachable=%v", assertions[0].LineNumber, assertions[0].IsReachable)
}

// TestAnalyzeControlFlow_MultipleReturns tests handling of multiple return statements
func TestAnalyzeControlFlow_MultipleReturns(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    return;
    XCTAssertFalse(NO);  // Unreachable
    return;
    XCTAssertNil(nil);   // Unreachable
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 3 assertions
	if len(assertions) != 3 {
		t.Fatalf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// First assertion should be reachable
	if !assertions[0].IsReachable {
		t.Error("First assertion should be reachable")
	}
	
	// Second and third assertions should be unreachable
	if assertions[1].IsReachable {
		t.Error("Second assertion (after first return) should be unreachable")
	}
	
	if assertions[2].IsReachable {
		t.Error("Third assertion (after first return) should be unreachable")
	}
	
	for i, assertion := range assertions {
		t.Logf("Assertion %d (line %d): reachable=%v", i+1, assertion.LineNumber, assertion.IsReachable)
	}
}

// TestAnalyzeControlFlow_NoUnreachableCode tests that all assertions are reachable in normal code
func TestAnalyzeControlFlow_NoUnreachableCode(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);
    XCTAssertFalse(NO);
    XCTAssertNil(nil);
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 3 assertions
	if len(assertions) != 3 {
		t.Fatalf("Expected 3 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// All assertions should be reachable
	for i, assertion := range assertions {
		if !assertion.IsReachable {
			t.Errorf("Assertion %d should be reachable", i+1)
		}
		t.Logf("Assertion %d (line %d): reachable=%v", i+1, assertion.LineNumber, assertion.IsReachable)
	}
}

// TestAnalyzeControlFlow_ConditionalAndUnconditional tests mixed conditional and unconditional assertions
func TestAnalyzeControlFlow_ConditionalAndUnconditional(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    XCTAssertTrue(YES);  // Unconditional, reachable
    
    if (YES) {
        XCTAssertEqual(1, 1);  // Conditional, reachable
    }
    
    if (NO) {
        XCTAssertFalse(NO);  // Conditional, unreachable
    }
    
    XCTAssertNotNil(@"test");  // Unconditional, reachable
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 4 assertions
	if len(assertions) != 4 {
		t.Fatalf("Expected 4 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// Check conditional flags
	if assertions[0].IsConditional {
		t.Error("First assertion should not be conditional")
	}
	if !assertions[1].IsConditional {
		t.Error("Second assertion should be conditional")
	}
	if !assertions[2].IsConditional {
		t.Error("Third assertion should be conditional")
	}
	if assertions[3].IsConditional {
		t.Error("Fourth assertion should not be conditional")
	}
	
	// Check reachability
	if !assertions[0].IsReachable {
		t.Error("First assertion should be reachable")
	}
	if !assertions[1].IsReachable {
		t.Error("Second assertion (in if (YES)) should be reachable")
	}
	if assertions[2].IsReachable {
		t.Error("Third assertion (in if (NO)) should be unreachable")
	}
	if !assertions[3].IsReachable {
		t.Error("Fourth assertion should be reachable")
	}
	
	for i, assertion := range assertions {
		t.Logf("Assertion %d (line %d): conditional=%v, reachable=%v", 
			i+1, assertion.LineNumber, assertion.IsConditional, assertion.IsReachable)
	}
}

// TestAnalyzeControlFlow_EmptyMethod tests control flow analysis on method with no assertions
func TestAnalyzeControlFlow_EmptyMethod(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    NSLog(@"No assertions");
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 0 assertions
	if len(assertions) != 0 {
		t.Fatalf("Expected 0 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow (should not panic on empty assertions)
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// Should still be empty
	if len(assertions) != 0 {
		t.Errorf("Expected 0 assertions after control flow analysis, found %d", len(assertions))
	}
}

// TestAnalyzeControlFlow_NestedIfStatements tests control flow with nested if statements
func TestAnalyzeControlFlow_NestedIfStatements(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.m")
	
	testCode := `
#import <Foundation/Foundation.h>

@interface TestClass : NSObject
@end

@implementation TestClass

- (void)testMethod {
    if (YES) {
        if (NO) {
            XCTAssertTrue(YES);  // Unreachable (nested in always-false)
        }
    }
    XCTAssertFalse(NO);  // Reachable
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
	
	// Find the test method
	methodCursor, found := engine.FindMethodByName(tu, "testMethod")
	if !found {
		t.Fatal("Could not find testMethod")
	}
	
	// Extract assertions
	assertions, err := engine.ExtractAssertions(methodCursor)
	if err != nil {
		t.Fatalf("Failed to extract assertions: %v", err)
	}
	
	// Verify we found 2 assertions
	if len(assertions) != 2 {
		t.Fatalf("Expected 2 assertions, found %d", len(assertions))
	}
	
	// Analyze control flow
	assertions = engine.AnalyzeControlFlow(methodCursor, assertions)
	
	// First assertion (nested in if (NO)) should be unreachable
	if assertions[0].IsReachable {
		t.Error("First assertion (in nested if (NO)) should be unreachable")
	}
	
	// Second assertion should be reachable
	if !assertions[1].IsReachable {
		t.Error("Second assertion should be reachable")
	}
	
	for i, assertion := range assertions {
		t.Logf("Assertion %d (line %d): conditional=%v, reachable=%v", 
			i+1, assertion.LineNumber, assertion.IsConditional, assertion.IsReachable)
	}
}
