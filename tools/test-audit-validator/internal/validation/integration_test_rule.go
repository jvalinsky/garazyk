package validation

import (
	"regexp"
	"sort"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// IntegrationTestRule validates integration tests
type IntegrationTestRule struct{}

// NewIntegrationTestRule creates a new instance of the rule
func NewIntegrationTestRule() *IntegrationTestRule {
	return &IntegrationTestRule{}
}

// Name returns the unique name of this rule
func (r *IntegrationTestRule) Name() string {
	return "IntegrationTestRule"
}

// Severity returns the severity level for findings from this rule
func (r *IntegrationTestRule) Severity() Severity {
	return MEDIUM
}

// Description returns a human-readable description of what this rule validates
func (r *IntegrationTestRule) Description() string {
	return "Validates that integration tests exercise multiple components, set up realistic environments, clean up resources, and assert on final outcomes"
}

// Validate applies the rule to the given context and returns findings
func (r *IntegrationTestRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod

	// Check if this is an integration test
	if !r.isIntegrationTest(method, ctx.TestClass, ctx.TestFile) {
		return nil
	}

	var findings []Finding

	// Validate multiple components are exercised
	if finding := r.checkMultipleComponents(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Validate realistic test environment setup
	if finding := r.checkRealisticEnvironment(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Validate resource cleanup
	if finding := r.checkResourceCleanup(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Validate assertions on final outcomes
	if finding := r.checkFinalOutcomeAssertions(method, ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// isIntegrationTest checks if a test appears to be an integration test
func (r *IntegrationTestRule) isIntegrationTest(method *models.TestMethod, class *models.TestClass, file *models.TestFile) bool {
	// Check file path for integration test directory
	if strings.Contains(strings.ToLower(file.Path), "integration") {
		return true
	}

	// Check class name
	className := strings.ToLower(class.Name)
	if strings.Contains(className, "integration") || strings.Contains(className, "e2e") || strings.Contains(className, "endtoend") {
		return true
	}

	// Check method name
	methodName := strings.ToLower(method.Name)
	if strings.Contains(methodName, "integration") || strings.Contains(methodName, "e2e") || strings.Contains(methodName, "endtoend") {
		return true
	}

	// Check comments for integration test indicators
	for _, comment := range method.Comments {
		commentLower := strings.ToLower(comment)
		if strings.Contains(commentLower, "integration") ||
			strings.Contains(commentLower, "end-to-end") ||
			strings.Contains(commentLower, "e2e") {
			return true
		}
	}

	return false
}

// checkMultipleComponents validates that multiple components are exercised
func (r *IntegrationTestRule) checkMultipleComponents(method *models.TestMethod, ctx ValidationContext) *Finding {
	sourceCode := method.SourceCode

	// Count distinct component types being used
	componentCount := 0
	componentsFound := make(map[string]bool)

	// Component patterns to look for
	componentPatterns := map[string]*regexp.Regexp{
		"database":   regexp.MustCompile(`(?i)(database|sqlite|sql|query|transaction|db)`),
		"network":    regexp.MustCompile(`(?i)(http|xrpc|request|response|url|websocket)`),
		"auth":       regexp.MustCompile(`(?i)(auth|oauth|token|jwt|dpop|session)`),
		"repository": regexp.MustCompile(`(?i)(repository|repo|commit|mst|car|cbor)`),
		"service":    regexp.MustCompile(`(?i)(service|controller|handler|manager)`),
		"storage":    regexp.MustCompile(`(?i)(storage|blob|file|upload|download)`),
		"identity":   regexp.MustCompile(`(?i)(did|handle|plc|identity|resolve)`),
		"sync":       regexp.MustCompile(`(?i)(sync|firehose|websocket|subscribe|event)`),
	}

	for componentName, pattern := range componentPatterns {
		if pattern.MatchString(sourceCode) {
			if !componentsFound[componentName] {
				componentsFound[componentName] = true
				componentCount++
			}
		}
	}

	// Integration tests should exercise at least 2 components
	if componentCount < 2 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: "Integration test appears to exercise only a single component. " +
				"Integration tests should validate interactions between multiple components.",
			Recommendation: "Consider moving this to unit tests if it only tests a single component, " +
				"or expand it to test interactions between multiple components (e.g., service + database, auth + network).",
			Confidence: 0.75,
		}
	}

	return nil
}

// checkRealisticEnvironment validates realistic test environment setup
func (r *IntegrationTestRule) checkRealisticEnvironment(method *models.TestMethod, ctx ValidationContext) *Finding {
	sourceCode := strings.ToLower(method.SourceCode)

	// Look for realistic environment setup patterns
	hasRealisticSetup := false

	// Patterns indicating realistic setup
	setupPatterns := []string{
		"pdsconfiguration",
		"pdsapplication",
		"createtestserver",
		"setupenvironment",
		"initializeserver",
		"createtestdatabase",
		"setupauth",
		"createtestuser",
		"setuprepository",
	}

	for _, pattern := range setupPatterns {
		if strings.Contains(sourceCode, pattern) {
			hasRealisticSetup = true
			break
		}
	}

	// Check for mock-heavy tests (might not be realistic)
	mockCount := 0
	mockPatterns := []string{"mock", "stub", "fake", "dummy"}
	for _, pattern := range mockPatterns {
		mockCount += strings.Count(sourceCode, pattern)
	}

	// If no realistic setup and heavy mocking, flag it
	if !hasRealisticSetup && mockCount > 3 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   LOW,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: "Integration test may not set up a realistic test environment. " +
				"Heavy use of mocks detected without clear environment initialization.",
			Recommendation: "Integration tests should use realistic components where possible. " +
				"Consider using actual database, server, and service instances instead of mocks.",
			Confidence: 0.65,
		}
	}

	return nil
}

// checkResourceCleanup validates that resources are properly cleaned up
func (r *IntegrationTestRule) checkResourceCleanup(method *models.TestMethod, ctx ValidationContext) *Finding {
	sourceCode := strings.ToLower(method.SourceCode)

	// Resources that need cleanup
	resourcesUsed := make(map[string]bool)
	resourcesCleanedUp := make(map[string]bool)

	// Database resources
	if r.containsAny(sourceCode, []string{"database", "sqlite", "db", "connection"}) {
		resourcesUsed["database"] = true
		if r.containsAny(sourceCode, []string{"close", "cleanup", "teardown", "remove"}) {
			resourcesCleanedUp["database"] = true
		}
	}

	// File resources
	if r.containsAny(sourceCode, []string{"file", "tempfile", "tmpfile", "createfile"}) {
		resourcesUsed["file"] = true
		if r.containsAny(sourceCode, []string{"deletefile", "removefile", "unlink", "cleanup"}) {
			resourcesCleanedUp["file"] = true
		}
	}

	// Network connections
	if r.containsAny(sourceCode, []string{"connection", "socket", "websocket", "httpserver"}) {
		resourcesUsed["network"] = true
		if r.containsAny(sourceCode, []string{"close", "disconnect", "shutdown", "stop"}) {
			resourcesCleanedUp["network"] = true
		}
	}

	// Server instances
	if r.containsAny(sourceCode, []string{"server", "pdsapplication", "httpserver"}) {
		resourcesUsed["server"] = true
		if r.containsAny(sourceCode, []string{"stop", "shutdown", "teardown"}) {
			resourcesCleanedUp["server"] = true
		}
	}

	// Check if resources are used but not cleaned up
	uncleaned := []string{}
	for resource := range resourcesUsed {
		if !resourcesCleanedUp[resource] {
			uncleaned = append(uncleaned, resource)
		}
	}
	sort.Strings(uncleaned)

	if len(uncleaned) > 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: "Integration test may not properly clean up resources: " + strings.Join(uncleaned, ", ") + ". " +
				"This can cause test pollution and flaky tests.",
			Recommendation: "Add cleanup code in tearDown or at the end of the test to close connections, " +
				"delete temporary files, shut down servers, and clean up database resources.",
			Confidence: 0.70,
		}
	}

	return nil
}

// checkFinalOutcomeAssertions validates assertions focus on final outcomes
func (r *IntegrationTestRule) checkFinalOutcomeAssertions(method *models.TestMethod, ctx ValidationContext) *Finding {
	if len(method.Assertions) == 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   HIGH,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message:    "Integration test has no assertions to validate outcomes",
			Recommendation: "Add assertions that validate the final state or outcome of the integration workflow. " +
				"Integration tests should verify end-to-end behavior, not just that operations complete without errors.",
			Confidence: 0.95,
		}
	}

	// Count intermediate vs final assertions
	intermediateAssertionCount := 0
	finalAssertionCount := 0

	sourceCode := strings.ToLower(method.SourceCode)
	lines := strings.Split(sourceCode, "\n")

	// Find assertion locations
	for i, line := range lines {
		if strings.Contains(line, "xctassert") {
			// Check if this is an intermediate assertion (checking setup/intermediate state)
			if r.isIntermediateAssertion(line, lines, i) {
				intermediateAssertionCount++
			} else {
				finalAssertionCount++
			}
		}
	}

	// If all assertions are intermediate (checking setup), flag it
	if intermediateAssertionCount > 0 && finalAssertionCount == 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: "Integration test only asserts on intermediate states (setup validation) " +
				"without validating final outcomes",
			Recommendation: "Add assertions that validate the final result of the integration workflow. " +
				"While setup validation is useful, integration tests should primarily verify end-to-end behavior.",
			Confidence: 0.75,
		}
	}

	return nil
}

// isIntermediateAssertion checks if an assertion is validating intermediate state
func (r *IntegrationTestRule) isIntermediateAssertion(line string, lines []string, lineIndex int) bool {
	// Look for patterns indicating intermediate/setup assertions
	intermediatePatterns := []string{
		"notnil", // Often used to check setup succeeded
		"setup",
		"init",
		"create",
		"start",
	}

	for _, pattern := range intermediatePatterns {
		if strings.Contains(line, pattern) {
			return true
		}
	}

	// Check context: if assertion is early in the test, likely intermediate
	// (rough heuristic: first 30% of test)
	if lineIndex < len(lines)/3 {
		// Check if it's a simple not-nil check
		if strings.Contains(line, "notnil") {
			return true
		}
	}

	return false
}

// containsAny checks if source contains any of the patterns
func (r *IntegrationTestRule) containsAny(source string, patterns []string) bool {
	for _, pattern := range patterns {
		if strings.Contains(source, pattern) {
			return true
		}
	}
	return false
}
