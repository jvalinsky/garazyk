package models

// TestClass represents a test class (typically inheriting from XCTestCase)
type TestClass struct {
	Name      string       // Name of the test class
	FilePath  string       // Path to the file containing this class
	Methods   []TestMethod // Test methods in this class
	BaseClass *string      // Base class name (e.g., "XCTestCase", "CharacterizationTestBase"), nil if none
	IsHelper  bool         // True for test utility classes, false for actual test classes
}
