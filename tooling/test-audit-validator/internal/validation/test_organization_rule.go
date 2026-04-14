package validation

import (
	"path/filepath"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// TestDomain represents the domain/category of a test
type TestDomain string

const (
	DomainAuth        TestDomain = "Auth"
	DomainNetwork     TestDomain = "Network"
	DomainCore        TestDomain = "Core"
	DomainDatabase    TestDomain = "Database"
	DomainRepository  TestDomain = "Repository"
	DomainSync        TestDomain = "Sync"
	DomainIdentity    TestDomain = "Identity"
	DomainSecurity    TestDomain = "Security"
	DomainIntegration TestDomain = "Integration"
	DomainAdmin       TestDomain = "Admin"
	DomainServices    TestDomain = "Services"
	DomainUnknown     TestDomain = "Unknown"
)

// TestOrganizationRule validates test organization and structure
type TestOrganizationRule struct{}

// NewTestOrganizationRule creates a new instance of the rule
func NewTestOrganizationRule() *TestOrganizationRule {
	return &TestOrganizationRule{}
}

// Name returns the unique name of this rule
func (r *TestOrganizationRule) Name() string {
	return "TestOrganizationRule"
}

// Severity returns the severity level for findings from this rule
func (r *TestOrganizationRule) Severity() Severity {
	return MEDIUM
}

// Description returns a human-readable description of what this rule validates
func (r *TestOrganizationRule) Description() string {
	return "Validates that tests are properly organized in appropriate directories and use correct base classes"
}

// Validate applies the rule to the given context and returns findings
func (r *TestOrganizationRule) Validate(ctx ValidationContext) []Finding {
	var findings []Finding

	// File-level validation: check directory structure
	if ctx.TestFile != nil {
		findings = append(findings, r.validateDirectoryStructure(ctx)...)
	}

	// Class-level validation: check base class usage
	if ctx.TestClass != nil && ctx.TestMethod == nil {
		findings = append(findings, r.validateBaseClassUsage(ctx)...)
	}

	return findings
}

// validateDirectoryStructure checks if test files are in appropriate subdirectories
func (r *TestOrganizationRule) validateDirectoryStructure(ctx ValidationContext) []Finding {
	var findings []Finding

	// Extract directory from file path
	dir := filepath.Dir(ctx.TestFile.Path)

	// Determine expected domain from file path
	expectedDomain := r.getDomainFromPath(ctx.TestFile.Path)

	// Determine actual domain from file content
	actualDomain := r.getDomainFromContent(ctx.TestFile)

	// NOTE: Content-based domain mismatch check disabled — too unreliable.
	// Keyword-based content analysis (e.g., "request" → Network) produces too many
	// false positives when tests span multiple domain concepts.
	// The Tests-root check below is retained as a clearer signal.

	// Check if file is in Tests root without subdirectory (when it should be categorized)
	// Only report if we're actually in the root AND we can determine a domain
	if r.isInTestsRoot(dir) && actualDomain != DomainUnknown && expectedDomain == DomainUnknown {
		findings = append(findings, Finding{
			RuleName:       r.Name(),
			Severity:       MEDIUM,
			TestMethod:     "",
			TestClass:      "",
			FilePath:       ctx.TestFile.Path,
			LineNumber:     1,
			Message:        "Test file is in Tests root directory but should be in a subdirectory for domain: " + string(actualDomain),
			Recommendation: "Move this test file to Garazyk/Tests/" + string(actualDomain) + "/ subdirectory",
			Confidence:     0.75,
		})
	}

	return findings
}

// validateBaseClassUsage checks if test classes use appropriate base classes
func (r *TestOrganizationRule) validateBaseClassUsage(ctx ValidationContext) []Finding {
	var findings []Finding

	if ctx.TestClass.BaseClass == nil {
		// No base class specified - this might be okay for XCTestCase direct inheritance
		return nil
	}

	baseClass := *ctx.TestClass.BaseClass

	// Check for characterization test base class usage
	if strings.Contains(baseClass, "CharacterizationTestBase") {
		// Verify the test is actually a characterization test
		if !r.isCharacterizationTest(ctx.TestClass) {
			findings = append(findings, Finding{
				RuleName:       r.Name(),
				Severity:       MEDIUM,
				TestMethod:     "",
				TestClass:      ctx.TestClass.Name,
				FilePath:       ctx.TestFile.Path,
				LineNumber:     1,
				Message:        "Test class inherits from CharacterizationTestBase but doesn't appear to be a characterization test",
				Recommendation: "Either change the base class to XCTestCase or ensure this test captures specific behavior for regression detection",
				Confidence:     0.65,
			})
		}
	}

	// Check for other specialized base classes
	if r.isSpecializedBaseClass(baseClass) {
		// Verify appropriate usage based on test content
		if !r.matchesBaseClassPurpose(ctx.TestClass, baseClass) {
			findings = append(findings, Finding{
				RuleName:       r.Name(),
				Severity:       LOW,
				TestMethod:     "",
				TestClass:      ctx.TestClass.Name,
				FilePath:       ctx.TestFile.Path,
				LineNumber:     1,
				Message:        "Test class inherits from " + baseClass + " but may not match the base class's intended purpose",
				Recommendation: "Review the base class usage and ensure it's appropriate for this test's purpose",
				Confidence:     0.60,
			})
		}
	}

	return findings
}

// getDomainFromPath determines the test domain from the file path
func (r *TestOrganizationRule) getDomainFromPath(path string) TestDomain {
	// Normalize path separators
	normalizedPath := filepath.ToSlash(path)

	// Extract the directory after Tests/
	parts := strings.Split(normalizedPath, "/Tests/")
	if len(parts) < 2 {
		return DomainUnknown
	}

	// Get the first directory component after Tests/
	afterTests := parts[1]
	firstDir := strings.Split(afterTests, "/")[0]

	// Map directory names to domains
	domainMap := map[string]TestDomain{
		"Auth":        DomainAuth,
		"Network":     DomainNetwork,
		"Core":        DomainCore,
		"Database":    DomainDatabase,
		"Repository":  DomainRepository,
		"Sync":        DomainSync,
		"Identity":    DomainIdentity,
		"Security":    DomainSecurity,
		"Integration": DomainIntegration,
		"Admin":       DomainAdmin,
		"Services":    DomainServices,
	}

	if domain, ok := domainMap[firstDir]; ok {
		return domain
	}

	return DomainUnknown
}

// getDomainFromContent determines the test domain from file content
func (r *TestOrganizationRule) getDomainFromContent(file *models.TestFile) TestDomain {
	// Analyze class names and imports to determine domain
	domainKeywords := map[TestDomain][]string{
		DomainAuth:        {"oauth", "dpop", "jwt", "token", "auth", "totp", "webauthn"},
		DomainNetwork:     {"xrpc", "http", "websocket", "request", "response", "endpoint"},
		DomainCore:        {"cbor", "car", "cid", "mst", "dag", "hash"},
		DomainDatabase:    {"sqlite", "database", "migration", "actor", "store", "sql"},
		DomainRepository:  {"repository", "commit", "blob", "record"},
		DomainSync:        {"sync", "firehose", "websocket", "event", "stream"},
		DomainIdentity:    {"did", "handle", "plc", "identity", "resolution"},
		DomainSecurity:    {"security", "validation", "ssrf", "sanitiz", "rate", "limit"},
		DomainIntegration: {"integration", "e2e", "endtoend"},
		DomainAdmin:       {"admin", "moderation", "takedown", "label"},
		DomainServices:    {"service", "account", "relay"},
	}

	// Count keyword matches for each domain
	domainScores := make(map[TestDomain]int)

	for _, class := range file.Classes {
		className := strings.ToLower(class.Name)

		for domain, keywords := range domainKeywords {
			for _, keyword := range keywords {
				if strings.Contains(className, keyword) {
					domainScores[domain]++
				}
			}
		}

		// Also check method names
		for _, method := range class.Methods {
			methodName := strings.ToLower(method.Name)

			for domain, keywords := range domainKeywords {
				for _, keyword := range keywords {
					if strings.Contains(methodName, keyword) {
						domainScores[domain]++
					}
				}
			}
		}
	}

	// Check imports
	for _, imp := range file.Imports {
		impLower := strings.ToLower(imp)

		for domain, keywords := range domainKeywords {
			for _, keyword := range keywords {
				if strings.Contains(impLower, keyword) {
					domainScores[domain]++
				}
			}
		}
	}

	// Find domain with highest score
	maxScore := 0
	bestDomain := DomainUnknown

	for domain, score := range domainScores {
		if score > maxScore {
			maxScore = score
			bestDomain = domain
		}
	}

	// Require at least 4 keyword matches to be confident
	// (content-based guessing is inherently noisy)
	if maxScore < 4 {
		return DomainUnknown
	}

	return bestDomain
}

// isInTestsRoot checks if the directory is the Tests root (not in a subdirectory)
func (r *TestOrganizationRule) isInTestsRoot(dir string) bool {
	normalizedDir := filepath.ToSlash(dir)

	// Check if path ends with /Tests (no subdirectory)
	if strings.HasSuffix(normalizedDir, "/Tests") {
		return true
	}

	// Not in Tests root if path doesn't contain /Tests/
	if !strings.Contains(normalizedDir, "/Tests/") {
		return false
	}

	return false
}

// isCharacterizationTest checks if a test class appears to be a characterization test
func (r *TestOrganizationRule) isCharacterizationTest(class *models.TestClass) bool {
	// Check class name
	className := strings.ToLower(class.Name)
	if strings.Contains(className, "characterization") || strings.Contains(className, "regression") {
		return true
	}

	// Check if methods capture specific behavior
	// Characterization tests typically have assertions on specific values
	for _, method := range class.Methods {
		// Look for patterns indicating behavior capture
		sourceCode := strings.ToLower(method.SourceCode)

		// Characterization tests often have comments about capturing behavior
		for _, comment := range method.Comments {
			commentLower := strings.ToLower(comment)
			if strings.Contains(commentLower, "capture") ||
				strings.Contains(commentLower, "characteriz") ||
				strings.Contains(commentLower, "regression") {
				return true
			}
		}

		// Check for specific value assertions (not just existence checks)
		hasSpecificValueAssertion := false
		for _, assertion := range method.Assertions {
			if assertion.Type == "XCTAssertEqual" || assertion.Type == "XCTAssertEqualObjects" {
				hasSpecificValueAssertion = true
				break
			}
		}

		if hasSpecificValueAssertion && strings.Contains(sourceCode, "expected") {
			return true
		}
	}

	return false
}

// isSpecializedBaseClass checks if a base class is a specialized test base class
func (r *TestOrganizationRule) isSpecializedBaseClass(baseClass string) bool {
	specializedBases := []string{
		"CharacterizationTestBase",
		"IntegrationTestBase",
		"PerformanceTestBase",
		"SecurityTestBase",
	}

	for _, specialized := range specializedBases {
		if strings.Contains(baseClass, specialized) {
			return true
		}
	}

	return false
}

// matchesBaseClassPurpose checks if test content matches the base class purpose
func (r *TestOrganizationRule) matchesBaseClassPurpose(class *models.TestClass, baseClass string) bool {
	// For now, we'll do basic checks
	// This can be expanded with more sophisticated analysis

	if strings.Contains(baseClass, "Integration") {
		// Integration tests should exercise multiple components
		// Check if test has multiple service/component interactions
		return r.hasMultipleComponentInteractions(class)
	}

	if strings.Contains(baseClass, "Performance") {
		// Performance tests should have timing assertions
		return r.hasPerformanceAssertions(class)
	}

	if strings.Contains(baseClass, "Security") {
		// Security tests should validate security properties
		return r.hasSecurityValidation(class)
	}

	// Default to true for unknown base classes
	return true
}

// hasMultipleComponentInteractions checks if test interacts with multiple components
func (r *TestOrganizationRule) hasMultipleComponentInteractions(class *models.TestClass) bool {
	// Count distinct service/component types mentioned
	componentKeywords := []string{
		"service", "controller", "repository", "database", "network", "client",
	}

	// Track which components are found
	componentsFound := make(map[string]bool)

	for _, method := range class.Methods {
		sourceCode := strings.ToLower(method.SourceCode)

		for _, keyword := range componentKeywords {
			if strings.Contains(sourceCode, keyword) {
				componentsFound[keyword] = true
			}
		}
	}

	// Integration tests should interact with at least 2 distinct components
	return len(componentsFound) >= 2
}

// hasPerformanceAssertions checks if test has timing/performance assertions
func (r *TestOrganizationRule) hasPerformanceAssertions(class *models.TestClass) bool {
	for _, method := range class.Methods {
		sourceCode := strings.ToLower(method.SourceCode)

		// Look for timing-related code
		if strings.Contains(sourceCode, "time") ||
			strings.Contains(sourceCode, "duration") ||
			strings.Contains(sourceCode, "performance") ||
			strings.Contains(sourceCode, "benchmark") {
			return true
		}
	}

	return false
}

// hasSecurityValidation checks if test validates security properties
func (r *TestOrganizationRule) hasSecurityValidation(class *models.TestClass) bool {
	for _, method := range class.Methods {
		sourceCode := strings.ToLower(method.SourceCode)

		// Look for security-related validation
		securityKeywords := []string{
			"security", "auth", "validate", "verify", "reject", "malicious", "invalid",
		}

		for _, keyword := range securityKeywords {
			if strings.Contains(sourceCode, keyword) {
				return true
			}
		}
	}

	return false
}
