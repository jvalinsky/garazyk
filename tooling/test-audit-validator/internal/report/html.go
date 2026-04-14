package report

import (
	"fmt"
	"html/template"
	"sort"
	"strings"
)

const htmlTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Test Audit Validation Report</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1a1a2e; color: #e0e0e0; line-height: 1.6; padding: 2rem; }
  h1 { color: #e0e0e0; font-size: 1.8rem; margin-bottom: 0.5rem; }
  h2 { color: #c0c0d0; font-size: 1.3rem; margin: 1.5rem 0 0.8rem; border-bottom: 1px solid #333; padding-bottom: 0.3rem; }
  .metadata { color: #888; font-size: 0.85rem; margin-bottom: 1.5rem; }
  .cards { display: flex; gap: 1rem; flex-wrap: wrap; margin-bottom: 1.5rem; }
  .card { background: #16213e; border-radius: 8px; padding: 1rem 1.5rem; min-width: 160px; flex: 1; }
  .card .label { font-size: 0.75rem; text-transform: uppercase; color: #888; letter-spacing: 0.05em; }
  .card .value { font-size: 1.6rem; font-weight: 700; color: #e0e0e0; }
  .severity-bar { display: flex; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 1.5rem; }
  .severity-item { border-radius: 6px; padding: 0.5rem 1rem; font-size: 0.85rem; font-weight: 600; }
  .sev-critical { background: #5c1a1a; color: #ff6b6b; }
  .sev-high { background: #5c3a1a; color: #ffa94d; }
  .sev-medium { background: #5c5a1a; color: #ffd43b; }
  .sev-low { background: #1a3a5c; color: #74c0fc; }
  .filters { margin-bottom: 1rem; }
  .filter-btn { background: #16213e; border: 1px solid #333; color: #c0c0d0; padding: 0.4rem 0.9rem; border-radius: 4px; cursor: pointer; margin-right: 0.3rem; font-size: 0.8rem; }
  .filter-btn:hover { background: #1a2744; }
  .filter-btn.active { border-color: #74c0fc; color: #74c0fc; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; font-size: 0.85rem; }
  th { background: #16213e; color: #888; text-align: left; padding: 0.6rem 0.8rem; font-weight: 600; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.05em; }
  td { padding: 0.6rem 0.8rem; border-bottom: 1px solid #222; }
  tr:hover td { background: #16213e; }
  .badge { padding: 0.15rem 0.5rem; border-radius: 3px; font-size: 0.75rem; font-weight: 600; }
  .badge-critical { background: #5c1a1a; color: #ff6b6b; }
  .badge-high { background: #5c3a1a; color: #ffa94d; }
  .badge-medium { background: #5c5a1a; color: #ffd43b; }
  .badge-low { background: #1a3a5c; color: #74c0fc; }
  .domain-list { list-style: none; }
  .domain-list li { padding: 0.3rem 0; display: flex; justify-content: space-between; max-width: 400px; border-bottom: 1px solid #222; }
  .no-findings { color: #6a6; font-style: italic; padding: 1rem 0; }
</style>
</head>
<body>
<h1>Test Audit Validation Report</h1>
<div class="metadata">
  Generated: {{.Metadata.AnalysisTimestamp}}{{if .Metadata.Duration}} &middot; Duration: {{.Metadata.Duration}}{{end}}
</div>

<h2>Summary</h2>
<div class="cards">
  <div class="card"><div class="label">Total Tests</div><div class="value">{{.Statistics.TotalTestsAnalyzed}}</div></div>
  <div class="card"><div class="label">Issues Found</div><div class="value">{{.Statistics.IssuesFound}}</div></div>
  <div class="card"><div class="label">Pass Rate</div><div class="value">{{printf "%.1f" (passRate .Statistics.PassRate)}}%</div></div>
  <div class="card"><div class="label">Assertion Density</div><div class="value">{{printf "%.2f" .Statistics.AssertionDensity}}</div></div>
</div>

<h2>Severity Breakdown</h2>
<div class="severity-bar">
{{range .SeverityOrder}}  <div class="severity-item sev-{{.Name}}">{{.Label}}: {{.Count}}</div>
{{end}}</div>

<h2>Findings</h2>
{{if .Findings}}
<div class="filters">
  <button class="filter-btn active" data-severity="all" onclick="filterFindings('all')">All</button>
  <button class="filter-btn" data-severity="critical" onclick="filterFindings('critical')">Critical</button>
  <button class="filter-btn" data-severity="high" onclick="filterFindings('high')">High</button>
  <button class="filter-btn" data-severity="medium" onclick="filterFindings('medium')">Medium</button>
  <button class="filter-btn" data-severity="low" onclick="filterFindings('low')">Low</button>
</div>
<table>
  <thead>
    <tr><th>Severity</th><th>Test Class</th><th>Test Method</th><th>File:Line</th><th>Message</th><th>Confidence</th></tr>
  </thead>
  <tbody>
{{range .Findings}}    <tr data-severity="{{.Severity}}">
      <td><span class="badge badge-{{.Severity}}">{{.Severity}}</span></td>
      <td>{{.TestClass}}</td>
      <td>{{.TestMethod}}</td>
      <td>{{.FilePath}}:{{.LineNumber}}</td>
      <td>{{.Message}}</td>
      <td>{{printf "%.0f" (confidence .Confidence)}}%</td>
    </tr>
{{end}}  </tbody>
</table>
{{else}}
<p class="no-findings">No findings — all tests passed validation.</p>
{{end}}

{{if .DomainCoverage}}
<h2>Domain Coverage</h2>
<ul class="domain-list">
{{range .DomainCoverage}}  <li><span>{{.Name}}</span><span>{{.Count}} tests</span></li>
{{end}}</ul>
{{end}}

<script>
function filterFindings(severity) {
  var rows = document.querySelectorAll('tbody tr[data-severity]');
  var btns = document.querySelectorAll('.filter-btn');
  btns.forEach(function(b) { b.classList.toggle('active', b.getAttribute('data-severity') === severity); });
  rows.forEach(function(r) {
    r.style.display = (severity === 'all' || r.getAttribute('data-severity') === severity) ? '' : 'none';
  });
}
</script>
</body>
</html>`

type htmlFinding struct {
	Severity   string
	TestClass  string
	TestMethod string
	FilePath   string
	LineNumber int
	Message    string
	Confidence float64
}

type htmlSeverityItem struct {
	Name  string
	Label string
	Count int
}

type htmlDomainItem struct {
	Name  string
	Count int
}

type htmlTemplateData struct {
	Metadata       Metadata
	Statistics     Statistics
	Findings       []htmlFinding
	SeverityOrder  []htmlSeverityItem
	DomainCoverage []htmlDomainItem
}

// HTMLReportGenerator produces self-contained HTML reports.
type HTMLReportGenerator struct{}

// NewHTMLReportGenerator creates a new HTMLReportGenerator.
func NewHTMLReportGenerator() *HTMLReportGenerator {
	return &HTMLReportGenerator{}
}

// Generate creates an interactive HTML report from the given report data.
func (g *HTMLReportGenerator) Generate(report *Report) (string, error) {
	if report == nil {
		return "", fmt.Errorf("report must not be nil")
	}

	funcMap := template.FuncMap{
		"passRate":   func(r float64) float64 { return r * 100 },
		"confidence": func(c float64) float64 { return c * 100 },
	}

	tmpl, err := template.New("report").Funcs(funcMap).Parse(htmlTemplate)
	if err != nil {
		return "", fmt.Errorf("parsing HTML template: %w", err)
	}

	data := g.buildTemplateData(report)

	var b strings.Builder
	if err := tmpl.Execute(&b, data); err != nil {
		return "", fmt.Errorf("executing HTML template: %w", err)
	}

	return b.String(), nil
}

func (g *HTMLReportGenerator) buildTemplateData(report *Report) htmlTemplateData {
	findings := make([]htmlFinding, len(report.Findings))
	for i, f := range report.Findings {
		findings[i] = htmlFinding{
			Severity:   f.Severity.String(),
			TestClass:  f.TestClass,
			TestMethod: f.TestMethod,
			FilePath:   f.FilePath,
			LineNumber: f.LineNumber,
			Message:    f.Message,
			Confidence: f.Confidence,
		}
	}

	severities := []struct {
		key   string
		label string
	}{
		{"critical", "Critical"},
		{"high", "High"},
		{"medium", "Medium"},
		{"low", "Low"},
	}
	sevItems := make([]htmlSeverityItem, len(severities))
	for i, s := range severities {
		sevItems[i] = htmlSeverityItem{
			Name:  s.key,
			Label: s.label,
			Count: report.Statistics.IssuesBySeverity[s.key],
		}
	}

	var domainItems []htmlDomainItem
	if len(report.Statistics.DomainCoverage) > 0 {
		domains := make([]string, 0, len(report.Statistics.DomainCoverage))
		for d := range report.Statistics.DomainCoverage {
			domains = append(domains, d)
		}
		sort.Strings(domains)
		for _, d := range domains {
			domainItems = append(domainItems, htmlDomainItem{
				Name:  d,
				Count: report.Statistics.DomainCoverage[d],
			})
		}
	}

	return htmlTemplateData{
		Metadata:       report.Metadata,
		Statistics:     report.Statistics,
		Findings:       findings,
		SeverityOrder:  sevItems,
		DomainCoverage: domainItems,
	}
}
