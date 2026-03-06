package validation

import "testing"

func TestFindingCreation(t *testing.T) {
	finding := Finding{
		RuleName:       "TestRule",
		Severity:       HIGH,
		TestMethod:     "testExample",
		TestClass:      "ExampleTests",
		FilePath:       "/path/to/test.m",
		LineNumber:     42,
		Message:        "Test issue found",
		Recommendation: "Fix the issue",
		Confidence:     0.85,
	}

	if finding.RuleName != "TestRule" {
		t.Errorf("RuleName = %v, want TestRule", finding.RuleName)
	}
	if finding.Severity != HIGH {
		t.Errorf("Severity = %v, want HIGH", finding.Severity)
	}
	if finding.Confidence != 0.85 {
		t.Errorf("Confidence = %v, want 0.85", finding.Confidence)
	}
}

func TestFindingConfidenceBounds(t *testing.T) {
	tests := []struct {
		name       string
		confidence float64
		valid      bool
	}{
		{"zero", 0.0, true},
		{"half", 0.5, true},
		{"one", 1.0, true},
		{"negative", -0.1, false},
		{"over_one", 1.1, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			finding := Finding{Confidence: tt.confidence}
			isValid := finding.Confidence >= 0.0 && finding.Confidence <= 1.0
			if isValid != tt.valid {
				t.Errorf("Confidence %v validity = %v, want %v", tt.confidence, isValid, tt.valid)
			}
		})
	}
}

func TestDedupeFindings(t *testing.T) {
	input := []Finding{
		{
			RuleName:   "ParserSerializerRule",
			FilePath:   "a.m",
			TestClass:  "A",
			TestMethod: "testOne",
			LineNumber: 10,
			Message:    "missing round-trip",
			Confidence: 0.7,
		},
		{
			RuleName:   "ParserSerializerRule",
			FilePath:   "a.m",
			TestClass:  "A",
			TestMethod: "testOne",
			LineNumber: 10,
			Message:    "missing round-trip",
			Confidence: 0.9, // differs but same dedupe key
		},
		{
			RuleName:   "CoverageGapRule",
			FilePath:   "a.m",
			TestClass:  "A",
			TestMethod: "testTwo",
			LineNumber: 20,
			Message:    "insufficient assertions",
		},
	}

	got := DedupeFindings(input)
	if len(got) != 2 {
		t.Fatalf("expected 2 findings after dedupe, got %d", len(got))
	}

	if got[0].RuleName != "ParserSerializerRule" || got[0].TestMethod != "testOne" {
		t.Fatalf("expected first finding to preserve original order, got %+v", got[0])
	}
	if got[1].RuleName != "CoverageGapRule" || got[1].TestMethod != "testTwo" {
		t.Fatalf("expected second finding to be CoverageGapRule, got %+v", got[1])
	}
}
