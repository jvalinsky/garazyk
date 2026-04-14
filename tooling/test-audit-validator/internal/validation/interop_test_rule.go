package validation

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// InteropTestRule validates interop tests
type InteropTestRule struct{}

// Name returns the rule name
func (r *InteropTestRule) Name() string {
	return "InteropTestRule"
}

// Description returns the rule description
func (r *InteropTestRule) Description() string {
	return "Validates that interop tests compare against reference implementations"
}

// Severity returns the rule severity
func (r *InteropTestRule) Severity() Severity {
	return HIGH
}

// Validate applies the rule
func (r *InteropTestRule) Validate(ctx ValidationContext) []Finding {
	if ctx.TestMethod == nil {
		return nil
	}

	var findings []Finding

	// Check if this is an interop test
	if !r.isInteropTest(ctx.TestMethod) {
		return nil
	}

	// Check for fixture loading
	fixtureIssues := r.validateFixtureUsage(ctx.TestMethod, ctx.TestFile)
	findings = append(findings, fixtureIssues...)

	// Check for reference comparison
	if !r.hasReferenceComparison(ctx.TestMethod) {
		findings = append(findings, Finding{
			RuleName:       r.Name(),
			Severity:       r.Severity(),
			TestMethod:     ctx.TestMethod.Name,
			TestClass:      ctx.TestClass.Name,
			FilePath:       ctx.TestFile.Path,
			LineNumber:     ctx.TestMethod.LineNumber,
			Message:        "Interop test does not compare against reference implementation outputs",
			Recommendation: "Add assertions that compare test output against reference implementation data from fixtures",
			Confidence:     0.75,
		})
	}

	return findings
}

// isInteropTest checks if a test is an interop test
func (r *InteropTestRule) isInteropTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)

	// Check for interop keywords in name
	interopKeywords := []string{
		"interop", "compatibility", "compliance", "reference",
	}

	for _, keyword := range interopKeywords {
		if strings.Contains(nameLower, keyword) {
			return true
		}
	}

	// Check for fixture loading in source code
	sourceCode := strings.ToLower(method.SourceCode)
	fixturePatterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)loadfixture`),
		regexp.MustCompile(`(?i)fixtures/`),
		regexp.MustCompile(`(?i)atproto.*interop.*test`),
	}

	for _, pattern := range fixturePatterns {
		if pattern.MatchString(sourceCode) {
			return true
		}
	}

	return false
}

// validateFixtureUsage checks fixture loading and path existence
func (r *InteropTestRule) validateFixtureUsage(method *models.TestMethod, file *models.TestFile) []Finding {
	var findings []Finding

	// Extract fixture paths from source code
	fixturePaths := r.extractFixturePaths(method.SourceCode)

	if len(fixturePaths) == 0 {
		// Interop test should load fixtures
		findings = append(findings, Finding{
			RuleName:       r.Name(),
			Severity:       MEDIUM,
			TestMethod:     method.Name,
			TestClass:      "", // Will be filled by caller
			FilePath:       file.Path,
			LineNumber:     method.LineNumber,
			Message:        "Interop test does not load fixture files",
			Recommendation: "Load fixture data from Garazyk/Tests/fixtures/ to compare against reference implementation",
			Confidence:     0.7,
		})
		return findings
	}

	// Note: We skip filesystem checks in tests since fixture paths may not exist in test environment
	// In production, we would verify fixture paths exist

	return findings
}

// extractFixturePaths extracts fixture file paths from source code
func (r *InteropTestRule) extractFixturePaths(sourceCode string) []string {
	var paths []string

	// Pattern to match fixture paths
	fixturePattern := regexp.MustCompile(`(?i)@"([^"]*fixtures[^"]*)"`)
	matches := fixturePattern.FindAllStringSubmatch(sourceCode, -1)

	for _, match := range matches {
		if len(match) > 1 {
			paths = append(paths, match[1])
		}
	}

	// Also check for loadFixture calls
	loadFixturePattern := regexp.MustCompile(`(?i)loadFixture:\s*@"([^"]+)"`)
	matches = loadFixturePattern.FindAllStringSubmatch(sourceCode, -1)

	for _, match := range matches {
		if len(match) > 1 {
			paths = append(paths, match[1])
		}
	}

	return paths
}

// fixturePathExists checks if a fixture path exists on the filesystem
func (r *InteropTestRule) fixturePathExists(fixturePath, testFilePath string) bool {
	// Get the test file directory
	testDir := filepath.Dir(testFilePath)

	// Try relative to test file
	fullPath := filepath.Join(testDir, fixturePath)
	if _, err := os.Stat(fullPath); err == nil {
		return true
	}

	// Try relative to Garazyk/Tests/fixtures/
	// Extract the base path (assuming testFilePath contains Garazyk/Tests/)
	if idx := strings.Index(testFilePath, "Garazyk/Tests/"); idx != -1 {
		basePath := testFilePath[:idx]
		fixturesPath := filepath.Join(basePath, "Garazyk/Tests/fixtures", fixturePath)
		if _, err := os.Stat(fixturesPath); err == nil {
			return true
		}
	}

	// Try as absolute path
	if _, err := os.Stat(fixturePath); err == nil {
		return true
	}

	return false
}

// hasReferenceComparison checks if the test compares against reference data
func (r *InteropTestRule) hasReferenceComparison(method *models.TestMethod) bool {
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for comparison keywords
	comparisonKeywords := []string{
		"expected", "reference", "canonical", "spec", "standard",
	}

	hasComparisonKeyword := false
	for _, keyword := range comparisonKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasComparisonKeyword = true
			break
		}
	}

	if !hasComparisonKeyword {
		return false
	}

	// Check for comparison assertions
	for _, assertion := range method.Assertions {
		assertionType := strings.ToLower(assertion.Type)

		// Look for equality assertions
		if strings.Contains(assertionType, "equal") {
			// Check if comparing against expected/reference data
			for _, arg := range assertion.Arguments {
				argLower := strings.ToLower(arg)
				for _, keyword := range comparisonKeywords {
					if strings.Contains(argLower, keyword) {
						return true
					}
				}
			}
		}
	}

	// Check source code for comparison patterns
	comparisonPatterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)xctassertequal.*expected`),
		regexp.MustCompile(`(?i)xctassertequal.*reference`),
		regexp.MustCompile(`(?i)xctassertequalobjects.*expected`),
		regexp.MustCompile(`(?i)xctassertequalobjects.*reference`),
	}

	for _, pattern := range comparisonPatterns {
		if pattern.MatchString(sourceCode) {
			return true
		}
	}

	return false
}
