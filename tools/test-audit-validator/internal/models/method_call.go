package models

// MethodCall represents a method invocation in test code
type MethodCall struct {
	Receiver   string   // Receiver object or class name (e.g., "parser", "NSString")
	Selector   string   // Method selector (e.g., "parse:", "stringWithFormat:")
	Arguments  []string // Argument expressions passed to the method
	LineNumber int      // Line number where the method call appears
}
