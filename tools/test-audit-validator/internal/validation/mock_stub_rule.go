package validation

import (
	"fmt"
	"strings"
)

// MockStubRule validates mock/stub usage in tests
type MockStubRule struct{}

// NewMockStubRule creates a new instance of the rule
func NewMockStubRule() *MockStubRule {
	return &MockStubRule{}
}

// Name returns the unique name of this rule
func (r *MockStubRule) Name() string {
	return "MockStubRule"
}

// Severity returns the severity level for findings from this rule
func (r *MockStubRule) Severity() Severity {
	return MEDIUM
}

// Description returns a human-readable description of what this rule validates
func (r *MockStubRule) Description() string {
	return "Validates mock/stub usage in tests, detecting over-mocking, under-mocking, and unverified mock interactions"
}

// Validate applies the rule to the given context and returns findings
func (r *MockStubRule) Validate(ctx ValidationContext) []Finding {
	if ctx.TestMethod == nil {
		return nil
	}

	var findings []Finding

	if finding := r.checkOverMocking(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	if finding := r.checkUnderMocking(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	if finding := r.checkMockVerification(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// checkOverMocking detects tests that mock too many dependencies (>3 mocks)
func (r *MockStubRule) checkOverMocking(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	count := r.countDistinctMocks(sourceCode)

	if count > 3 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   HIGH,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test uses %d mocks/stubs, which suggests over-mocking. "+
					"The test may be testing mock behavior rather than production code.", count),
			Recommendation: "Reduce the number of mocks by testing smaller units or refactoring " +
				"the code under test to have fewer dependencies. Consider using real collaborators " +
				"for simple, stateless dependencies.",
			Confidence: 0.80,
		}
	}

	return nil
}

// checkUnderMocking detects tests with external dependencies that aren't mocked
func (r *MockStubRule) checkUnderMocking(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	unmockedDeps := []string{}

	// Network dependencies without mocks
	networkPatterns := []string{
		"nsurlsession", "nsurlconnection", "nsurlrequest",
		"urlsession", "urlconnection",
	}
	if r.containsAnyPattern(sourceCode, networkPatterns) {
		if !r.hasMockForDependency(sourceCode) {
			unmockedDeps = append(unmockedDeps, "network")
		}
	}

	// Database dependencies without mocks
	databasePatterns := []string{
		"sqlite3_open", "executequery", "executesql",
		"pdsdatabasepool", "actorstore", "servicedatabase",
	}
	if r.containsAnyPattern(sourceCode, databasePatterns) {
		if !r.hasMockForDependency(sourceCode) && !r.usesTestDatabase(sourceCode) {
			unmockedDeps = append(unmockedDeps, "database")
		}
	}

	if len(unmockedDeps) > 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: fmt.Sprintf(
				"Test has external dependencies that are not mocked: %s. "+
					"This makes tests slow and brittle.", strings.Join(unmockedDeps, ", ")),
			Recommendation: "Mock external dependencies to improve test speed and reliability. " +
				"Use OCMock or custom mock objects to replace network and database dependencies.",
			Confidence: 0.70,
		}
	}

	return nil
}

// checkMockVerification detects mocks without verification
func (r *MockStubRule) checkMockVerification(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	hasMocks := r.countDistinctMocks(sourceCode) > 0

	if !hasMocks {
		return nil
	}

	// Strip comments before checking for verification calls
	codeOnly := r.stripComments(sourceCode)

	// Check for OCMock verification
	ocmockVerifyPatterns := []string{
		"ocmverify", "ocmverifyall",
	}
	if r.containsAnyPattern(codeOnly, ocmockVerifyPatterns) {
		return nil
	}

	// Check for assertion on mock state (custom mocks)
	customVerifyPatterns := []string{
		"xctassert", "wascalled", "callcount", "verifymock",
		"didcall", "wasinvoked", "invocationcount",
	}
	if r.containsAnyPattern(codeOnly, customVerifyPatterns) {
		return nil
	}

	return &Finding{
		RuleName:   r.Name(),
		Severity:   MEDIUM,
		TestMethod: method.Name,
		TestClass:  method.ClassName,
		FilePath:   ctx.TestFile.Path,
		LineNumber: method.LineNumber,
		Message:    "Test uses mocks but does not verify mock interactions. Mock behavior may not be validated.",
		Recommendation: "Add verification calls to ensure mocks were used as expected. " +
			"Use OCMVerify/OCMVerifyAll for OCMock, or assert on mock state for custom mocks.",
		Confidence: 0.75,
	}
}

// countDistinctMocks counts distinct mock/stub/fake instances in the source code
func (r *MockStubRule) countDistinctMocks(sourceCode string) int {
	seen := make(map[string]bool)

	// OCMock patterns - each call creates a distinct mock
	ocmockPatterns := []string{
		"ocmclassmock", "ocmprotocolmock", "ocmstrictclassmock",
	}

	lines := strings.Split(sourceCode, "\n")
	for _, line := range lines {
		lineLower := strings.ToLower(strings.TrimSpace(line))

		// Count OCMock factory calls per line (each creates a distinct mock)
		for _, pattern := range ocmockPatterns {
			if strings.Contains(lineLower, pattern) {
				// Use the whole line as key to count distinct OCMock instances
				seen[lineLower] = true
			}
		}

		// Skip lines that contain OCMock factory calls for custom prefix matching
		// to avoid double-counting
		hasOCMock := false
		for _, pattern := range ocmockPatterns {
			if strings.Contains(lineLower, pattern) {
				hasOCMock = true
				break
			}
		}
		if hasOCMock {
			continue
		}

		// Custom Mock/Stub/Fake class usage on non-OCMock lines
		mockPrefixes := []string{"mock", "stub", "fake"}
		words := strings.Fields(lineLower)
		for _, word := range words {
			cleaned := strings.TrimRight(word, "*;,=[](){}")
			cleaned = strings.TrimLeft(cleaned, "*[](){}")
			for _, prefix := range mockPrefixes {
				if strings.HasPrefix(cleaned, prefix) && len(cleaned) > len(prefix) {
					rest := cleaned[len(prefix):]
					if len(rest) > 0 && rest[0] >= 'a' && rest[0] <= 'z' || len(rest) > 0 && rest[0] >= 'A' && rest[0] <= 'Z' {
						seen[cleaned] = true
					}
				}
			}
		}
	}

	return len(seen)
}

// hasMockForDependency checks if the source code has mock/stub/fake objects present
func (r *MockStubRule) hasMockForDependency(sourceCode string) bool {
	return r.countDistinctMocks(sourceCode) > 0
}

// usesTestDatabase checks if database operations use test/in-memory database
func (r *MockStubRule) usesTestDatabase(sourceCode string) bool {
	testDbPatterns := []string{
		":memory:", "inmemory", "testdb", "test.db", "test.sqlite",
	}
	return r.containsAnyPattern(sourceCode, testDbPatterns)
}

// stripComments removes single-line comments from source code
func (r *MockStubRule) stripComments(source string) string {
	var result []string
	for _, line := range strings.Split(source, "\n") {
		if idx := strings.Index(line, "//"); idx >= 0 {
			line = line[:idx]
		}
		result = append(result, line)
	}
	return strings.Join(result, "\n")
}

// containsAnyPattern checks if source contains any of the patterns
func (r *MockStubRule) containsAnyPattern(source string, patterns []string) bool {
	for _, pattern := range patterns {
		if strings.Contains(source, pattern) {
			return true
		}
	}
	return false
}
