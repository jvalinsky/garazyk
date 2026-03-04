package validation

import (
	"fmt"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// CoverageGapRule detects gaps between claimed and validated functionality
type CoverageGapRule struct{}

// NewCoverageGapRule creates a new instance of the rule
func NewCoverageGapRule() *CoverageGapRule {
	return &CoverageGapRule{}
}

// Name returns the unique name of this rule
func (r *CoverageGapRule) Name() string {
	return "CoverageGapRule"
}

// Severity returns the severity level for findings from this rule
func (r *CoverageGapRule) Severity() Severity {
	return MEDIUM // Coverage gaps indicate incomplete testing
}

// Description returns a human-readable description of what this rule validates
func (r *CoverageGapRule) Description() string {
	return "Detects gaps between functionality claimed by test names and what is actually validated"
}

// CoverageGapType represents the type of coverage gap detected
type CoverageGapType string

const (
	GapMultipleClaimsSingleValidation CoverageGapType = "multiple_claims_single_validation"
	GapErrorHandlingWithoutException  CoverageGapType = "error_handling_without_exception"
	GapStateTransitionWithoutChecks   CoverageGapType = "state_transition_without_checks"
	GapConcurrencyWithoutRaceTesting  CoverageGapType = "concurrency_without_race_testing"
	GapPerformanceWithoutTiming       CoverageGapType = "performance_without_timing"
)

// Validate applies the rule to the given context and returns findings
func (r *CoverageGapRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod

	var findings []Finding

	// Check for each coverage gap pattern
	if finding := r.checkMultipleClaimsSingleValidation(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	if finding := r.checkErrorHandlingWithoutException(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	if finding := r.checkStateTransitionWithoutChecks(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	if finding := r.checkConcurrencyWithoutRaceTesting(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	if finding := r.checkPerformanceWithoutTiming(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// checkMultipleClaimsSingleValidation detects tests claiming multiple behaviors but only validating one
func (r *CoverageGapRule) checkMultipleClaimsSingleValidation(method *models.TestMethod, ctx ValidationContext) *Finding {
	nameLower := strings.ToLower(method.Name)

	// Look for "And" or "And" patterns in test names
	hasMultipleClaims := strings.Contains(nameLower, "and") ||
		strings.Contains(method.Name, "And")

	if !hasMultipleClaims {
		return nil
	}

	// If test claims multiple behaviors but has very few assertions
	if len(method.Assertions) <= 1 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' claims to test multiple behaviors (contains 'And') but only has %d assertion(s)",
				method.Name,
				len(method.Assertions),
			),
			Recommendation: "Add assertions to validate all claimed behaviors, or split into separate focused tests.",
			Confidence:     0.75,
		}
	}

	return nil
}

// checkErrorHandlingWithoutException detects error handling claims without exception checks
func (r *CoverageGapRule) checkErrorHandlingWithoutException(method *models.TestMethod, ctx ValidationContext) *Finding {
	nameLower := strings.ToLower(method.Name)

	// Look for error handling keywords in test name
	errorKeywords := []string{
		"error", "invalid", "malformed", "reject", "fail",
		"throw", "exception", "handle", "bad", "wrong",
	}

	claimsErrorHandling := false
	for _, keyword := range errorKeywords {
		if strings.Contains(nameLower, keyword) {
			claimsErrorHandling = true
			break
		}
	}

	if !claimsErrorHandling {
		return nil
	}

	// Check if test has exception-related assertions
	hasExceptionCheck := false
	for _, assertion := range method.Assertions {
		if assertion.Type == "XCTAssertThrows" ||
			assertion.Type == "XCTAssertThrowsError" ||
			assertion.Type == "XCTAssertThrowsSpecific" {
			hasExceptionCheck = true
			break
		}
	}

	// Also check for error parameter validation patterns
	hasErrorValidation := false
	for _, assertion := range method.Assertions {
		for _, arg := range assertion.Arguments {
			argLower := strings.ToLower(arg)
			if strings.Contains(argLower, "error") && assertion.Type == "XCTAssertNotNil" {
				hasErrorValidation = true
				break
			}
		}
	}

	if !hasExceptionCheck && !hasErrorValidation {
		// Use the rule's base severity (MEDIUM) but this specific gap type is more severe
		return &Finding{
			RuleName:   r.Name(),
			Severity:   HIGH, // Error handling gaps are more critical
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' claims to test error handling but has no exception assertions (XCTAssertThrows) or error validation",
				method.Name,
			),
			Recommendation: "Add XCTAssertThrows or XCTAssertThrowsError to verify that errors are properly raised, or validate error objects/codes.",
			Confidence:     0.85,
		}
	}

	return nil
}

// checkStateTransitionWithoutChecks detects state transition claims without before/after checks
func (r *CoverageGapRule) checkStateTransitionWithoutChecks(method *models.TestMethod, ctx ValidationContext) *Finding {
	nameLower := strings.ToLower(method.Name)

	// Look for state transition keywords
	transitionKeywords := []string{
		"remove", "delete", "add", "insert", "update", "change",
		"kick", "ban", "mute", "block", "unblock",
		"activate", "deactivate", "enable", "disable",
		"transition", "move", "transfer",
	}

	claimsStateTransition := false
	matchedKeyword := ""
	for _, keyword := range transitionKeywords {
		if strings.Contains(nameLower, keyword) {
			claimsStateTransition = true
			matchedKeyword = keyword
			break
		}
	}

	if !claimsStateTransition {
		return nil
	}

	// Check if test has sufficient assertions to verify state change
	// We expect at least 2 assertions for a proper before/after check
	if len(method.Assertions) < 2 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' claims to test state transition ('%s') but has only %d assertion(s) - insufficient to verify before/after state",
				method.Name,
				matchedKeyword,
				len(method.Assertions),
			),
			Recommendation: "Add assertions to verify both the initial state and the final state after the transition.",
			Confidence:     0.70,
		}
	}

	return nil
}

// checkConcurrencyWithoutRaceTesting detects concurrency claims without race testing
func (r *CoverageGapRule) checkConcurrencyWithoutRaceTesting(method *models.TestMethod, ctx ValidationContext) *Finding {
	nameLower := strings.ToLower(method.Name)

	// Look for concurrency keywords
	concurrencyKeywords := []string{
		"concurrent", "parallel", "thread", "race", "sync",
		"async", "lock", "mutex", "atomic", "queue",
	}

	claimsConcurrency := false
	matchedKeyword := ""
	for _, keyword := range concurrencyKeywords {
		if strings.Contains(nameLower, keyword) {
			claimsConcurrency = true
			matchedKeyword = keyword
			break
		}
	}

	if !claimsConcurrency {
		return nil
	}

	// Look for evidence of concurrent execution in method calls
	hasConcurrentExecution := false
	for _, call := range method.MethodCalls {
		selectorLower := strings.ToLower(call.Selector)
		if strings.Contains(selectorLower, "dispatch") ||
			strings.Contains(selectorLower, "async") ||
			strings.Contains(selectorLower, "concurrent") ||
			strings.Contains(selectorLower, "thread") ||
			strings.Contains(selectorLower, "queue") {
			hasConcurrentExecution = true
			break
		}
	}

	// If test claims concurrency but doesn't appear to test it
	if !hasConcurrentExecution {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' claims to test concurrency ('%s') but has no evidence of concurrent execution (dispatch, async, threads)",
				method.Name,
				matchedKeyword,
			),
			Recommendation: "Add concurrent execution patterns (dispatch queues, threads) to actually test race conditions or thread safety.",
			Confidence:     0.75,
		}
	}

	return nil
}

// checkPerformanceWithoutTiming detects performance claims without timing assertions
func (r *CoverageGapRule) checkPerformanceWithoutTiming(method *models.TestMethod, ctx ValidationContext) *Finding {
	nameLower := strings.ToLower(method.Name)

	// Look for performance keywords
	performanceKeywords := []string{
		"performance", "speed", "fast", "slow", "timing",
		"benchmark", "latency", "throughput", "optimize",
	}

	claimsPerformance := false
	matchedKeyword := ""
	for _, keyword := range performanceKeywords {
		if strings.Contains(nameLower, keyword) {
			claimsPerformance = true
			matchedKeyword = keyword
			break
		}
	}

	if !claimsPerformance {
		return nil
	}

	// Look for timing-related method calls or assertions
	hasTimingCheck := false
	for _, call := range method.MethodCalls {
		selectorLower := strings.ToLower(call.Selector)
		if strings.Contains(selectorLower, "measure") ||
			strings.Contains(selectorLower, "time") ||
			strings.Contains(selectorLower, "duration") ||
			strings.Contains(selectorLower, "benchmark") {
			hasTimingCheck = true
			break
		}
	}

	// Check for timing-related assertions
	for _, assertion := range method.Assertions {
		for _, arg := range assertion.Arguments {
			argLower := strings.ToLower(arg)
			if strings.Contains(argLower, "time") ||
				strings.Contains(argLower, "duration") ||
				strings.Contains(argLower, "elapsed") {
				hasTimingCheck = true
				break
			}
		}
	}

	if !hasTimingCheck {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test '%s' claims to test performance ('%s') but has no timing measurements or assertions",
				method.Name,
				matchedKeyword,
			),
			Recommendation: "Add timing measurements (measureBlock, CFAbsoluteTimeGetCurrent) and assertions on execution time.",
			Confidence:     0.80,
		}
	}

	return nil
}
