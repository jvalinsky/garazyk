package report

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/validation"
)

func makeFindings() []validation.Finding {
	return []validation.Finding{
		{RuleName: "rule-a", Severity: validation.CRITICAL, TestMethod: "testAuth", TestClass: "AuthTests", FilePath: "Auth/test_auth.m", LineNumber: 10, Message: "critical issue", Confidence: 0.9},
		{RuleName: "rule-b", Severity: validation.HIGH, TestMethod: "testNetwork", TestClass: "NetworkTests", FilePath: "Network/test_net.m", LineNumber: 20, Message: "high issue", Confidence: 0.8},
		{RuleName: "rule-a", Severity: validation.MEDIUM, TestMethod: "testCore", TestClass: "CoreTests", FilePath: "Core/test_core.m", LineNumber: 30, Message: "medium issue", Confidence: 0.7},
		{RuleName: "rule-c", Severity: validation.LOW, TestMethod: "testMisc", TestClass: "MiscTests", FilePath: "misc/test_misc.m", LineNumber: 40, Message: "low issue", Confidence: 0.5},
	}
}

func TestCalculateStatistics_Basic(t *testing.T) {
	findings := makeFindings()
	stats := CalculateStatistics(findings, 10, 4, 4, 30)

	if stats.TotalTestsAnalyzed != 10 {
		t.Errorf("TotalTestsAnalyzed = %d, want 10", stats.TotalTestsAnalyzed)
	}
	if stats.TotalClassesAnalyzed != 4 {
		t.Errorf("TotalClassesAnalyzed = %d, want 4", stats.TotalClassesAnalyzed)
	}
	if stats.TotalFilesAnalyzed != 4 {
		t.Errorf("TotalFilesAnalyzed = %d, want 4", stats.TotalFilesAnalyzed)
	}
	if stats.IssuesFound != 4 {
		t.Errorf("IssuesFound = %d, want 4", stats.IssuesFound)
	}
	if stats.IssuesBySeverity["critical"] != 1 {
		t.Errorf("IssuesBySeverity[critical] = %d, want 1", stats.IssuesBySeverity["critical"])
	}
	if stats.IssuesBySeverity["high"] != 1 {
		t.Errorf("IssuesBySeverity[high] = %d, want 1", stats.IssuesBySeverity["high"])
	}
	if stats.AssertionDensity != 3.0 {
		t.Errorf("AssertionDensity = %f, want 3.0", stats.AssertionDensity)
	}
}

func TestCalculateStatistics_NoFindings(t *testing.T) {
	stats := CalculateStatistics(nil, 5, 2, 2, 15)

	if stats.IssuesFound != 0 {
		t.Errorf("IssuesFound = %d, want 0", stats.IssuesFound)
	}
	if len(stats.IssuesBySeverity) != 0 {
		t.Errorf("IssuesBySeverity should be empty, got %v", stats.IssuesBySeverity)
	}
	if stats.PassRate != 100.0 {
		t.Errorf("PassRate = %f, want 100.0", stats.PassRate)
	}
	if stats.AssertionDensity != 3.0 {
		t.Errorf("AssertionDensity = %f, want 3.0", stats.AssertionDensity)
	}
}

func TestCalculateStatistics_AllCritical(t *testing.T) {
	findings := []validation.Finding{
		{Severity: validation.CRITICAL, TestMethod: "testA", TestClass: "ClassA"},
		{Severity: validation.CRITICAL, TestMethod: "testB", TestClass: "ClassB"},
		{Severity: validation.CRITICAL, TestMethod: "testC", TestClass: "ClassC"},
	}
	stats := CalculateStatistics(findings, 3, 3, 1, 0)

	if stats.PassRate != 0.0 {
		t.Errorf("PassRate = %f, want 0.0", stats.PassRate)
	}
	if stats.IssuesBySeverity["critical"] != 3 {
		t.Errorf("IssuesBySeverity[critical] = %d, want 3", stats.IssuesBySeverity["critical"])
	}
}

func TestCalculateStatistics_PassRate(t *testing.T) {
	// 2 unique critical/high test methods out of 10 total tests => 80% pass rate
	findings := []validation.Finding{
		{Severity: validation.CRITICAL, TestMethod: "testA", TestClass: "ClassA"},
		{Severity: validation.HIGH, TestMethod: "testB", TestClass: "ClassB"},
		{Severity: validation.MEDIUM, TestMethod: "testC", TestClass: "ClassC"},
		// Duplicate critical for testA - should not double-count
		{Severity: validation.CRITICAL, TestMethod: "testA", TestClass: "ClassA"},
	}
	stats := CalculateStatistics(findings, 10, 3, 2, 20)

	if stats.PassRate != 80.0 {
		t.Errorf("PassRate = %f, want 80.0", stats.PassRate)
	}
}

func TestCalculateStatistics_DomainCoverage(t *testing.T) {
	findings := []validation.Finding{
		{FilePath: "project/Tests/Auth/test_login.m"},
		{FilePath: "project/Tests/Auth/test_session.m"},
		{FilePath: "project/Tests/Core/test_core.m"},
		{FilePath: "project/Tests/Network/test_api.m"},
		{FilePath: "project/Tests/test_other.m"},
	}
	stats := CalculateStatistics(findings, 5, 5, 5, 10)

	if stats.DomainCoverage["Auth"] != 2 {
		t.Errorf("DomainCoverage[Auth] = %d, want 2", stats.DomainCoverage["Auth"])
	}
	if stats.DomainCoverage["Core"] != 1 {
		t.Errorf("DomainCoverage[Core] = %d, want 1", stats.DomainCoverage["Core"])
	}
	if stats.DomainCoverage["Network"] != 1 {
		t.Errorf("DomainCoverage[Network] = %d, want 1", stats.DomainCoverage["Network"])
	}
	if stats.DomainCoverage["test_other"] != 1 {
		t.Errorf("DomainCoverage[test_other] = %d, want 1", stats.DomainCoverage["test_other"])
	}
}

func TestGroupFindingsBySeverity(t *testing.T) {
	findings := makeFindings()
	groups := GroupFindingsBySeverity(findings)

	if len(groups["critical"]) != 1 {
		t.Errorf("critical count = %d, want 1", len(groups["critical"]))
	}
	if len(groups["high"]) != 1 {
		t.Errorf("high count = %d, want 1", len(groups["high"]))
	}
	if len(groups["medium"]) != 1 {
		t.Errorf("medium count = %d, want 1", len(groups["medium"]))
	}
	if len(groups["low"]) != 1 {
		t.Errorf("low count = %d, want 1", len(groups["low"]))
	}
}

func TestGroupFindingsByRule(t *testing.T) {
	findings := makeFindings()
	groups := GroupFindingsByRule(findings)

	if len(groups["rule-a"]) != 2 {
		t.Errorf("rule-a count = %d, want 2", len(groups["rule-a"]))
	}
	if len(groups["rule-b"]) != 1 {
		t.Errorf("rule-b count = %d, want 1", len(groups["rule-b"]))
	}
	if len(groups["rule-c"]) != 1 {
		t.Errorf("rule-c count = %d, want 1", len(groups["rule-c"]))
	}
}

func TestGroupFindingsByFile(t *testing.T) {
	findings := makeFindings()
	groups := GroupFindingsByFile(findings)

	if len(groups) != 4 {
		t.Errorf("number of file groups = %d, want 4", len(groups))
	}
	if len(groups["Auth/test_auth.m"]) != 1 {
		t.Errorf("Auth/test_auth.m count = %d, want 1", len(groups["Auth/test_auth.m"]))
	}
	if len(groups["Network/test_net.m"]) != 1 {
		t.Errorf("Network/test_net.m count = %d, want 1", len(groups["Network/test_net.m"]))
	}
}
