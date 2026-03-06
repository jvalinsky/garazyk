package validation

import (
	"regexp"
	"strings"
)

// DependencyType represents the type of test dependency
type DependencyType string

const (
	DependencyTypeExternal       DependencyType = "external"        // Network, filesystem, database
	DependencyTypeExecutionOrder DependencyType = "execution_order" // Depends on test execution order
	DependencyTypeSharedState    DependencyType = "shared_state"    // Shares mutable state
	DependencyTypeIsolation      DependencyType = "isolation"       // Lacks proper isolation
	DependencyTypeSideEffect     DependencyType = "side_effect"     // Depends on side effects
)

// TestDependencyRule validates test dependencies and isolation
type TestDependencyRule struct{}

var executionOrderCommentPatterns = []*regexp.Regexp{
	regexp.MustCompile(`\bmust\s+run\s+(before|after)\b`),
	regexp.MustCompile(`\bruns?\s+(before|after)\b.*\btest`),
	regexp.MustCompile(`\bdepends?\s+on\b.*\btest`),
	regexp.MustCompile(`\bexecution\s+order\b`),
	regexp.MustCompile(`\border[-\s]?dependent\b`),
	regexp.MustCompile(`\b(before|after)\s+other\s+tests?\b`),
}

// NewTestDependencyRule creates a new instance of the rule
func NewTestDependencyRule() *TestDependencyRule {
	return &TestDependencyRule{}
}

// Name returns the unique name of this rule
func (r *TestDependencyRule) Name() string {
	return "TestDependencyRule"
}

// Severity returns the severity level for findings from this rule
func (r *TestDependencyRule) Severity() Severity {
	return HIGH
}

// Description returns a human-readable description of what this rule validates
func (r *TestDependencyRule) Description() string {
	return "Identifies tests that depend on external services, execution order, shared mutable state, or lack proper environment isolation"
}

// Validate applies the rule to the given context and returns findings
func (r *TestDependencyRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	var findings []Finding

	// Check for external dependencies
	if finding := r.checkExternalDependencies(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Check for execution order dependencies
	if finding := r.checkExecutionOrderDependencies(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Check for shared mutable state
	if finding := r.checkSharedMutableState(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Check for proper test isolation
	if finding := r.checkTestIsolation(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	// Check for side effect dependencies
	if finding := r.checkSideEffectDependencies(ctx); finding != nil {
		findings = append(findings, *finding)
	}

	return findings
}

// checkExternalDependencies detects dependencies on external services
func (r *TestDependencyRule) checkExternalDependencies(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	externalDeps := []string{}

	// Network dependencies
	networkPatterns := []string{
		"nsurl", "nsurlsession", "nsurlrequest", "nsurlconnection",
		"http://", "https://", "ws://", "wss://",
		"urlsession", "urlrequest", "urlconnection",
	}
	if r.containsAnyPattern(sourceCode, networkPatterns) {
		// Check if it's mocked or using test server
		if !r.isMockedOrTestServer(sourceCode) {
			externalDeps = append(externalDeps, "network")
		}
	}

	// Filesystem dependencies
	filesystemPatterns := []string{
		"nsfilemanager", "filemanager", "createfile", "writefile",
		"readfile", "deletefile", "fileexists", "directoryexists",
		"/var/", "~/", "home/",
	}
	if r.containsAnyPattern(sourceCode, filesystemPatterns) {
		// Check if using temporary/test directories
		if !r.usesTemporaryDirectory(sourceCode) {
			externalDeps = append(externalDeps, "filesystem")
		}
	}

	// Database dependencies - use specific patterns to avoid false positives
	// ("commit", "connection", "transaction" are too generic)
	databasePatterns := []string{
		"sqlite", "executequery", "executesql",
		"pdsdatabasepool", "actorstore", "servicedatabase",
		"[database ", "[db ",
	}
	if r.containsAnyPattern(sourceCode, databasePatterns) {
		// Check if using in-memory or test database
		if !r.usesTestDatabase(sourceCode) {
			externalDeps = append(externalDeps, "database")
		}
	}

	// External service dependencies - check this AFTER network to avoid false positives
	servicePatterns := []string{
		"plc.directory", "bsky.network",
	}
	// Only flag if it's a real external service, not just "api.example" in tests
	for _, pattern := range servicePatterns {
		if strings.Contains(sourceCode, pattern) {
			externalDeps = append(externalDeps, "external_service")
			break
		}
	}

	if len(externalDeps) > 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: "Test depends on external services: " + strings.Join(externalDeps, ", ") + ". " +
				"This makes the test brittle and dependent on external availability.",
			Recommendation: "Mock external dependencies or use test doubles. For network calls, use mock servers. " +
				"For databases, use in-memory databases. For filesystems, use temporary test directories. " +
				"Tests should be self-contained and not depend on external services.",
			Confidence: 0.75,
		}
	}

	return nil
}

// checkExecutionOrderDependencies detects tests that depend on execution order
func (r *TestDependencyRule) checkExecutionOrderDependencies(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	// Check comments for order dependencies
	// But exclude "already exists" which is more about side effects
	for _, comment := range method.Comments {
		commentLower := strings.ToLower(comment)
		// Skip if it's about "already exists" - that's a side effect dependency
		if strings.Contains(commentLower, "already") {
			continue
		}
		if r.hasExecutionOrderDependencyComment(commentLower) {
			return &Finding{
				RuleName:   r.Name(),
				Severity:   CRITICAL,
				TestMethod: method.Name,
				TestClass:  method.ClassName,
				FilePath:   ctx.TestFile.Path,
				LineNumber: method.LineNumber,
				Message: "Test appears to depend on test execution order. " +
					"Comments indicate dependency on other tests running before/after.",
				Recommendation: "Tests should be independent and runnable in any order. " +
					"Move shared setup to setUp/tearDown methods or test fixtures. " +
					"Each test should set up its own state and clean up after itself.",
				Confidence: 0.90,
			}
		}
	}

	// Check for accessing results from other tests
	if r.containsAnyPattern(sourceCode, []string{"sharedresult", "testresult", "previousresult"}) {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   CRITICAL,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message:    "Test appears to access results from other tests, indicating execution order dependency",
			Recommendation: "Each test should be self-contained. Move shared data to setUp method or test fixtures. " +
				"Do not rely on state set by other tests.",
			Confidence: 0.85,
		}
	}

	return nil
}

func (r *TestDependencyRule) hasExecutionOrderDependencyComment(comment string) bool {
	for _, pattern := range executionOrderCommentPatterns {
		if pattern.MatchString(comment) {
			return true
		}
	}
	return false
}

// checkSharedMutableState detects tests sharing mutable state
func (r *TestDependencyRule) checkSharedMutableState(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := method.SourceCode

	// Look for static/class variables being modified
	staticVarPattern := regexp.MustCompile(`(?i)static\s+\w+\s*\*?\s*\w+\s*=`)
	if staticVarPattern.MatchString(sourceCode) {
		// Check if it's being assigned (modified)
		if strings.Contains(sourceCode, "=") {
			return &Finding{
				RuleName:   r.Name(),
				Severity:   HIGH,
				TestMethod: method.Name,
				TestClass:  method.ClassName,
				FilePath:   ctx.TestFile.Path,
				LineNumber: method.LineNumber,
				Message: "Test modifies static or class variables, which creates shared mutable state between tests. " +
					"This can cause test pollution and order-dependent failures.",
				Recommendation: "Avoid modifying static/class variables in tests. Use instance variables instead, " +
					"or reset static state in setUp/tearDown methods. Consider using dependency injection " +
					"to avoid global state.",
				Confidence: 0.85,
			}
		}
	}

	// Look for global variable access
	sourceCodeLower := strings.ToLower(sourceCode)
	globalPatterns := []string{
		"sharedinstance", "defaultinstance", "singleton",
		"globalstate", "sharedstate",
	}

	if r.containsAnyPattern(sourceCodeLower, globalPatterns) {
		// Check if it's being modified (not just read)
		modificationPatterns := []string{
			"setvalue", "set", "update", "modify", "change", "reset",
		}
		if r.containsAnyPattern(sourceCodeLower, modificationPatterns) {
			return &Finding{
				RuleName:   r.Name(),
				Severity:   HIGH,
				TestMethod: method.Name,
				TestClass:  method.ClassName,
				FilePath:   ctx.TestFile.Path,
				LineNumber: method.LineNumber,
				Message: "Test modifies global or shared singleton state, which can affect other tests. " +
					"This creates test pollution and makes tests order-dependent.",
				Recommendation: "Avoid modifying global state in tests. If you must use singletons, " +
					"reset them in setUp/tearDown. Better: use dependency injection to avoid singletons. " +
					"Create fresh instances for each test.",
				Confidence: 0.80,
			}
		}
	}

	return nil
}

// checkTestIsolation verifies tests properly isolate their environments
func (r *TestDependencyRule) checkTestIsolation(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for specific resource types that need cleanup
	resourceTypes := []string{}

	// Check files - need both creation and no cleanup
	if r.containsAnyPattern(sourceCode, []string{"createfile", "writefile"}) {
		if !r.containsAnyPattern(sourceCode, []string{"removefile", "deletefile", "cleanup"}) {
			resourceTypes = append(resourceTypes, "files")
		}
	}

	// Check database - need both open and no close (skip in-memory databases)
	if r.containsAnyPattern(sourceCode, []string{"sqlite3_open"}) {
		if !r.containsAnyPattern(sourceCode, []string{"sqlite3_close"}) && !r.usesInMemoryDatabase(sourceCode) {
			resourceTypes = append(resourceTypes, "database connections")
		}
	}

	// Check network - need both connection and no close (but skip if mocked/test)
	if r.containsAnyPattern(sourceCode, []string{"socket", "websocket"}) {
		if !r.isMockedOrTestServer(sourceCode) {
			if !r.containsAnyPattern(sourceCode, []string{"close", "disconnect", "shutdown", "stop"}) {
				resourceTypes = append(resourceTypes, "network connections")
			}
		}
	}

	if len(resourceTypes) > 0 {
		return &Finding{
			RuleName:   r.Name(),
			Severity:   MEDIUM,
			TestMethod: method.Name,
			TestClass:  method.ClassName,
			FilePath:   ctx.TestFile.Path,
			LineNumber: method.LineNumber,
			Message: "Test creates resources (" + strings.Join(resourceTypes, ", ") + ") " +
				"but may not properly clean them up. This can cause resource leaks and test pollution.",
			Recommendation: "Add cleanup code to release resources. Use tearDown method for cleanup, " +
				"or add cleanup code at the end of the test. Ensure cleanup happens even if test fails " +
				"(use try-finally or defer patterns).",
			Confidence: 0.70,
		}
	}

	return nil
}

// checkSideEffectDependencies detects tests depending on side effects from other tests
func (r *TestDependencyRule) checkSideEffectDependencies(ctx ValidationContext) *Finding {
	method := ctx.TestMethod
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for assumptions about pre-existing state in comments
	assumptionPatterns := []string{
		"assumes", "expects", "requires", "prerequisite",
		"must exist", "should exist", "already created",
	}

	for _, comment := range method.Comments {
		commentLower := strings.ToLower(comment)
		if r.containsAnyPattern(commentLower, assumptionPatterns) {
			return &Finding{
				RuleName:   r.Name(),
				Severity:   HIGH,
				TestMethod: method.Name,
				TestClass:  method.ClassName,
				FilePath:   ctx.TestFile.Path,
				LineNumber: method.LineNumber,
				Message: "Test comments indicate assumptions about pre-existing state. " +
					"This suggests the test depends on side effects from other tests.",
				Recommendation: "Tests should set up all required state themselves. " +
					"Do not assume state created by other tests. Move shared setup to setUp method " +
					"or create test fixtures that each test can use independently.",
				Confidence: 0.85,
			}
		}
	}

	// Check if test reads state without setting it up
	// Look for "get" or "find" without corresponding "create" or "setup"
	readsExisting := r.containsAnyPattern(sourceCode, []string{"getexisting", "findexisting", "loadexisting"})
	// Look for actual setup operations in method body, not in the method name
	// Use more specific patterns to avoid matching method names like "testReadWithoutSetup"
	setsUpState := r.containsAnyPattern(sourceCode, []string{
		"alloc] init", "create:", "insert:", "add:",
		"[self setup", "initialize:", "initwith",
	})

	// If reads existing state without setting it up, might depend on side effects
	if readsExisting && !setsUpState {
		// Check if it's reading from fixtures (which is OK)
		if !r.containsAnyPattern(sourceCode, []string{"fixture", "testdata", "sample"}) {
			return &Finding{
				RuleName:   r.Name(),
				Severity:   MEDIUM,
				TestMethod: method.Name,
				TestClass:  method.ClassName,
				FilePath:   ctx.TestFile.Path,
				LineNumber: method.LineNumber,
				Message: "Test reads state without setting it up first. " +
					"This may indicate dependency on side effects from other tests.",
				Recommendation: "Ensure test sets up all required state in setUp method or test body. " +
					"Do not rely on state created by other tests. Each test should be self-contained.",
				Confidence: 0.65,
			}
		}
	}

	return nil
}

// Helper methods

// containsAnyPattern checks if source contains any of the patterns
func (r *TestDependencyRule) containsAnyPattern(source string, patterns []string) bool {
	for _, pattern := range patterns {
		if strings.Contains(source, pattern) {
			return true
		}
	}
	return false
}

// isMockedOrTestServer checks if network calls are mocked or using test server
func (r *TestDependencyRule) isMockedOrTestServer(source string) bool {
	mockPatterns := []string{
		"mockserver", "mockurl", "mocksession", "mockhttp", "mocknetwork",
		"stubserver", "stuburl",
		"fakeserver", "fakeurl", "fakesession",
		"testserver", "testurl",
		"localhost", "127.0.0.1",
		"httptest",
	}
	// Check for standalone "mock", "stub", "fake" as class/variable prefixes
	// but not "test" which appears in every test method name
	standalonePatterns := []string{"mock ", "mock]", "mock*", "stub ", "stub]", "fake ", "fake]"}
	if r.containsAnyPattern(source, mockPatterns) {
		return true
	}
	if r.containsAnyPattern(source, standalonePatterns) {
		return true
	}
	return false
}

// usesTemporaryDirectory checks if filesystem operations use temporary directories
func (r *TestDependencyRule) usesTemporaryDirectory(source string) bool {
	tempPatterns := []string{
		"nstemporarydirectory", "tmpdir", "tempdir", "temporarydirectory",
		"mkdtemp", "tmpfile", "tempfile",
	}
	return r.containsAnyPattern(source, tempPatterns)
}

// usesTestDatabase checks if database operations use test/in-memory database
func (r *TestDependencyRule) usesTestDatabase(source string) bool {
	testDbPatterns := []string{
		":memory:", "inmemory", "testdb", "test.db", "test.sqlite",
		"temporary", "temp.db",
	}
	return r.containsAnyPattern(source, testDbPatterns)
}

// usesInMemoryDatabase checks if database is in-memory (no cleanup needed)
func (r *TestDependencyRule) usesInMemoryDatabase(source string) bool {
	return r.containsAnyPattern(source, []string{":memory:", "inmemory"})
}
