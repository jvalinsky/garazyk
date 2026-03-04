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
	if ctx.TestClass == nil {
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

	// Check for parser keywords in name
	parserKeywords := []string{
		"parse", "decoder", "decode", "unmarshal", "read",
	}

	for _, keyword := range parserKeywords {
		if strings.Contains(nameLower, keyword) {
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

	// Check for serializer keywords in name
	serializerKeywords := []string{
		"serialize", "encoder", "encode", "marshal", "write",
	}

	for _, keyword := range serializerKeywords {
		if strings.Contains(nameLower, keyword) {
			return true
		}
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
	hasParse := strings.Contains(sourceCode, "parse") ||
		strings.Contains(sourceCode, "decode") ||
		strings.Contains(sourceCode, "unmarshal")

	hasSerialize := strings.Contains(sourceCode, "serialize") ||
		strings.Contains(sourceCode, "encode") ||
		strings.Contains(sourceCode, "marshal")

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

// extractTestSubject extracts the subject being tested from the test name
func (r *ParserSerializerRule) extractTestSubject(testName string) string {
	// Remove common test prefixes
	name := strings.TrimPrefix(testName, "test")
	name = strings.TrimPrefix(name, "Test")

	// Remove common operation keywords (case-insensitive)
	nameLower := strings.ToLower(name)
	operations := []string{
		"parser", "parse", "decoder", "decode", "unmarshal",
		"serializer", "serialize", "encoder", "encode", "marshal",
		"roundtrip", "round_trip", "bidirectional",
		"pretty", "prettyprint", "format",
		"basic", "complex", "simple",
	}

	for _, op := range operations {
		nameLower = strings.ReplaceAll(nameLower, op, "")
	}

	// Remove common suffixes
	nameLower = strings.TrimSuffix(nameLower, "test")
	nameLower = strings.TrimSuffix(nameLower, "s")

	return strings.TrimSpace(nameLower)
}
