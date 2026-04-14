package validation

import "testing"

func TestSeverityString(t *testing.T) {
	tests := []struct {
		severity Severity
		expected string
	}{
		{CRITICAL, "critical"},
		{HIGH, "high"},
		{MEDIUM, "medium"},
		{LOW, "low"},
		{Severity(999), "unknown"},
	}

	for _, tt := range tests {
		t.Run(tt.expected, func(t *testing.T) {
			result := tt.severity.String()
			if result != tt.expected {
				t.Errorf("Severity.String() = %v, want %v", result, tt.expected)
			}
		})
	}
}

func TestParseSeverity(t *testing.T) {
	tests := []struct {
		input    string
		expected Severity
		valid    bool
	}{
		{"critical", CRITICAL, true},
		{"high", HIGH, true},
		{"medium", MEDIUM, true},
		{"low", LOW, true},
		{"invalid", LOW, false},
		{"", LOW, false},
		{"CRITICAL", LOW, false}, // Case sensitive
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result, valid := ParseSeverity(tt.input)
			if valid != tt.valid {
				t.Errorf("ParseSeverity(%q) valid = %v, want %v", tt.input, valid, tt.valid)
			}
			if tt.valid && result != tt.expected {
				t.Errorf("ParseSeverity(%q) = %v, want %v", tt.input, result, tt.expected)
			}
		})
	}
}

func TestSeverityOrdering(t *testing.T) {
	// Verify severity levels are ordered correctly
	if CRITICAL >= HIGH {
		t.Error("CRITICAL should be less than HIGH")
	}
	if HIGH >= MEDIUM {
		t.Error("HIGH should be less than MEDIUM")
	}
	if MEDIUM >= LOW {
		t.Error("MEDIUM should be less than LOW")
	}
}
