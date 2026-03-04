package validation

import "github.com/september-pds/test-audit-validator/internal/models"

// Engine orchestrates the execution of validation rules
type Engine struct {
	rules []ValidationRule
}

// NewEngine creates a new validation engine with the given rules
func NewEngine(rules []ValidationRule) *Engine {
	return &Engine{
		rules: rules,
	}
}

// AddRule adds a validation rule to the engine
func (e *Engine) AddRule(rule ValidationRule) {
	e.rules = append(e.rules, rule)
}

// ValidateTestMethod runs all validation rules on a single test method
func (e *Engine) ValidateTestMethod(method *models.TestMethod, class *models.TestClass, file *models.TestFile) []Finding {
	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	var findings []Finding
	for _, rule := range e.rules {
		ruleFindings := rule.Validate(ctx)
		findings = append(findings, ruleFindings...)
	}

	return findings
}

// ValidateTestClass runs all validation rules on a test class and its methods
func (e *Engine) ValidateTestClass(class *models.TestClass, file *models.TestFile) []Finding {
	var findings []Finding

	// Validate each test method in the class
	for i := range class.Methods {
		methodFindings := e.ValidateTestMethod(&class.Methods[i], class, file)
		findings = append(findings, methodFindings...)
	}

	// Run class-level validation (with nil method to indicate class-level context)
	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	for _, rule := range e.rules {
		ruleFindings := rule.Validate(ctx)
		findings = append(findings, ruleFindings...)
	}

	return findings
}

// ValidateTestFile runs all validation rules on a test file and all its classes
func (e *Engine) ValidateTestFile(file *models.TestFile) []Finding {
	var findings []Finding

	// Validate each test class in the file
	for i := range file.Classes {
		classFindings := e.ValidateTestClass(&file.Classes[i], file)
		findings = append(findings, classFindings...)
	}

	// Run file-level validation (with nil class and method to indicate file-level context)
	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  nil,
		TestFile:   file,
	}

	for _, rule := range e.rules {
		ruleFindings := rule.Validate(ctx)
		findings = append(findings, ruleFindings...)
	}

	return findings
}

// GetRules returns all registered validation rules
func (e *Engine) GetRules() []ValidationRule {
	return e.rules
}
