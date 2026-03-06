package validation

import (
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestTestDocumentationRule_Name(t *testing.T) {
	rule := NewTestDocumentationRule()
	if rule.Name() != "TestDocumentationRule" {
		t.Errorf("Expected name 'TestDocumentationRule', got '%s'", rule.Name())
	}
}

func TestTestDocumentationRule_Severity(t *testing.T) {
	rule := NewTestDocumentationRule()
	if rule.Severity() != LOW {
		t.Errorf("Expected severity LOW, got %v", rule.Severity())
	}
}

func TestTestDocumentationRule_Description(t *testing.T) {
	rule := NewTestDocumentationRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestTestDocumentationRule_ComplexTestWithoutComments(t *testing.T) {
	rule := NewTestDocumentationRule()

	// Generate >30 lines of source code with no comments
	sourceLines := make([]string, 35)
	for i := range sourceLines {
		sourceLines[i] = "    XCTAssertNotNil(result);"
	}

	method := &models.TestMethod{
		Name:       "testComplexWorkflow",
		ClassName:  "WorkflowTests",
		LineNumber: 10,
		SourceCode: strings.Join(sourceLines, "\n"),
		Comments:   []string{},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "WorkflowTests", FilePath: "/path/to/WorkflowTests.m"},
		TestFile:   &models.TestFile{Path: "/path/to/WorkflowTests.m"},
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Fatal("Expected finding for complex test without comments")
	}

	found := false
	for _, f := range findings {
		if strings.Contains(f.Message, "Complex test method has no documentation") {
			found = true
			if f.Severity != LOW {
				t.Errorf("Expected LOW severity, got %v", f.Severity)
			}
			if f.RuleName != "TestDocumentationRule" {
				t.Errorf("Expected rule name 'TestDocumentationRule', got '%s'", f.RuleName)
			}
			if f.TestMethod != "testComplexWorkflow" {
				t.Errorf("Expected test method 'testComplexWorkflow', got '%s'", f.TestMethod)
			}
		}
	}
	if !found {
		t.Error("Expected finding with message about complex test method having no documentation")
	}
}

func TestTestDocumentationRule_ComplexTestWithComments(t *testing.T) {
	rule := NewTestDocumentationRule()

	sourceLines := make([]string, 25)
	for i := range sourceLines {
		sourceLines[i] = "    XCTAssertNotNil(result);"
	}

	method := &models.TestMethod{
		Name:       "testComplexWorkflow",
		ClassName:  "WorkflowTests",
		LineNumber: 10,
		SourceCode: strings.Join(sourceLines, "\n"),
		Comments:   []string{"// Tests the full OAuth token refresh workflow including edge cases"},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "WorkflowTests", FilePath: "/path/to/WorkflowTests.m"},
		TestFile:   &models.TestFile{Path: "/path/to/WorkflowTests.m"},
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if strings.Contains(f.Message, "Complex test method has no documentation") {
			t.Errorf("Did not expect missing-documentation finding for commented test, got: %s", f.Message)
		}
	}
}

func TestTestDocumentationRule_SimpleTestWithoutComments(t *testing.T) {
	rule := NewTestDocumentationRule()

	method := &models.TestMethod{
		Name:       "testSimple",
		ClassName:  "SimpleTests",
		LineNumber: 5,
		SourceCode: "XCTAssertNotNil(result);",
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 5},
		},
		Comments: []string{},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "SimpleTests", FilePath: "/path/to/SimpleTests.m"},
		TestFile:   &models.TestFile{Path: "/path/to/SimpleTests.m"},
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for simple test, got %d: %v", len(findings), findings)
	}
}

func TestTestDocumentationRule_ComplexSetupWithoutDocumentation(t *testing.T) {
	rule := NewTestDocumentationRule()

	source := `PDSConfig *config = [[PDSConfig alloc] init];
PDSDatabase *db = [[PDSDatabase alloc] init];
PDSAccountService *svc = [[PDSAccountService alloc] init];
PDSTokenValidator *validator = [[PDSTokenValidator alloc] init];
XCTAssertNotNil(config);`

	method := &models.TestMethod{
		Name:       "testWithComplexSetup",
		ClassName:  "SetupTests",
		LineNumber: 20,
		SourceCode: source,
		Comments:   []string{},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "SetupTests", FilePath: "/path/to/SetupTests.m"},
		TestFile:   &models.TestFile{Path: "/path/to/SetupTests.m"},
	}

	findings := rule.Validate(ctx)

	found := false
	for _, f := range findings {
		if strings.Contains(f.Message, "complex setup code without explanatory comments") {
			found = true
		}
	}
	if !found {
		t.Error("Expected finding about complex setup without documentation")
	}
}

func TestTestDocumentationRule_NilMethod(t *testing.T) {
	rule := NewTestDocumentationRule()

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  &models.TestClass{Name: "SomeTests", FilePath: "/path/to/SomeTests.m"},
		TestFile:   &models.TestFile{Path: "/path/to/SomeTests.m"},
	}

	findings := rule.Validate(ctx)

	if findings != nil {
		t.Errorf("Expected nil findings for nil method, got %d", len(findings))
	}
}

func TestTestDocumentationRule_ManyAssertionsWithComments(t *testing.T) {
	rule := NewTestDocumentationRule()

	assertions := make([]models.Assertion, 8)
	for i := range assertions {
		assertions[i] = models.Assertion{Type: "XCTAssertEqual", LineNumber: 10 + i}
	}

	method := &models.TestMethod{
		Name:       "testManyAssertions",
		ClassName:  "AssertionTests",
		LineNumber: 5,
		SourceCode: "XCTAssertEqual(a, b);\nXCTAssertEqual(c, d);",
		Assertions: assertions,
		Comments:   []string{"// Validates all fields of the response object match expected values"},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "AssertionTests", FilePath: "/path/to/AssertionTests.m"},
		TestFile:   &models.TestFile{Path: "/path/to/AssertionTests.m"},
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if strings.Contains(f.Message, "Complex test method has no documentation") {
			t.Errorf("Did not expect missing-documentation finding for test with comments, got: %s", f.Message)
		}
	}
}
