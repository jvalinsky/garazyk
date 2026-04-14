package validation

import "github.com/september-pds/test-audit-validator/internal/models"

// ValidationContext provides context for validation rules
type ValidationContext struct {
	TestMethod *models.TestMethod
	TestClass  *models.TestClass
	TestFile   *models.TestFile
}

// ValidationRule defines the interface that all validation rules must implement
type ValidationRule interface {
	// Validate applies the rule to the given context and returns findings
	Validate(ctx ValidationContext) []Finding

	// Severity returns the severity level for findings from this rule
	Severity() Severity

	// Description returns a human-readable description of what this rule validates
	Description() string

	// Name returns the unique name of this rule
	Name() string
}
