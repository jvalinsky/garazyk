package validation

import (
	"fmt"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// CharacterizationTestRule validates characterization tests
type CharacterizationTestRule struct{}

// NewCharacterizationTestRule creates a new instance of the rule
func NewCharacterizationTestRule() *CharacterizationTestRule {
	return &CharacterizationTestRule{}
}

// Name returns the unique name of this rule
func (r *CharacterizationTestRule) Name() string {
	return "CharacterizationTestRule"
}

// Severity returns the severity level for findings from this rule
func (r *CharacterizationTestRule) Severity() Severity {
	return MEDIUM
}

// Description returns a human-readable description of what this rule validates
func (r *CharacterizationTestRule) Description() string {
	return "Validates that characterization tests properly capture specific behavior for regression detection"
}

// Validate applies the rule to the given context and returns findings
func (r *CharacterizationTestRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod

	// Check if this is a characterization test
	if !r.isCharacterizationTest(method, ctx.TestClass) {
		return nil
	}

	var findings []Finding

	// Validate that characterization tests assert specific values
	if finding := r.checkSpecificValueAssertions(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// isCharacterizationTest checks if a test appears to be a characterization test
func (r *CharacterizationTestRule) isCharacterizationTest(method *models.TestMethod, class *models.TestClass) bool {
	// Check if class inherits from CharacterizationTestBase
	if class.BaseClass != nil && strings.Contains(*class.BaseClass, "CharacterizationTestBase") {
		return true
	}

	// Check class name
	className := strings.ToLower(class.Name)
	if strings.Contains(className, "characterization") {
		return true
	}

	// Check method name
	methodName := strings.ToLower(method.Name)
	if strings.Contains(methodName, "characterization") || strings.Contains(methodName, "characterize") {
		return true
	}

	// Check comments for characterization indicators
	for _, comment := range method.Comments {
		commentLower := strings.ToLower(comment)
		if strings.Contains(commentLower, "characterization") ||
			strings.Contains(commentLower, "characterize") ||
			strings.Contains(commentLower, "capture") && strings.Contains(commentLower, "behavior") {
			return true
		}
	}

	return false
}

// checkSpecificValueAssertions validates that characterization tests assert specific values
func (r *CharacterizationTestRule) checkSpecificValueAssertions(method *models.TestMethod, ctx ValidationContext) *Finding {
	if len(method.Assertions) == 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   HIGH,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Characterization test '%s' has no assertions to capture behavior",
				method.Name,
			),
			Recommendation: "Add assertions that capture specific output values or states to enable regression detection.",
			Confidence:     0.95,
		}
	}

	// Count specific value assertions vs weak assertions
	specificValueCount := 0
	weakAssertionCount := 0

	for _, assertion := range method.Assertions {
		if r.isSpecificValueAssertion(assertion) {
			specificValueCount++
		} else if r.isWeakAssertion(assertion) {
			weakAssertionCount++
		}
	}

	// If all assertions are weak (only non-null checks), flag as weak characterization test
	if weakAssertionCount > 0 && specificValueCount == 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Characterization test '%s' only checks for non-null results (%d weak assertions) without validating specific values",
				method.Name,
				weakAssertionCount,
			),
			Recommendation: "Add assertions that capture specific output values, properties, or states. Characterization tests should document exact behavior for regression detection.",
			Confidence:     0.90,
		}
	}

	// If majority of assertions are weak, flag with lower severity
	totalAssertions := len(method.Assertions)
	if weakAssertionCount > specificValueCount && totalAssertions > 1 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   LOW,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Characterization test '%s' has more weak assertions (%d) than specific value assertions (%d)",
				method.Name,
				weakAssertionCount,
				specificValueCount,
			),
			Recommendation: "Increase the proportion of specific value assertions to better capture behavior for regression detection.",
			Confidence:     0.75,
		}
	}

	return nil
}

// isSpecificValueAssertion checks if an assertion validates specific values
func (r *CharacterizationTestRule) isSpecificValueAssertion(assertion models.Assertion) bool {
	// Assertions that check specific values
	specificAssertionTypes := []string{
		"XCTAssertEqual",
		"XCTAssertEqualObjects",
		"XCTAssertEqualWithAccuracy",
		"XCTAssertGreaterThan",
		"XCTAssertGreaterThanOrEqual",
		"XCTAssertLessThan",
		"XCTAssertLessThanOrEqual",
		"XCTAssertTrue",  // Can be specific if checking a computed condition
		"XCTAssertFalse", // Can be specific if checking a computed condition
	}

	for _, specificType := range specificAssertionTypes {
		if assertion.Type == specificType {
			return true
		}
	}

	return false
}

// isWeakAssertion checks if an assertion is weak (only existence checks)
func (r *CharacterizationTestRule) isWeakAssertion(assertion models.Assertion) bool {
	// Assertions that only check existence, not specific values
	weakAssertionTypes := []string{
		"XCTAssertNotNil",
		"XCTAssertNil",
		"XCTAssertNoThrow",
	}

	for _, weakType := range weakAssertionTypes {
		if assertion.Type == weakType {
			return true
		}
	}

	return false
}
