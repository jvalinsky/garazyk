package report

import (
	"path/filepath"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

// CalculateStatistics computes statistics from findings and test data
func CalculateStatistics(findings []validation.Finding, totalTests, totalClasses, totalFiles int, totalAssertions int) Statistics {
	issuesBySeverity := make(map[string]int)
	for _, f := range findings {
		issuesBySeverity[f.Severity.String()]++
	}

	// Count unique test methods with at least one CRITICAL or HIGH finding
	criticalHighTests := make(map[string]struct{})
	for _, f := range findings {
		if f.Severity == validation.CRITICAL || f.Severity == validation.HIGH {
			key := f.TestClass + "." + f.TestMethod
			criticalHighTests[key] = struct{}{}
		}
	}

	var passRate float64
	if totalTests > 0 {
		passRate = float64(totalTests-len(criticalHighTests)) / float64(totalTests) * 100
	}

	divisor := totalTests
	if divisor < 1 {
		divisor = 1
	}
	assertionDensity := float64(totalAssertions) / float64(divisor)

	domainCoverage := make(map[string]int)
	for _, f := range findings {
		domain := extractDomain(f.FilePath)
		domainCoverage[domain]++
	}

	return Statistics{
		TotalTestsAnalyzed:   totalTests,
		TotalClassesAnalyzed: totalClasses,
		TotalFilesAnalyzed:   totalFiles,
		IssuesFound:          len(findings),
		IssuesBySeverity:     issuesBySeverity,
		PassRate:             passRate,
		AssertionDensity:     assertionDensity,
		DomainCoverage:       domainCoverage,
	}
}

// extractDomain extracts a domain category from a file path.
// It looks for the first directory component after "Tests" or "Test".
func extractDomain(path string) string {
	parts := strings.Split(path, "/")
	foundTests := false
	for _, p := range parts {
		if p == "" {
			continue
		}
		if foundTests {
			// Skip file names
			if strings.HasSuffix(p, ".m") || strings.HasSuffix(p, ".h") {
				continue
			}
			// Return the first directory after Tests/
			if len(p) > 0 {
				return p
			}
		}
		if p == "Tests" || p == "Test" || p == "tests" || p == "test" {
			foundTests = true
		}
	}

	// Fallback: use basename without suffix as domain hint
	base := filepath.Base(path)
	base = strings.TrimSuffix(base, ".m")
	base = strings.TrimSuffix(base, "Tests")
	base = strings.TrimSuffix(base, "Test")
	if base != "" {
		return base
	}
	return "Other"
}

// GroupFindingsBySeverity groups findings into severity buckets
func GroupFindingsBySeverity(findings []validation.Finding) map[string][]validation.Finding {
	groups := make(map[string][]validation.Finding)
	for _, f := range findings {
		key := f.Severity.String()
		groups[key] = append(groups[key], f)
	}
	return groups
}

// GroupFindingsByRule groups findings by rule name
func GroupFindingsByRule(findings []validation.Finding) map[string][]validation.Finding {
	groups := make(map[string][]validation.Finding)
	for _, f := range findings {
		groups[f.RuleName] = append(groups[f.RuleName], f)
	}
	return groups
}

// GroupFindingsByFile groups findings by file path
func GroupFindingsByFile(findings []validation.Finding) map[string][]validation.Finding {
	groups := make(map[string][]validation.Finding)
	for _, f := range findings {
		groups[f.FilePath] = append(groups[f.FilePath], f)
	}
	return groups
}
