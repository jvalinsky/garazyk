package models

// Variable represents a variable declaration in test code
type Variable struct {
	Name         string  // Variable name
	Type         string  // Variable type (e.g., "NSString*", "BOOL", "int")
	InitialValue *string // Initial value expression, nil if not initialized
	LineNumber   int     // Line number where the variable is declared
}
