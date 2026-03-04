package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestInteropTestRule_WithFixtureAndComparison(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testMSTInteropCompatibility",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"mst-insert-1.json"];
			NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
			NSDictionary *actual = [mst toJSON];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "MSTInteropTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/MSTInteropTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for interop test with fixture and comparison
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid interop test, got %d", len(findings))
	}
}

func TestInteropTestRule_WithoutFixture(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testInteropCompatibility",
		LineNumber: 10,
		SourceCode: `
			NSDictionary *result = [processor process:input];
			XCTAssertNotNil(result);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"result"}},
		},
	}

	class := &models.TestClass{Name: "InteropTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/InteropTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report findings for interop test without fixture
	if len(findings) < 1 {
		t.Fatalf("Expected at least 1 finding for interop test without fixture, got %d", len(findings))
	}

	foundFixtureIssue := false
	for _, finding := range findings {
		if finding.Message == "Interop test does not load fixture files" {
			foundFixtureIssue = true
			if finding.Severity != MEDIUM {
				t.Errorf("Expected MEDIUM severity for missing fixture, got %v", finding.Severity)
			}
		}
	}

	if !foundFixtureIssue {
		t.Error("Expected finding about missing fixture")
	}
}

func TestInteropTestRule_WithoutReferenceComparison(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testInteropCompatibility",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"test.json"];
			NSDictionary *result = [processor process:fixtureData];
			XCTAssertNotNil(result);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"result"}},
		},
	}

	class := &models.TestClass{Name: "InteropTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/InteropTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for missing reference comparison
	if len(findings) < 1 {
		t.Fatalf("Expected at least 1 finding for missing reference comparison, got %d", len(findings))
	}

	foundComparisonIssue := false
	for _, finding := range findings {
		if finding.Message == "Interop test does not compare against reference implementation outputs" {
			foundComparisonIssue = true
			if finding.Severity != HIGH {
				t.Errorf("Expected HIGH severity for missing comparison, got %v", finding.Severity)
			}
		}
	}

	if !foundComparisonIssue {
		t.Error("Expected finding about missing reference comparison")
	}
}

func TestInteropTestRule_NonInteropTest(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testBasicOperation",
		LineNumber: 10,
		SourceCode: `
			id result = [processor process:input];
			XCTAssertNotNil(result);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"result"}},
		},
	}

	class := &models.TestClass{Name: "ProcessorTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/ProcessorTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for non-interop test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for non-interop test, got %d", len(findings))
	}
}

func TestInteropTestRule_CARInterop(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testCARInteropBinaryCompatibility",
		LineNumber: 10,
		SourceCode: `
			NSData *referenceCAR = [self loadFixture:@"example.car"];
			NSData *generatedCAR = [writer writeCAR:blocks];
			XCTAssertEqualObjects(generatedCAR, referenceCAR);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"generatedCAR", "referenceCAR"}},
		},
	}

	class := &models.TestClass{Name: "CARInteropTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/CARInteropTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for CAR interop test with binary comparison
	if len(findings) != 0 {
		t.Errorf("Expected no findings for CAR interop test, got %d", len(findings))
	}
}

func TestInteropTestRule_CBORCanonicalEncoding(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testCBORCanonicalEncodingInterop",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"cbor-canonical.bin"];
			NSData *encoded = [serializer encodeCanonical:object];
			XCTAssertEqualObjects(encoded, fixtureData, @"Canonical encoding must match reference");
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"encoded", "fixtureData", "@\"Canonical encoding must match reference\""}},
		},
	}

	class := &models.TestClass{Name: "CBORInteropTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/CBORInteropTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for CBOR canonical encoding interop test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for CBOR canonical encoding interop test, got %d", len(findings))
	}
}

func TestInteropTestRule_FixturePathInName(t *testing.T) {
	rule := &InteropTestRule{}

	method := &models.TestMethod{
		Name:       "testReferenceImplementationCompatibility",
		LineNumber: 10,
		SourceCode: `
			NSString *fixturePath = @"ATProtoPDS/Tests/fixtures/reference-output.json";
			NSData *expected = [NSData dataWithContentsOfFile:fixturePath];
			NSData *actual = [generator generate];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "ReferenceTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/ReferenceTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when fixture path is in source code
	if len(findings) != 0 {
		t.Errorf("Expected no findings for test with fixture path, got %d", len(findings))
	}
}
