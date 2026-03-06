package config

import (
	"strings"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

// FilterFindings applies configured filters to findings.
// Filters are AND'd together: a finding must pass all active filters.
func FilterFindings(findings []validation.Finding, cfg *Config) []validation.Finding {
	if len(cfg.Domains) == 0 && len(cfg.Severities) == 0 && len(cfg.TestClasses) == 0 && len(cfg.TestTypes) == 0 {
		return findings
	}

	var result []validation.Finding
	for _, f := range findings {
		if !matchesDomains(f, cfg.Domains) {
			continue
		}
		if !matchesSeverities(f, cfg.Severities) {
			continue
		}
		if !matchesClasses(f, cfg.TestClasses) {
			continue
		}
		if !matchesTestTypes(f, cfg.TestTypes) {
			continue
		}
		result = append(result, f)
	}
	return result
}

// matchesDomains returns true if the finding's FilePath contains one of the domain strings,
// or if no domains are configured.
func matchesDomains(f validation.Finding, domains []string) bool {
	if len(domains) == 0 {
		return true
	}
	for _, d := range domains {
		if strings.Contains(f.FilePath, d) {
			return true
		}
	}
	return false
}

// matchesSeverities returns true if the finding's severity string matches one of the configured severities,
// or if no severities are configured.
func matchesSeverities(f validation.Finding, severities []string) bool {
	if len(severities) == 0 {
		return true
	}
	sev := f.Severity.String()
	for _, s := range severities {
		if strings.EqualFold(sev, s) {
			return true
		}
	}
	return false
}

// matchesClasses returns true if the finding's TestClass matches one of the configured class names,
// or if no classes are configured.
func matchesClasses(f validation.Finding, classes []string) bool {
	if len(classes) == 0 {
		return true
	}
	for _, c := range classes {
		if f.TestClass == c {
			return true
		}
	}
	return false
}

// matchesTestTypes returns true if a finding matches one of the configured test types,
// or if no test types are configured.
func matchesTestTypes(f validation.Finding, testTypes []string) bool {
	if len(testTypes) == 0 {
		return true
	}

	for _, tt := range testTypes {
		if findingMatchesType(f, normalizeToken(tt)) {
			return true
		}
	}
	return false
}

func normalizeToken(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

func findingMatchesType(f validation.Finding, testType string) bool {
	file := normalizeToken(f.FilePath)
	class := normalizeToken(f.TestClass)
	method := normalizeToken(f.TestMethod)
	rule := normalizeToken(f.RuleName)
	msg := normalizeToken(f.Message)
	all := strings.Join([]string{file, class, method, rule, msg}, " ")

	switch testType {
	case "property":
		if rule == normalizeToken("PropertyBasedTestRule") {
			return true
		}
		return strings.Contains(all, "property") ||
			strings.Contains(all, "roundtrip") ||
			strings.Contains(all, "round-trip") ||
			strings.Contains(all, "invariant") ||
			strings.Contains(all, "idempot")
	case "integration":
		if rule == normalizeToken("IntegrationTestRule") {
			return true
		}
		return strings.Contains(file, "/integration/") ||
			strings.Contains(class, "integration") ||
			strings.Contains(method, "integration")
	case "interop":
		if rule == normalizeToken("InteropTestRule") {
			return true
		}
		return strings.Contains(all, "interop") ||
			strings.Contains(all, "compatibility") ||
			strings.Contains(all, "conformance")
	case "security":
		if rule == normalizeToken("SecurityTestRule") {
			return true
		}
		return strings.Contains(all, "security") ||
			strings.Contains(all, "oauth") ||
			strings.Contains(all, "jwt") ||
			strings.Contains(all, "dpop") ||
			strings.Contains(all, "ssrf") ||
			strings.Contains(all, "auth")
	case "async":
		if rule == normalizeToken("AsyncTestRule") {
			return true
		}
		return strings.Contains(all, "async") ||
			strings.Contains(all, "expectation") ||
			strings.Contains(all, "waitfor") ||
			strings.Contains(all, "concurrent") ||
			strings.Contains(all, "thread")
	case "characterization":
		if rule == normalizeToken("CharacterizationTestRule") {
			return true
		}
		return strings.Contains(all, "characterization") ||
			strings.Contains(all, "regression")
	default:
		return false
	}
}
