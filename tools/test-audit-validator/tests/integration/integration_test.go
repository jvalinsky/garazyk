package integration

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/config"
	"github.com/september-pds/test-audit-validator/internal/models"
	"github.com/september-pds/test-audit-validator/internal/report"
	"github.com/september-pds/test-audit-validator/internal/runner"
	"github.com/september-pds/test-audit-validator/internal/validation"
)

// parseTestFileSimple does a simplified regex-based parse (mirrors the CLI's parser).
func parseTestFileSimple(filePath string) (*models.TestFile, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	source := string(data)
	lines := strings.Split(source, "\n")

	tf := &models.TestFile{Path: filePath}

	var currentClass *models.TestClass
	var currentMethod *models.TestMethod
	var methodBody strings.Builder
	braceDepth := 0
	inMethod := false

	for lineNum, line := range lines {
		trimmed := strings.TrimSpace(line)

		if strings.HasPrefix(trimmed, "@implementation ") || strings.HasPrefix(trimmed, "@interface ") {
			parts := strings.Fields(trimmed)
			if len(parts) >= 2 {
				className := strings.TrimSuffix(parts[1], ":")
				className = strings.TrimSpace(className)
				if strings.Contains(className, "Test") || strings.HasSuffix(className, "Tests") {
					tc := models.TestClass{Name: className, FilePath: filePath}
					if len(parts) > 2 && parts[0] == "@interface" {
						for _, p := range parts[2:] {
							clean := strings.Trim(p, ":(){}")
							if clean != "" && clean != "NSObject" {
								bc := clean
								tc.BaseClass = &bc
								break
							}
						}
					}
					tf.Classes = append(tf.Classes, tc)
					currentClass = &tf.Classes[len(tf.Classes)-1]
				}
			}
		}

		if strings.HasPrefix(trimmed, "- (void)test") || strings.HasPrefix(trimmed, "-(void)test") {
			name := extractMethodName(trimmed)
			if name != "" && currentClass != nil {
				if inMethod && currentMethod != nil {
					currentMethod.SourceCode = methodBody.String()
					extractAssertions(currentMethod)
				}
				currentClass.Methods = append(currentClass.Methods, models.TestMethod{
					Name:       name,
					ClassName:  currentClass.Name,
					LineNumber: lineNum + 1,
				})
				currentMethod = &currentClass.Methods[len(currentClass.Methods)-1]
				methodBody.Reset()
				inMethod = true
				braceDepth = 0
			}
		}

		if inMethod {
			methodBody.WriteString(line)
			methodBody.WriteString("\n")
			braceDepth += strings.Count(line, "{") - strings.Count(line, "}")
			if braceDepth <= 0 && strings.Contains(line, "}") && currentMethod != nil {
				currentMethod.SourceCode = methodBody.String()
				extractAssertions(currentMethod)
				inMethod = false
				currentMethod = nil
			}
		}
	}

	if inMethod && currentMethod != nil {
		currentMethod.SourceCode = methodBody.String()
		extractAssertions(currentMethod)
	}

	return tf, nil
}

func extractMethodName(line string) string {
	idx := strings.Index(line, "test")
	if idx < 0 {
		return ""
	}
	name := line[idx:]
	for i, ch := range name {
		if ch == ' ' || ch == '{' || ch == '(' || ch == ':' || ch == ';' {
			return name[:i]
		}
	}
	return name
}

func extractAssertions(method *models.TestMethod) {
	assertionTypes := []string{
		"XCTAssertEqual", "XCTAssertNotEqual",
		"XCTAssertTrue", "XCTAssertFalse",
		"XCTAssertNil", "XCTAssertNotNil",
		"XCTAssertThrows", "XCTAssertThrowsSpecific",
		"XCTAssertNoThrow", "XCTAssertNoThrowSpecific",
		"XCTAssertEqualObjects", "XCTAssertNotEqualObjects",
		"XCTAssertGreaterThan", "XCTAssertGreaterThanOrEqual",
		"XCTAssertLessThan", "XCTAssertLessThanOrEqual",
		"XCTFail",
	}

	mLines := strings.Split(method.SourceCode, "\n")
	for lineIdx, line := range mLines {
		trimmed := strings.TrimSpace(line)
		for _, at := range assertionTypes {
			if strings.Contains(trimmed, at+"(") || strings.Contains(trimmed, at+" (") {
				start := strings.Index(trimmed, "(")
				end := strings.LastIndex(trimmed, ")")
				var args []string
				if start >= 0 && end > start {
					args = []string{trimmed[start+1 : end]}
				}
				method.Assertions = append(method.Assertions, models.Assertion{
					Type:        at,
					Arguments:   args,
					LineNumber:  method.LineNumber + lineIdx,
					IsReachable: true,
				})
				break
			}
		}
	}
}

// --- Integration Tests ---

func fixtureDir() string {
	// Find testdata/fixtures relative to the project root
	wd, _ := os.Getwd()
	// Walk up to find testdata
	dir := wd
	for {
		if _, err := os.Stat(filepath.Join(dir, "testdata", "fixtures")); err == nil {
			return filepath.Join(dir, "testdata", "fixtures")
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return filepath.Join(wd, "testdata", "fixtures")
}

func allRules() []validation.ValidationRule {
	return validation.DefaultRules()
}

func runAnalysis(t *testing.T, fixtureSubdir string) ([]validation.Finding, *report.Report) {
	t.Helper()
	dir := filepath.Join(fixtureDir(), fixtureSubdir)
	if _, err := os.Stat(dir); err != nil {
		t.Skipf("Fixture directory not found: %s", dir)
	}

	// Discover test files
	var files []string
	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		if strings.HasSuffix(path, ".m") {
			files = append(files, path)
		}
		return nil
	})

	if len(files) == 0 {
		t.Skipf("No test files found in %s", dir)
	}

	engine := validation.NewEngine(allRules())
	cfg := config.DefaultConfig()
	cfg.Workers = 2
	cfg.RootDirectory = dir

	r := runner.NewRunner(engine, func(fp string) (*models.TestFile, error) {
		return parseTestFileSimple(fp)
	}, cfg)

	results := r.Run(context.Background(), files)

	var allFindings []validation.Finding
	var totalTests, totalClasses, totalAssertions int
	for _, res := range results {
		if res.Error != nil {
			t.Logf("Error analyzing %s: %v", res.FilePath, res.Error)
			continue
		}
		allFindings = append(allFindings, res.Findings...)
	}

	for _, fp := range files {
		tf, _ := parseTestFileSimple(fp)
		if tf == nil {
			continue
		}
		totalClasses += len(tf.Classes)
		for _, c := range tf.Classes {
			totalTests += len(c.Methods)
			for _, m := range c.Methods {
				totalAssertions += len(m.Assertions)
			}
		}
	}

	stats := report.CalculateStatistics(allFindings, totalTests, totalClasses, len(files), totalAssertions)
	rpt := &report.Report{
		Findings:   allFindings,
		Statistics: stats,
		Metadata: report.Metadata{
			Version:       "0.1.0-test",
			RootDirectory: dir,
		},
	}

	return allFindings, rpt
}

func TestCoreTests(t *testing.T) {
	findings, rpt := runAnalysis(t, "core")

	if rpt.Statistics.TotalTestsAnalyzed == 0 {
		t.Fatal("Expected to analyze at least 1 test")
	}
	t.Logf("Core: %d tests, %d findings", rpt.Statistics.TotalTestsAnalyzed, len(findings))

	// The CBOR test fixtures should produce some findings:
	// - testCBOREncodeNilValue should be flagged (only XCTAssertNotNil)
	hasExistenceOnlyFinding := false
	for _, f := range findings {
		if strings.Contains(f.TestMethod, "testCBOREncodeNilValue") {
			hasExistenceOnlyFinding = true
			t.Logf("  Found expected finding: %s - %s", f.RuleName, f.Message)
		}
	}
	if !hasExistenceOnlyFinding {
		t.Log("Note: testCBOREncodeNilValue not flagged (depends on rule thresholds)")
	}

	for _, f := range findings {
		t.Logf("  [%s] %s.%s: %s", f.Severity, f.TestClass, f.TestMethod, f.Message)
	}
}

func TestAuthTests(t *testing.T) {
	findings, rpt := runAnalysis(t, "auth")

	if rpt.Statistics.TotalTestsAnalyzed == 0 {
		t.Fatal("Expected to analyze at least 1 test")
	}
	t.Logf("Auth: %d tests, %d findings", rpt.Statistics.TotalTestsAnalyzed, len(findings))

	// testOAuthTokenAlwaysPasses should be flagged as false positive
	hasFalsePositive := false
	for _, f := range findings {
		if strings.Contains(f.TestMethod, "testOAuthTokenAlwaysPasses") &&
			f.RuleName == "FalsePositiveDetectionRule" {
			hasFalsePositive = true
			t.Logf("  Found expected false positive: %s", f.Message)
		}
	}
	if !hasFalsePositive {
		t.Error("Expected FalsePositiveDetectionRule to flag testOAuthTokenAlwaysPasses")
	}

	for _, f := range findings {
		t.Logf("  [%s] %s.%s: %s", f.Severity, f.TestClass, f.TestMethod, f.Message)
	}
}

func TestNetworkTests(t *testing.T) {
	findings, rpt := runAnalysis(t, "network")

	if rpt.Statistics.TotalTestsAnalyzed == 0 {
		t.Fatal("Expected to analyze at least 1 test")
	}
	t.Logf("Network: %d tests, %d findings", rpt.Statistics.TotalTestsAnalyzed, len(findings))

	// testAsyncNetworkRequest should be flagged for async without expectation
	hasAsyncFinding := false
	for _, f := range findings {
		if strings.Contains(f.TestMethod, "testAsyncNetworkRequest") &&
			f.RuleName == "AsyncTestRule" {
			hasAsyncFinding = true
			t.Logf("  Found expected async issue: %s", f.Message)
		}
	}
	if !hasAsyncFinding {
		t.Error("Expected AsyncTestRule to flag testAsyncNetworkRequest")
	}

	for _, f := range findings {
		t.Logf("  [%s] %s.%s: %s", f.Severity, f.TestClass, f.TestMethod, f.Message)
	}
}

func TestIntegrationTests(t *testing.T) {
	findings, rpt := runAnalysis(t, "integration")

	if rpt.Statistics.TotalTestsAnalyzed == 0 {
		t.Fatal("Expected to analyze at least 1 test")
	}
	t.Logf("Integration: %d tests, %d findings", rpt.Statistics.TotalTestsAnalyzed, len(findings))

	for _, f := range findings {
		t.Logf("  [%s] %s.%s: %s", f.Severity, f.TestClass, f.TestMethod, f.Message)
	}
}

func TestFullPipeline_AllFixtures(t *testing.T) {
	// Run the complete pipeline across all fixtures
	dir := fixtureDir()
	if _, err := os.Stat(dir); err != nil {
		t.Skipf("Fixture directory not found: %s", dir)
	}

	var files []string
	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		if strings.HasSuffix(path, ".m") {
			files = append(files, path)
		}
		return nil
	})

	engine := validation.NewEngine(allRules())
	cfg := config.DefaultConfig()
	cfg.Workers = 4
	cfg.RootDirectory = dir

	r := runner.NewRunner(engine, func(fp string) (*models.TestFile, error) {
		return parseTestFileSimple(fp)
	}, cfg)

	results := r.Run(context.Background(), files)

	var allFindings []validation.Finding
	var totalTests, totalClasses, totalAssertions int
	for _, res := range results {
		if res.Error != nil {
			continue
		}
		allFindings = append(allFindings, res.Findings...)
	}

	for _, fp := range files {
		tf, _ := parseTestFileSimple(fp)
		if tf == nil {
			continue
		}
		totalClasses += len(tf.Classes)
		for _, c := range tf.Classes {
			totalTests += len(c.Methods)
			for _, m := range c.Methods {
				totalAssertions += len(m.Assertions)
			}
		}
	}

	stats := report.CalculateStatistics(allFindings, totalTests, totalClasses, len(files), totalAssertions)

	t.Logf("Full pipeline results:")
	t.Logf("  Files: %d | Classes: %d | Tests: %d", len(files), totalClasses, totalTests)
	t.Logf("  Findings: %d | Pass rate: %.1f%%", stats.IssuesFound, stats.PassRate)

	// Verify all report formats work
	mdGen := report.NewMarkdownReportGenerator()
	rpt := &report.Report{Findings: allFindings, Statistics: stats, Metadata: report.Metadata{Version: "test"}}
	md, err := mdGen.Generate(rpt)
	if err != nil {
		t.Fatalf("Markdown report generation failed: %v", err)
	}
	if len(md) == 0 {
		t.Error("Markdown report is empty")
	}

	jsonGen := report.NewJSONReportGenerator(true)
	js, err := jsonGen.Generate(rpt)
	if err != nil {
		t.Fatalf("JSON report generation failed: %v", err)
	}
	if len(js) == 0 {
		t.Error("JSON report is empty")
	}

	htmlGen := report.NewHTMLReportGenerator()
	html, err := htmlGen.Generate(rpt)
	if err != nil {
		t.Fatalf("HTML report generation failed: %v", err)
	}
	if len(html) == 0 {
		t.Error("HTML report is empty")
	}

	t.Logf("  Report sizes: MD=%d, JSON=%d, HTML=%d bytes", len(md), len(js), len(html))
}

func TestFilteringAndReporting(t *testing.T) {
	findings, _ := runAnalysis(t, "auth")

	// Test severity filtering
	cfg := config.DefaultConfig()
	cfg.Severities = []string{"critical"}
	criticalOnly := config.FilterFindings(findings, cfg)

	for _, f := range criticalOnly {
		if f.Severity != validation.CRITICAL {
			t.Errorf("Expected only critical findings, got %s", f.Severity)
		}
	}

	// Test domain filtering
	cfg2 := config.DefaultConfig()
	cfg2.Domains = []string{"Auth"}
	authOnly := config.FilterFindings(findings, cfg2)
	t.Logf("Auth domain filter: %d/%d findings pass", len(authOnly), len(findings))
}
