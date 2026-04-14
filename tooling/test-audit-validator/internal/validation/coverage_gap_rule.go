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
	// Look for standalone "and" tokens in test names.
	hasMultipleClaims := false
	for _, token := range splitTestNameTokens(method.Name) {
		if token == "and" {
			hasMultipleClaims = true
			break
		}
	}

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
	if !r.claimsErrorHandling(method.Name) {
		return nil
	}

	if !r.hasErrorValidationAssertions(method) {
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

func (r *CoverageGapRule) claimsErrorHandling(methodName string) bool {
	tokens := splitTestNameTokens(methodName)
	errorKeywords := []string{
		"error", "invalid", "malformed", "reject", "fail",
		"throw", "exception",
	}

	for i, token := range tokens {
		for _, keyword := range errorKeywords {
			// Avoid false positive matches such as "invalidates" in non-error-flow tests.
			if keyword == "invalid" && strings.HasPrefix(token, "invalidat") {
				continue
			}
			// Exclude explicit success-phrased names like "...NoError".
			if keyword == "error" && isNegatedErrorToken(tokens, i) {
				continue
			}
			if tokenMatchesKeyword(token, keyword) {
				return true
			}
		}
	}
	return false
}

func (r *CoverageGapRule) hasErrorValidationAssertions(method *models.TestMethod) bool {
	sourceLower := strings.ToLower(method.SourceCode)
	if strings.Contains(sourceLower, "error != nil") ||
		strings.Contains(sourceLower, "nil != error") ||
		strings.Contains(sourceLower, "if (error)") {
		return true
	}

	errorValidationArgKeywords := []string{
		"error", "status", "code", "fail", "failure", "exception",
		"invalid", "cancel", "retry", "decision", "denied",
	}

	for _, assertion := range method.Assertions {
		typeLower := strings.ToLower(assertion.Type)
		switch typeLower {
		case "xctassertthrows", "xctassertthrowserror", "xctassertthrowsspecific":
			return true
		case "xctassertfalse", "xctassertnil":
			// Negative assertions are often the expected behavior for invalid/failure paths.
			return true
		case "xctfail":
			// Conditional XCTFail branches are commonly used for explicit error-path checks.
			return true
		}

		for _, arg := range assertion.Arguments {
			argLower := strings.ToLower(arg)
			for _, keyword := range errorValidationArgKeywords {
				if strings.Contains(argLower, keyword) {
					return true
				}
			}
		}
	}
	return false
}

func isNegatedErrorToken(tokens []string, idx int) bool {
	if idx < 0 || idx >= len(tokens) {
		return false
	}
	if !tokenMatchesKeyword(tokens[idx], "error") {
		return false
	}

	if idx > 0 {
		prev := tokens[idx-1]
		if prev == "no" || prev == "without" || prev == "non" {
			return true
		}
	}

	return false
}

// checkStateTransitionWithoutChecks detects state transition claims without before/after checks
func (r *CoverageGapRule) checkStateTransitionWithoutChecks(method *models.TestMethod, ctx ValidationContext) *Finding {
	// Look for state transition keywords
	transitionKeywords := []string{
		"remove", "delete", "add", "insert", "update", "change",
		"kick", "ban", "mute", "block", "unblock",
		"activate", "deactivate", "enable", "disable",
		"transition", "move", "transfer",
	}

	claimsStateTransition := false
	matchedKeyword := ""
	for _, token := range splitTestNameTokens(method.Name) {
		for _, keyword := range transitionKeywords {
			if tokenMatchesKeyword(token, keyword) {
				claimsStateTransition = true
				matchedKeyword = keyword
				break
			}
		}
		if claimsStateTransition {
			break
		}
	}

	if !claimsStateTransition {
		return nil
	}

	if isAmbiguousTransitionKeyword(matchedKeyword) && !r.hasTransitionMethodCall(method, matchedKeyword) {
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

func splitTestNameTokens(name string) []string {
	if strings.HasPrefix(name, "test") && len(name) > 4 {
		name = name[4:]
	}

	tokens := make([]string, 0, 8)
	var current strings.Builder
	flush := func() {
		if current.Len() == 0 {
			return
		}
		tokens = append(tokens, current.String())
		current.Reset()
	}

	for i, r := range name {
		if r == '_' || r == '-' || r == ':' || r == ' ' {
			flush()
			continue
		}
		if i > 0 && r >= 'A' && r <= 'Z' && current.Len() > 0 {
			flush()
		}
		if r >= 'A' && r <= 'Z' {
			r = r - 'A' + 'a'
		}
		current.WriteRune(r)
	}
	flush()
	return tokens
}

func tokenMatchesKeyword(token, keyword string) bool {
	if token == keyword {
		return true
	}

	if len(keyword) <= 4 {
		suffixes := []string{"s", "ed", "ing", "er", "ers"}
		for _, suffix := range suffixes {
			if token == keyword+suffix {
				return true
			}
		}
		return false
	}

	return strings.HasPrefix(token, keyword)
}

func isAmbiguousTransitionKeyword(keyword string) bool {
	switch keyword {
	case "block", "kick", "ban", "mute":
		return true
	default:
		return false
	}
}

func (r *CoverageGapRule) hasTransitionMethodCall(method *models.TestMethod, keyword string) bool {
	for _, call := range method.MethodCalls {
		if strings.Contains(strings.ToLower(call.Selector), keyword) {
			return true
		}
	}
	return false
}

// checkConcurrencyWithoutRaceTesting detects concurrency claims without race testing
func (r *CoverageGapRule) checkConcurrencyWithoutRaceTesting(method *models.TestMethod, ctx ValidationContext) *Finding {
	// Look for concurrency keywords
	concurrencyKeywords := []string{
		"concurrent", "parallel", "thread", "race", "sync",
		"async", "lock", "mutex", "queue",
	}

	claimsConcurrency := false
	matchedKeyword := ""
	for _, token := range splitTestNameTokens(method.Name) {
		for _, keyword := range concurrencyKeywords {
			if tokenMatchesKeyword(token, keyword) {
				claimsConcurrency = true
				matchedKeyword = keyword
				break
			}
		}
		if claimsConcurrency {
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
