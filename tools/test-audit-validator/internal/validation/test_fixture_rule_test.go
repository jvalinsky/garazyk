package validation

import (
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestTestFixtureRule_WithFixtureAndAssertion(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testMSTWithFixture",
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

	class := &models.TestClass{Name: "MSTTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/MSTTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for test with fixture and assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for valid fixture usage, got %d: %v", len(findings), findings)
	}
}

func TestTestFixtureRule_WithoutAssertion(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testLoadFixture",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"test.json"];
			NSDictionary *data = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
			// No assertion using fixture data
		`,
		Assertions: []models.Assertion{},
	}

	class := &models.TestClass{Name: "FixtureTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/FixtureTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for fixture without assertion
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for fixture without assertion, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Message != "Test loads fixtures but does not assert against fixture data" {
		t.Errorf("Expected message about missing assertion, got: %s", finding.Message)
	}

	if finding.Severity != MEDIUM {
		t.Errorf("Expected MEDIUM severity, got %v", finding.Severity)
	}
}

func TestTestFixtureRule_NoFixture(t *testing.T) {
	rule := &TestFixtureRule{}

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

	// Should not report findings for test without fixtures
	if len(findings) != 0 {
		t.Errorf("Expected no findings for test without fixtures, got %d", len(findings))
	}
}

func TestTestFixtureRule_DirectFileLoad(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testWithDirectFileLoad",
		LineNumber: 10,
		SourceCode: `
			NSString *fixturePath = @"ATProtoPDS/Tests/fixtures/example.json";
			NSData *fixtureData = [NSData dataWithContentsOfFile:fixturePath];
			NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
			NSDictionary *actual = [parser parse:input];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "ParserTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/ParserTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for direct file load with assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for direct file load with assertion, got %d", len(findings))
	}
}

func TestTestFixtureRule_FixtureInAssertion(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testFixtureComparison",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"reference.bin"];
			NSData *generated = [encoder encode:object];
			XCTAssertEqualObjects(generated, fixtureData, @"Generated data must match fixture");
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"generated", "fixtureData", "@\"Generated data must match fixture\""}},
		},
	}

	class := &models.TestClass{Name: "EncoderTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/EncoderTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when fixture variable is in assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for fixture in assertion, got %d", len(findings))
	}
}

func TestTestFixtureRule_MultipleFixtures(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testMultipleFixtures",
		LineNumber: 10,
		SourceCode: `
			NSData *fixture1 = [self loadFixture:@"input.json"];
			NSData *fixture2 = [self loadFixture:@"output.json"];
			NSDictionary *input = [NSJSONSerialization JSONObjectWithData:fixture1 options:0 error:nil];
			NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:fixture2 options:0 error:nil];
			NSDictionary *actual = [transformer transform:input];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "TransformerTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/TransformerTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for multiple fixtures with assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for multiple fixtures with assertion, got %d", len(findings))
	}
}

func TestTestFixtureRule_FixtureWithoutDirectAssertion(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testFixtureProcessing",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"test.json"];
			NSDictionary *data = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
			[processor process:data];
			// No assertion at all
		`,
		Assertions: []models.Assertion{},
	}

	class := &models.TestClass{Name: "ProcessorTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/ProcessorTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for fixture loaded but no assertions
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for fixture without assertions, got %d", len(findings))
	}

	finding := findings[0]
	if finding.Message != "Test loads fixtures but does not assert against fixture data" {
		t.Errorf("Expected message about missing assertion, got: %s", finding.Message)
	}
}

func TestTestFixtureRule_FixtureWithExpectedVariable(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testWithExpectedVariable",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"expected.json"];
			NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
			NSDictionary *actual = [generator generate];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "GeneratorTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/GeneratorTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when fixture flows through expected variable
	if len(findings) != 0 {
		t.Errorf("Expected no findings for fixture with expected variable, got %d", len(findings))
	}
}

func TestTestFixtureRule_StringFixture(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testStringFixture",
		LineNumber: 10,
		SourceCode: `
			NSString *fixturePath = @"fixtures/template.txt";
			NSString *fixtureContent = [NSString stringWithContentsOfFile:fixturePath encoding:NSUTF8StringEncoding error:nil];
			NSString *result = [renderer render:template];
			XCTAssertEqualObjects(result, fixtureContent);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"result", "fixtureContent"}},
		},
	}

	class := &models.TestClass{Name: "RendererTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/RendererTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for string fixture with assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for string fixture with assertion, got %d", len(findings))
	}
}

func TestTestFixtureRule_CARFixture(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testCARFixture",
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

	class := &models.TestClass{Name: "CARTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/CARTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for CAR fixture with assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for CAR fixture with assertion, got %d", len(findings))
	}
}

func TestTestFixtureRule_ExtractFixturePaths(t *testing.T) {
	rule := &TestFixtureRule{}

	tests := []struct {
		name       string
		sourceCode string
		wantPaths  int
	}{
		{
			name: "loadFixture method",
			sourceCode: `
				NSData *data = [self loadFixture:@"test.json"];
			`,
			wantPaths: 1,
		},
		{
			name: "direct fixture path",
			sourceCode: `
				NSString *path = @"ATProtoPDS/Tests/fixtures/example.json";
			`,
			wantPaths: 1,
		},
		{
			name: "dataWithContentsOfFile",
			sourceCode: `
				NSData *data = [NSData dataWithContentsOfFile:@"fixtures/test.bin"];
			`,
			wantPaths: 1,
		},
		{
			name: "multiple fixtures",
			sourceCode: `
				NSData *data1 = [self loadFixture:@"input.json"];
				NSData *data2 = [self loadFixture:@"output.json"];
			`,
			wantPaths: 2,
		},
		{
			name: "no fixtures",
			sourceCode: `
				id result = [processor process:input];
			`,
			wantPaths: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			paths := rule.extractFixturePaths(tt.sourceCode)
			if len(paths) != tt.wantPaths {
				t.Errorf("extractFixturePaths() got %d paths, want %d", len(paths), tt.wantPaths)
			}
		})
	}
}

func TestTestFixtureRule_ExtractFixtureVariables(t *testing.T) {
	rule := &TestFixtureRule{}

	tests := []struct {
		name      string
		sourceCode string
		wantVars  int
	}{
		{
			name: "loadFixture assignment",
			sourceCode: `
				nsdata *fixturedata = [self loadfixture:@"test.json"];
			`,
			wantVars: 1,
		},
		{
			name: "dataWithContentsOfFile assignment",
			sourceCode: `
				nsdata *data = [nsdata datawithcontentsoffile:@"fixtures/test.bin"];
			`,
			wantVars: 1,
		},
		{
			name: "fixture in variable name",
			sourceCode: `
				nsstring *fixturepath = @"test.json";
			`,
			wantVars: 1,
		},
		{
			name: "multiple fixture variables",
			sourceCode: `
				nsdata *fixturedata = [self loadfixture:@"test.json"];
				nsstring *fixturepath = @"path.json";
			`,
			wantVars: 2,
		},
		{
			name: "no fixture variables",
			sourceCode: `
				id result = [processor process:input];
			`,
			wantVars: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			vars := rule.extractFixtureVariables(strings.ToLower(tt.sourceCode))
			if len(vars) != tt.wantVars {
				t.Errorf("extractFixtureVariables() got %d vars, want %d. Got: %v", len(vars), tt.wantVars, vars)
			}
		})
	}
}

func TestTestFixtureRule_ComplexFixtureFlow(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testComplexFixtureFlow",
		LineNumber: 10,
		SourceCode: `
			NSData *fixtureData = [self loadFixture:@"input.json"];
			NSDictionary *input = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
			id processed = [processor process:input];
			NSData *expectedData = [self loadFixture:@"expected.json"];
			NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:expectedData options:0 error:nil];
			XCTAssertEqualObjects(processed, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"processed", "expected"}},
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

	// Should not report findings for complex fixture flow with assertions
	if len(findings) != 0 {
		t.Errorf("Expected no findings for complex fixture flow, got %d", len(findings))
	}
}

func TestTestFixtureRule_FixtureInLoop(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testFixtureInLoop",
		LineNumber: 10,
		SourceCode: `
			for (NSString *fixtureName in @[@"test1.json", @"test2.json"]) {
				NSData *fixtureData = [self loadFixture:fixtureName];
				NSDictionary *data = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
				id result = [processor process:data];
				XCTAssertNotNil(result);
			}
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

	// Should not report findings for fixture used in loop with assertions
	if len(findings) != 0 {
		t.Errorf("Expected no findings for fixture in loop, got %d", len(findings))
	}
}

func TestTestFixtureRule_FixturePathWithSpaces(t *testing.T) {
	rule := &TestFixtureRule{}

	sourceCode := `
		NSData *data = [self loadFixture:@"test file with spaces.json"];
	`

	paths := rule.extractFixturePaths(sourceCode)
	if len(paths) != 1 {
		t.Fatalf("Expected 1 fixture path, got %d", len(paths))
	}

	if paths[0] != "test file with spaces.json" {
		t.Errorf("Expected 'test file with spaces.json', got '%s'", paths[0])
	}
}

func TestTestFixtureRule_NestedFixtureVariables(t *testing.T) {
	rule := &TestFixtureRule{}

	sourceCode := strings.ToLower(`
		NSData *fixtureData = [self loadFixture:@"test.json"];
		NSDictionary *fixtureDict = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
		NSArray *fixtureArray = fixtureDict[@"items"];
	`)

	vars := rule.extractFixtureVariables(sourceCode)
	
	// Should find at least the primary fixture variable
	if len(vars) == 0 {
		t.Error("Expected to find fixture variables")
	}

	// Check that fixturedata is found
	found := false
	for _, v := range vars {
		if v == "fixturedata" {
			found = true
			break
		}
	}

	if !found {
		t.Errorf("Expected to find 'fixturedata' variable, got: %v", vars)
	}
}

func TestTestFixtureRule_FixtureWithErrorHandling(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testFixtureWithErrorHandling",
		LineNumber: 10,
		SourceCode: `
			NSError *error = nil;
			NSData *fixtureData = [self loadFixture:@"test.json"];
			NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:&error];
			XCTAssertNil(error);
			XCTAssertNotNil(expected);
			id actual = [processor process:input];
			XCTAssertEqualObjects(actual, expected);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNil", Arguments: []string{"error"}},
			{Type: "XCTAssertNotNil", Arguments: []string{"expected"}},
			{Type: "XCTAssertEqualObjects", Arguments: []string{"actual", "expected"}},
		},
	}

	class := &models.TestClass{Name: "ParserTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/ParserTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when fixture data is validated through expected variable
	if len(findings) != 0 {
		t.Errorf("Expected no findings for fixture with error handling, got %d", len(findings))
	}
}

func TestTestFixtureRule_BinaryFixture(t *testing.T) {
	rule := &TestFixtureRule{}

	method := &models.TestMethod{
		Name:       "testBinaryFixture",
		LineNumber: 10,
		SourceCode: `
			NSData *referenceData = [self loadFixture:@"reference.bin"];
			NSData *generatedData = [encoder encode:object];
			XCTAssertEqualObjects(generatedData, referenceData);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqualObjects", Arguments: []string{"generatedData", "referenceData"}},
		},
	}

	class := &models.TestClass{Name: "EncoderTests"}
	file := &models.TestFile{Path: "ATProtoPDS/Tests/Core/EncoderTests.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for binary fixture with assertion
	if len(findings) != 0 {
		t.Errorf("Expected no findings for binary fixture, got %d", len(findings))
	}
}
