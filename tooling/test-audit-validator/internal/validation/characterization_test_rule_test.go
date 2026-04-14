package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestCharacterizationTestRule_Name(t *testing.T) {
	rule := NewCharacterizationTestRule()
	if rule.Name() != "CharacterizationTestRule" {
		t.Errorf("Expected rule name 'CharacterizationTestRule', got '%s'", rule.Name())
	}
}

func TestCharacterizationTestRule_Severity(t *testing.T) {
	rule := NewCharacterizationTestRule()
	if rule.Severity() != MEDIUM {
		t.Errorf("Expected severity MEDIUM, got %v", rule.Severity())
	}
}

func TestCharacterizationTestRule_Description(t *testing.T) {
	rule := NewCharacterizationTestRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestCharacterizationTestRule_IdentifyByBaseClass(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "MyCharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testSomeCharacterization",
		ClassName:  "MyCharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/MyCharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should detect it's a characterization test and flag weak assertions
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test with only weak assertions")
	}

	if len(findings) > 0 {
		if findings[0].Severity != MEDIUM {
			t.Errorf("Expected MEDIUM severity, got %v", findings[0].Severity)
		}
		if findings[0].TestMethod != "testSomeCharacterization" {
			t.Errorf("Expected test method 'testSomeCharacterization', got '%s'", findings[0].TestMethod)
		}
	}
}

func TestCharacterizationTestRule_IdentifyByClassName(t *testing.T) {
	rule := NewCharacterizationTestRule()

	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: nil,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testBehavior",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should detect it's a characterization test by class name
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test identified by class name")
	}
}

func TestCharacterizationTestRule_IdentifyByMethodName(t *testing.T) {
	rule := NewCharacterizationTestRule()

	testClass := &models.TestClass{
		Name:      "SomeTests",
		BaseClass: nil,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterizationOfBehavior",
		ClassName:  "SomeTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/SomeTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should detect it's a characterization test by method name
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test identified by method name")
	}
}

func TestCharacterizationTestRule_IdentifyByComment(t *testing.T) {
	rule := NewCharacterizationTestRule()

	testClass := &models.TestClass{
		Name:      "SomeTests",
		BaseClass: nil,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testSomething",
		ClassName:  "SomeTests",
		LineNumber: 10,
		Comments: []string{
			"// This test captures the current behavior for regression detection",
		},
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/SomeTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should detect it's a characterization test by comment
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test identified by comment")
	}
}

func TestCharacterizationTestRule_NoAssertions(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterization",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{}, // No assertions
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should flag characterization test with no assertions
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test with no assertions")
	}

	if len(findings) > 0 {
		if findings[0].Severity != HIGH {
			t.Errorf("Expected HIGH severity for no assertions, got %v", findings[0].Severity)
		}
	}
}

func TestCharacterizationTestRule_OnlyWeakAssertions(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterization",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
			{Type: "XCTAssertNotNil", LineNumber: 16},
			{Type: "XCTAssertNoThrow", LineNumber: 17},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should flag characterization test with only weak assertions
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test with only weak assertions")
	}

	if len(findings) > 0 {
		if findings[0].Severity != MEDIUM {
			t.Errorf("Expected MEDIUM severity for only weak assertions, got %v", findings[0].Severity)
		}
		if !stringContains(findings[0].Message, "only checks for non-null results") {
			t.Errorf("Expected message about non-null checks, got: %s", findings[0].Message)
		}
	}
}

func TestCharacterizationTestRule_GoodCharacterizationTest(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterization",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", LineNumber: 15},
			{Type: "XCTAssertEqualObjects", LineNumber: 16},
			{Type: "XCTAssertTrue", LineNumber: 17},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should not flag good characterization test with specific value assertions
	if len(findings) > 0 {
		t.Errorf("Expected no findings for good characterization test, got %d findings", len(findings))
	}
}

func TestCharacterizationTestRule_MixedAssertions(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterization",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
			{Type: "XCTAssertNotNil", LineNumber: 16},
			{Type: "XCTAssertEqual", LineNumber: 17},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should flag characterization test with more weak than specific assertions
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test with more weak than specific assertions")
	}

	if len(findings) > 0 {
		if findings[0].Severity != LOW {
			t.Errorf("Expected LOW severity for mixed assertions, got %v", findings[0].Severity)
		}
		if !stringContains(findings[0].Message, "more weak assertions") {
			t.Errorf("Expected message about more weak assertions, got: %s", findings[0].Message)
		}
	}
}

func TestCharacterizationTestRule_NotCharacterizationTest(t *testing.T) {
	rule := NewCharacterizationTestRule()

	testClass := &models.TestClass{
		Name:      "RegularTests",
		BaseClass: nil,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testSomething",
		ClassName:  "RegularTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/RegularTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should not flag regular tests
	if len(findings) > 0 {
		t.Errorf("Expected no findings for non-characterization test, got %d findings", len(findings))
	}
}

func TestCharacterizationTestRule_NilContext(t *testing.T) {
	rule := NewCharacterizationTestRule()

	// Test with nil method
	ctx := ValidationContext{
		TestFile:   &models.TestFile{},
		TestClass:  &models.TestClass{},
		TestMethod: nil,
	}

	findings := rule.Validate(ctx)

	// Should return no findings for nil method
	if len(findings) > 0 {
		t.Errorf("Expected no findings for nil method, got %d findings", len(findings))
	}
}

func TestCharacterizationTestRule_SpecificValueAssertionTypes(t *testing.T) {
	rule := NewCharacterizationTestRule()

	specificTypes := []string{
		"XCTAssertEqual",
		"XCTAssertEqualObjects",
		"XCTAssertEqualWithAccuracy",
		"XCTAssertGreaterThan",
		"XCTAssertGreaterThanOrEqual",
		"XCTAssertLessThan",
		"XCTAssertLessThanOrEqual",
		"XCTAssertTrue",
		"XCTAssertFalse",
	}

	for _, assertionType := range specificTypes {
		assertion := models.Assertion{
			Type:       assertionType,
			LineNumber: 10,
		}

		if !rule.isSpecificValueAssertion(assertion) {
			t.Errorf("Expected %s to be recognized as specific value assertion", assertionType)
		}
	}
}

func TestCharacterizationTestRule_WeakAssertionTypes(t *testing.T) {
	rule := NewCharacterizationTestRule()

	weakTypes := []string{
		"XCTAssertNotNil",
		"XCTAssertNil",
		"XCTAssertNoThrow",
	}

	for _, assertionType := range weakTypes {
		assertion := models.Assertion{
			Type:       assertionType,
			LineNumber: 10,
		}

		if !rule.isWeakAssertion(assertion) {
			t.Errorf("Expected %s to be recognized as weak assertion", assertionType)
		}
	}
}

func TestCharacterizationTestRule_MostlySpecificAssertions(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterization",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", LineNumber: 15},
			{Type: "XCTAssertEqual", LineNumber: 16},
			{Type: "XCTAssertNotNil", LineNumber: 17},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should not flag when specific assertions outnumber weak ones
	if len(findings) > 0 {
		t.Errorf("Expected no findings when specific assertions outnumber weak ones, got %d findings", len(findings))
	}
}

// Helper function to check if a string contains a substring
func stringContains(s, substr string) bool {
	return len(s) > 0 && len(substr) > 0 && (s == substr || len(s) >= len(substr) && findSubstring(s, substr))
}

func findSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func TestCharacterizationTestRule_EqualWeakAndSpecificAssertions(t *testing.T) {
	rule := NewCharacterizationTestRule()

	baseClass := "CharacterizationTestBase"
	testClass := &models.TestClass{
		Name:      "CharacterizationTests",
		BaseClass: &baseClass,
		Methods:   []models.TestMethod{},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterization",
		ClassName:  "CharacterizationTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", LineNumber: 15},
			{Type: "XCTAssertNotNil", LineNumber: 16},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/CharacterizationTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// With equal counts, should not flag (specific assertions are present)
	if len(findings) > 0 {
		t.Errorf("Expected no findings when specific and weak assertions are equal, got %d findings", len(findings))
	}
}

func TestCharacterizationTestRule_AllAssertionTypes(t *testing.T) {
	rule := NewCharacterizationTestRule()

	// Test all specific assertion types
	specificTypes := []string{
		"XCTAssertEqual",
		"XCTAssertEqualObjects",
		"XCTAssertEqualWithAccuracy",
		"XCTAssertGreaterThan",
		"XCTAssertGreaterThanOrEqual",
		"XCTAssertLessThan",
		"XCTAssertLessThanOrEqual",
		"XCTAssertTrue",
		"XCTAssertFalse",
	}

	for _, assertionType := range specificTypes {
		baseClass := "CharacterizationTestBase"
		testClass := &models.TestClass{
			Name:      "CharacterizationTests",
			BaseClass: &baseClass,
			Methods:   []models.TestMethod{},
		}

		testMethod := &models.TestMethod{
			Name:       "testCharacterization",
			ClassName:  "CharacterizationTests",
			LineNumber: 10,
			Assertions: []models.Assertion{
				{Type: assertionType, LineNumber: 15},
			},
		}

		testFile := &models.TestFile{
			Path:    "Tests/CharacterizationTests.m",
			Classes: []models.TestClass{*testClass},
		}

		ctx := ValidationContext{
			TestFile:   testFile,
			TestClass:  testClass,
			TestMethod: testMethod,
		}

		findings := rule.Validate(ctx)

		// Should not flag when using specific assertion types
		if len(findings) > 0 {
			t.Errorf("Expected no findings for %s assertion type, got %d findings", assertionType, len(findings))
		}
	}
}

func TestCharacterizationTestRule_IdentifyByMultipleMethods(t *testing.T) {
	rule := NewCharacterizationTestRule()

	testClass := &models.TestClass{
		Name:      "SomeTests",
		BaseClass: nil,
		Methods: []models.TestMethod{
			{
				Name: "testCharacterizationOfBehavior",
				Comments: []string{
					"// This test captures the current behavior",
				},
			},
		},
	}

	testMethod := &models.TestMethod{
		Name:       "testCharacterizationOfBehavior",
		ClassName:  "SomeTests",
		LineNumber: 10,
		Comments: []string{
			"// This test captures the current behavior",
		},
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	testFile := &models.TestFile{
		Path:    "Tests/SomeTests.m",
		Classes: []models.TestClass{*testClass},
	}

	ctx := ValidationContext{
		TestFile:   testFile,
		TestClass:  testClass,
		TestMethod: testMethod,
	}

	findings := rule.Validate(ctx)

	// Should detect characterization test by both method name and comment
	if len(findings) == 0 {
		t.Error("Expected findings for characterization test identified by multiple indicators")
	}
}
