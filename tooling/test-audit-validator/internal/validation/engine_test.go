package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// MockRule is a test implementation of ValidationRule
type MockRule struct {
	name        string
	severity    Severity
	description string
	findings    []Finding
}

func (m *MockRule) Validate(ctx ValidationContext) []Finding {
	return m.findings
}

func (m *MockRule) Severity() Severity {
	return m.severity
}

func (m *MockRule) Description() string {
	return m.description
}

func (m *MockRule) Name() string {
	return m.name
}

func TestNewEngine(t *testing.T) {
	rule1 := &MockRule{name: "Rule1", severity: HIGH, description: "Test rule 1"}
	rule2 := &MockRule{name: "Rule2", severity: MEDIUM, description: "Test rule 2"}

	engine := NewEngine([]ValidationRule{rule1, rule2})

	if engine == nil {
		t.Fatal("NewEngine returned nil")
	}

	rules := engine.GetRules()
	if len(rules) != 2 {
		t.Errorf("GetRules() returned %d rules, want 2", len(rules))
	}
}

func TestEngineAddRule(t *testing.T) {
	engine := NewEngine(nil)
	rule := &MockRule{name: "TestRule", severity: LOW, description: "Test rule"}

	engine.AddRule(rule)

	rules := engine.GetRules()
	if len(rules) != 1 {
		t.Errorf("After AddRule, engine has %d rules, want 1", len(rules))
	}
	if rules[0].Name() != "TestRule" {
		t.Errorf("Added rule name = %v, want TestRule", rules[0].Name())
	}
}

func TestValidateTestMethod(t *testing.T) {
	finding := Finding{
		RuleName:   "MockRule",
		Severity:   HIGH,
		TestMethod: "testExample",
		Message:    "Test finding",
		Confidence: 0.9,
	}

	rule := &MockRule{
		name:     "MockRule",
		severity: HIGH,
		findings: []Finding{finding},
	}

	engine := NewEngine([]ValidationRule{rule})

	method := &models.TestMethod{
		Name:       "testExample",
		ClassName:  "ExampleTests",
		LineNumber: 10,
	}

	class := &models.TestClass{
		Name:     "ExampleTests",
		FilePath: "/path/to/test.m",
	}

	file := &models.TestFile{
		Path: "/path/to/test.m",
	}

	findings := engine.ValidateTestMethod(method, class, file)

	if len(findings) != 1 {
		t.Fatalf("ValidateTestMethod returned %d findings, want 1", len(findings))
	}

	if findings[0].RuleName != "MockRule" {
		t.Errorf("Finding RuleName = %v, want MockRule", findings[0].RuleName)
	}
	if findings[0].Severity != HIGH {
		t.Errorf("Finding Severity = %v, want HIGH", findings[0].Severity)
	}
}

func TestValidateTestClass(t *testing.T) {
	methodFinding := Finding{
		RuleName:   "MethodRule",
		TestMethod: "testMethod1",
		Severity:   MEDIUM,
		Confidence: 0.8,
	}

	classFinding := Finding{
		RuleName:  "ClassRule",
		TestClass: "TestClass",
		Severity:  LOW,
		Confidence: 0.7,
	}

	methodRule := &MockRule{
		name:     "MethodRule",
		findings: []Finding{methodFinding},
	}

	classRule := &MockRule{
		name:     "ClassRule",
		findings: []Finding{classFinding},
	}

	engine := NewEngine([]ValidationRule{methodRule, classRule})

	class := &models.TestClass{
		Name:     "TestClass",
		FilePath: "/path/to/test.m",
		Methods: []models.TestMethod{
			{Name: "testMethod1", ClassName: "TestClass", LineNumber: 10},
		},
	}

	file := &models.TestFile{
		Path: "/path/to/test.m",
	}

	findings := engine.ValidateTestClass(class, file)

	// Should get findings from both method-level and class-level validation
	// Each rule runs once per method (1 method) + once for class-level = 2 findings per rule
	// With 2 rules, we expect 4 findings total
	if len(findings) != 4 {
		t.Errorf("ValidateTestClass returned %d findings, want 4", len(findings))
	}
}

func TestValidateTestFile(t *testing.T) {
	fileFinding := Finding{
		RuleName:   "FileRule",
		FilePath:   "/path/to/test.m",
		Severity:   CRITICAL,
		Confidence: 0.95,
	}

	rule := &MockRule{
		name:     "FileRule",
		findings: []Finding{fileFinding},
	}

	engine := NewEngine([]ValidationRule{rule})

	file := &models.TestFile{
		Path: "/path/to/test.m",
		Classes: []models.TestClass{
			{
				Name:     "TestClass1",
				FilePath: "/path/to/test.m",
				Methods: []models.TestMethod{
					{Name: "testMethod1", ClassName: "TestClass1", LineNumber: 10},
				},
			},
		},
	}

	findings := engine.ValidateTestFile(file)

	// Rule runs for: 1 method + 1 class + 1 file = 3 findings
	if len(findings) != 3 {
		t.Errorf("ValidateTestFile returned %d findings, want 3", len(findings))
	}
}

func TestValidateMultipleRules(t *testing.T) {
	rule1 := &MockRule{
		name: "Rule1",
		findings: []Finding{
			{RuleName: "Rule1", Severity: HIGH, Confidence: 0.9},
		},
	}

	rule2 := &MockRule{
		name: "Rule2",
		findings: []Finding{
			{RuleName: "Rule2", Severity: MEDIUM, Confidence: 0.8},
		},
	}

	engine := NewEngine([]ValidationRule{rule1, rule2})

	method := &models.TestMethod{Name: "testExample"}
	class := &models.TestClass{Name: "ExampleTests"}
	file := &models.TestFile{Path: "/path/to/test.m"}

	findings := engine.ValidateTestMethod(method, class, file)

	if len(findings) != 2 {
		t.Fatalf("ValidateTestMethod with 2 rules returned %d findings, want 2", len(findings))
	}

	// Verify both rules contributed findings
	foundRule1 := false
	foundRule2 := false
	for _, f := range findings {
		if f.RuleName == "Rule1" {
			foundRule1 = true
		}
		if f.RuleName == "Rule2" {
			foundRule2 = true
		}
	}

	if !foundRule1 {
		t.Error("Missing finding from Rule1")
	}
	if !foundRule2 {
		t.Error("Missing finding from Rule2")
	}
}

func TestValidateEmptyEngine(t *testing.T) {
	engine := NewEngine(nil)

	method := &models.TestMethod{Name: "testExample"}
	class := &models.TestClass{Name: "ExampleTests"}
	file := &models.TestFile{Path: "/path/to/test.m"}

	findings := engine.ValidateTestMethod(method, class, file)

	if len(findings) != 0 {
		t.Errorf("Empty engine returned %d findings, want 0", len(findings))
	}
}

// ContextCaptureRule is a special mock that captures the validation context
type ContextCaptureRule struct {
	capturedContext *ValidationContext
}

func (c *ContextCaptureRule) Validate(ctx ValidationContext) []Finding {
	*c.capturedContext = ctx
	return []Finding{}
}

func (c *ContextCaptureRule) Severity() Severity {
	return LOW
}

func (c *ContextCaptureRule) Description() string {
	return "Context capture rule"
}

func (c *ContextCaptureRule) Name() string {
	return "ContextCaptureRule"
}

func TestValidationContext(t *testing.T) {
	var capturedContext ValidationContext

	rule := &ContextCaptureRule{
		capturedContext: &capturedContext,
	}

	engine := NewEngine([]ValidationRule{rule})

	method := &models.TestMethod{Name: "testExample", ClassName: "ExampleTests"}
	class := &models.TestClass{Name: "ExampleTests", FilePath: "/path/to/test.m"}
	file := &models.TestFile{Path: "/path/to/test.m"}

	engine.ValidateTestMethod(method, class, file)

	if capturedContext.TestMethod == nil {
		t.Error("ValidationContext.TestMethod is nil")
	}
	if capturedContext.TestClass == nil {
		t.Error("ValidationContext.TestClass is nil")
	}
	if capturedContext.TestFile == nil {
		t.Error("ValidationContext.TestFile is nil")
	}

	if capturedContext.TestMethod.Name != "testExample" {
		t.Errorf("Context method name = %v, want testExample", capturedContext.TestMethod.Name)
	}
	if capturedContext.TestClass.Name != "ExampleTests" {
		t.Errorf("Context class name = %v, want ExampleTests", capturedContext.TestClass.Name)
	}
	if capturedContext.TestFile.Path != "/path/to/test.m" {
		t.Errorf("Context file path = %v, want /path/to/test.m", capturedContext.TestFile.Path)
	}
}
