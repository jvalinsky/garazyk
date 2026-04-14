package models

// TestFile represents a test file containing test classes
type TestFile struct {
	Path    string       // Path to the test file
	Classes []TestClass  // Test classes defined in this file
	Imports []string     // Import statements in the file
}
