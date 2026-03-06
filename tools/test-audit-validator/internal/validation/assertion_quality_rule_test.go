package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestAssertionQualityRule_Name(t *testing.T) {
	rule := NewAssertionQualityRule()
	if rule.Name() != "AssertionQualityRule" {
		t.Errorf("Expected rule name 'AssertionQualityRule', got '%s'", rule.Name())
	}
}

func TestAssertionQualityRule_Severity(t *testing.T) {
	rule := NewAssertionQualityRule()
	if rule.Severity() != MEDIUM {
		t.Errorf("Expected severity MEDIUM, got %v", rule.Severity())
	}
}

func TestAssertionQualityRule_Description(t *testing.T) {
	rule := NewAssertionQualityRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestAssertionQualityRule_NoFindings_NoAssertions(t *testing.T) {
	rule := NewAssertionQualityRule()

	method := &models.TestMethod{
		Name:       "testSomething",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for test with no assertions, got %d", len(findings))
	}
}

func TestAssertionQualityRule_LowAssertionCount_SingleAssertion(t *testing.T) {
	rule := NewAssertionQualityRule()

	method := &models.TestMethod{
		Name:       "testSingleAssertion",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)
	// Expect 2 findings: single existence assertion + low quality score
	if len(findings) < 1 {
		t.Fatalf("Expected at least 1 finding for single existence assertion, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Severity != LOW {
		t.Errorf("Expected LOW severity, got %v", finding.Severity)
	}
	if finding.RuleName != "AssertionQualityRule" {
		t.Errorf("Expected rule name 'AssertionQualityRule', got '%s'", finding.RuleName)
	}
	if finding.TestMethod != "testSingleAssertion" {
		t.Errorf("Expected test method 'testSingleAssertion', got '%s'", finding.TestMethod)
	}
}

func TestAssertionQualityRule_NoFinding_TwoAssertions(t *testing.T) {
	rule := NewAssertionQualityRule()

	method := &models.TestMethod{
		Name:       "testTwoAssertions",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", LineNumber: 15},
			{Type: "XCTAssertTrue", LineNumber: 16},
		},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not have low assertion count finding (only triggers for exactly 1)
	for _, finding := range findings {
		if finding.Message != "" && finding.Message[0:4] == "Test" {
			// Check if it's about low assertion count
			if len(method.Assertions) == 1 {
				t.Error("Should not flag test with 2 assertions for low count")
			}
		}
	}
}

func TestAssertionQualityRule_HighAssertionCount_TwentyOneAssertions(t *testing.T) {
	rule := NewAssertionQualityRule()

	// Create 21 assertions
	assertions := make([]models.Assertion, 21)
	for i := 0; i < 21; i++ {
		assertions[i] = models.Assertion{
			Type:       "XCTAssertEqual",
			LineNumber: 10 + i,
		}
	}

	method := &models.TestMethod{
		Name:       "testManyAssertions",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: assertions,
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should have at least one finding for high assertion count
	foundHighCountFinding := false
	for _, finding := range findings {
		if finding.Severity == MEDIUM && finding.TestMethod == "testManyAssertions" {
			foundHighCountFinding = true
			break
		}
	}

	if !foundHighCountFinding {
		t.Error("Expected finding for test with 21 assertions")
	}
}

func TestAssertionQualityRule_NoFinding_TwentyAssertions(t *testing.T) {
	rule := NewAssertionQualityRule()

	// Create exactly 20 assertions (threshold)
	assertions := make([]models.Assertion, 20)
	for i := 0; i < 20; i++ {
		assertions[i] = models.Assertion{
			Type:       "XCTAssertEqual",
			LineNumber: 10 + i,
		}
	}

	method := &models.TestMethod{
		Name:       "testTwentyAssertions",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: assertions,
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not flag exactly 20 assertions (threshold is >20)
	for _, finding := range findings {
		if finding.Message != "" {
			t.Errorf("Should not flag test with exactly 20 assertions, but got: %s", finding.Message)
		}
	}
}

func TestAssertionQualityRule_LowQuality_OnlyExistenceAssertions(t *testing.T) {
	rule := NewAssertionQualityRule()

	method := &models.TestMethod{
		Name:       "testOnlyNotNil",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
			{Type: "XCTAssertNotNil", LineNumber: 16},
			{Type: "XCTAssertNotNil", LineNumber: 17},
			{Type: "XCTAssertNotNil", LineNumber: 18},
		},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should have finding for low quality (only existence assertions)
	foundQualityFinding := false
	for _, finding := range findings {
		if finding.Severity == LOW && finding.TestMethod == "testOnlyNotNil" {
			foundQualityFinding = true
			break
		}
	}

	if !foundQualityFinding {
		t.Error("Expected finding for test with only existence assertions")
	}
}

func TestAssertionQualityRule_HighQuality_ValueAssertions(t *testing.T) {
	rule := NewAssertionQualityRule()

	method := &models.TestMethod{
		Name:       "testValueAssertions",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", LineNumber: 15},
			{Type: "XCTAssertEqual", LineNumber: 16},
			{Type: "XCTAssertTrue", LineNumber: 17},
		},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not have quality finding (all value assertions)
	for _, finding := range findings {
		if finding.Severity == LOW {
			t.Errorf("Should not flag test with all value assertions, but got: %s", finding.Message)
		}
	}
}

func TestAssertionQualityRule_MixedQuality_SomeValueSomeExistence(t *testing.T) {
	rule := NewAssertionQualityRule()

	method := &models.TestMethod{
		Name:       "testMixedAssertions",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", LineNumber: 15},
			{Type: "XCTAssertNotNil", LineNumber: 16},
			{Type: "XCTAssertTrue", LineNumber: 17},
		},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// With 2 value assertions and 1 existence, quality should be acceptable
	// Quality score = (2/3) + (1/3 * 0.3) = 0.67 + 0.1 = 0.77 (above 0.4 threshold)
	for _, finding := range findings {
		if finding.Severity == LOW {
			t.Errorf("Should not flag test with mixed but acceptable quality, but got: %s", finding.Message)
		}
	}
}

func TestAssertionQualityRule_IsValueAssertion(t *testing.T) {
	rule := NewAssertionQualityRule()

	tests := []struct {
		assertionType string
		expected      bool
	}{
		{"XCTAssertEqual", true},
		{"XCTAssertNotEqual", true},
		{"XCTAssertEqualObjects", true},
		{"XCTAssertGreaterThan", true},
		{"XCTAssertLessThan", true},
		{"XCTAssertTrue", true},
		{"XCTAssertFalse", true},
		{"XCTAssertThrows", true},
		{"XCTFail", true},
		{"XCTAssertNotNil", false},
		{"XCTAssertNil", false},
		{"XCTAssertNoThrow", false},
	}

	for _, tt := range tests {
		assertion := models.Assertion{Type: tt.assertionType}
		result := rule.isValueAssertion(assertion)
		if result != tt.expected {
			t.Errorf("isValueAssertion(%s) = %v, expected %v", tt.assertionType, result, tt.expected)
		}
	}
}

func TestAssertionQualityRule_IsExistenceAssertion(t *testing.T) {
	rule := NewAssertionQualityRule()

	tests := []struct {
		assertionType string
		expected      bool
	}{
		{"XCTAssertNotNil", true},
		{"XCTAssertNil", true},
		{"XCTAssertNoThrow", true},
		{"XCTAssertEqual", false},
		{"XCTAssertTrue", false},
		{"XCTAssertThrows", false},
	}

	for _, tt := range tests {
		assertion := models.Assertion{Type: tt.assertionType}
		result := rule.isExistenceAssertion(assertion)
		if result != tt.expected {
			t.Errorf("isExistenceAssertion(%s) = %v, expected %v", tt.assertionType, result, tt.expected)
		}
	}
}

func TestAssertionQualityRule_CalculateAssertionDensity(t *testing.T) {
	rule := NewAssertionQualityRule()

	tests := []struct {
		name            string
		assertionCount  int
		expectedDensity float64
	}{
		{"No assertions", 0, 0.0},
		{"One assertion", 1, 1.0},
		{"Five assertions", 5, 5.0},
		{"Twenty assertions", 20, 20.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertions := make([]models.Assertion, tt.assertionCount)
			for i := 0; i < tt.assertionCount; i++ {
				assertions[i] = models.Assertion{Type: "XCTAssertEqual"}
			}

			method := &models.TestMethod{
				Name:       "testMethod",
				Assertions: assertions,
			}

			density := rule.calculateAssertionDensity(method)
			if density != tt.expectedDensity {
				t.Errorf("calculateAssertionDensity() = %.2f, expected %.2f", density, tt.expectedDensity)
			}
		})
	}
}

func TestAssertionQualityRule_CalculateAssertionQualityScore(t *testing.T) {
	rule := NewAssertionQualityRule()

	tests := []struct {
		name                string
		valueAssertions     int
		existenceAssertions int
		totalAssertions     int
		expectedScore       float64
	}{
		{"All value assertions", 5, 0, 5, 1.0},
		{"All existence assertions", 0, 5, 5, 0.3},
		{"Mixed 50/50", 5, 5, 10, 0.65},      // 0.5 + (0.5 * 0.3) = 0.65
		{"Mostly value", 8, 2, 10, 0.86},     // 0.8 + (0.2 * 0.3) = 0.86
		{"Mostly existence", 2, 8, 10, 0.44}, // 0.2 + (0.8 * 0.3) = 0.44
		{"No assertions", 0, 0, 0, 0.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score := rule.calculateAssertionQualityScore(tt.valueAssertions, tt.existenceAssertions, tt.totalAssertions)
			if score < tt.expectedScore-0.01 || score > tt.expectedScore+0.01 {
				t.Errorf("calculateAssertionQualityScore(%d, %d, %d) = %.2f, expected %.2f",
					tt.valueAssertions, tt.existenceAssertions, tt.totalAssertions, score, tt.expectedScore)
			}
		})
	}
}

func TestAssertionQualityRule_QualityScoreBounds(t *testing.T) {
	rule := NewAssertionQualityRule()

	// Test that quality score is always between 0.0 and 1.0
	testCases := []struct {
		valueAssertions     int
		existenceAssertions int
		totalAssertions     int
	}{
		{0, 0, 0},
		{1, 0, 1},
		{0, 1, 1},
		{10, 0, 10},
		{0, 10, 10},
		{5, 5, 10},
		{100, 0, 100},
		{0, 100, 100},
	}

	for _, tc := range testCases {
		score := rule.calculateAssertionQualityScore(tc.valueAssertions, tc.existenceAssertions, tc.totalAssertions)
		if score < 0.0 || score > 1.0 {
			t.Errorf("Quality score %.2f is out of bounds [0.0, 1.0] for value=%d, existence=%d, total=%d",
				score, tc.valueAssertions, tc.existenceAssertions, tc.totalAssertions)
		}
	}
}

func TestAssertionQualityRule_MultipleFindings(t *testing.T) {
	rule := NewAssertionQualityRule()

	// Create a test with both single assertion AND low quality
	// This should only trigger the single assertion finding since we have exactly 1 assertion
	method := &models.TestMethod{
		Name:       "testSingleExistenceAssertion",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", LineNumber: 15},
		},
	}

	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should have finding for single assertion
	// Quality check requires multiple assertions to be meaningful
	if len(findings) == 0 {
		t.Error("Expected at least one finding")
	}

	// Verify we got the low assertion count finding
	foundLowCount := false
	for _, finding := range findings {
		if finding.Severity == LOW {
			foundLowCount = true
		}
	}

	if !foundLowCount {
		t.Error("Expected low assertion count finding")
	}
}

func TestAssertionQualityRule_NoContext(t *testing.T) {
	rule := NewAssertionQualityRule()

	// Test with nil method
	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "test.m",
		},
		TestMethod: nil,
	}

	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for nil method, got %d", len(findings))
	}
}
