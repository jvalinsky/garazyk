package report

import "github.com/september-pds/test-audit-validator/internal/validation"

// Report contains the complete results of a test audit validation run.
type Report struct {
	Findings   []validation.Finding
	Statistics Statistics
	Metadata   Metadata
	Errors     []AnalysisError
}

// AnalysisError captures a file-level analysis failure in machine-readable form.
type AnalysisError struct {
	FilePath string
	Message  string
}

// Statistics contains aggregate metrics about the validation run.
type Statistics struct {
	TotalTestsAnalyzed   int
	TotalClassesAnalyzed int
	TotalFilesAnalyzed   int
	IssuesFound          int
	IssuesBySeverity     map[string]int
	PassRate             float64
	AssertionDensity     float64
	DomainCoverage       map[string]int
}

// Metadata contains contextual information about the validation run.
type Metadata struct {
	AnalysisTimestamp string
	Version           string
	RootDirectory     string
	Configuration     map[string]string
	Duration          string
	ParserMode        string
	ClangAttempted    int
	ClangSucceeded    int
	ClangFallbacks    int
}
