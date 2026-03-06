package report

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

func sampleReport() *Report {
	return &Report{
		Findings: []validation.Finding{
			{
				RuleName:       "assertion-quality",
				Severity:       validation.CRITICAL,
				TestMethod:     "testHandleRequest",
				TestClass:      "ATProtoServerTests",
				FilePath:       "Tests/ATProtoServerTests.m",
				LineNumber:     42,
				Message:        "Test has no assertions",
				Recommendation: "Add at least one assertion to verify behavior",
				Confidence:     0.95,
			},
			{
				RuleName:       "coverage-gap",
				Severity:       validation.HIGH,
				TestMethod:     "testCreateSession",
				TestClass:      "SessionTests",
				FilePath:       "Tests/SessionTests.m",
				LineNumber:     100,
				Message:        "Error path not tested",
				Recommendation: "Add test for error handling path",
				Confidence:     0.8,
			},
			{
				RuleName:       "test-organization",
				Severity:       validation.MEDIUM,
				TestMethod:     "testAll",
				TestClass:      "MiscTests",
				FilePath:       "Tests/MiscTests.m",
				LineNumber:     10,
				Message:        "Test method too long",
				Recommendation: "Split into focused test methods",
				Confidence:     0.7,
			},
			{
				RuleName:       "test-documentation",
				Severity:       validation.LOW,
				TestMethod:     "testFoo",
				TestClass:      "FooTests",
				FilePath:       "Tests/FooTests.m",
				LineNumber:     5,
				Message:        "Missing test documentation",
				Recommendation: "Add comments describing test intent",
				Confidence:     0.6,
			},
		},
		Statistics: Statistics{
			TotalTestsAnalyzed:   150,
			TotalClassesAnalyzed: 20,
			TotalFilesAnalyzed:   15,
			IssuesFound:          4,
			IssuesBySeverity: map[string]int{
				"critical": 1,
				"high":     1,
				"medium":   1,
				"low":      1,
			},
			PassRate:         0.973,
			AssertionDensity: 2.5,
			DomainCoverage: map[string]int{
				"auth":    10,
				"repo":    25,
				"session": 15,
			},
		},
		Metadata: Metadata{
			AnalysisTimestamp: "2026-03-04T12:00:00Z",
			Version:           "1.0.0",
			RootDirectory:     "/project",
			Configuration:     map[string]string{"mode": "strict"},
			Duration:          "1.5s",
			ParserMode:        "auto",
			ClangAttempted:    15,
			ClangSucceeded:    14,
			ClangFallbacks:    1,
		},
	}
}

func emptyReport() *Report {
	return &Report{
		Findings: nil,
		Statistics: Statistics{
			TotalTestsAnalyzed:   0,
			TotalClassesAnalyzed: 0,
			TotalFilesAnalyzed:   0,
			IssuesFound:          0,
			IssuesBySeverity:     map[string]int{},
			PassRate:             1.0,
			AssertionDensity:     0.0,
			DomainCoverage:       map[string]int{},
		},
		Metadata: Metadata{
			AnalysisTimestamp: "2026-03-04T12:00:00Z",
			Version:           "1.0.0",
			RootDirectory:     "/project",
			Duration:          "0s",
		},
	}
}

// --- Markdown Tests ---

func TestMarkdownReportGenerator_Generate(t *testing.T) {
	gen := NewMarkdownReportGenerator()
	output, err := gen.Generate(sampleReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expectedSections := []string{
		"# Test Audit Validation Report",
		"## Executive Summary",
		"## Issues by Severity",
		"## Critical Findings",
		"## High Findings",
		"## Medium Findings",
		"## Low Findings",
		"## Recommendations Summary",
		"## Test Quality Metrics",
	}
	for _, section := range expectedSections {
		if !strings.Contains(output, section) {
			t.Errorf("output missing section %q", section)
		}
	}

	if !strings.Contains(output, "150") {
		t.Error("output should contain total tests analyzed count")
	}
	if !strings.Contains(output, "97.3%") {
		t.Error("output should contain pass rate percentage")
	}
}

func TestMarkdownReportGenerator_EmptyFindings(t *testing.T) {
	gen := NewMarkdownReportGenerator()
	output, err := gen.Generate(emptyReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(output, "# Test Audit Validation Report") {
		t.Error("output should contain title")
	}
	if !strings.Contains(output, "## Executive Summary") {
		t.Error("output should contain executive summary")
	}
	if strings.Contains(output, "## Critical Findings") {
		t.Error("output should not contain critical findings section when none exist")
	}
	if strings.Contains(output, "## Recommendations Summary") {
		t.Error("output should not contain recommendations when no findings")
	}
}

func TestMarkdownReportGenerator_CriticalFindings(t *testing.T) {
	report := &Report{
		Findings: []validation.Finding{
			{
				RuleName:       "assertion-quality",
				Severity:       validation.CRITICAL,
				TestMethod:     "testCritical",
				TestClass:      "CriticalTests",
				FilePath:       "Tests/CriticalTests.m",
				LineNumber:     99,
				Message:        "No assertions found",
				Recommendation: "Add assertions",
				Confidence:     1.0,
			},
		},
		Statistics: Statistics{
			IssuesBySeverity: map[string]int{"critical": 1},
		},
		Metadata: Metadata{AnalysisTimestamp: "2026-03-04T12:00:00Z"},
	}

	gen := NewMarkdownReportGenerator()
	output, err := gen.Generate(report)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(output, "## Critical Findings") {
		t.Error("output should contain critical findings section")
	}
	if !strings.Contains(output, "CriticalTests.testCritical") {
		t.Error("output should contain test class and method")
	}
	if !strings.Contains(output, "Tests/CriticalTests.m:99") {
		t.Error("output should contain file and line number")
	}
	if !strings.Contains(output, "No assertions found") {
		t.Error("output should contain finding message")
	}
	if !strings.Contains(output, "Add assertions") {
		t.Error("output should contain recommendation")
	}
}

// --- JSON Tests ---

func TestJSONReportGenerator_Generate(t *testing.T) {
	gen := NewJSONReportGenerator(false)
	output, err := gen.Generate(sampleReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var parsed jsonReport
	if err := json.Unmarshal([]byte(output), &parsed); err != nil {
		t.Fatalf("output is not valid JSON: %v", err)
	}

	if parsed.Statistics.TotalTestsAnalyzed != 150 {
		t.Errorf("expected 150 tests analyzed, got %d", parsed.Statistics.TotalTestsAnalyzed)
	}
	if len(parsed.Findings) != 4 {
		t.Errorf("expected 4 findings, got %d", len(parsed.Findings))
	}
	if parsed.Findings[0].Severity != "critical" {
		t.Errorf("expected first finding severity to be 'critical', got %q", parsed.Findings[0].Severity)
	}
	if parsed.Metadata.Version != "1.0.0" {
		t.Errorf("expected version '1.0.0', got %q", parsed.Metadata.Version)
	}
	if parsed.Metadata.ParserMode != "auto" {
		t.Errorf("expected parser mode 'auto', got %q", parsed.Metadata.ParserMode)
	}
	if parsed.Metadata.ClangAttempted != 15 || parsed.Metadata.ClangSucceeded != 14 || parsed.Metadata.ClangFallbacks != 1 {
		t.Errorf("unexpected clang counters: attempted=%d succeeded=%d fallbacks=%d",
			parsed.Metadata.ClangAttempted, parsed.Metadata.ClangSucceeded, parsed.Metadata.ClangFallbacks)
	}
}

func TestJSONReportGenerator_Pretty(t *testing.T) {
	gen := NewJSONReportGenerator(true)
	output, err := gen.Generate(sampleReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(output, "\n") {
		t.Error("pretty output should contain newlines")
	}
	if !strings.Contains(output, "  ") {
		t.Error("pretty output should contain indentation")
	}

	var parsed jsonReport
	if err := json.Unmarshal([]byte(output), &parsed); err != nil {
		t.Fatalf("pretty output is not valid JSON: %v", err)
	}
}

func TestJSONReportGenerator_RoundTrip(t *testing.T) {
	gen := NewJSONReportGenerator(false)
	report := sampleReport()
	output, err := gen.Generate(report)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var parsed jsonReport
	if err := json.Unmarshal([]byte(output), &parsed); err != nil {
		t.Fatalf("failed to unmarshal: %v", err)
	}

	if parsed.Statistics.IssuesFound != report.Statistics.IssuesFound {
		t.Errorf("round-trip issues found: got %d, want %d",
			parsed.Statistics.IssuesFound, report.Statistics.IssuesFound)
	}
	if len(parsed.Findings) != len(report.Findings) {
		t.Errorf("round-trip findings count: got %d, want %d",
			len(parsed.Findings), len(report.Findings))
	}
	for i, f := range parsed.Findings {
		if f.RuleName != report.Findings[i].RuleName {
			t.Errorf("finding %d rule name: got %q, want %q", i, f.RuleName, report.Findings[i].RuleName)
		}
		if f.Severity != report.Findings[i].Severity.String() {
			t.Errorf("finding %d severity: got %q, want %q", i, f.Severity, report.Findings[i].Severity.String())
		}
		if f.Confidence != report.Findings[i].Confidence {
			t.Errorf("finding %d confidence: got %f, want %f", i, f.Confidence, report.Findings[i].Confidence)
		}
	}

	if parsed.Metadata.AnalysisTimestamp != report.Metadata.AnalysisTimestamp {
		t.Errorf("round-trip timestamp: got %q, want %q",
			parsed.Metadata.AnalysisTimestamp, report.Metadata.AnalysisTimestamp)
	}
}

// --- HTML Tests ---

func TestHTMLReportGenerator_Generate(t *testing.T) {
	gen := NewHTMLReportGenerator()
	output, err := gen.Generate(sampleReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	expectedStrings := []string{
		"<html",
		"Test Audit Validation Report",
		"Summary",
		"Severity Breakdown",
		"Findings",
		"Domain Coverage",
		"150",
		"97.3%",
	}
	for _, s := range expectedStrings {
		if !strings.Contains(output, s) {
			t.Errorf("output missing expected string %q", s)
		}
	}
}

func TestHTMLReportGenerator_EmptyFindings(t *testing.T) {
	gen := NewHTMLReportGenerator()
	output, err := gen.Generate(emptyReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(output, "<html") {
		t.Error("output should contain <html tag")
	}
	if !strings.Contains(output, "Test Audit Validation Report") {
		t.Error("output should contain report title")
	}
	if !strings.Contains(output, "No findings") {
		t.Error("output should contain no-findings message when empty")
	}
	if strings.Contains(output, "<tbody>") {
		t.Error("output should not contain findings table body when empty")
	}
}

func TestHTMLReportGenerator_FilterButtons(t *testing.T) {
	gen := NewHTMLReportGenerator()
	output, err := gen.Generate(sampleReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	buttons := []string{
		`data-severity="all"`,
		`data-severity="critical"`,
		`data-severity="high"`,
		`data-severity="medium"`,
		`data-severity="low"`,
	}
	for _, btn := range buttons {
		if !strings.Contains(output, btn) {
			t.Errorf("output missing filter button with %s", btn)
		}
	}

	if !strings.Contains(output, "filterFindings") {
		t.Error("output should contain filterFindings JavaScript function")
	}
}

func TestHTMLReportGenerator_ContainsFindingData(t *testing.T) {
	gen := NewHTMLReportGenerator()
	output, err := gen.Generate(sampleReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	findingData := []string{
		"ATProtoServerTests",
		"testHandleRequest",
		"Tests/ATProtoServerTests.m:42",
		"Test has no assertions",
		"SessionTests",
		"testCreateSession",
		"Error path not tested",
		"badge-critical",
		"badge-high",
		"badge-medium",
		"badge-low",
	}
	for _, d := range findingData {
		if !strings.Contains(output, d) {
			t.Errorf("output missing finding data %q", d)
		}
	}
}

func TestJSONReportGenerator_EmptyFindings(t *testing.T) {
	gen := NewJSONReportGenerator(false)
	output, err := gen.Generate(emptyReport())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var parsed jsonReport
	if err := json.Unmarshal([]byte(output), &parsed); err != nil {
		t.Fatalf("output is not valid JSON: %v", err)
	}

	if len(parsed.Findings) != 0 {
		t.Errorf("expected 0 findings, got %d", len(parsed.Findings))
	}
	if parsed.Statistics.IssuesFound != 0 {
		t.Errorf("expected 0 issues, got %d", parsed.Statistics.IssuesFound)
	}
}

func TestJSONReportGenerator_IncludesAnalysisErrors(t *testing.T) {
	gen := NewJSONReportGenerator(false)
	rpt := emptyReport()
	rpt.Errors = []AnalysisError{
		{
			FilePath: "Tests/Auth/OAuthDPoPTests.m",
			Message:  "failed to parse file (error: ASTReadError)",
		},
		{
			FilePath: "Tests/Network/HttpRouterTests.m",
			Message:  "failed to parse file (error: Failure)",
		},
	}

	output, err := gen.Generate(rpt)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var parsed struct {
		Errors []struct {
			FilePath string `json:"file_path"`
			Message  string `json:"message"`
		} `json:"errors"`
	}
	if err := json.Unmarshal([]byte(output), &parsed); err != nil {
		t.Fatalf("output is not valid JSON: %v", err)
	}

	if len(parsed.Errors) != 2 {
		t.Fatalf("expected 2 errors, got %d", len(parsed.Errors))
	}
	if parsed.Errors[0].FilePath != "Tests/Auth/OAuthDPoPTests.m" {
		t.Fatalf("unexpected first error file path: %q", parsed.Errors[0].FilePath)
	}
	if parsed.Errors[0].Message == "" {
		t.Fatal("expected first error message to be non-empty")
	}
}
