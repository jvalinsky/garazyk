package validation

import (
	"fmt"
	"strings"
	"unicode"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// NameAssertionAlignmentRule validates that test assertions match what the test name claims to test
type NameAssertionAlignmentRule struct{}

// NewNameAssertionAlignmentRule creates a new instance of the rule
func NewNameAssertionAlignmentRule() *NameAssertionAlignmentRule {
	return &NameAssertionAlignmentRule{}
}

// Name returns the unique name of this rule
func (r *NameAssertionAlignmentRule) Name() string {
	return "NameAssertionAlignmentRule"
}

// Severity returns the severity level for findings from this rule
func (r *NameAssertionAlignmentRule) Severity() Severity {
	return HIGH // Default severity, adjusted based on alignment score
}

// Description returns a human-readable description of what this rule validates
func (r *NameAssertionAlignmentRule) Description() string {
	return "Validates that test assertions match what the test name claims to test"
}

// Validate applies the rule to the given context and returns findings
func (r *NameAssertionAlignmentRule) Validate(ctx ValidationContext) []Finding {
	// Only validate at method level
	if ctx.TestMethod == nil {
		return nil
	}

	method := ctx.TestMethod

	// Skip if no assertions (will be caught by other rules)
	if len(method.Assertions) == 0 {
		return nil
	}

	// Skip tests with enough assertions — they're likely substantive
	// regardless of name-assertion keyword overlap
	if len(method.Assertions) >= 3 {
		return nil
	}

	// Parse test name to extract claimed functionality
	claimedKeywords := r.parseTestName(method.Name)
	if len(claimedKeywords) == 0 {
		return nil // Can't validate if we can't extract meaning from name
	}

	// Extract semantic meaning from assertions
	assertionSemantics := r.extractAssertionSemantics(method.Assertions)

	// Calculate alignment score
	score := r.calculateAlignmentScore(claimedKeywords, assertionSemantics)

	// Generate finding if score is below threshold
	if score < 0.3 {
		severity := r.determineSeverity(score)

		return []Finding{
			{
				RuleName:       r.Name(),
				Severity:       severity,
				TestMethod:     method.Name,
				TestClass:      method.ClassName,
				FilePath:       ctx.TestFile.Path,
				LineNumber:     method.LineNumber,
				Message:        r.generateMessage(method.Name, claimedKeywords, assertionSemantics, score),
				Recommendation: r.generateRecommendation(claimedKeywords, assertionSemantics),
				Confidence:     r.calculateConfidence(score, len(method.Assertions)),
			},
		}
	}

	return nil
}

// parseTestName extracts claimed functionality keywords from a test method name
func (r *NameAssertionAlignmentRule) parseTestName(name string) []string {
	// Remove "test" prefix
	name = strings.TrimPrefix(name, "test")

	// Handle common naming patterns
	name = r.normalizeTestName(name)

	// Split camelCase into words
	words := r.splitCamelCase(name)

	// Filter out noise words and normalize
	keywords := r.filterAndNormalizeKeywords(words)

	return keywords
}

// normalizeTestName handles common test naming patterns
func (r *NameAssertionAlignmentRule) normalizeTestName(name string) string {
	// Handle "testThat*" pattern
	name = strings.TrimPrefix(name, "That")

	// Handle "testShould*" pattern
	name = strings.TrimPrefix(name, "Should")

	// Handle "testWhen*Then*" pattern - remove these keywords but keep camelCase structure
	// We'll split on these words to preserve the camelCase boundaries
	name = strings.ReplaceAll(name, "Then", "")
	name = strings.ReplaceAll(name, "When", "")

	return name
}

// splitCamelCase splits a camelCase string into individual words
// Handles acronyms like "OAuth", "JWT", "DID" as single words
func (r *NameAssertionAlignmentRule) splitCamelCase(s string) []string {
	if s == "" {
		return []string{}
	}

	var words []string
	lastWordStart := 0

	runes := []rune(s)

	for i := 1; i < len(runes); i++ {
		// Check if this position starts a new word
		curr := runes[i]
		prev := runes[i-1]

		// New word starts if:
		// 1. Current is uppercase and previous is lowercase (e.g., "tokenValidation")
		// 2. Current is uppercase, next is lowercase, and previous is uppercase (e.g., "JWTToken" - T starts new word)
		if unicode.IsUpper(curr) {
			if unicode.IsLower(prev) {
				// Case 1: previous was lowercase
				word := string(runes[lastWordStart:i])
				words = append(words, strings.ToLower(word))
				lastWordStart = i
			} else if i+1 < len(runes) && unicode.IsLower(runes[i+1]) && unicode.IsUpper(prev) {
				// Case 2: end of acronym (e.g., "T" in "JWTToken")
				if i > lastWordStart {
					word := string(runes[lastWordStart:i])
					words = append(words, strings.ToLower(word))
					lastWordStart = i
				}
			}
		}
	}

	// Add the last word
	if lastWordStart < len(runes) {
		word := string(runes[lastWordStart:])
		words = append(words, strings.ToLower(word))
	}

	return words
}

// filterAndNormalizeKeywords removes noise words and normalizes keywords
func (r *NameAssertionAlignmentRule) filterAndNormalizeKeywords(words []string) []string {
	noiseWords := map[string]bool{
		"test": true, "the": true, "a": true, "an": true, "is": true, "are": true,
		"with": true, "for": true, "to": true, "of": true, "in": true, "on": true,
		"at": true, "by": true, "from": true,
	}

	var keywords []string
	for _, word := range words {
		word = strings.ToLower(strings.TrimSpace(word))
		if word != "" && !noiseWords[word] && len(word) > 1 {
			keywords = append(keywords, word)
		}
	}

	return keywords
}

// extractAssertionSemantics extracts semantic meaning from assertion arguments
func (r *NameAssertionAlignmentRule) extractAssertionSemantics(assertions []models.Assertion) []string {
	var semantics []string

	for _, assertion := range assertions {
		// Extract keywords from assertion type
		assertionKeywords := r.extractKeywordsFromAssertionType(assertion.Type)
		semantics = append(semantics, assertionKeywords...)

		// Extract keywords from assertion arguments
		for _, arg := range assertion.Arguments {
			argKeywords := r.extractKeywordsFromExpression(arg)
			semantics = append(semantics, argKeywords...)
		}
	}

	return semantics
}

// extractKeywordsFromAssertionType extracts semantic keywords from assertion type
func (r *NameAssertionAlignmentRule) extractKeywordsFromAssertionType(assertionType string) []string {
	// Map assertion types to semantic keywords
	typeKeywords := map[string][]string{
		"XCTAssertEqual":        {"equal", "value", "match"},
		"XCTAssertNotEqual":     {"not", "equal", "different"},
		"XCTAssertTrue":         {"true", "valid", "success"},
		"XCTAssertFalse":        {"false", "invalid", "fail"},
		"XCTAssertNil":          {"nil", "null", "empty"},
		"XCTAssertNotNil":       {"not", "nil", "exists", "present"},
		"XCTAssertThrows":       {"throws", "error", "exception", "invalid", "reject"},
		"XCTAssertNoThrow":      {"no", "throw", "valid", "success"},
		"XCTAssertGreaterThan":  {"greater", "more", "larger"},
		"XCTAssertLessThan":     {"less", "fewer", "smaller"},
		"XCTAssertEqualObjects": {"equal", "object", "match"},
		"XCTFail":               {"fail", "error", "invalid"},
	}

	if keywords, ok := typeKeywords[assertionType]; ok {
		return keywords
	}

	return []string{}
}

// extractKeywordsFromExpression extracts keywords from an expression string
func (r *NameAssertionAlignmentRule) extractKeywordsFromExpression(expr string) []string {
	// Remove common Objective-C syntax
	expr = strings.ReplaceAll(expr, "@\"", "")
	expr = strings.ReplaceAll(expr, "\"", "")
	expr = strings.ReplaceAll(expr, "[", " ")
	expr = strings.ReplaceAll(expr, "]", " ")
	expr = strings.ReplaceAll(expr, "(", " ")
	expr = strings.ReplaceAll(expr, ")", " ")
	expr = strings.ReplaceAll(expr, ".", " ")
	expr = strings.ReplaceAll(expr, ":", " ")

	// Split into words
	words := strings.Fields(expr)

	// Filter and normalize
	return r.filterAndNormalizeKeywords(words)
}

// calculateAlignmentScore computes alignment between claimed and validated functionality
func (r *NameAssertionAlignmentRule) calculateAlignmentScore(claimedKeywords, assertionSemantics []string) float64 {
	if len(claimedKeywords) == 0 {
		return 1.0 // Can't determine misalignment if no claims
	}

	score := 0.0
	matchedKeywords := 0

	// Check how many claimed keywords appear in assertion semantics
	for _, claimed := range claimedKeywords {
		for _, semantic := range assertionSemantics {
			if r.keywordsMatch(claimed, semantic) {
				score += 0.3 // Keyword present in assertions
				matchedKeywords++
				break
			}
		}
	}

	// Bonus for high match rate
	matchRate := float64(matchedKeywords) / float64(len(claimedKeywords))
	if matchRate > 0.7 {
		score += 0.4 // Good alignment
	} else if matchRate > 0.5 {
		score += 0.2 // Partial alignment
	}

	// Penalty for many unrelated assertions
	if len(assertionSemantics) > len(claimedKeywords)*3 {
		score -= 0.1 // Too many unrelated validations
	}

	// Normalize to 0.0-1.0 range
	if score < 0.0 {
		score = 0.0
	}
	if score > 1.0 {
		score = 1.0
	}

	return score
}

// keywordsMatch checks if two keywords are semantically related
func (r *NameAssertionAlignmentRule) keywordsMatch(keyword1, keyword2 string) bool {
	// Exact match
	if keyword1 == keyword2 {
		return true
	}

	// Substring match
	if strings.Contains(keyword1, keyword2) || strings.Contains(keyword2, keyword1) {
		return true
	}

	// Common synonyms and related terms
	synonyms := map[string][]string{
		"oauth":         {"token", "auth", "authorization", "authentication"},
		"auth":          {"oauth", "token", "authorization", "authentication", "login", "session"},
		"token":         {"oauth", "jwt", "auth", "bearer", "session"},
		"validation":    {"validate", "valid", "verify", "check", "assert"},
		"validate":      {"validation", "valid", "verify", "check"},
		"verify":        {"validate", "check", "assert", "confirm"},
		"error":         {"fail", "exception", "throw", "invalid", "reject"},
		"parse":         {"parser", "parsing", "decode", "deserialize", "read"},
		"serialize":     {"serializer", "encode", "encoding", "write"},
		"did":           {"identifier", "identity", "decentralized", "document"},
		"handle":        {"username", "name", "identifier", "request", "handler"},
		"reject":        {"invalid", "error", "fail", "throw", "deny"},
		"accept":        {"valid", "success", "allow", "permit"},
		"request":       {"handle", "handler", "response", "http", "url"},
		"response":      {"request", "status", "code", "http"},
		"create":        {"new", "init", "make", "build", "alloc"},
		"server":        {"start", "stop", "run", "listen", "service"},
		"start":         {"server", "run", "begin", "init", "launch"},
		"stop":          {"server", "shutdown", "close", "end"},
		"invoke":        {"call", "execute", "run", "perform"},
		"invokes":       {"call", "execute", "run", "perform", "calls"},
		"controller":    {"handler", "manager", "service", "delegate"},
		"returns":       {"return", "result", "output", "value"},
		"failure":       {"error", "fail", "invalid", "exception"},
		"success":       {"valid", "pass", "ok", "correct"},
		"index":         {"list", "page", "home", "root"},
		"config":        {"configuration", "settings", "options", "setup"},
		"round":         {"roundtrip", "bidirectional"},
		"trip":          {"roundtrip", "bidirectional"},
		"middleware":    {"handler", "filter", "interceptor", "chain"},
		"delegate":      {"controller", "handler", "callback"},
		"application":   {"app", "delegate", "lifecycle"},
		"terminate":     {"stop", "shutdown", "close", "end", "quit"},
		"missing":       {"nil", "null", "empty", "absent", "undefined"},
		"header":        {"authorization", "content", "http", "request"},
		"forbidden":     {"denied", "reject", "unauthorized", "access"},
		"admin":         {"administrator", "management", "moderator"},
		"configuration": {"config", "settings", "options", "setup"},
		"builder":       {"create", "build", "construct", "make", "sets"},
		"sets":          {"set", "assign", "configure", "update"},
		"stops":         {"stop", "shutdown", "terminate", "close"},
		"allowed":       {"allow", "permit", "accept", "valid", "true"},
		"default":       {"fallback", "initial", "base", "standard"},
		"uses":          {"use", "utilize", "employ", "apply"},
		"removes":       {"remove", "delete", "clear", "drop"},
		"adds":          {"add", "insert", "append", "include"},
		"update":        {"modify", "change", "set", "patch"},
		"generates":     {"generate", "create", "produce", "make"},
		"stores":        {"store", "save", "persist", "write"},
		"loads":         {"load", "read", "fetch", "get"},
	}

	// Check if keywords are synonyms
	if syns, ok := synonyms[keyword1]; ok {
		for _, syn := range syns {
			if syn == keyword2 {
				return true
			}
		}
	}

	if syns, ok := synonyms[keyword2]; ok {
		for _, syn := range syns {
			if syn == keyword1 {
				return true
			}
		}
	}

	return false
}

// determineSeverity determines the severity based on alignment score
func (r *NameAssertionAlignmentRule) determineSeverity(score float64) Severity {
	if score < 0.1 {
		return CRITICAL // Likely false positive — no keyword overlap at all
	}
	return HIGH // Some overlap but below threshold
}

// calculateConfidence calculates confidence in the finding
func (r *NameAssertionAlignmentRule) calculateConfidence(score float64, assertionCount int) float64 {
	// Base confidence on how far from threshold
	confidence := (0.5 - score) * 2.0 // 0.0 at threshold, 1.0 at score=0.0

	// Adjust for assertion count (more assertions = more confidence)
	if assertionCount >= 3 {
		confidence += 0.1
	}
	if assertionCount >= 5 {
		confidence += 0.1
	}

	// Clamp to 0.0-1.0
	if confidence < 0.0 {
		confidence = 0.0
	}
	if confidence > 1.0 {
		confidence = 1.0
	}

	return confidence
}

// generateMessage creates a human-readable message for the finding
func (r *NameAssertionAlignmentRule) generateMessage(testName string, claimedKeywords, assertionSemantics []string, score float64) string {
	return fmt.Sprintf(
		"Test name '%s' claims to test [%s] but assertions validate [%s]. Alignment score: %.2f (threshold: 0.30)",
		testName,
		strings.Join(claimedKeywords, ", "),
		strings.Join(r.uniqueKeywords(assertionSemantics), ", "),
		score,
	)
}

// generateRecommendation creates an actionable recommendation
func (r *NameAssertionAlignmentRule) generateRecommendation(claimedKeywords, assertionSemantics []string) string {
	missingKeywords := r.findMissingKeywords(claimedKeywords, assertionSemantics)

	if len(missingKeywords) > 0 {
		return fmt.Sprintf(
			"Add assertions to validate: %s. Or rename the test to match what it actually validates.",
			strings.Join(missingKeywords, ", "),
		)
	}

	return "Review test name and assertions to ensure they align. Consider renaming the test or adding missing validations."
}

// findMissingKeywords identifies claimed keywords not validated by assertions
func (r *NameAssertionAlignmentRule) findMissingKeywords(claimedKeywords, assertionSemantics []string) []string {
	var missing []string

	for _, claimed := range claimedKeywords {
		found := false
		for _, semantic := range assertionSemantics {
			if r.keywordsMatch(claimed, semantic) {
				found = true
				break
			}
		}
		if !found {
			missing = append(missing, claimed)
		}
	}

	return missing
}

// uniqueKeywords returns unique keywords from a list
func (r *NameAssertionAlignmentRule) uniqueKeywords(keywords []string) []string {
	seen := make(map[string]bool)
	var unique []string

	for _, keyword := range keywords {
		if !seen[keyword] {
			seen[keyword] = true
			unique = append(unique, keyword)
		}
	}

	return unique
}
