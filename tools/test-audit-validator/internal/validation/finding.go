package validation

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
