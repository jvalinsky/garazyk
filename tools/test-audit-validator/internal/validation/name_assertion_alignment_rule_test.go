package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestNameAssertionAlignmentRule_Name(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	if rule.Name() != "NameAssertionAlignmentRule" {
		t.Errorf("Expected rule name 'NameAssertionAlignmentRule', got '%s'", rule.Name())
	}
}

func TestNameAssertionAlignmentRule_Description(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestNameAssertionAlignmentRule_Severity(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	if rule.Severity() != HIGH {
		t.Errorf("Expected HIGH severity, got %v", rule.Severity())
	}
}

func TestNameAssertionAlignmentRule_ParseTestName(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{
			name:     "Simple camelCase",
			input:    "testOAuthTokenValidation",
			expected: []string{"auth", "token", "validation"}, // "OAuth" splits to "o" + "auth", but "o" is filtered as too short
		},
		{
			name:     "testThat pattern",
			input:    "testThatInvalidTokenIsRejected",
			expected: []string{"invalid", "token", "rejected"},
		},
		{
			name:     "testShould pattern",
			input:    "testShouldRejectInvalidDID",
			expected: []string{"reject", "invalid", "did"},
		},
		{
			name:     "testWhenThen pattern",
			input:    "testWhenUserKickedThenRemoved",
			expected: []string{"user", "kicked", "removed"},
		},
		{
			name:     "Complex name",
			input:    "testJWTTokenExpirationValidation",
			expected: []string{"jwt", "token", "expiration", "validation"},
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.parseTestName(tt.input)
			// Check that all expected keywords are present (order may vary)
			for _, expected := range tt.expected {
				if !containsString(result, expected) {
					t.Errorf("Expected result to contain '%s', got %v", expected, result)
				}
			}
			// Also check we don't have unexpected extras
			if len(result) > len(tt.expected)+1 { // Allow 1 extra for flexibility
				t.Logf("Warning: got more keywords than expected: %v vs %v", result, tt.expected)
			}
		})
	}
}

func TestNameAssertionAlignmentRule_SplitCamelCase(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{
			name:     "Simple camelCase with acronym",
			input:    "OAuthToken",
			expected: []string{"o", "auth", "token"}, // "OAuth" is actually "O" + "Auth" in camelCase
		},
		{
			name:     "Multiple words with acronym",
			input:    "JWTTokenValidation",
			expected: []string{"jwt", "token", "validation"},
		},
		{
			name:     "Single word",
			input:    "Token",
			expected: []string{"token"},
		},
		{
			name:     "Lowercase",
			input:    "token",
			expected: []string{"token"},
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.splitCamelCase(tt.input)
			if !stringSlicesEqual(result, tt.expected) {
				t.Errorf("Expected %v, got %v", tt.expected, result)
			}
		})
	}
}

func TestNameAssertionAlignmentRule_ExtractAssertionSemantics(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	tests := []struct {
		name       string
		assertions []models.Assertion
		contains   []string // Keywords that should be present
	}{
		{
			name: "Token validation assertions",
			assertions: []models.Assertion{
				{
					Type:      "XCTAssertEqual",
					Arguments: []string{"token.type", "@\"Bearer\""},
				},
				{
					Type:      "XCTAssertNotNil",
					Arguments: []string{"token"},
				},
			},
			contains: []string{"equal", "token", "bearer", "not", "nil"},
		},
		{
			name: "Error handling assertions",
			assertions: []models.Assertion{
				{
					Type:      "XCTAssertThrows",
					Arguments: []string{"[parser parse:invalidInput]"},
				},
			},
			contains: []string{"throws", "error", "parser", "parse", "invalidinput"},
		},
		{
			name: "Boolean assertions",
			assertions: []models.Assertion{
				{
					Type:      "XCTAssertTrue",
					Arguments: []string{"[validator isValid]"},
				},
			},
			contains: []string{"true", "valid", "validator"},
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.extractAssertionSemantics(tt.assertions)
			for _, keyword := range tt.contains {
				if !containsString(result, keyword) {
					t.Errorf("Expected result to contain '%s', got %v", keyword, result)
				}
			}
		})
	}
}

func TestNameAssertionAlignmentRule_KeywordsMatch(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	tests := []struct {
		name     string
		keyword1 string
		keyword2 string
		expected bool
	}{
		{
			name:     "Exact match",
			keyword1: "token",
			keyword2: "token",
			expected: true,
		},
		{
			name:     "Substring match",
			keyword1: "validation",
			keyword2: "validate",
			expected: true,
		},
		{
			name:     "Synonym match - oauth/token",
			keyword1: "oauth",
			keyword2: "token",
			expected: true,
		},
		{
			name:     "Synonym match - error/fail",
			keyword1: "error",
			keyword2: "fail",
			expected: true,
		},
		{
			name:     "No match",
			keyword1: "token",
			keyword2: "database",
			expected: false,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.keywordsMatch(tt.keyword1, tt.keyword2)
			if result != tt.expected {
				t.Errorf("Expected %v, got %v for keywords '%s' and '%s'", 
					tt.expected, result, tt.keyword1, tt.keyword2)
			}
		})
	}
}

func TestNameAssertionAlignmentRule_CalculateAlignmentScore(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	tests := []struct {
		name               string
		claimedKeywords    []string
		assertionSemantics []string
		minScore           float64
		maxScore           float64
	}{
		{
			name:               "Perfect alignment",
			claimedKeywords:    []string{"oauth", "token", "validation"},
			assertionSemantics: []string{"oauth", "token", "valid", "equal", "bearer"},
			minScore:           0.7,
			maxScore:           1.0,
		},
		{
			name:     "Partial alignment",
			claimedKeywords:    []string{"oauth", "token", "validation"},
			assertionSemantics: []string{"token", "not", "nil"},
			minScore:           0.2,
			maxScore:           0.9,
		},
		{
			name:               "Poor alignment",
			claimedKeywords:    []string{"oauth", "token", "validation"},
			assertionSemantics: []string{"database", "query", "result"},
			minScore:           0.0,
			maxScore:           0.3,
		},
		{
			name:               "No claimed keywords",
			claimedKeywords:    []string{},
			assertionSemantics: []string{"token", "valid"},
			minScore:           1.0,
			maxScore:           1.0,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score := rule.calculateAlignmentScore(tt.claimedKeywords, tt.assertionSemantics)
			if score < tt.minScore || score > tt.maxScore {
				t.Errorf("Expected score between %.2f and %.2f, got %.2f", 
					tt.minScore, tt.maxScore, score)
			}
		})
	}
}

func TestNameAssertionAlignmentRule_Validate_GoodAlignment(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	method := &models.TestMethod{
		Name:       "testOAuthTokenValidation",
		ClassName:  "OAuthTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{
				Type:      "XCTAssertEqual",
				Arguments: []string{"token.type", "@\"Bearer\""},
			},
			{
				Type:      "XCTAssertNotNil",
				Arguments: []string{"token"},
			},
			{
				Type:      "XCTAssertTrue",
				Arguments: []string{"[validator validateToken:token]"},
			},
		},
	}
	
	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "OAuthTests"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}
	
	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for good alignment, got %d", len(findings))
	}
}

func TestNameAssertionAlignmentRule_Validate_PoorAlignment(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	method := &models.TestMethod{
		Name:       "testOAuthTokenValidation",
		ClassName:  "OAuthTests",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{
				Type:      "XCTAssertNotNil",
				Arguments: []string{"result"},
			},
		},
	}
	
	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "OAuthTests"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}
	
	findings := rule.Validate(ctx)
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for poor alignment, got %d", len(findings))
	}
	
	finding := findings[0]
	if finding.RuleName != "NameAssertionAlignmentRule" {
		t.Errorf("Expected rule name 'NameAssertionAlignmentRule', got '%s'", finding.RuleName)
	}
	if finding.Severity != CRITICAL && finding.Severity != HIGH {
		t.Errorf("Expected CRITICAL or HIGH severity, got %v", finding.Severity)
	}
	if finding.TestMethod != "testOAuthTokenValidation" {
		t.Errorf("Expected test method 'testOAuthTokenValidation', got '%s'", finding.TestMethod)
	}
	if finding.Confidence < 0.0 || finding.Confidence > 1.0 {
		t.Errorf("Expected confidence between 0.0 and 1.0, got %.2f", finding.Confidence)
	}
}

func TestNameAssertionAlignmentRule_Validate_NoAssertions(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	method := &models.TestMethod{
		Name:       "testOAuthTokenValidation",
		ClassName:  "OAuthTests",
		LineNumber: 10,
		Assertions: []models.Assertion{},
	}
	
	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  &models.TestClass{Name: "OAuthTests"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}
	
	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings when no assertions present, got %d", len(findings))
	}
}

func TestNameAssertionAlignmentRule_Validate_NilMethod(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  &models.TestClass{Name: "OAuthTests"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}
	
	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for nil method, got %d", len(findings))
	}
}

func TestNameAssertionAlignmentRule_DetermineSeverity(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	tests := []struct {
		name     string
		score    float64
		expected Severity
	}{
		{
			name:     "Critical - very low score",
			score:    0.2,
			expected: CRITICAL,
		},
		{
			name:     "High - low score",
			score:    0.4,
			expected: HIGH,
		},
		{
			name:     "Medium - moderate score",
			score:    0.6,
			expected: MEDIUM,
		},
		{
			name:     "Low - good score",
			score:    0.8,
			expected: LOW,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.determineSeverity(tt.score)
			if result != tt.expected {
				t.Errorf("Expected severity %v for score %.2f, got %v", 
					tt.expected, tt.score, result)
			}
		})
	}
}

func TestNameAssertionAlignmentRule_SecurityTestExample(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	// Good security test - validates rejection
	goodMethod := &models.TestMethod{
		Name:       "testShouldRejectInvalidDID",
		ClassName:  "SecurityTests",
		LineNumber: 20,
		Assertions: []models.Assertion{
			{
				Type:      "XCTAssertThrows",
				Arguments: []string{"[validator validateDID:invalidDID]"},
			},
			{
				Type:      "XCTAssertFalse",
				Arguments: []string{"[validator isValid]"},
			},
		},
	}
	
	ctx := ValidationContext{
		TestMethod: goodMethod,
		TestClass:  &models.TestClass{Name: "SecurityTests"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}
	
	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for good security test, got %d", len(findings))
	}
	
	// Bad security test - only checks non-null
	badMethod := &models.TestMethod{
		Name:       "testShouldRejectInvalidDID",
		ClassName:  "SecurityTests",
		LineNumber: 30,
		Assertions: []models.Assertion{
			{
				Type:      "XCTAssertNotNil",
				Arguments: []string{"result"},
			},
		},
	}
	
	ctx.TestMethod = badMethod
	findings = rule.Validate(ctx)
	if len(findings) == 0 {
		t.Error("Expected findings for bad security test")
	}
}

func TestNameAssertionAlignmentRule_InteropTestExample(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()
	
	// Good interop test - compares against reference
	goodMethod := &models.TestMethod{
		Name:       "testMSTInteropWithReference",
		ClassName:  "MSTInteropTests",
		LineNumber: 40,
		Assertions: []models.Assertion{
			{
				Type:      "XCTAssertEqualObjects",
				Arguments: []string{"actual", "expected"},
			},
			{
				Type:      "XCTAssertEqual",
				Arguments: []string{"[mst toJSON]", "[reference toJSON]"},
			},
		},
	}
	
	ctx := ValidationContext{
		TestMethod: goodMethod,
		TestClass:  &models.TestClass{Name: "MSTInteropTests"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}
	
	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for good interop test, got %d: %+v", len(findings), findings)
	}
}

// Helper functions

func stringSlicesEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func containsString(slice []string, str string) bool {
	for _, s := range slice {
		if s == str {
			return true
		}
	}
	return false
}
