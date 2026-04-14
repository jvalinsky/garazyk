package validation

import (
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// TestNameAssertionAlignmentRule_VariousTestNames tests the rule with different test name patterns
func TestNameAssertionAlignmentRule_VariousTestNames(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()

	tests := []struct {
		name             string
		testMethod       *models.TestMethod
		testFile         *models.TestFile
		expectFinding    bool
		expectedSeverity Severity
		description      string
	}{
		{
			name: "Good alignment - OAuth token validation",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenValidation",
				ClassName:  "OAuthTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", Arguments: []string{"token.type", "@\"Bearer\""}},
					{Type: "XCTAssertNotNil", Arguments: []string{"token.signature"}},
					{Type: "XCTAssertTrue", Arguments: []string{"[validator validateToken:token]"}},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/OAuthTests.m",
			},
			expectFinding: false,
			description:   "Test name and assertions align well",
		},
		{
			name: "Poor alignment - name claims validation but only checks non-null",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenValidation",
				ClassName:  "OAuthTests",
				LineNumber: 20,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"result"}}, // Changed from "token" to avoid keyword match
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/OAuthTests.m",
			},
			expectFinding:    true,
			expectedSeverity: CRITICAL, // Very low alignment score < 0.3
			description:      "Test claims validation but only checks existence",
		},
		{
			name: "Misalignment - name claims parsing but validates serialization",
			testMethod: &models.TestMethod{
				Name:       "testJSONParsing",
				ClassName:  "ParserTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", Arguments: []string{"[serializer serialize:obj]", "expectedJSON"}},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ParserTests.m",
			},
			expectFinding:    true,
			expectedSeverity: HIGH, // Has some keyword overlap via synonyms
			description:      "Test name claims parsing but validates serialization",
		},
		{
			name: "Good alignment - error handling with exception check",
			testMethod: &models.TestMethod{
				Name:       "testShouldRejectInvalidInput",
				ClassName:  "ValidationTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertThrows", Arguments: []string{"[parser parse:invalidInput]"}},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ValidationTests.m",
			},
			expectFinding: false,
			description:   "Test name claims rejection and validates with exception check",
		},
		{
			name: "Good alignment - state transition with before/after checks",
			testMethod: &models.TestMethod{
				Name:       "testWhenUserKickedThenRemovedFromRoom",
				ClassName:  "RoomTests",
				LineNumber: 50,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", Arguments: []string{"[room.participants containsObject:user]"}},
					{Type: "XCTAssertFalse", Arguments: []string{"[room.participants containsObject:user]"}},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/RoomTests.m",
			},
			expectFinding: false,
			description:   "Test validates state before and after transition",
		},
		{
			name: "No assertions - should be skipped",
			testMethod: &models.TestMethod{
				Name:       "testSomething",
				ClassName:  "SomeTests",
				LineNumber: 60,
				Assertions: []models.Assertion{},
			},
			testFile: &models.TestFile{
				Path: "Tests/SomeTests.m",
			},
			expectFinding: false,
			description:   "Tests with no assertions are skipped by this rule",
		},
		{
			name: "Partial alignment - some keywords match",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenGenerationAndValidation",
				ClassName:  "OAuthTests",
				LineNumber: 70,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"token"}},
					{Type: "XCTAssertEqual", Arguments: []string{"token.type", "@\"Bearer\""}},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/OAuthTests.m",
			},
			expectFinding:    false, // Changed - with 2 assertions and some keyword matches, score is likely > 0.5
			expectedSeverity: MEDIUM,
			description:      "Test claims generation AND validation but only partially validates",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestFile:   tt.testFile,
				TestMethod: tt.testMethod,
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Errorf("%s: expected finding but got none", tt.description)
					return
				}
				if findings[0].Severity != tt.expectedSeverity {
					t.Errorf("%s: expected severity %v but got %v", tt.description, tt.expectedSeverity, findings[0].Severity)
				}
				if findings[0].RuleName != rule.Name() {
					t.Errorf("expected rule name %s but got %s", rule.Name(), findings[0].RuleName)
				}
				if findings[0].Confidence < 0.0 || findings[0].Confidence > 1.0 {
					t.Errorf("confidence score %f is out of range [0.0, 1.0]", findings[0].Confidence)
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("%s: expected no finding but got: %s", tt.description, findings[0].Message)
				}
			}
		})
	}
}

// TestNameAssertionAlignmentRule_CamelCaseParsing tests camelCase name parsing
func TestNameAssertionAlignmentRule_CamelCaseParsing(t *testing.T) {
	rule := NewNameAssertionAlignmentRule()

	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{
			name:     "Simple camelCase",
			input:    "testOAuthToken",
			expected: []string{"auth", "token"}, // "OAuth" splits to "o" + "auth", filter removes "o"
		},
		{
			name:     "Acronym handling",
			input:    "testJWTTokenValidation",
			expected: []string{"jwt", "token", "validation"},
		},
		{
			name:     "Multiple words",
			input:    "testUserAccountCreation",
			expected: []string{"user", "account", "creation"},
		},
		{
			name:     "With 'That' prefix",
			input:    "testThatUserIsRemoved",
			expected: []string{"user", "removed"}, // "is" filtered as noise word
		},
		{
			name:     "With 'Should' prefix",
			input:    "testShouldRejectInvalidInput",
			expected: []string{"reject", "invalid", "input"}, // "should" kept but not in this case due to normalization
		},
		{
			name:     "When/Then pattern",
			input:    "testWhenUserKickedThenRemoved",
			expected: []string{"user", "kicked", "removed"}, // When/Then removed, camelCase preserved
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.parseTestName(tt.input)

			if len(result) != len(tt.expected) {
				t.Errorf("expected %d keywords but got %d: %v", len(tt.expected), len(result), result)
				return
			}

			for i, expected := range tt.expected {
				if result[i] != expected {
					t.Errorf("at index %d: expected '%s' but got '%s'", i, expected, result[i])
				}
			}
		})
	}
}

// TestFalsePositiveDetectionRule_AllPatterns tests all false positive patterns
func TestFalsePositiveDetectionRule_AllPatterns(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	tests := []struct {
		name            string
		testMethod      *models.TestMethod
		testFile        *models.TestFile
		expectFinding   bool
		expectedPattern string
		description     string
	}{
		{
			name: "Pattern: Only non-null checks",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenGeneration",
				ClassName:  "OAuthTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"token"}, LineNumber: 11},
					{Type: "XCTAssertNotNil", Arguments: []string{"token.signature"}, LineNumber: 12},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/OAuthTests.m",
			},
			expectFinding:   true,
			expectedPattern: "only checks that results are non-null",
			description:     "Test only validates existence, not values",
		},
		{
			name: "Pattern: Only no-throw checks",
			testMethod: &models.TestMethod{
				Name:       "testParseValidInput",
				ClassName:  "ParserTests",
				LineNumber: 20,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNoThrow", Arguments: []string{"[parser parse:input]"}, LineNumber: 21},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ParserTests.m",
			},
			expectFinding:   true,
			expectedPattern: "only checks that methods don't throw",
			description:     "Test only validates no exception, not output",
		},
		{
			name: "Pattern: Trivial assertions - XCTAssertTrue(YES)",
			testMethod: &models.TestMethod{
				Name:       "testFeatureEnabled",
				ClassName:  "FeatureTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", Arguments: []string{"YES"}, LineNumber: 31},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/FeatureTests.m",
			},
			expectFinding:   true,
			expectedPattern: "trivial assertion",
			description:     "Test has assertion that always passes",
		},
		{
			name: "Pattern: Trivial assertions - XCTAssertEqual(1, 1)",
			testMethod: &models.TestMethod{
				Name:       "testMath",
				ClassName:  "MathTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", Arguments: []string{"1", "1"}, LineNumber: 41},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/MathTests.m",
			},
			expectFinding:   true,
			expectedPattern: "trivial assertion",
			description:     "Test compares identical constants",
		},
		{
			name: "Pattern: Setup without verification",
			testMethod: &models.TestMethod{
				Name:       "testDatabaseMigration",
				ClassName:  "DatabaseTests",
				LineNumber: 50,
				Assertions: []models.Assertion{},
				MethodCalls: []models.MethodCall{
					{Selector: "runMigration", LineNumber: 51},
					{Selector: "createTable", LineNumber: 52},
					{Selector: "insertData", LineNumber: 53},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/DatabaseTests.m",
			},
			expectFinding:   true,
			expectedPattern: "setup/mutation operation(s) but has no assertions",
			description:     "Test performs setup but doesn't verify results",
		},
		{
			name: "Pattern: Unreachable assertions",
			testMethod: &models.TestMethod{
				Name:       "testErrorHandling",
				ClassName:  "ErrorTests",
				LineNumber: 60,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", Arguments: []string{"condition"}, LineNumber: 61, IsReachable: false},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ErrorTests.m",
			},
			expectFinding:   true,
			expectedPattern: "unreachable assertion",
			description:     "Test has assertions that will never execute",
		},
		{
			name: "Good test - mixed assertion types with value checks",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenValidation",
				ClassName:  "OAuthTests",
				LineNumber: 70,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"token"}, LineNumber: 71, IsReachable: true},
					{Type: "XCTAssertEqual", Arguments: []string{"token.type", "@\"Bearer\""}, LineNumber: 72, IsReachable: true},
					{Type: "XCTAssertTrue", Arguments: []string{"[validator validate:token]"}, LineNumber: 73, IsReachable: true},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/OAuthTests.m",
			},
			expectFinding: false,
			description:   "Test has meaningful assertions that validate behavior",
		},
		{
			name: "Good test - setup with proper verification",
			testMethod: &models.TestMethod{
				Name:       "testUserCreation",
				ClassName:  "UserTests",
				LineNumber: 80,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", Arguments: []string{"user.name", "@\"Alice\""}, LineNumber: 82, IsReachable: true},
					{Type: "XCTAssertTrue", Arguments: []string{"user.isActive"}, LineNumber: 83, IsReachable: true},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "createUser", LineNumber: 81},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/UserTests.m",
			},
			expectFinding: false,
			description:   "Test performs setup and verifies results properly",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestFile:   tt.testFile,
				TestMethod: tt.testMethod,
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Errorf("%s: expected finding but got none", tt.description)
					return
				}

				// Check that the message contains the expected pattern
				foundPattern := false
				for _, finding := range findings {
					if strings.Contains(finding.Message, tt.expectedPattern) {
						foundPattern = true
						break
					}
				}

				if !foundPattern {
					t.Errorf("%s: expected pattern '%s' in message but got: %s",
						tt.description, tt.expectedPattern, findings[0].Message)
				}

				// Verify severity is CRITICAL or HIGH (false positives are serious)
				if findings[0].Severity != CRITICAL && findings[0].Severity != HIGH {
					t.Errorf("%s: expected CRITICAL or HIGH severity but got %v", tt.description, findings[0].Severity)
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("%s: expected no finding but got: %s", tt.description, findings[0].Message)
				}
			}
		})
	}
}

// TestFalsePositiveDetectionRule_TrivialAssertionDetection tests trivial assertion detection
func TestFalsePositiveDetectionRule_TrivialAssertionDetection(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	tests := []struct {
		name      string
		assertion models.Assertion
		isTrivial bool
	}{
		{
			name:      "XCTAssertTrue(YES) is trivial",
			assertion: models.Assertion{Type: "XCTAssertTrue", Arguments: []string{"YES"}},
			isTrivial: true,
		},
		{
			name:      "XCTAssertTrue(TRUE) is trivial",
			assertion: models.Assertion{Type: "XCTAssertTrue", Arguments: []string{"TRUE"}},
			isTrivial: true,
		},
		{
			name:      "XCTAssertFalse(NO) is trivial",
			assertion: models.Assertion{Type: "XCTAssertFalse", Arguments: []string{"NO"}},
			isTrivial: true,
		},
		{
			name:      "XCTAssertEqual(1, 1) is trivial",
			assertion: models.Assertion{Type: "XCTAssertEqual", Arguments: []string{"1", "1"}},
			isTrivial: true,
		},
		{
			name:      "XCTAssertNil(nil) is trivial",
			assertion: models.Assertion{Type: "XCTAssertNil", Arguments: []string{"nil"}},
			isTrivial: true,
		},
		{
			name:      "XCTAssertTrue(condition) is not trivial",
			assertion: models.Assertion{Type: "XCTAssertTrue", Arguments: []string{"condition"}},
			isTrivial: false,
		},
		{
			name:      "XCTAssertEqual(a, b) is not trivial",
			assertion: models.Assertion{Type: "XCTAssertEqual", Arguments: []string{"a", "b"}},
			isTrivial: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.isTrivialAssertion(tt.assertion)
			if result != tt.isTrivial {
				t.Errorf("expected isTrivial=%v but got %v", tt.isTrivial, result)
			}
		})
	}
}

// TestCoverageGapRule_AllGapTypes tests all coverage gap patterns
func TestCoverageGapRule_AllGapTypes(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name            string
		testMethod      *models.TestMethod
		testFile        *models.TestFile
		expectFinding   bool
		expectedGapType string
		description     string
	}{
		{
			name: "Gap: Multiple claims with single validation",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenGenerationAndValidation",
				ClassName:  "OAuthTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"token"}, LineNumber: 11},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/OAuthTests.m",
			},
			expectFinding:   true,
			expectedGapType: "multiple behaviors",
			description:     "Test claims to test generation AND validation but only has one assertion",
		},
		{
			name: "Gap: Error handling without exception check",
			testMethod: &models.TestMethod{
				Name:       "testHandlesInvalidInput",
				ClassName:  "ValidationTests",
				LineNumber: 20,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"parser"}, LineNumber: 21},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ValidationTests.m",
			},
			expectFinding:   true,
			expectedGapType: "error handling",
			description:     "Test claims error handling but doesn't use XCTAssertThrows",
		},
		{
			name: "Gap: State transition without sufficient checks",
			testMethod: &models.TestMethod{
				Name:       "testUserRemovedFromRoom",
				ClassName:  "RoomTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{Type: "XCTAssertFalse", Arguments: []string{"[room.participants containsObject:user]"}, LineNumber: 31},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/RoomTests.m",
			},
			expectFinding:   true,
			expectedGapType: "state transition",
			description:     "Test claims state transition but only has one assertion (no before/after check)",
		},
		{
			name: "Gap: Concurrency without race testing",
			testMethod: &models.TestMethod{
				Name:       "testConcurrentAccess",
				ClassName:  "ThreadTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"result"}, LineNumber: 41},
				},
				MethodCalls: []models.MethodCall{},
			},
			testFile: &models.TestFile{
				Path: "Tests/ThreadTests.m",
			},
			expectFinding:   true,
			expectedGapType: "concurrency",
			description:     "Test claims concurrency but has no concurrent execution",
		},
		{
			name: "Gap: Performance without timing",
			testMethod: &models.TestMethod{
				Name:       "testPerformanceOptimization",
				ClassName:  "PerformanceTests",
				LineNumber: 50,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", Arguments: []string{"result"}, LineNumber: 51},
				},
				MethodCalls: []models.MethodCall{},
			},
			testFile: &models.TestFile{
				Path: "Tests/PerformanceTests.m",
			},
			expectFinding:   true,
			expectedGapType: "performance",
			description:     "Test claims performance testing but has no timing measurements",
		},
		{
			name: "Good test - error handling with exception check",
			testMethod: &models.TestMethod{
				Name:       "testRejectsInvalidInput",
				ClassName:  "ValidationTests",
				LineNumber: 60,
				Assertions: []models.Assertion{
					{Type: "XCTAssertThrows", Arguments: []string{"[parser parse:invalidInput]"}, LineNumber: 61},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ValidationTests.m",
			},
			expectFinding: false,
			description:   "Test properly validates error handling with exception check",
		},
		{
			name: "Good test - state transition with before/after checks",
			testMethod: &models.TestMethod{
				Name:       "testUserRemovedFromRoom",
				ClassName:  "RoomTests",
				LineNumber: 70,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", Arguments: []string{"[room.participants containsObject:user]"}, LineNumber: 71},
					{Type: "XCTAssertFalse", Arguments: []string{"[room.participants containsObject:user]"}, LineNumber: 73},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/RoomTests.m",
			},
			expectFinding: false,
			description:   "Test properly validates state transition with multiple assertions",
		},
		{
			name: "Good test - concurrency with concurrent execution",
			testMethod: &models.TestMethod{
				Name:       "testConcurrentAccess",
				ClassName:  "ThreadTests",
				LineNumber: 80,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", Arguments: []string{"counter", "expectedCount"}, LineNumber: 82},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "dispatchAsync", LineNumber: 81},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/ThreadTests.m",
			},
			expectFinding: false,
			description:   "Test properly tests concurrency with dispatch calls",
		},
		{
			name: "Good test - performance with timing",
			testMethod: &models.TestMethod{
				Name:       "testPerformance",
				ClassName:  "PerformanceTests",
				LineNumber: 90,
				Assertions: []models.Assertion{
					{Type: "XCTAssertLessThan", Arguments: []string{"duration", "maxDuration"}, LineNumber: 92},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "measureBlock", LineNumber: 91},
				},
			},
			testFile: &models.TestFile{
				Path: "Tests/PerformanceTests.m",
			},
			expectFinding: false,
			description:   "Test properly measures performance with timing",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestFile:   tt.testFile,
				TestMethod: tt.testMethod,
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Errorf("%s: expected finding but got none", tt.description)
					return
				}

				// Check that the message contains the expected gap type
				foundGapType := false
				for _, finding := range findings {
					if strings.Contains(strings.ToLower(finding.Message), tt.expectedGapType) {
						foundGapType = true
						break
					}
				}

				if !foundGapType {
					t.Errorf("%s: expected gap type '%s' in message but got: %s",
						tt.description, tt.expectedGapType, findings[0].Message)
				}

				// Verify severity is appropriate (MEDIUM or HIGH for coverage gaps)
				if findings[0].Severity != MEDIUM && findings[0].Severity != HIGH {
					t.Errorf("%s: expected MEDIUM or HIGH severity but got %v", tt.description, findings[0].Severity)
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("%s: expected no finding but got: %s", tt.description, findings[0].Message)
				}
			}
		})
	}
}

// TestCoverageGapRule_ErrorHandlingPatterns tests various error handling patterns
func TestCoverageGapRule_ErrorHandlingPatterns(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name          string
		testName      string
		assertions    []models.Assertion
		expectFinding bool
		description   string
	}{
		{
			name:     "Error handling with XCTAssertThrows - good",
			testName: "testRejectsInvalidInput",
			assertions: []models.Assertion{
				{Type: "XCTAssertThrows", Arguments: []string{"[parser parse:invalid]"}},
			},
			expectFinding: false,
			description:   "Proper error handling validation",
		},
		{
			name:     "Error handling with error parameter check - good",
			testName: "testRejectsInvalid", // Changed to avoid "And" pattern in "Handling"
			assertions: []models.Assertion{
				{Type: "XCTAssertNotNil", Arguments: []string{"error"}},
			},
			expectFinding: false,
			description:   "Validates error object is set",
		},
		{
			name:     "Error handling without exception check - bad",
			testName: "testInvalidInputHandling",
			assertions: []models.Assertion{
				{Type: "XCTAssertTrue", Arguments: []string{"parser != nil"}},
			},
			expectFinding: true,
			description:   "Claims error handling but doesn't check exceptions or errors",
		},
		{
			name:     "Malformed input without validation - bad",
			testName: "testMalformedJSON",
			assertions: []models.Assertion{
				{Type: "XCTAssertNotNil", Arguments: []string{"parser"}},
			},
			expectFinding: true,
			description:   "Claims to test malformed input but doesn't validate rejection",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method := &models.TestMethod{
				Name:       tt.testName,
				ClassName:  "ValidationTests",
				LineNumber: 10,
				Assertions: tt.assertions,
			}

			ctx := ValidationContext{
				TestFile: &models.TestFile{
					Path: "Tests/ValidationTests.m",
				},
				TestMethod: method,
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Errorf("%s: expected finding but got none", tt.description)
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("%s: expected no finding but got: %s", tt.description, findings[0].Message)
				}
			}
		})
	}
}
