package validation

import (
	"fmt"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// FalsePositiveDetectionRule detects tests that pass without validating behavior
type FalsePositiveDetectionRule struct{}

// NewFalsePositiveDetectionRule creates a new instance of the rule
func NewFalsePositiveDetectionRule() *FalsePositiveDetectionRule {
	return &FalsePositiveDetectionRule{}
}

// Name returns the unique name of this rule
func (r *FalsePositiveDetectionRule) Name() string {
	return "FalsePositiveDetectionRule"
}

// Severity returns the severity level for findings from this rule
func (r *FalsePositiveDetectionRule) Severity() Severity {
	return CRITICAL // False positives provide false confidence
}

// Description returns a human-readable description of what this rule validates
func (r *FalsePositiveDetectionRule) Description() string {
	return "Detects tests that pass without validating behavior (false positives)"
}

// FalsePositivePattern represents the type of false positive detected
type FalsePositivePattern string

const (
	PatternOnlyNonNullChecks    FalsePositivePattern = "only_non_null_checks"
	PatternOnlyNoThrowChecks    FalsePositivePattern = "only_no_throw_checks"
	PatternTrivialAssertions    FalsePositivePattern = "trivial_assertions"
	PatternSetupWithoutVerify   FalsePositivePattern = "setup_without_verification"
	PatternUnreachableAssertion FalsePositivePattern = "unreachable_assertions"
)

// Validate applies the rule to the given context and returns findings
func (r *FalsePositiveDetectionRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod

	var findings []Finding

	// Check for each false positive pattern
	// Note: Some checks require assertions, others don't (like setup-without-verification)

	if len(method.Assertions) > 0 {
		// These checks require assertions to be present
		if finding := r.checkOnlyNonNullChecks(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}

		if finding := r.checkOnlyNoThrowChecks(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}

		if finding := r.checkTrivialAssertions(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}

		if finding := r.checkUnreachableAssertions(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}
	}

	// This check works with or without assertions
	if finding := r.checkSetupWithoutVerification(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// checkOnlyNonNullChecks detects tests that only assert non-null results
func (r *FalsePositiveDetectionRule) checkOnlyNonNullChecks(method *models.TestMethod, ctx ValidationContext) *Finding {
	if len(method.Assertions) == 0 {
		return nil
	}

	// Check if all assertions are XCTAssertNotNil
	allNonNullChecks := true
	for _, assertion := range method.Assertions {
		if assertion.Type != "XCTAssertNotNil" {
			allNonNullChecks = false
			break
		}
	}

	if !allNonNullChecks {
		return nil
	}

	return &Finding{
		RuleName:   r.Name(),
		Severity:   CRITICAL,
		TestMethod: method.Name,
		TestClass:  method.ClassName,
		FilePath:   ctx.TestFile.Path,
		LineNumber: method.LineNumber,
		Message: fmt.Sprintf(
			"Test '%s' only checks that results are non-null (%d XCTAssertNotNil assertions) without validating actual values or behavior",
			method.Name,
			len(method.Assertions),
		),
		Recommendation: "Add assertions to validate actual values, properties, or behavior. Non-null checks alone don't verify correctness.",
		Confidence:     0.95,
	}
}

// checkOnlyNoThrowChecks detects tests that only assert methods don't throw
func (r *FalsePositiveDetectionRule) checkOnlyNoThrowChecks(method *models.TestMethod, ctx ValidationContext) *Finding {
	if len(method.Assertions) == 0 {
		return nil
	}

	// Check if all assertions are XCTAssertNoThrow
	allNoThrowChecks := true
	for _, assertion := range method.Assertions {
		if assertion.Type != "XCTAssertNoThrow" {
			allNoThrowChecks = false
			break
		}
	}

	if !allNoThrowChecks {
		return nil
	}

	return &Finding{
		RuleName:   r.Name(),
		Severity:   CRITICAL,
		TestMethod: method.Name,
		TestClass:  method.ClassName,
		FilePath:   ctx.TestFile.Path,
		LineNumber: method.LineNumber,
		Message: fmt.Sprintf(
			"Test '%s' only checks that methods don't throw exceptions (%d XCTAssertNoThrow assertions) without validating outputs or side effects",
			method.Name,
			len(method.Assertions),
		),
		Recommendation: "Add assertions to validate the actual output, return values, or state changes. No-throw checks alone don't verify correctness.",
		Confidence:     0.95,
	}
}

// checkTrivialAssertions detects tests with trivial assertions that always pass
func (r *FalsePositiveDetectionRule) checkTrivialAssertions(method *models.TestMethod, ctx ValidationContext) *Finding {
	trivialCount := 0
	var trivialExamples []string

	for _, assertion := range method.Assertions {
		if r.isTrivialAssertion(assertion) {
			trivialCount++
			trivialExample := fmt.Sprintf("%s at line %d", assertion.Type, assertion.LineNumber)
			trivialExamples = append(trivialExamples, trivialExample)
		}
	}

	// If more than half the assertions are trivial, report it
	if trivialCount > 0 && float64(trivialCount)/float64(len(method.Assertions)) > 0.5 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   CRITICAL,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' contains %d trivial assertion(s) that always pass: %s",
				method.Name,
				trivialCount,
				strings.Join(trivialExamples, ", "),
			),
			Recommendation: "Replace trivial assertions with meaningful checks that validate actual behavior or values.",
			Confidence:     0.90,
		}
	}

	return nil
}

// isTrivialAssertion checks if an assertion is trivial (always passes)
func (r *FalsePositiveDetectionRule) isTrivialAssertion(assertion models.Assertion) bool {
	// Check for XCTAssertTrue/False with constant values
	if assertion.Type == "XCTAssertTrue" {
		for _, arg := range assertion.Arguments {
			// Extract first argument before comma (XCTAssertTrue(YES, @"message"))
			firstArg := strings.TrimSpace(strings.SplitN(arg, ",", 2)[0])
			argNormalized := strings.ToUpper(firstArg)
			if argNormalized == "YES" || argNormalized == "TRUE" || argNormalized == "1" {
				return true
			}
		}
	}

	if assertion.Type == "XCTAssertFalse" {
		for _, arg := range assertion.Arguments {
			firstArg := strings.TrimSpace(strings.SplitN(arg, ",", 2)[0])
			argNormalized := strings.ToUpper(firstArg)
			if argNormalized == "NO" || argNormalized == "FALSE" || argNormalized == "0" {
				return true
			}
		}
	}

	// Check for XCTAssertEqual with identical constant arguments
	if assertion.Type == "XCTAssertEqual" && len(assertion.Arguments) >= 2 {
		arg1 := strings.TrimSpace(assertion.Arguments[0])
		arg2 := strings.TrimSpace(assertion.Arguments[1])

		// Check if both arguments are the same constant
		if arg1 == arg2 {
			// Check if it's a constant (number or boolean literal)
			if r.isConstantLiteral(arg1) {
				return true
			}
		}
	}

	// Check for XCTAssertNil with nil literal
	if assertion.Type == "XCTAssertNil" {
		for _, arg := range assertion.Arguments {
			argNormalized := strings.TrimSpace(strings.ToLower(arg))
			if argNormalized == "nil" || argNormalized == "null" {
				return true
			}
		}
	}

	return false
}

// isConstantLiteral checks if a string represents a constant literal
func (r *FalsePositiveDetectionRule) isConstantLiteral(s string) bool {
	s = strings.TrimSpace(s)

	// Check for numeric literals
	if len(s) > 0 && (s[0] >= '0' && s[0] <= '9') {
		return true
	}

	// Check for boolean literals
	sLower := strings.ToLower(s)
	if sLower == "true" || sLower == "false" || sLower == "yes" || sLower == "no" {
		return true
	}

	return false
}

// checkSetupWithoutVerification detects tests that set up state but don't verify it
func (r *FalsePositiveDetectionRule) checkSetupWithoutVerification(method *models.TestMethod, ctx ValidationContext) *Finding {
	// Some tests verify behavior indirectly (helper assertions, perf harnesses, async expectations).
	if r.hasDelegatedVerification(method) ||
		r.isPerformanceMeasurementTest(method) ||
		r.hasExpectationDrivenVerification(method) {
		return nil
	}

	// Look for method calls that suggest setup/mutation
	setupCallCount := 0

	for _, call := range method.MethodCalls {
		if r.isSetupMethodCall(call) {
			setupCallCount++
		}
	}

	// Only flag if there are at least 2 setup calls (to avoid false positives)
	if setupCallCount < 2 {
		return nil
	}

	// If there's setup but no assertions
	if len(method.Assertions) == 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   HIGH,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' performs %d setup/mutation operation(s) but has no assertions to verify the results",
				method.Name,
				setupCallCount,
			),
			Recommendation: "Add assertions to verify that the setup operations had the expected effect on state or behavior.",
			Confidence:     0.85,
		}
	}

	// If there's significant setup but only weak assertions (non-null checks)
	if setupCallCount >= 3 {
		weakAssertionCount := 0
		for _, assertion := range method.Assertions {
			if assertion.Type == "XCTAssertNotNil" || assertion.Type == "XCTAssertNoThrow" {
				weakAssertionCount++
			}
		}

		if weakAssertionCount == len(method.Assertions) && len(method.Assertions) > 0 {
			return &Finding{
				RuleName:   r.Name(),
				Severity:   HIGH,
				TestMethod: method.Name,
				TestClass:  method.ClassName,
				FilePath:   ctx.TestFile.Path,
				LineNumber: method.LineNumber,
				Message: fmt.Sprintf(
					"Test '%s' performs %d setup operations but only has weak assertions (non-null/no-throw checks)",
					method.Name,
					setupCallCount,
				),
				Recommendation: "Add stronger assertions to verify the actual state changes or behavior resulting from the setup operations.",
				Confidence:     0.80,
			}
		}
	}

	return nil
}

// isSetupMethodCall checks if a method call is likely a setup/mutation operation
func (r *FalsePositiveDetectionRule) isSetupMethodCall(call models.MethodCall) bool {
	// Common setup/mutation method patterns
	setupPatterns := []string{
		"set", "add", "insert", "create", "update", "delete", "remove",
		"put", "push", "append", "register", "configure", "initialize",
		"save", "store", "write", "execute", "run", "perform", "apply",
		"kick", "ban", "mute", "block", "follow", "unfollow",
	}

	selectorLower := strings.ToLower(call.Selector)

	for _, pattern := range setupPatterns {
		if strings.Contains(selectorLower, pattern) {
			return true
		}
	}

	return false
}

func (r *FalsePositiveDetectionRule) hasDelegatedVerification(method *models.TestMethod) bool {
	verificationPrefixes := []string{"verify", "assert", "expect", "check", "validate"}
	for _, call := range method.MethodCalls {
		selectorLower := strings.ToLower(call.Selector)
		for _, prefix := range verificationPrefixes {
			if strings.HasPrefix(selectorLower, prefix) {
				return true
			}
		}
	}
	return false
}

func (r *FalsePositiveDetectionRule) isPerformanceMeasurementTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)
	if strings.Contains(nameLower, "performance") || strings.Contains(nameLower, "benchmark") {
		return true
	}

	sourceLower := strings.ToLower(method.SourceCode)
	if strings.Contains(sourceLower, "measureblock") || strings.Contains(sourceLower, "measuremetrics") {
		return true
	}

	for _, call := range method.MethodCalls {
		selectorLower := strings.ToLower(call.Selector)
		if strings.Contains(selectorLower, "measure") ||
			strings.Contains(selectorLower, "benchmark") ||
			strings.Contains(selectorLower, "duration") ||
			strings.Contains(selectorLower, "elapsedtime") {
			return true
		}
	}

	return false
}

func (r *FalsePositiveDetectionRule) hasExpectationDrivenVerification(method *models.TestMethod) bool {
	sourceLower := strings.ToLower(method.SourceCode)
	if strings.Contains(sourceLower, "expectationwithdescription") &&
		strings.Contains(sourceLower, "waitforexpectationswithtimeout") {
		return true
	}

	hasExpectation := false
	hasWait := false
	for _, call := range method.MethodCalls {
		selectorLower := strings.ToLower(call.Selector)
		if strings.Contains(selectorLower, "expectationwithdescription") {
			hasExpectation = true
		}
		if strings.Contains(selectorLower, "waitforexpectationswithtimeout") {
			hasWait = true
		}
	}

	return hasExpectation && hasWait
}

// checkUnreachableAssertions detects assertions in unreachable code paths
func (r *FalsePositiveDetectionRule) checkUnreachableAssertions(method *models.TestMethod, ctx ValidationContext) *Finding {
	unreachableCount := 0
	var unreachableLines []int

	for _, assertion := range method.Assertions {
		if !assertion.IsReachable {
			unreachableCount++
			unreachableLines = append(unreachableLines, assertion.LineNumber)
		}
	}

	if unreachableCount > 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   CRITICAL,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' has %d unreachable assertion(s) at line(s) %v that will never execute",
				method.Name,
				unreachableCount,
				unreachableLines,
			),
			Recommendation: "Remove unreachable code or fix the control flow to ensure assertions can execute.",
			Confidence:     1.0,
		}
	}

	return nil
}
