// Package discovery provides functionality for discovering test files, classes, and methods
// in the September PDS codebase.
package discovery

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/go-clang/clang-v14/clang"
	"github.com/september-pds/test-audit-validator/internal/models"
)

// TestDiscoveryEngine discovers test classes and methods using ObjC patterns
type TestDiscoveryEngine struct {
	// ExcludePatterns are directory/file patterns to exclude from discovery
	ExcludePatterns []string
}

// NewTestDiscoveryEngine creates a new test discovery engine with default settings
func NewTestDiscoveryEngine() *TestDiscoveryEngine {
	return &TestDiscoveryEngine{
		ExcludePatterns: []string{
			"fixtures",
			"plc_e2e",
			"helpers",
		},
	}
}

// DiscoverTestFiles recursively finds all test files in the given directory
// It filters for .m files and excludes fixture directories and helper files
func (e *TestDiscoveryEngine) DiscoverTestFiles(rootPath string) ([]*models.TestFile, error) {
	var testFiles []*models.TestFile

	// Verify root path exists
	info, err := os.Stat(rootPath)
	if err != nil {
		return nil, fmt.Errorf("failed to access root path %s: %w", rootPath, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("root path %s is not a directory", rootPath)
	}

	// Walk the directory tree
	err = filepath.Walk(rootPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip directories that match exclude patterns
		if info.IsDir() {
			if e.shouldExcludeDir(info.Name()) {
				return filepath.SkipDir
			}
			return nil
		}

		// Only process .m files
		if !strings.HasSuffix(path, ".m") {
			return nil
		}

		// Skip helper files
		if e.isHelperFile(path) {
			return nil
		}

		// Create test file entry
		testFile := &models.TestFile{
			Path:    path,
			Classes: []models.TestClass{},
			Imports: []string{},
		}

		testFiles = append(testFiles, testFile)
		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to walk directory tree: %w", err)
	}

	return testFiles, nil
}

// shouldExcludeDir checks if a directory should be excluded from discovery
func (e *TestDiscoveryEngine) shouldExcludeDir(dirName string) bool {
	for _, pattern := range e.ExcludePatterns {
		if strings.Contains(strings.ToLower(dirName), strings.ToLower(pattern)) {
			return true
		}
	}
	return false
}

// isHelperFile checks if a file is a helper file that should be excluded
func (e *TestDiscoveryEngine) isHelperFile(path string) bool {
	baseName := filepath.Base(path)
	lowerName := strings.ToLower(baseName)

	// Exclude common helper file patterns
	helperPatterns := []string{
		"helper",
		"util",
		"base",
		"common",
		"test_main",
	}

	for _, pattern := range helperPatterns {
		if strings.Contains(lowerName, pattern) {
			return true
		}
	}

	return false
}

// classInfo holds information about a class discovered during AST parsing
type classInfo struct {
	name      string
	baseClass *string
	isHelper  bool
}

// DiscoverTestClasses extracts test classes from a file using clang AST parsing
// It identifies classes inheriting from XCTestCase or test base classes
func (e *TestDiscoveryEngine) DiscoverTestClasses(filePath string) ([]models.TestClass, error) {
	// Verify file exists
	if _, err := os.Stat(filePath); err != nil {
		return nil, fmt.Errorf("failed to access file %s: %w", filePath, err)
	}

	// Create clang index
	index := clang.NewIndex(0, 0)
	defer index.Dispose()

	// Parse the file
	// Use Objective-C language options with common include paths
	args := []string{
		"-x", "objective-c",
		"-fobjc-arc",
		"-fblocks",
		"-isysroot", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
		"-F", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
	}

	// Use lenient parsing - continue even with errors
	tu := index.ParseTranslationUnit(filePath, args, nil, clang.TranslationUnit_SkipFunctionBodies|clang.TranslationUnit_KeepGoing)
	if !tu.IsValid() {
		return nil, fmt.Errorf("failed to parse file %s", filePath)
	}
	defer tu.Dispose()

	// Check for fatal parsing errors only
	// We allow warnings and non-fatal errors since we're doing best-effort parsing
	diagnostics := tu.Diagnostics()
	hasFatalError := false
	for _, diag := range diagnostics {
		severity := diag.Severity()
		// Only fail on fatal errors
		if severity == clang.Diagnostic_Fatal {
			hasFatalError = true
			break
		}
	}
	
	if hasFatalError {
		return nil, fmt.Errorf("fatal parse error in %s", filePath)
	}

	// Two-pass approach to handle inheritance chains:
	// Pass 1: Collect all classes and their base classes
	allClasses := make(map[string]classInfo)
	cursor := tu.TranslationUnitCursor()

	// First pass: collect all @interface declarations from THIS file only
	cursor.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		if cursor.Kind() == clang.Cursor_ObjCInterfaceDecl {
			className := cursor.Spelling()
			
			// Only include classes defined in the target file (not imported headers)
			location := cursor.Location()
			file, _, _, _ := location.FileLocation()
			if file.Name() != filePath {
				return clang.ChildVisit_Continue
			}
			
			var baseClassName *string
			
			// Visit the class to find its superclass
			cursor.Visit(func(child, parent clang.Cursor) clang.ChildVisitResult {
				if child.Kind() == clang.Cursor_ObjCSuperClassRef {
					baseName := child.Spelling()
					baseClassName = &baseName
				}
				return clang.ChildVisit_Continue
			})

			allClasses[className] = classInfo{
				name:      className,
				baseClass: baseClassName,
				isHelper:  e.isHelperClass(className),
			}
		}
		return clang.ChildVisit_Continue
	})

	// Pass 2: Determine which classes are test classes by checking inheritance chain
	var testClasses []models.TestClass
	for className, info := range allClasses {
		if e.isTestClassByInheritance(className, allClasses) {
			testClass := models.TestClass{
				Name:      info.name,
				FilePath:  filePath,
				Methods:   []models.TestMethod{},
				BaseClass: info.baseClass,
				IsHelper:  info.isHelper,
			}
			testClasses = append(testClasses, testClass)
		}
	}

	return testClasses, nil
}

// isTestBaseClass checks if a class name is a known test base class
func (e *TestDiscoveryEngine) isTestBaseClass(className string) bool {
	testBaseClasses := []string{
		"XCTestCase",
		"CharacterizationTestBase",
		"TestBase",
		"BaseTestCase",
		"IntegrationTestBase",
	}

	for _, baseClass := range testBaseClasses {
		if className == baseClass {
			return true
		}
	}

	return false
}

// isTestClassByInheritance checks if a class is a test class by walking its inheritance chain
// It checks both known test base classes and classes defined in the same file
func (e *TestDiscoveryEngine) isTestClassByInheritance(className string, allClasses map[string]classInfo) bool {
	// Prevent infinite loops in case of circular inheritance (shouldn't happen but be safe)
	visited := make(map[string]bool)
	return e.isTestClassByInheritanceHelper(className, allClasses, visited)
}

// isTestClassByInheritanceHelper is a recursive helper that tracks visited classes
func (e *TestDiscoveryEngine) isTestClassByInheritanceHelper(className string, allClasses map[string]classInfo, visited map[string]bool) bool {
	// Check if we've already visited this class (circular inheritance protection)
	if visited[className] {
		return false
	}
	visited[className] = true

	// Check if this is a known test base class
	if e.isTestBaseClass(className) {
		return true
	}

	// Look up the class in our collected classes
	info, exists := allClasses[className]
	if !exists {
		// Class not in this file - assume it's not a test class unless it's a known base
		return false
	}

	// If no base class, it's not a test class
	if info.baseClass == nil {
		return false
	}

	// Recursively check the base class
	return e.isTestClassByInheritanceHelper(*info.baseClass, allClasses, visited)
}

// isHelperClass determines if a class is a test helper rather than an actual test class
func (e *TestDiscoveryEngine) isHelperClass(className string) bool {
	lowerName := strings.ToLower(className)

	// Helper class patterns
	helperPatterns := []string{
		"helper",
		"util",
		"mock",
		"stub",
		"fake",
		"fixture",
		"base",
		"common",
	}

	for _, pattern := range helperPatterns {
		if strings.Contains(lowerName, pattern) {
			return true
		}
	}

	// Classes ending with "Base" are typically helpers
	if strings.HasSuffix(className, "Base") {
		return true
	}

	return false
}

// DiscoverTestMethods extracts test methods from a class using clang AST
// It finds methods starting with "test" and extracts their metadata
func (e *TestDiscoveryEngine) DiscoverTestMethods(filePath string, className string) ([]models.TestMethod, error) {
	// Verify file exists
	if _, err := os.Stat(filePath); err != nil {
		return nil, fmt.Errorf("failed to access file %s: %w", filePath, err)
	}

	// Create clang index
	index := clang.NewIndex(0, 0)
	defer index.Dispose()

	// Parse the file
	args := []string{
		"-x", "objective-c",
		"-fobjc-arc",
		"-fblocks",
		"-isysroot", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
		"-F", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks",
	}

	// Use lenient parsing
	tu := index.ParseTranslationUnit(filePath, args, nil, clang.TranslationUnit_SkipFunctionBodies|clang.TranslationUnit_KeepGoing)
	if !tu.IsValid() {
		return nil, fmt.Errorf("failed to parse file %s", filePath)
	}
	defer tu.Dispose()

	// Check for fatal parsing errors only
	diagnostics := tu.Diagnostics()
	hasFatalError := false
	for _, diag := range diagnostics {
		severity := diag.Severity()
		if severity == clang.Diagnostic_Fatal {
			hasFatalError = true
			break
		}
	}
	
	if hasFatalError {
		return nil, fmt.Errorf("fatal parse error in %s", filePath)
	}

	// Find the target class and extract its methods
	var testMethods []models.TestMethod
	cursor := tu.TranslationUnitCursor()

	// Visit all top-level declarations to find the target class
	cursor.Visit(func(cursor, parent clang.Cursor) clang.ChildVisitResult {
		// Look for @interface or @implementation of the target class
		if cursor.Kind() == clang.Cursor_ObjCInterfaceDecl || cursor.Kind() == clang.Cursor_ObjCImplementationDecl {
			currentClassName := cursor.Spelling()
			
			// Only process the target class
			if currentClassName != className {
				return clang.ChildVisit_Continue
			}

			// Visit methods in this class
			cursor.Visit(func(methodCursor, classCursor clang.Cursor) clang.ChildVisitResult {
				// Look for instance and class methods
				if methodCursor.Kind() == clang.Cursor_ObjCInstanceMethodDecl || 
				   methodCursor.Kind() == clang.Cursor_ObjCClassMethodDecl {
					methodName := methodCursor.Spelling()
					
					// Only include methods starting with "test"
					if strings.HasPrefix(methodName, "test") {
						// Get line number
						location := methodCursor.Location()
						_, line, _, _ := location.FileLocation()
						
						// Get source code for the method
						sourceCode := e.extractMethodSource(filePath, methodCursor)
						
						// Extract comments
						comments := e.extractMethodComments(methodCursor)

						testMethod := models.TestMethod{
							Name:       methodName,
							ClassName:  className,
							LineNumber: int(line),
							SourceCode: sourceCode,
							Assertions: []models.Assertion{}, // Will be populated by static analysis
							Comments:   comments,
						}

						testMethods = append(testMethods, testMethod)
					}
				}
				return clang.ChildVisit_Continue
			})
		}

		return clang.ChildVisit_Continue
	})

	return testMethods, nil
}

// extractMethodSource extracts the source code for a method
func (e *TestDiscoveryEngine) extractMethodSource(filePath string, methodCursor clang.Cursor) string {
	// Get the extent (range) of the method
	extent := methodCursor.Extent()
	startLocation := extent.Start()
	endLocation := extent.End()
	
	_, startLine, _, startOffset := startLocation.FileLocation()
	_, endLine, _, endOffset := endLocation.FileLocation()
	
	// Read the file content
	content, err := os.ReadFile(filePath)
	if err != nil {
		return ""
	}

	// Extract the source code between start and end offsets
	if startOffset >= 0 && endOffset >= 0 && int(endOffset) <= len(content) {
		sourceCode := string(content[startOffset:endOffset])
		return sourceCode
	}

	// Fallback: extract by line numbers if offsets don't work
	lines := strings.Split(string(content), "\n")
	if int(startLine) > 0 && int(endLine) <= len(lines) {
		methodLines := lines[startLine-1 : endLine]
		return strings.Join(methodLines, "\n")
	}

	return ""
}

// extractMethodComments extracts comments associated with a method
func (e *TestDiscoveryEngine) extractMethodComments(methodCursor clang.Cursor) []string {
	var comments []string
	
	// Get the raw comment text
	rawComment := methodCursor.RawCommentText()
	if rawComment != "" {
		// Split multi-line comments
		commentLines := strings.Split(rawComment, "\n")
		for _, line := range commentLines {
			trimmed := strings.TrimSpace(line)
			// Remove comment markers
			trimmed = strings.TrimPrefix(trimmed, "//")
			trimmed = strings.TrimPrefix(trimmed, "/*")
			trimmed = strings.TrimSuffix(trimmed, "*/")
			trimmed = strings.TrimPrefix(trimmed, "*")
			trimmed = strings.TrimSpace(trimmed)
			
			if trimmed != "" {
				comments = append(comments, trimmed)
			}
		}
	}

	return comments
}

// ParseTestMainRegistration parses test_main.m to extract the testClasses array
// Returns a map of registered test class names for quick lookup
func (e *TestDiscoveryEngine) ParseTestMainRegistration(testMainPath string) (map[string]bool, error) {
	// Verify file exists
	if _, err := os.Stat(testMainPath); err != nil {
		return nil, fmt.Errorf("failed to access test_main.m at %s: %w", testMainPath, err)
	}

	// Read the file content
	content, err := os.ReadFile(testMainPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read test_main.m: %w", err)
	}

	fileContent := string(content)
	registeredClasses := make(map[string]bool)

	// Find the testClasses array declaration
	// Pattern: NSArray *testClasses = @[ ... ];
	// We need to extract all string literals within the array

	// Find the start of the testClasses array
	arrayStart := strings.Index(fileContent, "NSArray *testClasses = @[")
	if arrayStart == -1 {
		return nil, fmt.Errorf("could not find testClasses array declaration in test_main.m")
	}

	// Find the matching closing bracket
	// Start after the opening @[
	searchStart := arrayStart + len("NSArray *testClasses = @[")
	bracketCount := 1
	arrayEnd := -1

	for i := searchStart; i < len(fileContent); i++ {
		if fileContent[i] == '[' {
			bracketCount++
		} else if fileContent[i] == ']' {
			bracketCount--
			if bracketCount == 0 {
				arrayEnd = i
				break
			}
		}
	}

	if arrayEnd == -1 {
		return nil, fmt.Errorf("could not find closing bracket for testClasses array")
	}

	// Extract the array content
	arrayContent := fileContent[searchStart:arrayEnd]

	// Parse string literals from the array
	// Pattern: @"ClassName"
	// We'll use a simple state machine to extract quoted strings

	inString := false
	currentString := ""
	escaped := false

	for i := 0; i < len(arrayContent); i++ {
		char := arrayContent[i]

		if escaped {
			currentString += string(char)
			escaped = false
			continue
		}

		if char == '\\' {
			escaped = true
			continue
		}

		if char == '"' {
			if inString {
				// End of string - add to registered classes
				if currentString != "" {
					registeredClasses[currentString] = true
				}
				currentString = ""
				inString = false
			} else {
				// Start of string
				inString = true
			}
		} else if inString {
			currentString += string(char)
		}
	}

	return registeredClasses, nil
}

// CheckTestRegistration verifies if a test class is registered in test_main.m
// Returns true if the class is registered, false otherwise
func (e *TestDiscoveryEngine) CheckTestRegistration(className string, registeredClasses map[string]bool) bool {
	return registeredClasses[className]
}

// FindUnregisteredTestClasses finds all test classes that exist but aren't registered
// Returns a list of unregistered test class names with their file paths
func (e *TestDiscoveryEngine) FindUnregisteredTestClasses(testFiles []*models.TestFile, registeredClasses map[string]bool) []UnregisteredClass {
	var unregistered []UnregisteredClass

	for _, testFile := range testFiles {
		for _, testClass := range testFile.Classes {
			// Skip helper classes - they don't need to be registered
			if testClass.IsHelper {
				continue
			}

			// Check if the class is registered
			if !e.CheckTestRegistration(testClass.Name, registeredClasses) {
				unregistered = append(unregistered, UnregisteredClass{
					ClassName: testClass.Name,
					FilePath:  testClass.FilePath,
				})
			}
		}
	}

	return unregistered
}

// UnregisteredClass represents a test class that exists but isn't registered in test_main.m
type UnregisteredClass struct {
	ClassName string
	FilePath  string
}
