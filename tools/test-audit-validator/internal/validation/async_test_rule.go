package validation

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// AsyncTestRule validates async test patterns in Objective-C XCTest
type AsyncTestRule struct{}

// NewAsyncTestRule creates a new instance of the rule
func NewAsyncTestRule() *AsyncTestRule {
	return &AsyncTestRule{}
}

// Name returns the unique name of this rule
func (r *AsyncTestRule) Name() string {
	return "AsyncTestRule"
}

// Severity returns the severity level for findings from this rule
func (r *AsyncTestRule) Severity() Severity {
	return HIGH
}

// Description returns a human-readable description of what this rule validates
func (r *AsyncTestRule) Description() string {
	return "Validates that async tests properly create expectations, fulfill them, and wait with reasonable timeouts"
}

// Validate applies the rule to the given context and returns findings
func (r *AsyncTestRule) Validate(ctx ValidationContext) []Finding {
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod
	source := method.SourceCode

	hasExpectation := r.hasExpectation(source)
	hasAsyncDispatch := r.hasAsyncDispatch(source)

	// If no async patterns at all, nothing to validate
	if !hasExpectation && !hasAsyncDispatch {
		return nil
	}

	var findings []Finding

	if hasExpectation {
		if finding := r.checkFulfill(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}
		if finding := r.checkWait(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}
		if finding := r.checkTimeout(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}
	}

	if hasAsyncDispatch && !hasExpectation {
		if finding := r.checkAsyncWithoutExpectation(method, ctx); finding != nil {
			findings = append(findings, *finding)
		}
	}

	return findings
}

// hasExpectation checks if the source creates XCTestExpectations
func (r *AsyncTestRule) hasExpectation(source string) bool {
	return strings.Contains(source, "expectationWithDescription:") ||
		strings.Contains(source, "XCTestExpectation")
}

// hasAsyncDispatch checks if the source uses async dispatch patterns
func (r *AsyncTestRule) hasAsyncDispatch(source string) bool {
	return strings.Contains(source, "dispatch_async") ||
		strings.Contains(source, "performSelector:afterDelay:") ||
		strings.Contains(source, "dispatch_after")
}

// checkFulfill verifies that expectations are fulfilled
func (r *AsyncTestRule) checkFulfill(method *models.TestMethod, ctx ValidationContext) *Finding {
	source := method.SourceCode
	if strings.Contains(source, "[expectation fulfill]") || strings.Contains(source, "fulfill]") {
		return nil
	}
	return &Finding{
		RuleName:       r.Name(),
		Severity:       HIGH,
		TestMethod:     method.Name,
		TestClass:      method.ClassName,
		FilePath:       ctx.TestFile.Path,
		LineNumber:     method.LineNumber,
		Message:        "Test creates expectations but never fulfills them. The test may always pass trivially.",
		Recommendation: "Add [expectation fulfill] inside the async callback to signal completion.",
		Confidence:     0.9,
	}
}

// checkWait verifies that the test waits for expectations
func (r *AsyncTestRule) checkWait(method *models.TestMethod, ctx ValidationContext) *Finding {
	source := method.SourceCode
	if strings.Contains(source, "waitForExpectations") || strings.Contains(source, "waitForExpectationsWithTimeout") {
		return nil
	}
	return &Finding{
		RuleName:       r.Name(),
		Severity:       HIGH,
		TestMethod:     method.Name,
		TestClass:      method.ClassName,
		FilePath:       ctx.TestFile.Path,
		LineNumber:     method.LineNumber,
		Message:        "Test creates expectations but does not wait for them. Async assertions may not execute.",
		Recommendation: "Add [self waitForExpectationsWithTimeout:timeout handler:nil] after the async operation.",
		Confidence:     0.9,
	}
}

var timeoutRegexp = regexp.MustCompile(`waitForExpectationsWithTimeout:\s*([\d.]+)`)

// checkTimeout validates that timeout values are reasonable
func (r *AsyncTestRule) checkTimeout(method *models.TestMethod, ctx ValidationContext) *Finding {
	matches := timeoutRegexp.FindStringSubmatch(method.SourceCode)
	if matches == nil {
		return nil
	}

	timeout, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return nil
	}

	if timeout < 1.0 {
		return &Finding{
			RuleName:       r.Name(),
			Severity:       MEDIUM,
			TestMethod:     method.Name,
			TestClass:      method.ClassName,
			FilePath:       ctx.TestFile.Path,
			LineNumber:     method.LineNumber,
			Message:        "Async test timeout (" + matches[1] + "s) may be too short and cause flaky failures.",
			Recommendation: "Consider using a timeout of at least 1 second to avoid flaky tests on slower CI machines.",
			Confidence:     0.8,
		}
	}

	if timeout > 30.0 {
		return &Finding{
			RuleName:       r.Name(),
			Severity:       LOW,
			TestMethod:     method.Name,
			TestClass:      method.ClassName,
			FilePath:       ctx.TestFile.Path,
			LineNumber:     method.LineNumber,
			Message:        "Async test timeout (" + matches[1] + "s) is very long. Consider reducing for faster test execution.",
			Recommendation: "Reduce the timeout to a reasonable value (e.g., 5-10 seconds) unless the operation genuinely requires more time.",
			Confidence:     0.7,
		}
	}

	return nil
}

// checkAsyncWithoutExpectation flags async dispatch without XCTestExpectation
func (r *AsyncTestRule) checkAsyncWithoutExpectation(method *models.TestMethod, ctx ValidationContext) *Finding {
	return &Finding{
		RuleName:       r.Name(),
		Severity:       HIGH,
		TestMethod:     method.Name,
		TestClass:      method.ClassName,
		FilePath:       ctx.TestFile.Path,
		LineNumber:     method.LineNumber,
		Message:        "Test uses asynchronous dispatch but does not use XCTestExpectation. Async callbacks may not execute before the test ends.",
		Recommendation: "Use XCTestExpectation to synchronize async operations. Create an expectation, fulfill it in the callback, and wait for it.",
		Confidence:     0.85,
	}
}
