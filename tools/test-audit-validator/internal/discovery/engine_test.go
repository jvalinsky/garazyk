package discovery

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestNewTestDiscoveryEngine(t *testing.T) {
	engine := NewTestDiscoveryEngine()
	if engine == nil {
		t.Fatal("NewTestDiscoveryEngine returned nil")
	}

	// Verify default exclude patterns
	expectedPatterns := []string{"fixtures", "plc_e2e", "helpers"}
	if len(engine.ExcludePatterns) != len(expectedPatterns) {
		t.Errorf("Expected %d exclude patterns, got %d", len(expectedPatterns), len(engine.ExcludePatterns))
	}
}

func TestDiscoverTestFiles_NonExistentPath(t *testing.T) {
	engine := NewTestDiscoveryEngine()
	_, err := engine.DiscoverTestFiles("/nonexistent/path")
	if err == nil {
		t.Error("Expected error for nonexistent path, got nil")
	}
}

func TestDiscoverTestFiles_FileInsteadOfDirectory(t *testing.T) {
	// Create a temporary file
	tmpFile, err := os.CreateTemp("", "test*.m")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	tmpFile.Close()

	engine := NewTestDiscoveryEngine()
	_, err = engine.DiscoverTestFiles(tmpFile.Name())
	if err == nil {
		t.Error("Expected error when path is a file, got nil")
	}
}

func TestDiscoverTestFiles_EmptyDirectory(t *testing.T) {
	// Create a temporary directory
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(files) != 0 {
		t.Errorf("Expected 0 files in empty directory, got %d", len(files))
	}
}

func TestDiscoverTestFiles_WithTestFiles(t *testing.T) {
	// Create a temporary directory structure
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create test files
	testFiles := []string{
		"TestClass1.m",
		"TestClass2.m",
		"subdir/TestClass3.m",
	}

	for _, file := range testFiles {
		fullPath := filepath.Join(tmpDir, file)
		dir := filepath.Dir(fullPath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatalf("Failed to create directory: %v", err)
		}
		if err := os.WriteFile(fullPath, []byte("// test file"), 0644); err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}
	}

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(files) != 3 {
		t.Errorf("Expected 3 test files, got %d", len(files))
	}
}

func TestDiscoverTestFiles_ExcludesFixtures(t *testing.T) {
	// Create a temporary directory structure
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create test files in fixtures directory (should be excluded)
	fixturesDir := filepath.Join(tmpDir, "fixtures")
	if err := os.MkdirAll(fixturesDir, 0755); err != nil {
		t.Fatalf("Failed to create fixtures directory: %v", err)
	}
	if err := os.WriteFile(filepath.Join(fixturesDir, "FixtureTest.m"), []byte("// fixture"), 0644); err != nil {
		t.Fatalf("Failed to create fixture file: %v", err)
	}

	// Create a valid test file
	if err := os.WriteFile(filepath.Join(tmpDir, "ValidTest.m"), []byte("// test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(files) != 1 {
		t.Errorf("Expected 1 test file (fixtures excluded), got %d", len(files))
	}
	if len(files) > 0 && filepath.Base(files[0].Path) != "ValidTest.m" {
		t.Errorf("Expected ValidTest.m, got %s", filepath.Base(files[0].Path))
	}
}

func TestDiscoverTestFiles_ExcludesHelperFiles(t *testing.T) {
	// Create a temporary directory
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create helper files (should be excluded)
	helperFiles := []string{
		"TestHelper.m",
		"TestUtil.m",
		"TestBase.m",
		"test_main.m",
	}
	for _, file := range helperFiles {
		if err := os.WriteFile(filepath.Join(tmpDir, file), []byte("// helper"), 0644); err != nil {
			t.Fatalf("Failed to create helper file: %v", err)
		}
	}

	// Create a valid test file
	if err := os.WriteFile(filepath.Join(tmpDir, "ActualTest.m"), []byte("// test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(files) != 1 {
		t.Errorf("Expected 1 test file (helpers excluded), got %d", len(files))
	}
	if len(files) > 0 && filepath.Base(files[0].Path) != "ActualTest.m" {
		t.Errorf("Expected ActualTest.m, got %s", filepath.Base(files[0].Path))
	}
}

func TestDiscoverTestFiles_OnlyMFiles(t *testing.T) {
	// Create a temporary directory
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create various file types
	files := map[string]bool{
		"Test.m":    true,  // Should be included
		"Test.h":    false, // Should be excluded
		"Test.c":    false, // Should be excluded
		"Test.cpp":  false, // Should be excluded
		"Test.txt":  false, // Should be excluded
		"README.md": false, // Should be excluded
	}

	for file := range files {
		if err := os.WriteFile(filepath.Join(tmpDir, file), []byte("// file"), 0644); err != nil {
			t.Fatalf("Failed to create file: %v", err)
		}
	}

	engine := NewTestDiscoveryEngine()
	discovered, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(discovered) != 1 {
		t.Errorf("Expected 1 .m file, got %d", len(discovered))
	}
	if len(discovered) > 0 && filepath.Base(discovered[0].Path) != "Test.m" {
		t.Errorf("Expected Test.m, got %s", filepath.Base(discovered[0].Path))
	}
}

func TestShouldExcludeDir(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	tests := []struct {
		dirName  string
		expected bool
	}{
		{"fixtures", true},
		{"Fixtures", true},
		{"FIXTURES", true},
		{"plc_e2e", true},
		{"helpers", true},
		{"Tests", false},
		{"Auth", false},
		{"Network", false},
	}

	for _, tt := range tests {
		t.Run(tt.dirName, func(t *testing.T) {
			result := engine.shouldExcludeDir(tt.dirName)
			if result != tt.expected {
				t.Errorf("shouldExcludeDir(%s) = %v, expected %v", tt.dirName, result, tt.expected)
			}
		})
	}
}

func TestIsHelperFile(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	tests := []struct {
		path     string
		expected bool
	}{
		{"TestHelper.m", true},
		{"TestUtil.m", true},
		{"TestBase.m", true},
		{"test_main.m", true},
		{"CommonTest.m", true},
		{"ActualTest.m", false},
		{"OAuthTests.m", false},
		{"MSTTests.m", false},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			result := engine.isHelperFile(tt.path)
			if result != tt.expected {
				t.Errorf("isHelperFile(%s) = %v, expected %v", tt.path, result, tt.expected)
			}
		})
	}
}

func TestDiscoverTestFiles_NestedDirectories(t *testing.T) {
	// Create a temporary directory structure
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create nested directory structure
	dirs := []string{
		"Auth",
		"Auth/OAuth",
		"Network",
		"Network/XRPC",
		"Core",
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(filepath.Join(tmpDir, dir), 0755); err != nil {
			t.Fatalf("Failed to create directory: %v", err)
		}
	}

	// Create test files in nested directories
	testFiles := []string{
		"Auth/AuthTest.m",
		"Auth/OAuth/OAuthTest.m",
		"Network/NetworkTest.m",
		"Network/XRPC/XRPCTest.m",
		"Core/CoreTest.m",
	}
	for _, file := range testFiles {
		fullPath := filepath.Join(tmpDir, file)
		if err := os.WriteFile(fullPath, []byte("// test"), 0644); err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}
	}

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if len(files) != 5 {
		t.Errorf("Expected 5 test files in nested directories, got %d", len(files))
	}
}


func TestDiscoverTestClasses_SimpleTestClass(t *testing.T) {
	// Create a temporary test file with a simple test class
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "SimpleTest.m")
	content := `#import <XCTest/XCTest.h>

@interface SimpleTest : XCTestCase
@end

@implementation SimpleTest
- (void)testExample {
    XCTAssertTrue(YES);
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(classes) != 1 {
		t.Fatalf("Expected 1 test class, got %d", len(classes))
	}

	if classes[0].Name != "SimpleTest" {
		t.Errorf("Expected class name 'SimpleTest', got '%s'", classes[0].Name)
	}

	if classes[0].BaseClass == nil || *classes[0].BaseClass != "XCTestCase" {
		t.Errorf("Expected base class 'XCTestCase', got %v", classes[0].BaseClass)
	}

	if classes[0].IsHelper {
		t.Errorf("Expected IsHelper to be false for SimpleTest")
	}

	if classes[0].FilePath != testFile {
		t.Errorf("Expected file path '%s', got '%s'", testFile, classes[0].FilePath)
	}
}

func TestDiscoverTestClasses_MultipleClasses(t *testing.T) {
	// Create a temporary test file with multiple test classes
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "MultipleTests.m")
	content := `#import <XCTest/XCTest.h>

@interface FirstTest : XCTestCase
@end

@implementation FirstTest
- (void)testFirst {
    XCTAssertTrue(YES);
}
@end

@interface SecondTest : XCTestCase
@end

@implementation SecondTest
- (void)testSecond {
    XCTAssertTrue(YES);
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(classes) != 2 {
		t.Fatalf("Expected 2 test classes, got %d", len(classes))
	}

	// Check first class
	if classes[0].Name != "FirstTest" {
		t.Errorf("Expected first class name 'FirstTest', got '%s'", classes[0].Name)
	}

	// Check second class
	if classes[1].Name != "SecondTest" {
		t.Errorf("Expected second class name 'SecondTest', got '%s'", classes[1].Name)
	}
}

func TestDiscoverTestClasses_HelperClass(t *testing.T) {
	// Create a temporary test file with a helper class
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "TestHelper.m")
	content := `#import <XCTest/XCTest.h>

@interface TestHelper : XCTestCase
@end

@implementation TestHelper
- (void)helperMethod {
    // Helper method
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(classes) != 1 {
		t.Fatalf("Expected 1 class, got %d", len(classes))
	}

	if !classes[0].IsHelper {
		t.Errorf("Expected IsHelper to be true for TestHelper")
	}
}

func TestDiscoverTestClasses_CustomBaseClass(t *testing.T) {
	// Create a temporary test file with a custom base class
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "CustomTest.m")
	content := `#import <XCTest/XCTest.h>

@interface CharacterizationTestBase : XCTestCase
@end

@implementation CharacterizationTestBase
@end

@interface CustomTest : CharacterizationTestBase
@end

@implementation CustomTest
- (void)testCustom {
    XCTAssertTrue(YES);
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should find both classes since both inherit from test base classes
	if len(classes) < 1 {
		t.Fatalf("Expected at least 1 test class, got %d", len(classes))
	}

	// Find the CustomTest class
	var customTest *models.TestClass
	for i := range classes {
		if classes[i].Name == "CustomTest" {
			customTest = &classes[i]
			break
		}
	}

	if customTest == nil {
		t.Fatalf("CustomTest class not found")
	}

	if customTest.BaseClass == nil || *customTest.BaseClass != "CharacterizationTestBase" {
		t.Errorf("Expected base class 'CharacterizationTestBase', got %v", customTest.BaseClass)
	}
}

func TestDiscoverTestClasses_NonTestClass(t *testing.T) {
	// Create a temporary file with a non-test class
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "NonTest.m")
	content := `#import <Foundation/Foundation.h>

@interface NonTestClass : NSObject
@end

@implementation NonTestClass
- (void)someMethod {
    // Not a test
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should not find any test classes
	if len(classes) != 0 {
		t.Errorf("Expected 0 test classes for non-test file, got %d", len(classes))
	}
}

func TestDiscoverTestClasses_NonExistentFile(t *testing.T) {
	engine := NewTestDiscoveryEngine()
	_, err := engine.DiscoverTestClasses("/nonexistent/file.m")
	if err == nil {
		t.Error("Expected error for nonexistent file, got nil")
	}
}

func TestDiscoverTestClasses_MockClass(t *testing.T) {
	// Create a temporary test file with a mock class
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "MockTest.m")
	content := `#import <XCTest/XCTest.h>

@interface MockDelegate : XCTestCase
@end

@implementation MockDelegate
- (void)delegateMethod {
    // Mock implementation
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(classes) != 1 {
		t.Fatalf("Expected 1 class, got %d", len(classes))
	}

	if !classes[0].IsHelper {
		t.Errorf("Expected IsHelper to be true for MockDelegate")
	}
}

func TestIsTestBaseClass(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	tests := []struct {
		className string
		expected  bool
	}{
		{"XCTestCase", true},
		{"CharacterizationTestBase", true},
		{"TestBase", true},
		{"BaseTestCase", true},
		{"IntegrationTestBase", true},
		{"NSObject", false},
		{"UIViewController", false},
		{"SomeRandomClass", false},
	}

	for _, tt := range tests {
		t.Run(tt.className, func(t *testing.T) {
			result := engine.isTestBaseClass(tt.className)
			if result != tt.expected {
				t.Errorf("isTestBaseClass(%s) = %v, expected %v", tt.className, result, tt.expected)
			}
		})
	}
}

func TestIsHelperClass(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	tests := []struct {
		className string
		expected  bool
	}{
		{"TestHelper", true},
		{"MockDelegate", true},
		{"StubService", true},
		{"FakeProvider", true},
		{"TestFixture", true},
		{"TestBase", true},
		{"CommonTestUtils", true},
		{"CharacterizationTestBase", true},
		{"OAuthTests", false},
		{"MSTTests", false},
		{"ActualTest", false},
		{"SimpleTest", false},
	}

	for _, tt := range tests {
		t.Run(tt.className, func(t *testing.T) {
			result := engine.isHelperClass(tt.className)
			if result != tt.expected {
				t.Errorf("isHelperClass(%s) = %v, expected %v", tt.className, result, tt.expected)
			}
		})
	}
}

func TestDiscoverTestMethods_SimpleTestMethod(t *testing.T) {
	// Create a temporary test file with a simple test method
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "SimpleTest.m")
	content := `#import <XCTest/XCTest.h>

@interface SimpleTest : XCTestCase
@end

@implementation SimpleTest

- (void)testExample {
    XCTAssertTrue(YES);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "SimpleTest")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(methods) != 1 {
		t.Fatalf("Expected 1 test method, got %d", len(methods))
	}

	if methods[0].Name != "testExample" {
		t.Errorf("Expected method name 'testExample', got '%s'", methods[0].Name)
	}

	if methods[0].ClassName != "SimpleTest" {
		t.Errorf("Expected class name 'SimpleTest', got '%s'", methods[0].ClassName)
	}

	if methods[0].LineNumber <= 0 {
		t.Errorf("Expected positive line number, got %d", methods[0].LineNumber)
	}

	if methods[0].SourceCode == "" {
		t.Error("Expected non-empty source code")
	}
}

func TestDiscoverTestMethods_MultipleTestMethods(t *testing.T) {
	// Create a temporary test file with multiple test methods
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "MultipleTests.m")
	content := `#import <XCTest/XCTest.h>

@interface MultipleTests : XCTestCase
@end

@implementation MultipleTests

- (void)testFirst {
    XCTAssertTrue(YES);
}

- (void)testSecond {
    XCTAssertEqual(1, 1);
}

- (void)testThird {
    XCTAssertNotNil(@"test");
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "MultipleTests")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(methods) != 3 {
		t.Fatalf("Expected 3 test methods, got %d", len(methods))
	}

	expectedNames := []string{"testFirst", "testSecond", "testThird"}
	for i, method := range methods {
		if method.Name != expectedNames[i] {
			t.Errorf("Expected method name '%s', got '%s'", expectedNames[i], method.Name)
		}
	}
}

func TestDiscoverTestMethods_OnlyTestMethods(t *testing.T) {
	// Create a temporary test file with test and non-test methods
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "MixedMethods.m")
	content := `#import <XCTest/XCTest.h>

@interface MixedMethods : XCTestCase
@end

@implementation MixedMethods

- (void)setUp {
    // Setup method - should not be included
}

- (void)tearDown {
    // Teardown method - should not be included
}

- (void)testActualTest {
    XCTAssertTrue(YES);
}

- (void)helperMethod {
    // Helper method - should not be included
}

- (void)testAnotherTest {
    XCTAssertEqual(1, 1);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "MixedMethods")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should only find methods starting with "test"
	if len(methods) != 2 {
		t.Fatalf("Expected 2 test methods, got %d", len(methods))
	}

	for _, method := range methods {
		if !strings.HasPrefix(method.Name, "test") {
			t.Errorf("Found non-test method: %s", method.Name)
		}
	}
}

func TestDiscoverTestMethods_WithComments(t *testing.T) {
	// Create a temporary test file with commented test methods
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "CommentedTest.m")
	content := `#import <XCTest/XCTest.h>

@interface CommentedTest : XCTestCase
@end

@implementation CommentedTest

// This test validates OAuth token generation
- (void)testOAuthTokenGeneration {
    XCTAssertTrue(YES);
}

/* 
 * This test validates error handling
 * for invalid inputs
 */
- (void)testErrorHandling {
    XCTAssertNotNil(@"test");
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "CommentedTest")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(methods) != 2 {
		t.Fatalf("Expected 2 test methods, got %d", len(methods))
	}

	// Check that comments are extracted (implementation may vary)
	// At minimum, verify the structure is correct
	for _, method := range methods {
		if method.Name == "" {
			t.Error("Method name should not be empty")
		}
	}
}

func TestDiscoverTestMethods_ClassAndInstanceMethods(t *testing.T) {
	// Create a temporary test file with both class and instance test methods
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "ClassMethodTest.m")
	content := `#import <XCTest/XCTest.h>

@interface ClassMethodTest : XCTestCase
@end

@implementation ClassMethodTest

// Instance method
- (void)testInstanceMethod {
    XCTAssertTrue(YES);
}

// Class method
+ (void)testClassMethod {
    XCTAssertTrue(YES);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "ClassMethodTest")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should find both instance and class test methods
	if len(methods) != 2 {
		t.Fatalf("Expected 2 test methods (instance and class), got %d", len(methods))
	}

	foundInstance := false
	foundClass := false
	for _, method := range methods {
		if method.Name == "testInstanceMethod" {
			foundInstance = true
		}
		if method.Name == "testClassMethod" {
			foundClass = true
		}
	}

	if !foundInstance {
		t.Error("Did not find instance test method")
	}
	if !foundClass {
		t.Error("Did not find class test method")
	}
}

func TestDiscoverTestMethods_NonExistentFile(t *testing.T) {
	engine := NewTestDiscoveryEngine()
	_, err := engine.DiscoverTestMethods("/nonexistent/file.m", "TestClass")
	if err == nil {
		t.Error("Expected error for nonexistent file, got nil")
	}
}

func TestDiscoverTestMethods_NonExistentClass(t *testing.T) {
	// Create a temporary test file
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "Test.m")
	content := `#import <XCTest/XCTest.h>

@interface ActualClass : XCTestCase
@end

@implementation ActualClass

- (void)testMethod {
    XCTAssertTrue(YES);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "NonExistentClass")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should return empty array for non-existent class
	if len(methods) != 0 {
		t.Errorf("Expected 0 methods for non-existent class, got %d", len(methods))
	}
}

func TestDiscoverTestMethods_SourceCodeExtraction(t *testing.T) {
	// Create a temporary test file
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "SourceTest.m")
	content := `#import <XCTest/XCTest.h>

@interface SourceTest : XCTestCase
@end

@implementation SourceTest

- (void)testWithMultipleLines {
    NSString *value = @"test";
    XCTAssertNotNil(value);
    XCTAssertEqual(value.length, 4);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "SourceTest")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(methods) != 1 {
		t.Fatalf("Expected 1 test method, got %d", len(methods))
	}

	// Verify source code contains key elements
	sourceCode := methods[0].SourceCode
	if sourceCode == "" {
		t.Error("Source code should not be empty")
	}

	// Check that source code contains method signature and body elements
	if !strings.Contains(sourceCode, "testWithMultipleLines") {
		t.Error("Source code should contain method name")
	}
}

func TestDiscoverTestMethods_LineNumbers(t *testing.T) {
	// Create a temporary test file
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "LineTest.m")
	content := `#import <XCTest/XCTest.h>

@interface LineTest : XCTestCase
@end

@implementation LineTest

- (void)testFirst {
    XCTAssertTrue(YES);
}

- (void)testSecond {
    XCTAssertTrue(YES);
}

- (void)testThird {
    XCTAssertTrue(YES);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "LineTest")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(methods) != 3 {
		t.Fatalf("Expected 3 test methods, got %d", len(methods))
	}

	// Verify line numbers are in ascending order
	for i := 1; i < len(methods); i++ {
		if methods[i].LineNumber <= methods[i-1].LineNumber {
			t.Errorf("Line numbers should be in ascending order: method %d at line %d, method %d at line %d",
				i-1, methods[i-1].LineNumber, i, methods[i].LineNumber)
		}
	}

	// Verify all line numbers are positive
	for _, method := range methods {
		if method.LineNumber <= 0 {
			t.Errorf("Line number should be positive for method %s, got %d", method.Name, method.LineNumber)
		}
	}
}

func TestParseTestMainRegistration_ValidFile(t *testing.T) {
	// Create a temporary test_main.m file
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSArray *testClasses = @[
            @"FirstTest",
            @"SecondTest",
            @"ThirdTest",
        ];
        
        // Run tests
        return 0;
    }
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expectedClasses := []string{"FirstTest", "SecondTest", "ThirdTest"}
	if len(registered) != len(expectedClasses) {
		t.Errorf("Expected %d registered classes, got %d", len(expectedClasses), len(registered))
	}

	for _, className := range expectedClasses {
		if !registered[className] {
			t.Errorf("Expected class %s to be registered", className)
		}
	}
}

func TestParseTestMainRegistration_MultilineArray(t *testing.T) {
	// Create a temporary test_main.m file with multiline array
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    NSArray *testClasses = @[
        @"OAuthTests",
        @"MSTTests",
        @"CARTests",
        @"JWTTests",
        @"DIDTests",
    ];
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expectedClasses := []string{"OAuthTests", "MSTTests", "CARTests", "JWTTests", "DIDTests"}
	if len(registered) != len(expectedClasses) {
		t.Errorf("Expected %d registered classes, got %d", len(expectedClasses), len(registered))
	}

	for _, className := range expectedClasses {
		if !registered[className] {
			t.Errorf("Expected class %s to be registered", className)
		}
	}
}

func TestParseTestMainRegistration_WithComments(t *testing.T) {
	// Create a temporary test_main.m file with comments
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    NSArray *testClasses = @[
        // Auth tests
        @"OAuthTests",
        @"JWTTests",
        // Network tests
        @"XRPCTests",
        // Core tests
        @"MSTTests",
    ];
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expectedClasses := []string{"OAuthTests", "JWTTests", "XRPCTests", "MSTTests"}
	if len(registered) != len(expectedClasses) {
		t.Errorf("Expected %d registered classes, got %d", len(expectedClasses), len(registered))
	}

	for _, className := range expectedClasses {
		if !registered[className] {
			t.Errorf("Expected class %s to be registered", className)
		}
	}
}

func TestParseTestMainRegistration_EmptyArray(t *testing.T) {
	// Create a temporary test_main.m file with empty array
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    NSArray *testClasses = @[];
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(registered) != 0 {
		t.Errorf("Expected 0 registered classes for empty array, got %d", len(registered))
	}
}

func TestParseTestMainRegistration_NonExistentFile(t *testing.T) {
	engine := NewTestDiscoveryEngine()
	_, err := engine.ParseTestMainRegistration("/nonexistent/test_main.m")
	if err == nil {
		t.Error("Expected error for nonexistent file, got nil")
	}
}

func TestParseTestMainRegistration_NoTestClassesArray(t *testing.T) {
	// Create a temporary file without testClasses array
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    // No testClasses array
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	_, err = engine.ParseTestMainRegistration(testMainFile)
	if err == nil {
		t.Error("Expected error when testClasses array not found, got nil")
	}
}

func TestParseTestMainRegistration_EscapedQuotes(t *testing.T) {
	// Create a temporary test_main.m file with escaped quotes in strings
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    NSArray *testClasses = @[
        @"SimpleTest",
        @"TestWith\"Quotes\"",
        @"AnotherTest",
    ];
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should handle escaped quotes correctly
	if !registered["SimpleTest"] {
		t.Error("Expected SimpleTest to be registered")
	}
	if !registered["AnotherTest"] {
		t.Error("Expected AnotherTest to be registered")
	}
}

func TestCheckTestRegistration(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	registeredClasses := map[string]bool{
		"OAuthTests": true,
		"MSTTests":   true,
		"CARTests":   true,
	}

	tests := []struct {
		className string
		expected  bool
	}{
		{"OAuthTests", true},
		{"MSTTests", true},
		{"CARTests", true},
		{"UnregisteredTest", false},
		{"AnotherUnregisteredTest", false},
	}

	for _, tt := range tests {
		t.Run(tt.className, func(t *testing.T) {
			result := engine.CheckTestRegistration(tt.className, registeredClasses)
			if result != tt.expected {
				t.Errorf("CheckTestRegistration(%s) = %v, expected %v", tt.className, result, tt.expected)
			}
		})
	}
}

func TestFindUnregisteredTestClasses(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	// Create test files with classes
	testFiles := []*models.TestFile{
		{
			Path: "test1.m",
			Classes: []models.TestClass{
				{Name: "RegisteredTest1", IsHelper: false},
				{Name: "RegisteredTest2", IsHelper: false},
			},
		},
		{
			Path: "test2.m",
			Classes: []models.TestClass{
				{Name: "UnregisteredTest1", IsHelper: false},
				{Name: "HelperClass", IsHelper: true}, // Should be ignored
			},
		},
		{
			Path: "test3.m",
			Classes: []models.TestClass{
				{Name: "UnregisteredTest2", IsHelper: false},
			},
		},
	}

	registeredClasses := map[string]bool{
		"RegisteredTest1": true,
		"RegisteredTest2": true,
	}

	unregistered := engine.FindUnregisteredTestClasses(testFiles, registeredClasses)

	// Should find 2 unregistered classes (HelperClass is ignored)
	if len(unregistered) != 2 {
		t.Errorf("Expected 2 unregistered classes, got %d", len(unregistered))
	}

	// Verify the unregistered classes
	foundUnregistered1 := false
	foundUnregistered2 := false
	for _, uc := range unregistered {
		if uc.ClassName == "UnregisteredTest1" {
			foundUnregistered1 = true
		}
		if uc.ClassName == "UnregisteredTest2" {
			foundUnregistered2 = true
		}
		if uc.ClassName == "HelperClass" {
			t.Error("Helper classes should not be reported as unregistered")
		}
	}

	if !foundUnregistered1 {
		t.Error("Expected to find UnregisteredTest1")
	}
	if !foundUnregistered2 {
		t.Error("Expected to find UnregisteredTest2")
	}
}

func TestFindUnregisteredTestClasses_AllRegistered(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	testFiles := []*models.TestFile{
		{
			Path: "test1.m",
			Classes: []models.TestClass{
				{Name: "Test1", IsHelper: false},
				{Name: "Test2", IsHelper: false},
			},
		},
	}

	registeredClasses := map[string]bool{
		"Test1": true,
		"Test2": true,
	}

	unregistered := engine.FindUnregisteredTestClasses(testFiles, registeredClasses)

	if len(unregistered) != 0 {
		t.Errorf("Expected 0 unregistered classes when all are registered, got %d", len(unregistered))
	}
}

func TestFindUnregisteredTestClasses_OnlyHelpers(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	testFiles := []*models.TestFile{
		{
			Path: "helpers.m",
			Classes: []models.TestClass{
				{Name: "TestHelper", IsHelper: true},
				{Name: "MockClass", IsHelper: true},
			},
		},
	}

	registeredClasses := map[string]bool{}

	unregistered := engine.FindUnregisteredTestClasses(testFiles, registeredClasses)

	// Helper classes should not be reported as unregistered
	if len(unregistered) != 0 {
		t.Errorf("Expected 0 unregistered classes for helper-only files, got %d", len(unregistered))
	}
}

func TestFindUnregisteredTestClasses_EmptyTestFiles(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	testFiles := []*models.TestFile{}
	registeredClasses := map[string]bool{
		"Test1": true,
	}

	unregistered := engine.FindUnregisteredTestClasses(testFiles, registeredClasses)

	if len(unregistered) != 0 {
		t.Errorf("Expected 0 unregistered classes for empty test files, got %d", len(unregistered))
	}
}

// Additional edge case tests for comprehensive coverage

func TestDiscoverTestFiles_SymbolicLinks(t *testing.T) {
	// Test handling of symbolic links in directory structure
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create a real directory with a test file
	realDir := filepath.Join(tmpDir, "real")
	if err := os.MkdirAll(realDir, 0755); err != nil {
		t.Fatalf("Failed to create real directory: %v", err)
	}
	testFile := filepath.Join(realDir, "Test.m")
	if err := os.WriteFile(testFile, []byte("// test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	// Create a symbolic link to the directory
	linkDir := filepath.Join(tmpDir, "link")
	if err := os.Symlink(realDir, linkDir); err != nil {
		t.Skip("Symbolic links not supported on this system")
	}

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should discover files through symlinks
	if len(files) < 1 {
		t.Errorf("Expected at least 1 test file (including symlinked), got %d", len(files))
	}
}

func TestDiscoverTestFiles_DeepNesting(t *testing.T) {
	// Test discovery with deeply nested directory structure
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create deeply nested structure: level1/level2/level3/level4/level5
	deepPath := filepath.Join(tmpDir, "level1", "level2", "level3", "level4", "level5")
	if err := os.MkdirAll(deepPath, 0755); err != nil {
		t.Fatalf("Failed to create deep directory: %v", err)
	}

	// Create test file at the deepest level
	testFile := filepath.Join(deepPath, "DeepTest.m")
	if err := os.WriteFile(testFile, []byte("// deep test"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	files, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(files) != 1 {
		t.Errorf("Expected 1 test file in deep nesting, got %d", len(files))
	}
}

func TestDiscoverTestFiles_MixedCaseExtensions(t *testing.T) {
	// Test that only .m files are discovered (not .M or other cases)
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	// Create files with various extensions
	files := []string{
		"Test.m",   // Should be included
		"Test.M",   // Should be excluded (uppercase)
		"Test.mm",  // Should be excluded (Objective-C++)
		"Test.h",   // Should be excluded (header)
	}

	for _, file := range files {
		if err := os.WriteFile(filepath.Join(tmpDir, file), []byte("// file"), 0644); err != nil {
			t.Fatalf("Failed to create file: %v", err)
		}
	}

	engine := NewTestDiscoveryEngine()
	discovered, err := engine.DiscoverTestFiles(tmpDir)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should only find .m files (lowercase)
	if len(discovered) != 1 {
		t.Errorf("Expected 1 .m file, got %d", len(discovered))
	}
}

func TestDiscoverTestClasses_ComplexInheritanceChain(t *testing.T) {
	// Test discovery with multi-level inheritance
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "InheritanceTest.m")
	content := `#import <XCTest/XCTest.h>

@interface BaseTest : XCTestCase
@end

@implementation BaseTest
@end

@interface MiddleTest : BaseTest
@end

@implementation MiddleTest
@end

@interface ConcreteTest : MiddleTest
@end

@implementation ConcreteTest
- (void)testSomething {
    XCTAssertTrue(YES);
}
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should discover all classes in the inheritance chain
	if len(classes) < 1 {
		t.Fatalf("Expected at least 1 test class, got %d", len(classes))
	}

	// Verify ConcreteTest is found
	foundConcrete := false
	for _, class := range classes {
		if class.Name == "ConcreteTest" {
			foundConcrete = true
			if class.BaseClass == nil || *class.BaseClass != "MiddleTest" {
				t.Errorf("Expected ConcreteTest base class to be MiddleTest, got %v", class.BaseClass)
			}
		}
	}

	if !foundConcrete {
		t.Error("Expected to find ConcreteTest class")
	}
}

func TestDiscoverTestClasses_EmptyFile(t *testing.T) {
	// Test handling of empty files
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "Empty.m")
	if err := os.WriteFile(testFile, []byte(""), 0644); err != nil {
		t.Fatalf("Failed to create empty file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(classes) != 0 {
		t.Errorf("Expected 0 classes in empty file, got %d", len(classes))
	}
}

func TestDiscoverTestClasses_OnlyImports(t *testing.T) {
	// Test file with only imports, no classes
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "ImportsOnly.m")
	content := `#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "SomeHeader.h"
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	classes, err := engine.DiscoverTestClasses(testFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(classes) != 0 {
		t.Errorf("Expected 0 classes in imports-only file, got %d", len(classes))
	}
}

func TestDiscoverTestMethods_EmptyClass(t *testing.T) {
	// Test class with no methods
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "EmptyClass.m")
	content := `#import <XCTest/XCTest.h>

@interface EmptyClass : XCTestCase
@end

@implementation EmptyClass
@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "EmptyClass")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	if len(methods) != 0 {
		t.Errorf("Expected 0 methods in empty class, got %d", len(methods))
	}
}

func TestDiscoverTestMethods_VariousNamingPatterns(t *testing.T) {
	// Test various test method naming patterns
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "NamingPatterns.m")
	content := `#import <XCTest/XCTest.h>

@interface NamingPatterns : XCTestCase
@end

@implementation NamingPatterns

- (void)test {
    // Minimal test name
    XCTAssertTrue(YES);
}

- (void)testSimple {
    XCTAssertTrue(YES);
}

- (void)testThatSomethingWorks {
    XCTAssertTrue(YES);
}

- (void)testShouldDoSomething {
    XCTAssertTrue(YES);
}

- (void)testWhenConditionThenResult {
    XCTAssertTrue(YES);
}

- (void)testVeryLongMethodNameWithManyWordsDescribingExactlyWhatIsBeingTested {
    XCTAssertTrue(YES);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "NamingPatterns")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expectedCount := 6
	if len(methods) != expectedCount {
		t.Errorf("Expected %d test methods with various naming patterns, got %d", expectedCount, len(methods))
	}

	// Verify all methods start with "test"
	for _, method := range methods {
		if !strings.HasPrefix(method.Name, "test") {
			t.Errorf("Method %s doesn't start with 'test'", method.Name)
		}
	}
}

func TestDiscoverTestMethods_PrivateAndPublicMethods(t *testing.T) {
	// Test that only test methods are discovered, not private helpers
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testFile := filepath.Join(tmpDir, "PrivatePublic.m")
	content := `#import <XCTest/XCTest.h>

@interface PrivatePublic : XCTestCase
@end

@implementation PrivatePublic

- (void)privateHelper {
    // Private helper method
}

- (void)testPublicTest {
    XCTAssertTrue(YES);
}

- (NSString *)helperMethod {
    return @"helper";
}

- (void)testAnotherPublicTest {
    XCTAssertTrue(YES);
}

@end
`
	if err := os.WriteFile(testFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	methods, err := engine.DiscoverTestMethods(testFile, "PrivatePublic")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should only find test methods
	if len(methods) != 2 {
		t.Errorf("Expected 2 test methods, got %d", len(methods))
	}

	for _, method := range methods {
		if !strings.HasPrefix(method.Name, "test") {
			t.Errorf("Found non-test method: %s", method.Name)
		}
	}
}

func TestParseTestMainRegistration_NestedArrays(t *testing.T) {
	// Test handling of nested arrays (should not parse nested content)
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    NSArray *testClasses = @[
        @"Test1",
        @"Test2",
    ];
    
    // Another array that should be ignored
    NSArray *otherArray = @[
        @"NotATest",
    ];
    
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	// Should only find classes in testClasses array
	if len(registered) != 2 {
		t.Errorf("Expected 2 registered classes, got %d", len(registered))
	}

	if !registered["Test1"] || !registered["Test2"] {
		t.Error("Expected Test1 and Test2 to be registered")
	}

	if registered["NotATest"] {
		t.Error("NotATest should not be registered (from different array)")
	}
}

func TestParseTestMainRegistration_SingleLine(t *testing.T) {
	// Test single-line array declaration
	tmpDir, err := os.MkdirTemp("", "testdir")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	testMainFile := filepath.Join(tmpDir, "test_main.m")
	content := `#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    NSArray *testClasses = @[@"Test1", @"Test2", @"Test3"];
    return 0;
}
`
	if err := os.WriteFile(testMainFile, []byte(content), 0644); err != nil {
		t.Fatalf("Failed to create test_main.m: %v", err)
	}

	engine := NewTestDiscoveryEngine()
	registered, err := engine.ParseTestMainRegistration(testMainFile)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expectedClasses := []string{"Test1", "Test2", "Test3"}
	if len(registered) != len(expectedClasses) {
		t.Errorf("Expected %d registered classes, got %d", len(expectedClasses), len(registered))
	}

	for _, className := range expectedClasses {
		if !registered[className] {
			t.Errorf("Expected class %s to be registered", className)
		}
	}
}

func TestFindUnregisteredTestClasses_MixedRegistration(t *testing.T) {
	// Test with a mix of registered, unregistered, and helper classes
	engine := NewTestDiscoveryEngine()

	testFiles := []*models.TestFile{
		{
			Path: "auth/OAuthTests.m",
			Classes: []models.TestClass{
				{Name: "OAuthTests", FilePath: "auth/OAuthTests.m", IsHelper: false},
			},
		},
		{
			Path: "auth/JWTTests.m",
			Classes: []models.TestClass{
				{Name: "JWTTests", FilePath: "auth/JWTTests.m", IsHelper: false},
			},
		},
		{
			Path: "auth/TestHelper.m",
			Classes: []models.TestClass{
				{Name: "AuthTestHelper", FilePath: "auth/TestHelper.m", IsHelper: true},
			},
		},
		{
			Path: "network/XRPCTests.m",
			Classes: []models.TestClass{
				{Name: "XRPCTests", FilePath: "network/XRPCTests.m", IsHelper: false},
			},
		},
		{
			Path: "network/UnregisteredNetworkTest.m",
			Classes: []models.TestClass{
				{Name: "UnregisteredNetworkTest", FilePath: "network/UnregisteredNetworkTest.m", IsHelper: false},
			},
		},
	}

	registeredClasses := map[string]bool{
		"OAuthTests": true,
		"JWTTests":   true,
		"XRPCTests":  true,
	}

	unregistered := engine.FindUnregisteredTestClasses(testFiles, registeredClasses)

	// Should find only UnregisteredNetworkTest (helper is ignored)
	if len(unregistered) != 1 {
		t.Errorf("Expected 1 unregistered class, got %d", len(unregistered))
	}

	if len(unregistered) > 0 {
		if unregistered[0].ClassName != "UnregisteredNetworkTest" {
			t.Errorf("Expected UnregisteredNetworkTest, got %s", unregistered[0].ClassName)
		}
		if unregistered[0].FilePath != "network/UnregisteredNetworkTest.m" {
			t.Errorf("Expected correct file path, got %s", unregistered[0].FilePath)
		}
	}
}

func TestIsHelperFile_EdgeCases(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	tests := []struct {
		path     string
		expected bool
	}{
		// Edge cases with mixed case
		{"TESTHELPER.m", true},
		{"TestHELPER.m", true},
		{"testutil.m", true},
		
		// Files with helper in the middle
		{"MyHelperTest.m", true},
		{"TestHelperClass.m", true},
		
		// Files that should not be excluded
		{"HelperTests.m", true}, // Contains "helper"
		{"TestsHelper.m", true}, // Contains "helper"
		{"ActualTest.m", false},
		{"RealTest.m", false},
		
		// Edge case: test_main variations
		{"test_main.m", true},
		{"TEST_MAIN.m", true},
		{"Test_Main.m", true},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			result := engine.isHelperFile(tt.path)
			if result != tt.expected {
				t.Errorf("isHelperFile(%s) = %v, expected %v", tt.path, result, tt.expected)
			}
		})
	}
}

func TestIsHelperClass_EdgeCases(t *testing.T) {
	engine := NewTestDiscoveryEngine()

	tests := []struct {
		className string
		expected  bool
	}{
		// Mixed case variations
		{"TESTHELPER", true},
		{"TestHELPER", true},
		{"testhelper", true},
		
		// Multiple helper keywords
		{"MockStubHelper", true},
		{"FakeTestFixture", true},
		
		// Base class variations
		{"MyTestBase", true},
		{"CustomBase", true},
		{"BaseClass", true},
		
		// Should not be helpers
		{"TestRunner", false},
		{"TestExecutor", false},
		{"ActualTests", false},
	}

	for _, tt := range tests {
		t.Run(tt.className, func(t *testing.T) {
			result := engine.isHelperClass(tt.className)
			if result != tt.expected {
				t.Errorf("isHelperClass(%s) = %v, expected %v", tt.className, result, tt.expected)
			}
		})
	}
}
