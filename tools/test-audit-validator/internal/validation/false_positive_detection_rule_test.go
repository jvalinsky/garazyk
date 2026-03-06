package validation

import (
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestFalsePositiveDetectionRule_Name(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()
	if rule.Name() != "FalsePositiveDetectionRule" {
		t.Errorf("Expected rule name 'FalsePositiveDetectionRule', got '%s'", rule.Name())
	}
}

func TestFalsePositiveDetectionRule_Severity(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()
	if rule.Severity() != CRITICAL {
		t.Errorf("Expected severity CRITICAL, got %v", rule.Severity())
	}
}

func TestFalsePositiveDetectionRule_Description(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestFalsePositiveDetectionRule_OnlyNonNullChecks(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with only XCTAssertNotNil assertions
	method := &models.TestMethod{
		Name:       "testOAuthTokenGeneration",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"token"}, LineNumber: 12, IsReachable: true},
			{Type: "XCTAssertNotNil", Arguments: []string{"token.value"}, LineNumber: 13, IsReachable: true},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Severity != CRITICAL {
		t.Errorf("Expected CRITICAL severity, got %v", finding.Severity)
	}
	if finding.Confidence < 0.9 {
		t.Errorf("Expected high confidence (>0.9), got %.2f", finding.Confidence)
	}
}

func TestFalsePositiveDetectionRule_OnlyNonNullChecks_WithOtherAssertions(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with mixed assertions (should not trigger)
	method := &models.TestMethod{
		Name:       "testOAuthTokenGeneration",
		ClassName:  "TestClass",
		LineNumber: 10,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"token"}, LineNumber: 12, IsReachable: true},
			{Type: "XCTAssertEqual", Arguments: []string{"token.type", "@\"Bearer\""}, LineNumber: 13, IsReachable: true},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	// Should not find only-non-null-checks pattern
	for _, finding := range findings {
		if finding.Message != "" && finding.Message[:20] == "Test 'testOAuthToken" {
			if finding.Message[len(finding.Message)-50:] == "only checks that results are non-null" {
				t.Error("Should not detect only-non-null-checks when other assertions present")
			}
		}
	}
}

func TestFalsePositiveDetectionRule_OnlyNoThrowChecks(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with only XCTAssertNoThrow assertions
	method := &models.TestMethod{
		Name:       "testParseValidInput",
		ClassName:  "TestClass",
		LineNumber: 20,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNoThrow", Arguments: []string{"[parser parse:input]"}, LineNumber: 22, IsReachable: true},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Severity != CRITICAL {
		t.Errorf("Expected CRITICAL severity, got %v", finding.Severity)
	}
	if finding.Confidence < 0.9 {
		t.Errorf("Expected high confidence (>0.9), got %.2f", finding.Confidence)
	}
}

func TestFalsePositiveDetectionRule_TrivialAssertions(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	tests := []struct {
		name       string
		assertions []models.Assertion
		shouldFind bool
	}{
		{
			name: "XCTAssertTrue(YES)",
			assertions: []models.Assertion{
				{Type: "XCTAssertTrue", Arguments: []string{"YES"}, LineNumber: 10, IsReachable: true},
			},
			shouldFind: true,
		},
		{
			name: "XCTAssertFalse(NO)",
			assertions: []models.Assertion{
				{Type: "XCTAssertFalse", Arguments: []string{"NO"}, LineNumber: 10, IsReachable: true},
			},
			shouldFind: true,
		},
		{
			name: "XCTAssertEqual(1, 1)",
			assertions: []models.Assertion{
				{Type: "XCTAssertEqual", Arguments: []string{"1", "1"}, LineNumber: 10, IsReachable: true},
			},
			shouldFind: true,
		},
		{
			name: "XCTAssertTrue(true)",
			assertions: []models.Assertion{
				{Type: "XCTAssertTrue", Arguments: []string{"true"}, LineNumber: 10, IsReachable: true},
			},
			shouldFind: true,
		},
		{
			name: "Non-trivial assertion",
			assertions: []models.Assertion{
				{Type: "XCTAssertTrue", Arguments: []string{"[result isValid]"}, LineNumber: 10, IsReachable: true},
			},
			shouldFind: false,
		},
		{
			name: "Mixed trivial and non-trivial (50/50)",
			assertions: []models.Assertion{
				{Type: "XCTAssertTrue", Arguments: []string{"YES"}, LineNumber: 10, IsReachable: true},
				{Type: "XCTAssertTrue", Arguments: []string{"[result isValid]"}, LineNumber: 11, IsReachable: true},
			},
			shouldFind: false, // Only 50% trivial, threshold is >50%
		},
		{
			name: "Mostly trivial (2 out of 3)",
			assertions: []models.Assertion{
				{Type: "XCTAssertTrue", Arguments: []string{"YES"}, LineNumber: 10, IsReachable: true},
				{Type: "XCTAssertFalse", Arguments: []string{"NO"}, LineNumber: 11, IsReachable: true},
				{Type: "XCTAssertTrue", Arguments: []string{"[result isValid]"}, LineNumber: 12, IsReachable: true},
			},
			shouldFind: true, // >50% trivial
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method := &models.TestMethod{
				Name:       "testFeature",
				ClassName:  "TestClass",
				LineNumber: 5,
				Assertions: tt.assertions,
			}

			ctx := ValidationContext{
				TestMethod: method,
				TestClass:  testClass,
				TestFile:   testFile,
			}

			findings := rule.Validate(ctx)

			foundTrivial := false
			for _, finding := range findings {
				if finding.Message != "" && (finding.Message[:len("Test 'testFeature' contains")] == "Test 'testFeature' contains") {
					foundTrivial = true
					break
				}
			}

			if foundTrivial != tt.shouldFind {
				t.Errorf("Expected shouldFind=%v, got foundTrivial=%v", tt.shouldFind, foundTrivial)
			}
		})
	}
}

func TestFalsePositiveDetectionRule_SetupWithoutVerification_NoAssertions(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with setup calls but no assertions (need at least 2 setup calls)
	method := &models.TestMethod{
		Name:       "testDatabaseMigration",
		ClassName:  "TestClass",
		LineNumber: 30,
		Assertions: []models.Assertion{},
		MethodCalls: []models.MethodCall{
			{Receiver: "db", Selector: "runMigration", LineNumber: 32},
			{Receiver: "db", Selector: "insertRecord:", LineNumber: 33},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Severity != HIGH {
		t.Errorf("Expected HIGH severity, got %v", finding.Severity)
	}
}

func TestFalsePositiveDetectionRule_SetupWithoutVerification_WeakAssertions(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with many setup calls but only weak assertions (need 3+ setup calls)
	method := &models.TestMethod{
		Name:       "testComplexSetup",
		ClassName:  "TestClass",
		LineNumber: 40,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"result"}, LineNumber: 45, IsReachable: true},
		},
		MethodCalls: []models.MethodCall{
			{Receiver: "obj", Selector: "setProperty:", LineNumber: 41},
			{Receiver: "obj", Selector: "addItem:", LineNumber: 42},
			{Receiver: "obj", Selector: "configure", LineNumber: 43},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	// Should find 2 findings: only-non-null-checks AND setup-without-verification
	if len(findings) != 2 {
		t.Fatalf("Expected 2 findings (only-non-null + setup-weak-assertions), got %d", len(findings))
	}

	// Verify we have both types of findings
	foundOnlyNonNull := false
	foundSetupWeak := false

	for _, finding := range findings {
		if strings.Contains(finding.Message, "only checks that results are non-null") {
			foundOnlyNonNull = true
		}
		if strings.Contains(finding.Message, "setup operations but only has weak assertions") {
			foundSetupWeak = true
		}
	}

	if !foundOnlyNonNull {
		t.Error("Expected to find only-non-null-checks finding")
	}
	if !foundSetupWeak {
		t.Error("Expected to find setup-with-weak-assertions finding")
	}
}

func TestFalsePositiveDetectionRule_SetupWithoutVerification_GoodTest(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with setup calls and strong assertions (should not trigger)
	method := &models.TestMethod{
		Name:       "testProperVerification",
		ClassName:  "TestClass",
		LineNumber: 50,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", Arguments: []string{"obj.property", "expectedValue"}, LineNumber: 53, IsReachable: true},
			{Type: "XCTAssertTrue", Arguments: []string{"[obj isConfigured]"}, LineNumber: 54, IsReachable: true},
		},
		MethodCalls: []models.MethodCall{
			{Receiver: "obj", Selector: "setProperty:", LineNumber: 51},
			{Receiver: "obj", Selector: "configure", LineNumber: 52},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	// Should not find setup-without-verification pattern
	for _, finding := range findings {
		if finding.Severity == HIGH && finding.Message != "" {
			t.Errorf("Should not detect setup-without-verification for test with strong assertions")
		}
	}
}

func TestFalsePositiveDetectionRule_SetupWithoutVerification_DelegatedVerificationHelper(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:       "testPreservation_EndpointsAreRegistered",
			ClassName:  "BuilderTests",
			LineNumber: 10,
			Assertions: []models.Assertion{},
			MethodCalls: []models.MethodCall{
				{Receiver: "builder", Selector: "setEnableOAuth:", LineNumber: 11},
				{Receiver: "builder", Selector: "buildWithError:", LineNumber: 12},
				{Receiver: "self", Selector: "verifyEndpointIsRegistered:expectation:", LineNumber: 13},
			},
		},
		TestClass: &models.TestClass{Name: "BuilderTests"},
		TestFile:  &models.TestFile{Path: "builder_test.m"},
	}

	findings := rule.Validate(ctx)
	for _, finding := range findings {
		if finding.Severity == HIGH && strings.Contains(finding.Message, "has no assertions") {
			t.Fatalf("did not expect setup-without-verification finding when helper verification is delegated: %+v", finding)
		}
	}
}

func TestFalsePositiveDetectionRule_SetupWithoutVerification_PerformanceMeasurement(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:       "testComponentFilteringPerformance",
			ClassName:  "LoggerPerfTests",
			LineNumber: 20,
			Assertions: []models.Assertion{},
			MethodCalls: []models.MethodCall{
				{Receiver: "logger", Selector: "setLogLevel:", LineNumber: 21},
				{Receiver: "self", Selector: "measureBlock:", LineNumber: 22},
			},
			SourceCode: "[self measureBlock:^{ /* benchmark */ }];",
		},
		TestClass: &models.TestClass{Name: "LoggerPerfTests"},
		TestFile:  &models.TestFile{Path: "perf_test.m"},
	}

	findings := rule.Validate(ctx)
	for _, finding := range findings {
		if finding.Severity == HIGH && strings.Contains(finding.Message, "has no assertions") {
			t.Fatalf("did not expect setup-without-verification finding for performance measurement test: %+v", finding)
		}
	}
}

func TestFalsePositiveDetectionRule_SetupWithoutVerification_ExpectationDrivenAsync(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:       "testConcurrentAccess",
			ClassName:  "RouteTrieTests",
			LineNumber: 30,
			Assertions: []models.Assertion{},
			MethodCalls: []models.MethodCall{
				{Receiver: "self", Selector: "expectationWithDescription:", LineNumber: 31},
				{Receiver: "queue", Selector: "dispatch_async", LineNumber: 32},
				{Receiver: "self", Selector: "waitForExpectationsWithTimeout:handler:", LineNumber: 33},
			},
			SourceCode: "XCTestExpectation *e = [self expectationWithDescription:@\"x\"]; [self waitForExpectationsWithTimeout:5 handler:nil];",
		},
		TestClass: &models.TestClass{Name: "RouteTrieTests"},
		TestFile:  &models.TestFile{Path: "concurrency_test.m"},
	}

	findings := rule.Validate(ctx)
	for _, finding := range findings {
		if finding.Severity == HIGH && strings.Contains(finding.Message, "has no assertions") {
			t.Fatalf("did not expect setup-without-verification finding for expectation-driven async test: %+v", finding)
		}
	}
}

func TestFalsePositiveDetectionRule_UnreachableAssertions(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with unreachable assertions
	method := &models.TestMethod{
		Name:       "testErrorHandling",
		ClassName:  "TestClass",
		LineNumber: 60,
		Assertions: []models.Assertion{
			{Type: "XCTAssertTrue", Arguments: []string{"condition"}, LineNumber: 62, IsReachable: false},
			{Type: "XCTAssertEqual", Arguments: []string{"a", "b"}, LineNumber: 63, IsReachable: false},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Severity != CRITICAL {
		t.Errorf("Expected CRITICAL severity, got %v", finding.Severity)
	}
	if finding.Confidence != 1.0 {
		t.Errorf("Expected confidence 1.0 for unreachable code, got %.2f", finding.Confidence)
	}
}

func TestFalsePositiveDetectionRule_UnreachableAssertions_AllReachable(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with all reachable assertions (should not trigger)
	method := &models.TestMethod{
		Name:       "testNormalFlow",
		ClassName:  "TestClass",
		LineNumber: 70,
		Assertions: []models.Assertion{
			{Type: "XCTAssertTrue", Arguments: []string{"condition"}, LineNumber: 72, IsReachable: true},
			{Type: "XCTAssertEqual", Arguments: []string{"a", "b"}, LineNumber: 73, IsReachable: true},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	// Should not find unreachable assertions
	for _, finding := range findings {
		if finding.Message != "" && finding.Message[:len("Test 'testNormalFlow' has")] == "Test 'testNormalFlow' has" {
			t.Error("Should not detect unreachable assertions when all are reachable")
		}
	}
}

func TestFalsePositiveDetectionRule_NoAssertions(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with no assertions (should be caught by other rules, not this one)
	method := &models.TestMethod{
		Name:       "testEmpty",
		ClassName:  "TestClass",
		LineNumber: 80,
		Assertions: []models.Assertion{},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected 0 findings for test with no assertions, got %d", len(findings))
	}
}

func TestFalsePositiveDetectionRule_MultiplePatterns(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test that can trigger multiple patterns (trivial + unreachable)
	method := &models.TestMethod{
		Name:       "testBadTest",
		ClassName:  "TestClass",
		LineNumber: 90,
		Assertions: []models.Assertion{
			{Type: "XCTAssertTrue", Arguments: []string{"YES"}, LineNumber: 92, IsReachable: true},
			{Type: "XCTAssertTrue", Arguments: []string{"condition"}, LineNumber: 93, IsReachable: false},
		},
	}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	// Should find both trivial assertions and unreachable assertions
	// Note: With 50% trivial (1 out of 2), trivial check won't trigger (needs >50%)
	// So we should only get unreachable assertion finding
	if len(findings) < 1 {
		t.Errorf("Expected at least 1 finding (unreachable), got %d", len(findings))
	}

	// Verify we got the unreachable assertion finding
	foundUnreachable := false
	for _, finding := range findings {
		if strings.Contains(finding.Message, "unreachable") {
			foundUnreachable = true
		}
	}

	if !foundUnreachable {
		t.Error("Expected to find unreachable assertion finding")
	}
}

func TestFalsePositiveDetectionRule_NilContext(t *testing.T) {
	rule := NewFalsePositiveDetectionRule()

	testFile := &models.TestFile{
		Path: "test.m",
	}

	testClass := &models.TestClass{
		Name: "TestClass",
	}

	// Test with nil method (class-level or file-level validation)
	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  testClass,
		TestFile:   testFile,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected 0 findings for nil method context, got %d", len(findings))
	}
}
