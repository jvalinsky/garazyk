package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestCoverageGapRule_Name(t *testing.T) {
	rule := NewCoverageGapRule()
	if rule.Name() != "CoverageGapRule" {
		t.Errorf("Expected name 'CoverageGapRule', got '%s'", rule.Name())
	}
}

func TestCoverageGapRule_Severity(t *testing.T) {
	rule := NewCoverageGapRule()
	if rule.Severity() != MEDIUM {
		t.Errorf("Expected severity MEDIUM, got %v", rule.Severity())
	}
}

func TestCoverageGapRule_Description(t *testing.T) {
	rule := NewCoverageGapRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestCoverageGapRule_MultipleClaimsSingleValidation(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name             string
		testMethod       *models.TestMethod
		expectFinding    bool
		expectedSeverity Severity
	}{
		{
			name: "Test with 'And' and single assertion",
			testMethod: &models.TestMethod{
				Name:       "testOAuthTokenGenerationAndValidation",
				ClassName:  "OAuthTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 12},
				},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "Test with 'and' (lowercase) and no assertions",
			testMethod: &models.TestMethod{
				Name:       "testCreateAndDeleteUser",
				ClassName:  "UserTests",
				LineNumber: 20,
				Assertions: []models.Assertion{},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "Test with 'And' and multiple assertions",
			testMethod: &models.TestMethod{
				Name:       "testCreateAndDeleteUser",
				ClassName:  "UserTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 32},
					{Type: "XCTAssertEqual", LineNumber: 33},
				},
			},
			expectFinding: false,
		},
		{
			name: "Test without 'And'",
			testMethod: &models.TestMethod{
				Name:       "testUserCreation",
				ClassName:  "UserTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 42},
				},
			},
			expectFinding: false,
		},
		{
			name: "Substring 'and' should not count as multiple claims",
			testMethod: &models.TestMethod{
				Name:       "testRandomness",
				ClassName:  "EntropyTests",
				LineNumber: 45,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 46},
				},
			},
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestMethod: tt.testMethod,
				TestClass:  &models.TestClass{Name: tt.testMethod.ClassName},
				TestFile:   &models.TestFile{Path: "test.m"},
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Error("Expected finding but got none")
				} else {
					if findings[0].Severity != tt.expectedSeverity {
						t.Errorf("Expected severity %v, got %v", tt.expectedSeverity, findings[0].Severity)
					}
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("Expected no findings but got %d", len(findings))
				}
			}
		})
	}
}

func TestCoverageGapRule_ErrorHandlingWithoutException(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name             string
		testMethod       *models.TestMethod
		expectFinding    bool
		expectedSeverity Severity
	}{
		{
			name: "Error handling claim without exception check",
			testMethod: &models.TestMethod{
				Name:       "testErrorOnInvalidInput",
				ClassName:  "ParserTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNil", LineNumber: 12},
				},
			},
			expectFinding: false,
		},
		{
			name: "Error handling with XCTAssertThrows",
			testMethod: &models.TestMethod{
				Name:       "testRejectsInvalidInput",
				ClassName:  "ParserTests",
				LineNumber: 20,
				Assertions: []models.Assertion{
					{Type: "XCTAssertThrows", LineNumber: 22},
				},
			},
			expectFinding: false,
		},
		{
			name: "Error handling with error parameter validation",
			testMethod: &models.TestMethod{
				Name:       "testErrorOnInvalidInput",
				ClassName:  "ParserTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{
						Type:       "XCTAssertNotNil",
						Arguments:  []string{"error"},
						LineNumber: 32,
					},
				},
			},
			expectFinding: false,
		},
		{
			name: "Test with 'fail' keyword without exception check",
			testMethod: &models.TestMethod{
				Name:       "testShouldFailOnBadData",
				ClassName:  "ValidationTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertFalse", LineNumber: 42},
				},
			},
			expectFinding: false,
		},
		{
			name: "Error handling with error code assertion",
			testMethod: &models.TestMethod{
				Name:       "testRejectsMalformedRequest",
				ClassName:  "ValidationTests",
				LineNumber: 45,
				Assertions: []models.Assertion{
					{
						Type:       "XCTAssertEqual",
						Arguments:  []string{"error.code", "400"},
						LineNumber: 47,
					},
				},
			},
			expectFinding: false,
		},
		{
			name: "NoError phrasing should not imply error-path claim",
			testMethod: &models.TestMethod{
				Name:       "testPreservation_ServerBuildReturnsNoError",
				ClassName:  "ServerTests",
				LineNumber: 46,
				Assertions: []models.Assertion{},
			},
			expectFinding: false,
		},
		{
			name: "Error handling with failure decision assertion",
			testMethod: &models.TestMethod{
				Name:       "testFailsImmediatelyOn404",
				ClassName:  "RetryPolicyTests",
				LineNumber: 47,
				Assertions: []models.Assertion{
					{
						Type:       "XCTAssertEqual",
						Arguments:  []string{"result.decision", "HttpRetryDecisionFail"},
						LineNumber: 48,
					},
				},
			},
			expectFinding: false,
		},
		{
			name: "Error handling with conditional XCTFail branch",
			testMethod: &models.TestMethod{
				Name:       "testEventSizeConstraintFailsEncoding",
				ClassName:  "FirehoseTests",
				LineNumber: 49,
				Assertions: []models.Assertion{
					{Type: "XCTFail", LineNumber: 50},
				},
				SourceCode: "if (encoded == nil && error != nil) { /* pass */ } else { XCTFail(@\"expected failure\"); }",
			},
			expectFinding: false,
		},
		{
			name: "Invalidates keyword does not imply error handling claim",
			testMethod: &models.TestMethod{
				Name:       "testLogoutInvalidatesToken",
				ClassName:  "AuthTests",
				LineNumber: 48,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 49},
				},
			},
			expectFinding: false,
		},
		{
			name: "Test without error keywords",
			testMethod: &models.TestMethod{
				Name:       "testUserCreation",
				ClassName:  "UserTests",
				LineNumber: 50,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 52},
				},
			},
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestMethod: tt.testMethod,
				TestClass:  &models.TestClass{Name: tt.testMethod.ClassName},
				TestFile:   &models.TestFile{Path: "test.m"},
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Error("Expected finding but got none")
				} else {
					if findings[0].Severity != tt.expectedSeverity {
						t.Errorf("Expected severity %v, got %v", tt.expectedSeverity, findings[0].Severity)
					}
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("Expected no findings but got %d", len(findings))
				}
			}
		})
	}
}

func TestCoverageGapRule_StateTransitionWithoutChecks(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name             string
		testMethod       *models.TestMethod
		expectFinding    bool
		expectedSeverity Severity
	}{
		{
			name: "State transition with single assertion",
			testMethod: &models.TestMethod{
				Name:       "testUserRemovedFromRoom",
				ClassName:  "RoomTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 12},
				},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "State transition with no assertions",
			testMethod: &models.TestMethod{
				Name:       "testDeleteUser",
				ClassName:  "UserTests",
				LineNumber: 20,
				Assertions: []models.Assertion{},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "State transition with multiple assertions",
			testMethod: &models.TestMethod{
				Name:       "testUserKickedFromRoom",
				ClassName:  "RoomTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 32},
					{Type: "XCTAssertFalse", LineNumber: 33},
				},
			},
			expectFinding: false,
		},
		{
			name: "Test with 'update' keyword and single assertion",
			testMethod: &models.TestMethod{
				Name:       "testUpdateUserProfile",
				ClassName:  "UserTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 42},
				},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "Test without state transition keywords",
			testMethod: &models.TestMethod{
				Name:       "testUserValidation",
				ClassName:  "UserTests",
				LineNumber: 50,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 52},
				},
			},
			expectFinding: false,
		},
		{
			name: "Ambiguous block wording without block method call should not trigger",
			testMethod: &models.TestMethod{
				Name:       "testOAuthAuthorizeEndpointBlocksBadClient",
				ClassName:  "OAuthTests",
				LineNumber: 55,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", LineNumber: 56},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "handleAuthorizeRequest:", LineNumber: 57},
				},
			},
			expectFinding: false,
		},
		{
			name: "Block transition with matching method call should still trigger when under-asserted",
			testMethod: &models.TestMethod{
				Name:       "testBlockUser",
				ClassName:  "ModerationTests",
				LineNumber: 58,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 59},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "blockUser:", LineNumber: 60},
				},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestMethod: tt.testMethod,
				TestClass:  &models.TestClass{Name: tt.testMethod.ClassName},
				TestFile:   &models.TestFile{Path: "test.m"},
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Error("Expected finding but got none")
				} else {
					if findings[0].Severity != tt.expectedSeverity {
						t.Errorf("Expected severity %v, got %v", tt.expectedSeverity, findings[0].Severity)
					}
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("Expected no findings but got %d", len(findings))
				}
			}
		})
	}
}

func TestCoverageGapRule_ConcurrencyWithoutRaceTesting(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name             string
		testMethod       *models.TestMethod
		expectFinding    bool
		expectedSeverity Severity
	}{
		{
			name: "Concurrency claim without concurrent execution",
			testMethod: &models.TestMethod{
				Name:       "testConcurrentAccess",
				ClassName:  "ThreadTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 12},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "doSomething", LineNumber: 11},
				},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "Concurrency claim with dispatch queue",
			testMethod: &models.TestMethod{
				Name:       "testThreadSafety",
				ClassName:  "ThreadTests",
				LineNumber: 20,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 22},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "dispatchAsync", LineNumber: 21},
				},
			},
			expectFinding: false,
		},
		{
			name: "Concurrency claim with async method",
			testMethod: &models.TestMethod{
				Name:       "testParallelExecution",
				ClassName:  "ConcurrencyTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 32},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "executeAsync", LineNumber: 31},
				},
			},
			expectFinding: false,
		},
		{
			name: "Test without concurrency keywords",
			testMethod: &models.TestMethod{
				Name:       "testUserCreation",
				ClassName:  "UserTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 42},
				},
			},
			expectFinding: false,
		},
		{
			name: "Substring matches should not imply concurrency claims",
			testMethod: &models.TestMethod{
				Name:       "testGetRepoContentsDeltaIncludesOnlyPostSinceRecordBlocks",
				ClassName:  "RepoTests",
				LineNumber: 45,
				Assertions: []models.Assertion{
					{Type: "XCTAssertEqual", LineNumber: 46},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "loadDelta", LineNumber: 47},
				},
			},
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestMethod: tt.testMethod,
				TestClass:  &models.TestClass{Name: tt.testMethod.ClassName},
				TestFile:   &models.TestFile{Path: "test.m"},
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Error("Expected finding but got none")
				} else {
					if findings[0].Severity != tt.expectedSeverity {
						t.Errorf("Expected severity %v, got %v", tt.expectedSeverity, findings[0].Severity)
					}
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("Expected no findings but got %d", len(findings))
				}
			}
		})
	}
}

func TestCoverageGapRule_PerformanceWithoutTiming(t *testing.T) {
	rule := NewCoverageGapRule()

	tests := []struct {
		name             string
		testMethod       *models.TestMethod
		expectFinding    bool
		expectedSeverity Severity
	}{
		{
			name: "Performance claim without timing",
			testMethod: &models.TestMethod{
				Name:       "testPerformanceOfParser",
				ClassName:  "ParserTests",
				LineNumber: 10,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 12},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "parse", LineNumber: 11},
				},
			},
			expectFinding:    true,
			expectedSeverity: MEDIUM,
		},
		{
			name: "Performance claim with measure method",
			testMethod: &models.TestMethod{
				Name:       "testBenchmarkParsing",
				ClassName:  "ParserTests",
				LineNumber: 20,
				Assertions: []models.Assertion{
					{Type: "XCTAssertTrue", LineNumber: 22},
				},
				MethodCalls: []models.MethodCall{
					{Selector: "measureBlock", LineNumber: 21},
				},
			},
			expectFinding: false,
		},
		{
			name: "Performance claim with timing assertion",
			testMethod: &models.TestMethod{
				Name:       "testFastExecution",
				ClassName:  "PerformanceTests",
				LineNumber: 30,
				Assertions: []models.Assertion{
					{
						Type:       "XCTAssertLessThan",
						Arguments:  []string{"elapsedTime", "1.0"},
						LineNumber: 32,
					},
				},
			},
			expectFinding: false,
		},
		{
			name: "Test without performance keywords",
			testMethod: &models.TestMethod{
				Name:       "testUserCreation",
				ClassName:  "UserTests",
				LineNumber: 40,
				Assertions: []models.Assertion{
					{Type: "XCTAssertNotNil", LineNumber: 42},
				},
			},
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := ValidationContext{
				TestMethod: tt.testMethod,
				TestClass:  &models.TestClass{Name: tt.testMethod.ClassName},
				TestFile:   &models.TestFile{Path: "test.m"},
			}

			findings := rule.Validate(ctx)

			if tt.expectFinding {
				if len(findings) == 0 {
					t.Error("Expected finding but got none")
				} else {
					if findings[0].Severity != tt.expectedSeverity {
						t.Errorf("Expected severity %v, got %v", tt.expectedSeverity, findings[0].Severity)
					}
				}
			} else {
				if len(findings) > 0 {
					t.Errorf("Expected no findings but got %d", len(findings))
				}
			}
		})
	}
}

func TestCoverageGapRule_NoFindingsForNilMethod(t *testing.T) {
	rule := NewCoverageGapRule()

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  &models.TestClass{Name: "TestClass"},
		TestFile:   &models.TestFile{Path: "test.m"},
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for nil method, got %d", len(findings))
	}
}

func TestCoverageGapRule_MultipleGapsInSameTest(t *testing.T) {
	rule := NewCoverageGapRule()

	// Test that claims multiple things AND error handling but has no assertions
	testMethod := &models.TestMethod{
		Name:       "testCreateAndValidateWithErrorHandling",
		ClassName:  "ComplexTests",
		LineNumber: 10,
		Assertions: []models.Assertion{},
	}

	ctx := ValidationContext{
		TestMethod: testMethod,
		TestClass:  &models.TestClass{Name: testMethod.ClassName},
		TestFile:   &models.TestFile{Path: "test.m"},
	}

	findings := rule.Validate(ctx)

	// Should detect both multiple claims gap and error handling gap
	if len(findings) < 2 {
		t.Errorf("Expected at least 2 findings for test with multiple gaps, got %d", len(findings))
	}
}
