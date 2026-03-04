package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestPropertyBasedTestRule_RoundTripProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testCBORRoundTrip",
		LineNumber: 10,
		SourceCode: `
			NSData *encoded = [serializer encode:object];
			id decoded = [serializer decode:encoded];
			XCTAssertEqualObjects(decoded, object);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"decoded", "object"}},
		},
	}

	class := &models.TestClass{Name: "CBORTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for valid round-trip test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid round-trip test, got %d", len(findings))
	}
}

func TestPropertyBasedTestRule_InvariantProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testMSTInvariant",
		LineNumber: 10,
		SourceCode: `
			[mst insertKey:key value:value];
			XCTAssertTrue([mst isBalanced]);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertTrue", Arguments: []string{"[mst isBalanced]"}},
		},
	}

	class := &models.TestClass{Name: "MSTTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for valid invariant test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid invariant test, got %d", len(findings))
	}
}

func TestPropertyBasedTestRule_IdempotenceProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testIdempotentNormalization",
		LineNumber: 10,
		SourceCode: `
			NSString *once = [normalizer normalize:input];
			NSString *twice = [normalizer normalize:once];
			XCTAssertEqualObjects(once, twice);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"once", "twice"}},
		},
	}

	class := &models.TestClass{Name: "NormalizerTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for valid idempotence test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid idempotence test, got %d", len(findings))
	}
}

func TestPropertyBasedTestRule_UnknownProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testPropertySomething",
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
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for unrecognized property pattern
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for unknown property, got %d", len(findings))
	}

	if findings[0].Severity != HIGH {
		t.Errorf("Expected HIGH severity, got %v", findings[0].Severity)
	}

	if findings[0].Message != "Property-based test does not match recognized correctness property patterns" {
		t.Errorf("Unexpected message: %s", findings[0].Message)
	}
}

func TestPropertyBasedTestRule_NotPropertyBasedTest(t *testing.T) {
	rule := &PropertyBasedTestRule{}

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
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for non-property-based test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for non-property-based test, got %d", len(findings))
	}
}

func TestPropertyBasedTestRule_MetamorphicProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testMetamorphicRelationship",
		LineNumber: 10,
		SourceCode: `
			id result1 = [processor process:input1];
			id result2 = [processor process:input2];
			XCTAssertTrue([self verifyRelationship:result1 with:result2]);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertTrue", Arguments: []string{"[self verifyRelationship:result1 with:result2]"}},
		},
	}

	class := &models.TestClass{Name: "ProcessorTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for valid metamorphic test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid metamorphic test, got %d", len(findings))
	}
}

func TestPropertyBasedTestRule_ModelBasedProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testAgainstReferenceImplementation",
		LineNumber: 10,
		SourceCode: `
			id actual = [optimized process:input];
			id expected = [reference process:input];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "OptimizedTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for valid model-based test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid model-based test, got %d", len(findings))
	}
}

func TestPropertyBasedTestRule_ErrorConditionProperty(t *testing.T) {
	rule := &PropertyBasedTestRule{}

	method := &models.TestMethod{
		Name:       "testRejectsInvalidInput",
		LineNumber: 10,
		SourceCode: `
			NSError *error = nil;
			id result = [parser parse:invalidInput error:&error];
			XCTAssertNil(result);
			XCTAssertNotNil(error);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNil", Arguments: []string{"result"}},
			{Type: "XCTAssertNotNil", Arguments: []string{"error"}},
		},
	}

	class := &models.TestClass{Name: "ParserTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for valid error condition test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid error condition test, got %d", len(findings))
	}
}
