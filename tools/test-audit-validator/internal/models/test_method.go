package models

// TestMethod represents a single test method within a test class
type TestMethod struct {
	Name        string       // Name of the test method (e.g., "testOAuthTokenValidation")
	ClassName   string       // Name of the class containing this method
	LineNumber  int          // Line number where the method is defined
	SourceCode  string       // Full source code of the method
	Assertions  []Assertion  // Assertions found in this method
	Comments    []string     // Comments and documentation for this method
	MethodCalls []MethodCall // Method calls found in this method
}
