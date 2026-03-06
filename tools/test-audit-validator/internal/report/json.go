package report

import (
	"encoding/json"
	"fmt"
)

// JSONReportGenerator produces JSON-formatted reports.
type JSONReportGenerator struct {
	Pretty bool // if true, use indented JSON
}

// NewJSONReportGenerator creates a new JSONReportGenerator.
func NewJSONReportGenerator(pretty bool) *JSONReportGenerator {
	return &JSONReportGenerator{Pretty: pretty}
}

type jsonReport struct {
	Metadata   jsonMetadata   `json:"metadata"`
	Statistics jsonStatistics `json:"statistics"`
	Findings   []jsonFinding  `json:"findings"`
	Errors     []jsonError    `json:"errors,omitempty"`
}

type jsonMetadata struct {
	AnalysisTimestamp string            `json:"analysis_timestamp"`
	Version           string            `json:"version"`
	RootDirectory     string            `json:"root_directory"`
	Configuration     map[string]string `json:"configuration,omitempty"`
	Duration          string            `json:"duration"`
	ParserMode        string            `json:"parser_mode,omitempty"`
	ClangAttempted    int               `json:"clang_attempted_count,omitempty"`
	ClangSucceeded    int               `json:"clang_success_count,omitempty"`
	ClangFallbacks    int               `json:"clang_fallback_count,omitempty"`
}

type jsonStatistics struct {
	TotalTestsAnalyzed   int            `json:"total_tests_analyzed"`
	TotalClassesAnalyzed int            `json:"total_classes_analyzed"`
	TotalFilesAnalyzed   int            `json:"total_files_analyzed"`
	IssuesFound          int            `json:"issues_found"`
	IssuesBySeverity     map[string]int `json:"issues_by_severity"`
	PassRate             float64        `json:"pass_rate"`
	AssertionDensity     float64        `json:"assertion_density"`
	DomainCoverage       map[string]int `json:"domain_coverage,omitempty"`
}

type jsonFinding struct {
	RuleName       string  `json:"rule_name"`
	Severity       string  `json:"severity"`
	TestMethod     string  `json:"test_method"`
	TestClass      string  `json:"test_class"`
	FilePath       string  `json:"file_path"`
	LineNumber     int     `json:"line_number"`
	Message        string  `json:"message"`
	Recommendation string  `json:"recommendation"`
	Confidence     float64 `json:"confidence"`
}

type jsonError struct {
	FilePath string `json:"file_path"`
	Message  string `json:"message"`
}

// Generate creates a JSON report from the given report data.
func (g *JSONReportGenerator) Generate(report *Report) (string, error) {
	if report == nil {
		return "", fmt.Errorf("report must not be nil")
	}

	jr := jsonReport{
		Metadata: jsonMetadata{
			AnalysisTimestamp: report.Metadata.AnalysisTimestamp,
			Version:           report.Metadata.Version,
			RootDirectory:     report.Metadata.RootDirectory,
			Configuration:     report.Metadata.Configuration,
			Duration:          report.Metadata.Duration,
			ParserMode:        report.Metadata.ParserMode,
			ClangAttempted:    report.Metadata.ClangAttempted,
			ClangSucceeded:    report.Metadata.ClangSucceeded,
			ClangFallbacks:    report.Metadata.ClangFallbacks,
		},
		Statistics: jsonStatistics{
			TotalTestsAnalyzed:   report.Statistics.TotalTestsAnalyzed,
			TotalClassesAnalyzed: report.Statistics.TotalClassesAnalyzed,
			TotalFilesAnalyzed:   report.Statistics.TotalFilesAnalyzed,
			IssuesFound:          report.Statistics.IssuesFound,
			IssuesBySeverity:     report.Statistics.IssuesBySeverity,
			PassRate:             report.Statistics.PassRate,
			AssertionDensity:     report.Statistics.AssertionDensity,
			DomainCoverage:       report.Statistics.DomainCoverage,
		},
		Findings: make([]jsonFinding, 0, len(report.Findings)),
	}

	for _, f := range report.Findings {
		jr.Findings = append(jr.Findings, jsonFinding{
			RuleName:       f.RuleName,
			Severity:       f.Severity.String(),
			TestMethod:     f.TestMethod,
			TestClass:      f.TestClass,
			FilePath:       f.FilePath,
			LineNumber:     f.LineNumber,
			Message:        f.Message,
			Recommendation: f.Recommendation,
			Confidence:     f.Confidence,
		})
	}

	if len(report.Errors) > 0 {
		jr.Errors = make([]jsonError, 0, len(report.Errors))
		for _, e := range report.Errors {
			jr.Errors = append(jr.Errors, jsonError{
				FilePath: e.FilePath,
				Message:  e.Message,
			})
		}
	}

	var data []byte
	var err error
	if g.Pretty {
		data, err = json.MarshalIndent(jr, "", "  ")
	} else {
		data, err = json.Marshal(jr)
	}
	if err != nil {
		return "", fmt.Errorf("failed to marshal report to JSON: %w", err)
	}

	return string(data), nil
}
