package validation

import (
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestParserSerializerRule_ParserWithRoundTrip(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "CBORTests",
		Methods: []models.TestMethod{
			{
				Name:       "testCBORParser",
				LineNumber: 10,
				SourceCode: `
					id object = [parser parse:data];
					XCTAssertNotNil(object);
				`,
			},
			{
				Name:       "testCBORRoundTrip",
				LineNumber: 20,
				SourceCode: `
					NSData *encoded = [serializer encode:object];
					id decoded = [parser parse:encoded];
					XCTAssertEqualObjects(decoded, object);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when round-trip test exists
	if len(findings) != 0 {
		t.Errorf("Expected no findings when round-trip test exists, got %d", len(findings))
	}
}

func TestParserSerializerRule_ParserWithoutRoundTrip(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "CBORTests",
		Methods: []models.TestMethod{
			{
				Name:       "testCBORParser",
				LineNumber: 10,
				SourceCode: `
					id object = [parser parse:data];
					XCTAssertNotNil(object);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for missing round-trip test
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for missing round-trip test, got %d", len(findings))
	}

	if findings[0].Severity != MEDIUM {
		t.Errorf("Expected MEDIUM severity, got %v", findings[0].Severity)
	}

	if findings[0].Message != "Parser test exists without corresponding round-trip test" {
		t.Errorf("Unexpected message: %s", findings[0].Message)
	}
}

func TestParserSerializerRule_SerializerWithPrettyPrinter(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "JSONTests",
		Methods: []models.TestMethod{
			{
				Name:       "testJSONSerializer",
				LineNumber: 10,
				SourceCode: `
					NSData *data = [serializer serialize:object];
					XCTAssertNotNil(data);
				`,
			},
			{
				Name:       "testJSONPrettyPrint",
				LineNumber: 20,
				SourceCode: `
					NSString *pretty = [formatter prettyPrint:object];
					XCTAssertTrue([pretty containsString:@"\n"]);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when pretty-printer test exists
	if len(findings) != 0 {
		t.Errorf("Expected no findings when pretty-printer test exists, got %d", len(findings))
	}
}

func TestParserSerializerRule_SerializerWithoutPrettyPrinter(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "JSONTests",
		Methods: []models.TestMethod{
			{
				Name:       "testJSONSerializer",
				LineNumber: 10,
				SourceCode: `
					NSData *data = [serializer serialize:object];
					XCTAssertNotNil(data);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for missing pretty-printer test
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for missing pretty-printer test, got %d", len(findings))
	}

	if findings[0].Severity != LOW {
		t.Errorf("Expected LOW severity, got %v", findings[0].Severity)
	}

	if findings[0].Message != "Serializer test exists without corresponding pretty-printer test" {
		t.Errorf("Unexpected message: %s", findings[0].Message)
	}
}

func TestParserSerializerRule_NoParserOrSerializer(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "BasicTests",
		Methods: []models.TestMethod{
			{
				Name:       "testBasicOperation",
				LineNumber: 10,
				SourceCode: `
					id result = [processor process:input];
					XCTAssertNotNil(result);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for non-parser/serializer tests
	if len(findings) != 0 {
		t.Errorf("Expected no findings for non-parser/serializer tests, got %d", len(findings))
	}
}

func TestParserSerializerRule_MultipleParserTests(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "CBORTests",
		Methods: []models.TestMethod{
			{
				Name:       "testCBORParserBasic",
				LineNumber: 10,
				SourceCode: `
					id object = [parser parse:data];
					XCTAssertNotNil(object);
				`,
			},
			{
				Name:       "testCBORParserComplex",
				LineNumber: 20,
				SourceCode: `
					id object = [parser parse:complexData];
					XCTAssertNotNil(object);
				`,
			},
			{
				Name:       "testCBORRoundTrip",
				LineNumber: 30,
				SourceCode: `
					NSData *encoded = [serializer encode:object];
					id decoded = [parser parse:encoded];
					XCTAssertEqualObjects(decoded, object);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings when round-trip test exists (covers all parser tests)
	if len(findings) != 0 {
		t.Errorf("Expected no findings when round-trip test exists, got %d", len(findings))
	}
}

func TestParserSerializerRule_DecodeEncode(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "MSTTests",
		Methods: []models.TestMethod{
			{
				Name:       "testMSTDecode",
				LineNumber: 10,
				SourceCode: `
					MST *tree = [decoder decode:data];
					XCTAssertNotNil(tree);
				`,
			},
			{
				Name:       "testMSTRoundTrip",
				LineNumber: 20,
				SourceCode: `
					NSData *encoded = [encoder encode:tree];
					MST *decoded = [decoder decode:encoded];
					XCTAssertEqualObjects(decoded, tree);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for decode/encode pattern
	if len(findings) != 0 {
		t.Errorf("Expected no findings for decode/encode pattern, got %d", len(findings))
	}
}

func TestParserSerializerRule_UnmarshalMarshal(t *testing.T) {
	rule := &ParserSerializerRule{}

	class := &models.TestClass{
		Name: "ProtobufTests",
		Methods: []models.TestMethod{
			{
				Name:       "testProtobufUnmarshal",
				LineNumber: 10,
				SourceCode: `
					Message *msg = [Message unmarshal:data];
					XCTAssertNotNil(msg);
				`,
			},
		},
	}

	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: nil,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for unmarshal without round-trip
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for unmarshal without round-trip, got %d", len(findings))
	}

	// The message should be about missing round-trip test
	if !strings.Contains(findings[0].Message, "round-trip") {
		t.Errorf("Expected message about round-trip, got: %s", findings[0].Message)
	}
}
