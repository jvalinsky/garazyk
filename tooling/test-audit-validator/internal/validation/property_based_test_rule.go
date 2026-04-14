package validation

import (
	"regexp"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// PropertyType represents the type of property being tested
type PropertyType string

const (
	PropertyTypeRoundTrip    PropertyType = "round_trip"
	PropertyTypeInvariant    PropertyType = "invariant"
	PropertyTypeIdempotence  PropertyType = "idempotence"
	PropertyTypeMetamorphic  PropertyType = "metamorphic"
	PropertyTypeModelBased   PropertyType = "model_based"
	PropertyTypeConfluence   PropertyType = "confluence"
	PropertyTypeErrorCond    PropertyType = "error_condition"
	PropertyTypeUnknown      PropertyType = "unknown"
)

// PropertyBasedTestRule validates property-based tests
type PropertyBasedTestRule struct{}

// Name returns the rule name
func (r *PropertyBasedTestRule) Name() string {
	return "PropertyBasedTestRule"
}

// Description returns the rule description
func (r *PropertyBasedTestRule) Description() string {
	return "Validates that property-based tests check meaningful correctness properties"
}

// Severity returns the rule severity
func (r *PropertyBasedTestRule) Severity() Severity {
	return HIGH
}

// Validate applies the rule
func (r *PropertyBasedTestRule) Validate(ctx ValidationContext) []Finding {
	if ctx.TestMethod == nil {
		return nil
	}

	var findings []Finding

	// Check if this appears to be a property-based test
	if !r.isPropertyBasedTest(ctx.TestMethod) {
		return nil
	}

	// Detect property type
	propertyType := r.detectPropertyType(ctx.TestMethod)

	// If property type is unknown, report finding
	if propertyType == PropertyTypeUnknown {
		findings = append(findings, Finding{
			RuleName:       r.Name(),
			Severity:       r.Severity(),
			TestMethod:     ctx.TestMethod.Name,
			TestClass:      ctx.TestClass.Name,
			FilePath:       ctx.TestFile.Path,
			LineNumber:     ctx.TestMethod.LineNumber,
			Message:        "Property-based test does not match recognized correctness property patterns",
			Recommendation: "Ensure the test validates a recognized property: round-trip, invariant, idempotence, metamorphic, model-based, confluence, or error-condition",
			Confidence:     0.7,
		})
	}

	return findings
}

// isPropertyBasedTest checks if a test appears to be property-based
func (r *PropertyBasedTestRule) isPropertyBasedTest(method *models.TestMethod) bool {
	nameLower := strings.ToLower(method.Name)

	// Check for property-related keywords in name
	propertyKeywords := []string{
		"property", "roundtrip", "round_trip", "invariant",
		"idempotent", "idempotence", "metamorphic", "model",
	}

	for _, keyword := range propertyKeywords {
		if strings.Contains(nameLower, keyword) {
			return true
		}
	}

	// Check for multiple encode/decode operations
	sourceCode := strings.ToLower(method.SourceCode)
	if (strings.Contains(sourceCode, "encode") && strings.Contains(sourceCode, "decode")) ||
		(strings.Contains(sourceCode, "serialize") && strings.Contains(sourceCode, "deserialize")) ||
		(strings.Contains(sourceCode, "parse") && strings.Contains(sourceCode, "print")) {
		return true
	}

	return false
}

// detectPropertyType identifies the type of property being tested
func (r *PropertyBasedTestRule) detectPropertyType(method *models.TestMethod) PropertyType {
	sourceCode := strings.ToLower(method.SourceCode)
	nameLower := strings.ToLower(method.Name)

	// Round-trip: encode → decode → compare
	if r.isRoundTripProperty(sourceCode, nameLower) {
		return PropertyTypeRoundTrip
	}

	// Invariant: operation → check invariant
	if r.isInvariantProperty(sourceCode, nameLower) {
		return PropertyTypeInvariant
	}

	// Idempotence: f(x) = f(f(x))
	if r.isIdempotenceProperty(sourceCode, nameLower) {
		return PropertyTypeIdempotence
	}

	// Metamorphic: relationships between inputs/outputs
	if r.isMetamorphicProperty(sourceCode, nameLower) {
		return PropertyTypeMetamorphic
	}

	// Model-based: compare optimized vs reference
	if r.isModelBasedProperty(sourceCode, nameLower) {
		return PropertyTypeModelBased
	}

	// Confluence: order independence
	if r.isConfluenceProperty(sourceCode, nameLower) {
		return PropertyTypeConfluence
	}

	// Error condition: invalid inputs rejected
	if r.isErrorConditionProperty(sourceCode, nameLower) {
		return PropertyTypeErrorCond
	}

	return PropertyTypeUnknown
}

// isRoundTripProperty checks for round-trip patterns
func (r *PropertyBasedTestRule) isRoundTripProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "roundtrip") || strings.Contains(name, "round_trip") {
		return true
	}

	// Check for encode/decode pattern
	encodePattern := regexp.MustCompile(`(?i)(encode|serialize|write|marshal)`)
	decodePattern := regexp.MustCompile(`(?i)(decode|deserialize|read|unmarshal|parse)`)

	hasEncode := encodePattern.MatchString(sourceCode)
	hasDecode := decodePattern.MatchString(sourceCode)

	if hasEncode && hasDecode {
		// Check for comparison assertion
		comparePattern := regexp.MustCompile(`(?i)xctassertequal|xctassertequalobjects`)
		return comparePattern.MatchString(sourceCode)
	}

	return false
}

// isInvariantProperty checks for invariant patterns
func (r *PropertyBasedTestRule) isInvariantProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "invariant") {
		return true
	}

	// Check for invariant-related assertions
	invariantKeywords := []string{
		"isbalanced", "isvalid", "isconsistent", "issorted",
		"checkintegrity", "verify", "validate",
	}

	for _, keyword := range invariantKeywords {
		if strings.Contains(sourceCode, keyword) {
			return true
		}
	}

	return false
}

// isIdempotenceProperty checks for idempotence patterns
func (r *PropertyBasedTestRule) isIdempotenceProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "idempotent") || strings.Contains(name, "idempotence") {
		return true
	}

	// Check for repeated application pattern (once, twice)
	oncePattern := regexp.MustCompile(`(?i)\bonce\b`)
	twicePattern := regexp.MustCompile(`(?i)\btwice\b`)

	if oncePattern.MatchString(sourceCode) && twicePattern.MatchString(sourceCode) {
		return true
	}

	// Check for double application pattern
	// Note: Go regex doesn't support backreferences, so we check for repeated method names differently
	applyPattern := regexp.MustCompile(`(?i)(apply|filter|transform|normalize)`)
	matches := applyPattern.FindAllString(sourceCode, -1)
	if len(matches) >= 2 {
		return true
	}

	return false
}

// isMetamorphicProperty checks for metamorphic patterns
func (r *PropertyBasedTestRule) isMetamorphicProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "metamorphic") {
		return true
	}

	// Check for relationship testing between different inputs
	relationshipKeywords := []string{
		"relationship", "relation", "equivalent", "proportional",
	}

	for _, keyword := range relationshipKeywords {
		if strings.Contains(sourceCode, keyword) {
			return true
		}
	}

	return false
}

// isModelBasedProperty checks for model-based patterns
func (r *PropertyBasedTestRule) isModelBasedProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "model") || strings.Contains(name, "reference") {
		return true
	}

	// Check for reference implementation comparison
	referenceKeywords := []string{
		"reference", "expected", "canonical", "spec", "standard",
	}

	for _, keyword := range referenceKeywords {
		if strings.Contains(sourceCode, keyword) {
			return true
		}
	}

	return false
}

// isConfluenceProperty checks for confluence patterns
func (r *PropertyBasedTestRule) isConfluenceProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "confluence") || strings.Contains(name, "order") {
		return true
	}

	// Check for order independence testing
	orderKeywords := []string{
		"orderindependent", "commutative", "permutation",
	}

	for _, keyword := range orderKeywords {
		if strings.Contains(sourceCode, keyword) {
			return true
		}
	}

	return false
}

// isErrorConditionProperty checks for error condition patterns
func (r *PropertyBasedTestRule) isErrorConditionProperty(sourceCode, name string) bool {
	// Check name
	if strings.Contains(name, "error") || strings.Contains(name, "invalid") ||
		strings.Contains(name, "reject") || strings.Contains(name, "fail") {
		return true
	}

	// Check for error/exception assertions
	errorPattern := regexp.MustCompile(`(?i)xctassertthrows|xctassertnil|xctassertfalse.*error`)
	return errorPattern.MatchString(sourceCode)
}
