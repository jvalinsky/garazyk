package validation

import (
	"fmt"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// AssertionQualityRule analyzes the quality and quantity of assertions in test methods
type AssertionQualityRule struct{}

// NewAssertionQualityRule creates a new instance of the rule
func NewAssertionQualityRule() *AssertionQualityRule {
	return &AssertionQualityRule{}
}

// Name returns the unique name of this rule
func (r *AssertionQualityRule) Name() string {
	return "AssertionQualityRule"
}

// Severity returns the severity level for findings from this rule
func (r *AssertionQualityRule) Severity() Severity {
	return MEDIUM // Default severity, adjusted based on specific issues
}

// Description returns a human-readable description of what this rule validates
func (r *AssertionQualityRule) Description() string {
	return "Analyzes the quality and quantity of assertions in test methods"
}

// Validate applies the rule to the given context and returns findings
func (r *AssertionQualityRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod

	// Skip if no assertions (will be caught by other rules)
	if len(method.Assertions) == 0 {
		return nil
	}

	var findings []Finding

	// Check for low assertion count (single assertion)
	if finding := r.checkLowAssertionCount(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Check for high assertion count (>20 assertions)
	if finding := r.checkHighAssertionCount(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Check assertion quality (value vs existence assertions)
	if finding := r.checkAssertionQuality(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// checkLowAssertionCount identifies tests with only one weak assertion
func (r *AssertionQualityRule) checkLowAssertionCount(method *models.TestMethod, ctx ValidationContext) *Finding {
	if len(method.Assertions) != 1 {
		return nil
	}

	// Skip if the single assertion is a value assertion (e.g., XCTAssertEqual)
	// — one focused value assertion is a valid testing pattern
	if r.isValueAssertion(method.Assertions[0]) {
		return nil
	}

	// Calculate assertion density (assertions per test method)
	density := r.calculateAssertionDensity(method)

	return &Finding{
		RuleName:   r.Name(),
		Severity:   LOW,
		TestMethod: method.Name,
		TestClass:  method.ClassName,
		FilePath:   ctx.TestFile.Path,
		LineNumber: method.LineNumber,
		Message: fmt.Sprintf(
			"Test '%s' has only 1 existence assertion (density: %.2f). Consider adding value assertions.",
			method.Name,
			density,
		),
		Recommendation: "Replace existence assertion (XCTAssertNotNil) with a value assertion (XCTAssertEqual) that validates actual behavior.",
		Confidence:     0.70,
	}
}

// checkHighAssertionCount identifies tests with excessive assertions (>20)
func (r *AssertionQualityRule) checkHighAssertionCount(method *models.TestMethod, ctx ValidationContext) *Finding {
	assertionCount := len(method.Assertions)

	if assertionCount <= 20 {
		return nil
	}

	// Calculate assertion density
	density := r.calculateAssertionDensity(method)

	return &Finding{
		RuleName:   r.Name(),
		Severity:   MEDIUM,
		TestMethod: method.Name,
		TestClass:  method.ClassName,
		FilePath:   ctx.TestFile.Path,
		LineNumber: method.LineNumber,
		Message: fmt.Sprintf(
			"Test '%s' has %d assertions (density: %.2f). This may indicate the test is testing too much.",
			method.Name,
			assertionCount,
			density,
		),
		Recommendation: "Consider splitting this test into multiple smaller, focused tests. Each test should validate a single behavior or aspect.",
		Confidence:     0.75,
	}
}

// checkAssertionQuality analyzes the quality of assertions (value vs existence)
func (r *AssertionQualityRule) checkAssertionQuality(method *models.TestMethod, ctx ValidationContext) *Finding {
	if len(method.Assertions) == 0 {
		return nil
	}

	// Classify assertions
	valueAssertions := 0
	existenceAssertions := 0

	for _, assertion := range method.Assertions {
		if r.isValueAssertion(assertion) {
			valueAssertions++
		} else if r.isExistenceAssertion(assertion) {
			existenceAssertions++
		}
	}

	// Calculate assertion quality score
	qualityScore := r.calculateAssertionQualityScore(valueAssertions, existenceAssertions, len(method.Assertions))

	// Only report if quality is very low (almost entirely existence assertions)
	if qualityScore <= 0.3 && existenceAssertions > 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   LOW,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' has low assertion quality (score: %.2f). %d existence assertion(s) vs %d value assertion(s).",
				method.Name,
				qualityScore,
				existenceAssertions,
				valueAssertions,
			),
			Recommendation: "Replace existence assertions (XCTAssertNotNil) with more specific value assertions (XCTAssertEqual) that validate actual behavior.",
			Confidence:     0.65,
		}
	}

	return nil
}

// calculateAssertionDensity calculates assertions per test method
func (r *AssertionQualityRule) calculateAssertionDensity(method *models.TestMethod) float64 {
	// For a single test method, density is just the assertion count
	// In a broader context, this would be assertions per method across multiple methods
	return float64(len(method.Assertions))
}

// isValueAssertion checks if an assertion validates specific values
func (r *AssertionQualityRule) isValueAssertion(assertion models.Assertion) bool {
	valueAssertionTypes := map[string]bool{
		"XCTAssertEqual":              true,
		"XCTAssertNotEqual":           true,
		"XCTAssertEqualObjects":       true,
		"XCTAssertGreaterThan":        true,
		"XCTAssertLessThan":           true,
		"XCTAssertGreaterThanOrEqual": true,
		"XCTAssertLessThanOrEqual":    true,
		"XCTAssertTrue":               true, // Can be value assertion if checking specific condition
		"XCTAssertFalse":              true, // Can be value assertion if checking specific condition
		"XCTAssertThrows":             true, // Validates specific behavior (error throwing)
		"XCTFail":                     true, // Explicit failure is a form of value assertion
	}

	return valueAssertionTypes[assertion.Type]
}

// isExistenceAssertion checks if an assertion only validates existence/non-existence
func (r *AssertionQualityRule) isExistenceAssertion(assertion models.Assertion) bool {
	existenceAssertionTypes := map[string]bool{
		"XCTAssertNil":     true,
		"XCTAssertNotNil":  true,
		"XCTAssertNoThrow": true, // Only checks that no exception is thrown
	}

	return existenceAssertionTypes[assertion.Type]
}

// calculateAssertionQualityScore computes a quality score (0.0-1.0) based on assertion types
func (r *AssertionQualityRule) calculateAssertionQualityScore(valueAssertions, existenceAssertions, totalAssertions int) float64 {
	if totalAssertions == 0 {
		return 0.0
	}

	// Score is based on the ratio of value assertions to total assertions
	// Value assertions are weighted more heavily
	valueRatio := float64(valueAssertions) / float64(totalAssertions)
	existenceRatio := float64(existenceAssertions) / float64(totalAssertions)

	// Quality score: value assertions contribute fully, existence assertions contribute partially
	score := valueRatio + (existenceRatio * 0.3)

	// Normalize to 0.0-1.0 range
	if score > 1.0 {
		score = 1.0
	}

	return score
}
