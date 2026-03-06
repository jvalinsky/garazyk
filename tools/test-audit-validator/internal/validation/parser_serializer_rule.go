package validation

import (
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// ParserSerializerRule validates parser and serializer tests
type ParserSerializerRule struct{}

// Name returns the rule name
func (r *ParserSerializerRule) Name() string {
	return "ParserSerializerRule"
}

// Description returns the rule description
func (r *ParserSerializerRule) Description() string {
	return "Validates that parser/serializer tests include round-trip and pretty-printer tests"
}

// Severity returns the rule severity
func (r *ParserSerializerRule) Severity() Severity {
	return MEDIUM
}

// Validate applies the rule
func (r *ParserSerializerRule) Validate(ctx ValidationContext) []Finding {
	// This rule operates at the class level to check for missing companion tests
	if ctx.TestClass == nil || ctx.TestMethod != nil {
		return nil
	}

	var findings []Finding

	// Collect parser and serializer tests
	parserTests := make(map[string]*models.TestMethod)
	serializerTests := make(map[string]*models.TestMethod)
	roundTripTests := make(map[string]*models.TestMethod)
	prettyPrinterTests := make(map[string]*models.TestMethod)

	for i := range ctx.TestClass.Methods {
		method := &ctx.TestClass.Methods[i]

		// Check for round-trip and pretty-printer tests first (they take precedence)
		if r.isRoundTripTest(method) {
			roundTripTests[r.extractTestSubject(method.Name)] = method
			continue // Don't classify as parser or serializer
		}
		if r.isPrettyPrinterTest(method) {
			prettyPrinterTests[r.extractTestSubject(method.Name)] = method
			continue
		}

		// Then check for parser and serializer tests
		if r.isParserTest(method) {
			parserTests[r.extractTestSubject(method.Name)] = method
		}
		if r.isSerializerTest(method) {
			serializerTests[r.extractTestSubject(method.Name)] = method
		}
	}

	// Check for missing round-trip tests for parsers
	for subject, parserTest := range parserTests {
		if _, hasRoundTrip := roundTripTests[subject]; !hasRoundTrip {
			findings = append(findings, Finding{
				RuleName:       r.Name(),
				Severity:       r.Severity(),
				TestMethod:     parserTest.Name,
				TestClass:      ctx.TestClass.Name,
				FilePath:       ctx.TestFile.Path,
				LineNumber:     parserTest.LineNumber,
				Message:        "Parser test exists without corresponding round-trip test",
				Recommendation: "Add a round-trip test that parses → serializes → parses to verify bidirectional correctness",
				Confidence:     0.7,
			})
		}
	}

	// Check for missing pretty-printer tests for serializers
	for subject, serializerTest := range serializerTests {
		if _, hasPrettyPrinter := prettyPrinterTests[subject]; !hasPrettyPrinter {
			findings = append(findings, Finding{
				RuleName:       r.Name(),
				Severity:       LOW,
				TestMethod:     serializerTest.Name,
				TestClass:      ctx.TestClass.Name,
				FilePath:       ctx.TestFile.Path,
				LineNumber:     serializerTest.LineNumber,
				Message:        "Serializer test exists without corresponding pretty-printer test",
				Recommendation: "Consider adding a pretty-printer test to verify human-readable output formatting",
				Confidence:     0.6,
			})
		}
	}

	return findings
}

// isParserTest checks if a test is a parser test (but not a round-trip test)
func (r *ParserSerializerRule) isParserTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)

	// Exclude round-trip tests
	if strings.Contains(nameLower, "roundtrip") || strings.Contains(nameLower, "round_trip") {
		return false
	}

	// Only match if the method or class indicates a data format context
	// "parse" and "read" are too generic on their own
	hasDataFormatContext := r.hasDataFormatContext(method)

	// Strong parser keywords — these alone indicate a parser test
	strongKeywords := []string{"decoder", "decode", "unmarshal", "deserializ"}
	for _, keyword := range strongKeywords {
		if strings.Contains(nameLower, keyword) {
			return true
		}
	}

	// Weak parser keywords — only match with data format context
	if hasDataFormatContext {
		weakKeywords := []string{"parse", "read"}
		for _, keyword := range weakKeywords {
			if strings.Contains(nameLower, keyword) {
				return true
			}
		}
	}

	return false
}

// hasDataFormatContext checks if the test method or its class is about a data format
func (r *ParserSerializerRule) hasDataFormatContext(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)
	classLower := strings.ToLower(method.ClassName)
	combined := nameLower + " " + classLower

	formatKeywords := []string{
		"json", "cbor", "xml", "protobuf", "proto", "msgpack", "yaml", "yml",
		"plist", "bson", "avro", "thrift", "dagcbor", "dag-cbor",
		"serializ", "deserializ", "marshal", "codec", "lexicon",
		"car", "cid", "tid", "nsid", "aturi", "did",
	}

	for _, kw := range formatKeywords {
		if strings.Contains(combined, kw) {
			return true
		}
	}
	return false
}

// isSerializerTest checks if a test is a serializer test (but not a round-trip test)
func (r *ParserSerializerRule) isSerializerTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)

	// Exclude round-trip tests
	if strings.Contains(nameLower, "roundtrip") || strings.Contains(nameLower, "round_trip") {
		return false
	}

	// Strong serializer keywords
	if strings.Contains(nameLower, "serialize") ||
		strings.Contains(nameLower, "encoder") ||
		strings.Contains(nameLower, "encode") {
		return true
	}

	// "marshal" but not "unmarshal"
	if strings.Contains(nameLower, "marshal") && !strings.Contains(nameLower, "unmarshal") {
		return true
	}

	// Weak keyword "write" — only with data format context
	if r.hasDataFormatContext(method) && strings.Contains(nameLower, "write") {
		return true
	}

	return false
}

// isRoundTripTest checks if a test is a round-trip test
func (r *ParserSerializerRule) isRoundTripTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for round-trip keywords in name
	if strings.Contains(nameLower, "roundtrip") ||
		strings.Contains(nameLower, "round_trip") ||
		strings.Contains(nameLower, "bidirectional") {
		return true
	}

	// Check for both parse and serialize operations
	// Use word-boundary-aware matching to avoid "unmarshal" matching "marshal"
	hasParse := strings.Contains(sourceCode, "parse") ||
		strings.Contains(sourceCode, "decode") ||
		strings.Contains(sourceCode, "unmarshal")

	// For serialize-side keywords, ensure we don't match "unmarshal" as "marshal"
	hasSerialize := strings.Contains(sourceCode, "serialize") ||
		strings.Contains(sourceCode, "encode") ||
		r.containsMarshalNotUnmarshal(sourceCode)

	return hasParse && hasSerialize
}

// isPrettyPrinterTest checks if a test is a pretty-printer test
func (r *ParserSerializerRule) isPrettyPrinterTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for pretty-printer keywords
	prettyKeywords := []string{
		"pretty", "format", "print", "display", "readable",
	}

	for _, keyword := range prettyKeywords {
		if strings.Contains(nameLower, keyword) {
			return true
		}
	}

	// Check for formatting operations in source code
	if strings.Contains(sourceCode, "prettyprint") ||
		strings.Contains(sourceCode, "format") {
		return true
	}

	return false
}

// containsMarshalNotUnmarshal checks if source contains "marshal" that is not part of "unmarshal"
func (r *ParserSerializerRule) containsMarshalNotUnmarshal(source string) bool {
	idx := 0
	for {
		pos := strings.Index(source[idx:], "marshal")
		if pos < 0 {
			return false
		}
		absPos := idx + pos
		// Check that this "marshal" is not preceded by "un"
		if absPos < 2 || source[absPos-2:absPos] != "un" {
			return true
		}
		idx = absPos + len("marshal")
		if idx >= len(source) {
			return false
		}
	}
}

// extractTestSubject extracts the subject being tested from the test name
func (r *ParserSerializerRule) extractTestSubject(testName string) string {
	// Remove common test prefixes
	name := strings.TrimPrefix(testName, "test")
	name = strings.TrimPrefix(name, "Test")

	nameLower := strings.ToLower(name)

	// Remove operation keywords from the name, keeping the subject
	// Order matters - remove longer keywords first to avoid partial matches
	operations := []string{
		"prettyprint", "roundtrip", "round_trip", "bidirectional",
		"serializer", "serialize", "deserializer", "deserialize",
		"parser", "parse", "decoder", "decode", "encoder", "encode",
		"unmarshal", "marshal", "writer", "write", "reader", "read",
		"pretty", "format", "print",
		"basic", "complex", "simple",
	}

	for _, op := range operations {
		// Remove the operation keyword but preserve what comes before/after
		nameLower = strings.ReplaceAll(nameLower, op, "")
	}

	// Remove common suffixes
	nameLower = strings.TrimSuffix(nameLower, "test")
	nameLower = strings.TrimSuffix(nameLower, "s")

	// Clean up any extra whitespace or underscores
	nameLower = strings.TrimSpace(nameLower)
	nameLower = strings.Trim(nameLower, "_")

	return nameLower
}
