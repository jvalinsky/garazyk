package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestAsyncTestRule_Name(t *testing.T) {
	rule := NewAsyncTestRule()
	if rule.Name() != "AsyncTestRule" {
		t.Errorf("Expected rule name 'AsyncTestRule', got '%s'", rule.Name())
	}
}

func TestAsyncTestRule_Severity(t *testing.T) {
	rule := NewAsyncTestRule()
	if rule.Severity() != HIGH {
		t.Errorf("Expected severity HIGH, got %v", rule.Severity())
	}
}

func TestAsyncTestRule_Description(t *testing.T) {
	rule := NewAsyncTestRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestAsyncTestRule_NilMethod(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)
	if findings != nil {
		t.Errorf("Expected nil findings for nil method, got %d", len(findings))
	}
}

func TestAsyncTestRule_NoAsyncPatterns(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:       "testSimpleSync",
			ClassName:  "SyncTests",
			SourceCode: `XCTAssertEqual(1 + 1, 2);`,
		},
		TestFile:  &models.TestFile{Path: "Tests/SyncTests.m"},
		TestClass: &models.TestClass{Name: "SyncTests"},
	}
	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for sync test, got %d", len(findings))
	}
}

func TestAsyncTestRule_MissingFulfill(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsync",
			ClassName: "AsyncTests",
			SourceCode: `
				XCTestExpectation *expectation = [self expectationWithDescription:@"callback"];
				[self waitForExpectationsWithTimeout:5 handler:nil];
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	found := false
	for _, f := range findings {
		if f.Message == "Test creates expectations but never fulfills them. The test may always pass trivially." {
			found = true
			if f.Severity != HIGH {
				t.Errorf("Expected HIGH severity, got %v", f.Severity)
			}
		}
	}
	if !found {
		t.Error("Expected finding about missing fulfill")
	}
}

func TestAsyncTestRule_MissingWait(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsync",
			ClassName: "AsyncTests",
			SourceCode: `
				XCTestExpectation *expectation = [self expectationWithDescription:@"callback"];
				[expectation fulfill];
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	found := false
	for _, f := range findings {
		if f.Message == "Test creates expectations but does not wait for them. Async assertions may not execute." {
			found = true
			if f.Severity != HIGH {
				t.Errorf("Expected HIGH severity, got %v", f.Severity)
			}
		}
	}
	if !found {
		t.Error("Expected finding about missing wait")
	}
}

func TestAsyncTestRule_TimeoutTooShort(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsync",
			ClassName: "AsyncTests",
			SourceCode: `
				XCTestExpectation *expectation = [self expectationWithDescription:@"callback"];
				[expectation fulfill];
				[self waitForExpectationsWithTimeout:0.5 handler:nil];
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	found := false
	for _, f := range findings {
		if f.Severity == MEDIUM && f.Message == "Async test timeout (0.5s) may be too short and cause flaky failures." {
			found = true
		}
	}
	if !found {
		t.Error("Expected MEDIUM finding about short timeout")
	}
}

func TestAsyncTestRule_TimeoutTooLong(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsync",
			ClassName: "AsyncTests",
			SourceCode: `
				XCTestExpectation *expectation = [self expectationWithDescription:@"callback"];
				[expectation fulfill];
				[self waitForExpectationsWithTimeout:60 handler:nil];
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	found := false
	for _, f := range findings {
		if f.Severity == LOW && f.Message == "Async test timeout (60s) is very long. Consider reducing for faster test execution." {
			found = true
		}
	}
	if !found {
		t.Error("Expected LOW finding about long timeout")
	}
}

func TestAsyncTestRule_ReasonableTimeout(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsync",
			ClassName: "AsyncTests",
			SourceCode: `
				XCTestExpectation *expectation = [self expectationWithDescription:@"callback"];
				[expectation fulfill];
				[self waitForExpectationsWithTimeout:5 handler:nil];
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for reasonable timeout, got %d: %v", len(findings), findings)
	}
}

func TestAsyncTestRule_AsyncDispatchWithoutExpectation(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsync",
			ClassName: "AsyncTests",
			SourceCode: `
				dispatch_async(dispatch_get_global_queue(0, 0), ^{
					[self doSomething];
				});
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding, got %d", len(findings))
	}
	f := findings[0]
	if f.Severity != HIGH {
		t.Errorf("Expected HIGH severity, got %v", f.Severity)
	}
	if f.Message != "Test uses asynchronous dispatch but does not use XCTestExpectation. Async callbacks may not execute before the test ends." {
		t.Errorf("Unexpected message: %s", f.Message)
	}
}

func TestAsyncTestRule_ProperAsyncTest(t *testing.T) {
	rule := NewAsyncTestRule()
	ctx := ValidationContext{
		TestMethod: &models.TestMethod{
			Name:      "testAsyncCallback",
			ClassName: "AsyncTests",
			SourceCode: `
				XCTestExpectation *expectation = [self expectationWithDescription:@"callback fired"];
				[service performAsyncOperationWithCompletion:^{
					XCTAssertTrue(YES);
					[expectation fulfill];
				}];
				[self waitForExpectationsWithTimeout:5 handler:nil];
			`,
		},
		TestFile:  &models.TestFile{Path: "Tests/AsyncTests.m"},
		TestClass: &models.TestClass{Name: "AsyncTests"},
	}
	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for proper async test, got %d: %v", len(findings), findings)
	}
}
