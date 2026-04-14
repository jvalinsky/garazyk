package validation

import "strconv"

// Finding represents a validation issue discovered in test code
type Finding struct {
	RuleName       string   // Name of the validation rule that generated this finding
	Severity       Severity // Severity level of the finding
	TestMethod     string   // Name of the test method where the issue was found
	TestClass      string   // Name of the test class containing the method
	FilePath       string   // Path to the file containing the test
	LineNumber     int      // Line number where the issue occurs
	Message        string   // Human-readable description of the issue
	Recommendation string   // Actionable recommendation for fixing the issue
	Confidence     float64  // Confidence score (0.0-1.0) indicating certainty of the finding
}

// DedupeFindings removes exact duplicate findings while preserving order.
// Dedupe key: rule, file, class, method, line, message.
func DedupeFindings(findings []Finding) []Finding {
	if len(findings) < 2 {
		return findings
	}

	seen := make(map[string]struct{}, len(findings))
	deduped := make([]Finding, 0, len(findings))

	for _, f := range findings {
		key := f.RuleName + "\x00" + f.FilePath + "\x00" + f.TestClass + "\x00" +
			f.TestMethod + "\x00" + strconv.Itoa(f.LineNumber) + "\x00" + f.Message
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		deduped = append(deduped, f)
	}

	return deduped
}
