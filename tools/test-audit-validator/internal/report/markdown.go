package report

import (
	"fmt"
	"sort"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

// MarkdownReportGenerator produces Markdown-formatted reports.
type MarkdownReportGenerator struct{}

// NewMarkdownReportGenerator creates a new MarkdownReportGenerator.
func NewMarkdownReportGenerator() *MarkdownReportGenerator {
	return &MarkdownReportGenerator{}
}

// Generate creates a Markdown report from the given report data.
func (g *MarkdownReportGenerator) Generate(report *Report) (string, error) {
	if report == nil {
		return "", fmt.Errorf("report must not be nil")
	}

	var b strings.Builder

	g.writeTitle(&b)
	g.writeExecutiveSummary(&b, report)
	g.writeStatisticsTable(&b, report)
	g.writeFindingsBySection(&b, report, validation.CRITICAL, "Critical Findings")
	g.writeFindingsBySection(&b, report, validation.HIGH, "High Findings")
	g.writeFindingsBySection(&b, report, validation.MEDIUM, "Medium Findings")
	g.writeFindingsBySection(&b, report, validation.LOW, "Low Findings")
	g.writeRecommendationsSummary(&b, report)
	g.writeTestQualityMetrics(&b, report)

	return b.String(), nil
}

func (g *MarkdownReportGenerator) writeTitle(b *strings.Builder) {
	b.WriteString("# Test Audit Validation Report\n\n")
}

func (g *MarkdownReportGenerator) writeExecutiveSummary(b *strings.Builder, report *Report) {
	b.WriteString("## Executive Summary\n\n")
	b.WriteString(fmt.Sprintf("- **Date**: %s\n", report.Metadata.AnalysisTimestamp))
	b.WriteString(fmt.Sprintf("- **Total Tests Analyzed**: %d\n", report.Statistics.TotalTestsAnalyzed))
	b.WriteString(fmt.Sprintf("- **Issues Found**: %d\n", report.Statistics.IssuesFound))
	b.WriteString(fmt.Sprintf("- **Pass Rate**: %.1f%%\n", report.Statistics.PassRate*100))
	b.WriteString("\n")
}

func (g *MarkdownReportGenerator) writeStatisticsTable(b *strings.Builder, report *Report) {
	b.WriteString("## Issues by Severity\n\n")
	b.WriteString("| Severity | Count |\n")
	b.WriteString("|----------|-------|\n")

	severities := []string{"critical", "high", "medium", "low"}
	for _, sev := range severities {
		count := report.Statistics.IssuesBySeverity[sev]
		b.WriteString(fmt.Sprintf("| %s | %d |\n", sev, count))
	}
	b.WriteString("\n")
}

func (g *MarkdownReportGenerator) writeFindingsBySection(b *strings.Builder, report *Report, severity validation.Severity, title string) {
	var filtered []validation.Finding
	for _, f := range report.Findings {
		if f.Severity == severity {
			filtered = append(filtered, f)
		}
	}

	if len(filtered) == 0 {
		return
	}

	b.WriteString(fmt.Sprintf("## %s\n\n", title))
	for i, f := range filtered {
		b.WriteString(fmt.Sprintf("### %d. %s\n\n", i+1, f.RuleName))
		b.WriteString(fmt.Sprintf("- **Test**: `%s.%s`\n", f.TestClass, f.TestMethod))
		b.WriteString(fmt.Sprintf("- **Location**: `%s:%d`\n", f.FilePath, f.LineNumber))
		b.WriteString(fmt.Sprintf("- **Message**: %s\n", f.Message))
		if f.Recommendation != "" {
			b.WriteString(fmt.Sprintf("- **Recommendation**: %s\n", f.Recommendation))
		}
		b.WriteString(fmt.Sprintf("- **Confidence**: %.0f%%\n", f.Confidence*100))
		b.WriteString("\n")
	}
}

func (g *MarkdownReportGenerator) writeRecommendationsSummary(b *strings.Builder, report *Report) {
	if len(report.Findings) == 0 {
		return
	}

	b.WriteString("## Recommendations Summary\n\n")

	ruleCounts := make(map[string]int)
	for _, f := range report.Findings {
		ruleCounts[f.RuleName]++
	}

	rules := make([]string, 0, len(ruleCounts))
	for rule := range ruleCounts {
		rules = append(rules, rule)
	}
	sort.Strings(rules)

	b.WriteString("| Rule | Findings |\n")
	b.WriteString("|------|----------|\n")
	for _, rule := range rules {
		b.WriteString(fmt.Sprintf("| %s | %d |\n", rule, ruleCounts[rule]))
	}
	b.WriteString("\n")
}

func (g *MarkdownReportGenerator) writeTestQualityMetrics(b *strings.Builder, report *Report) {
	b.WriteString("## Test Quality Metrics\n\n")
	b.WriteString(fmt.Sprintf("- **Assertion Density**: %.2f assertions per test\n", report.Statistics.AssertionDensity))

	if len(report.Statistics.DomainCoverage) > 0 {
		b.WriteString("- **Domain Coverage**:\n")

		domains := make([]string, 0, len(report.Statistics.DomainCoverage))
		for domain := range report.Statistics.DomainCoverage {
			domains = append(domains, domain)
		}
		sort.Strings(domains)

		for _, domain := range domains {
			b.WriteString(fmt.Sprintf("  - %s: %d tests\n", domain, report.Statistics.DomainCoverage[domain]))
		}
	}
	b.WriteString("\n")
}
