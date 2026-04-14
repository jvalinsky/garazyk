package validation

import (
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// SecurityTestType represents the type of security test
type SecurityTestType string

const (
	SecurityTypeOAuth     SecurityTestType = "oauth"
	SecurityTypeDPoP      SecurityTestType = "dpop"
	SecurityTypeJWT       SecurityTestType = "jwt"
	SecurityTypeSSRF      SecurityTestType = "ssrf"
	SecurityTypeInputVal  SecurityTestType = "input_validation"
	SecurityTypeRateLimit SecurityTestType = "rate_limit"
	SecurityTypeNone      SecurityTestType = "none"
)

// SecurityTestRule validates security tests
type SecurityTestRule struct{}

// Name returns the rule name
func (r *SecurityTestRule) Name() string {
	return "SecurityTestRule"
}

// Description returns the rule description
func (r *SecurityTestRule) Description() string {
	return "Validates that security tests actually test security properties (rejection of malicious inputs, cryptographic validation)"
}

// Severity returns the rule severity
func (r *SecurityTestRule) Severity() Severity {
	return CRITICAL
}

// Validate applies the rule
func (r *SecurityTestRule) Validate(ctx ValidationContext) []Finding {
	if ctx.TestMethod == nil {
		return nil
	}

	var findings []Finding

	// Detect security test type
	securityType := r.detectSecurityTestType(ctx.TestMethod, ctx.TestClass)

	// If not a security test, skip
	if securityType == SecurityTypeNone {
		return nil
	}

	// Check if test validates rejection/security properties
	hasRejectionValidation := r.hasRejectionValidation(ctx.TestMethod, securityType)

	if !hasRejectionValidation {
		// Only flag if the test name specifically claims to test rejection/invalid/expired
		nameIndicatesRejection := false
		nameLower := strings.ToLower(ctx.TestMethod.Name)
		for _, keyword := range []string{"invalid", "reject", "expired", "tamper", "malformed", "unauthorized"} {
			if strings.Contains(nameLower, keyword) {
				nameIndicatesRejection = true
				break
			}
		}
		if !nameIndicatesRejection {
			return findings
		}

		findings = append(findings, Finding{
			RuleName:       r.Name(),
			Severity:       HIGH,
			TestMethod:     ctx.TestMethod.Name,
			TestClass:      ctx.TestClass.Name,
			FilePath:       ctx.TestFile.Path,
			LineNumber:     ctx.TestMethod.LineNumber,
			Message:        r.getSecurityMessage(securityType),
			Recommendation: r.getSecurityRecommendation(securityType),
			Confidence:     0.8,
		})
	}

	return findings
}

// detectSecurityTestType identifies the type of security test
func (r *SecurityTestRule) detectSecurityTestType(method *models.TestMethod, class *models.TestClass) SecurityTestType {
	nameLower := strings.ToLower(method.Name)
	classLower := strings.ToLower(class.Name)
	sourceCode := strings.ToLower(method.SourceCode)

	// OAuth tests - only match on 'oauth' specifically, not 'token' (too broad)
	if r.matchesKeywords(nameLower, classLower, sourceCode, []string{"oauth"}) {
		return SecurityTypeOAuth
	}

	// DPoP tests
	if r.matchesKeywords(nameLower, classLower, sourceCode, []string{"dpop", "proof"}) {
		return SecurityTypeDPoP
	}

	// JWT tests
	if r.matchesKeywords(nameLower, classLower, sourceCode, []string{"jwt", "jws", "jwe"}) {
		return SecurityTypeJWT
	}

	// SSRF protection tests
	if r.matchesKeywords(nameLower, classLower, sourceCode, []string{"ssrf", "urlvalidat", "urlcheck"}) {
		return SecurityTypeSSRF
	}

	// Input validation tests
	if r.matchesKeywords(nameLower, classLower, sourceCode, []string{"inputvalidat", "malformed", "sanitiz", "xss", "injection"}) {
		return SecurityTypeInputVal
	}

	// Rate limiting tests
	if r.matchesKeywords(nameLower, classLower, sourceCode, []string{"ratelimit", "throttl", "dos", "ddos"}) {
		return SecurityTypeRateLimit
	}

	return SecurityTypeNone
}

// matchesKeywords checks if any keyword matches in the method name or class name.
// Deliberately does NOT match on source code to avoid false positives from
// incidental keyword usage (e.g., "token" in any auth-adjacent test).
func (r *SecurityTestRule) matchesKeywords(name, class, source string, keywords []string) bool {
	for _, keyword := range keywords {
		if strings.Contains(name, keyword) || strings.Contains(class, keyword) {
			return true
		}
	}
	return false
}

// hasRejectionValidation checks if test validates rejection/security properties
func (r *SecurityTestRule) hasRejectionValidation(method *models.TestMethod, securityType SecurityTestType) bool {
	switch securityType {
	case SecurityTypeOAuth, SecurityTypeDPoP:
		return r.hasSignatureValidation(method)
	case SecurityTypeJWT:
		return r.hasJWTValidation(method)
	case SecurityTypeSSRF:
		return r.hasURLRejection(method)
	case SecurityTypeInputVal:
		return r.hasInputRejection(method)
	case SecurityTypeRateLimit:
		return r.hasThrottlingCheck(method)
	default:
		return false
	}
}

// hasSignatureValidation checks for signature/cryptographic validation
func (r *SecurityTestRule) hasSignatureValidation(method *models.TestMethod) bool {
	// Check for XCTAssertFalse on validation result
	for _, assertion := range method.Assertions {
		if assertion.Type == "XCTAssertFalse" {
			// Check if asserting on validation/verification result
			args := strings.Join(assertion.Arguments, " ")
			if r.containsValidationKeywords(args) {
				return true
			}
		}
	}

	// Check source code for rejection patterns
	sourceCode := strings.ToLower(method.SourceCode)
	validationKeywords := []string{
		"verify", "validate", "check", "tamper", "invalid", "reject",
	}

	hasValidationCall := false
	for _, keyword := range validationKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasValidationCall = true
			break
		}
	}

	// Must have both validation call and assertion of failure
	return hasValidationCall && r.hasFailureAssertion(method)
}

// hasJWTValidation checks for JWT expiration/signature validation
func (r *SecurityTestRule) hasJWTValidation(method *models.TestMethod) bool {
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for expiration or signature keywords
	jwtKeywords := []string{
		"expir", "signature", "invalid", "tamper", "verify",
	}

	hasJWTValidation := false
	for _, keyword := range jwtKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasJWTValidation = true
			break
		}
	}

	// Must have JWT validation and failure assertion
	return hasJWTValidation && r.hasFailureAssertion(method)
}

// hasURLRejection checks for URL rejection validation
func (r *SecurityTestRule) hasURLRejection(method *models.TestMethod) bool {
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for malicious URL patterns
	maliciousPatterns := []string{
		"169.254", "localhost", "127.0.0.1", "malicious", "internal",
	}

	hasMaliciousURL := false
	for _, pattern := range maliciousPatterns {
		if strings.Contains(sourceCode, pattern) {
			hasMaliciousURL = true
			break
		}
	}

	// Must have malicious URL and failure assertion
	return hasMaliciousURL && r.hasFailureAssertion(method)
}

// hasInputRejection checks for input rejection validation
func (r *SecurityTestRule) hasInputRejection(method *models.TestMethod) bool {
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for malformed/malicious input
	inputKeywords := []string{
		"malformed", "invalid", "malicious", "script", "inject",
	}

	hasMaliciousInput := false
	for _, keyword := range inputKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasMaliciousInput = true
			break
		}
	}

	// Check for rejection assertions
	hasRejection := false
	for _, assertion := range method.Assertions {
		if assertion.Type == "XCTAssertNil" || assertion.Type == "XCTAssertFalse" {
			hasRejection = true
			break
		}
		if assertion.Type == "XCTAssertNotNil" {
			// Check if asserting on error
			args := strings.Join(assertion.Arguments, " ")
			if strings.Contains(strings.ToLower(args), "error") {
				hasRejection = true
				break
			}
		}
	}

	return hasMaliciousInput && hasRejection
}

// hasThrottlingCheck checks for rate limiting/throttling validation
func (r *SecurityTestRule) hasThrottlingCheck(method *models.TestMethod) bool {
	sourceCode := strings.ToLower(method.SourceCode)

	// Check for loop exceeding limit
	hasLoop := strings.Contains(sourceCode, "for") || strings.Contains(sourceCode, "while")
	hasLimit := strings.Contains(sourceCode, "limit")

	// Check for blocking/throttling assertions
	hasBlockCheck := false
	for _, assertion := range method.Assertions {
		if assertion.Type == "XCTAssertTrue" {
			args := strings.Join(assertion.Arguments, " ")
			argsLower := strings.ToLower(args)
			if strings.Contains(argsLower, "block") || strings.Contains(argsLower, "throttl") {
				hasBlockCheck = true
				break
			}
		}
	}

	return hasLoop && hasLimit && hasBlockCheck
}

// hasFailureAssertion checks if test asserts failure/rejection
func (r *SecurityTestRule) hasFailureAssertion(method *models.TestMethod) bool {
	for _, assertion := range method.Assertions {
		switch assertion.Type {
		case "XCTAssertFalse", "XCTAssertNil":
			return true
		case "XCTAssertNotNil":
			// Check if asserting on error
			args := strings.Join(assertion.Arguments, " ")
			if strings.Contains(strings.ToLower(args), "error") {
				return true
			}
		}
	}
	return false
}

// containsValidationKeywords checks if arguments contain validation keywords
func (r *SecurityTestRule) containsValidationKeywords(args string) bool {
	argsLower := strings.ToLower(args)
	keywords := []string{"valid", "verify", "check", "auth"}
	for _, keyword := range keywords {
		if strings.Contains(argsLower, keyword) {
			return true
		}
	}
	return false
}

// getSecurityMessage returns the appropriate message for the security type
func (r *SecurityTestRule) getSecurityMessage(securityType SecurityTestType) string {
	switch securityType {
	case SecurityTypeOAuth:
		return "OAuth test does not verify signature validation or token rejection"
	case SecurityTypeDPoP:
		return "DPoP test does not verify proof signature validation or rejection"
	case SecurityTypeJWT:
		return "JWT test does not verify expiration or signature checks"
	case SecurityTypeSSRF:
		return "SSRF protection test does not verify malicious URL rejection"
	case SecurityTypeInputVal:
		return "Input validation test does not verify malformed input rejection"
	case SecurityTypeRateLimit:
		return "Rate limiting test does not verify request throttling"
	default:
		return "Security test does not validate security properties"
	}
}

// getSecurityRecommendation returns the appropriate recommendation for the security type
func (r *SecurityTestRule) getSecurityRecommendation(securityType SecurityTestType) string {
	switch securityType {
	case SecurityTypeOAuth:
		return "Add assertions that verify tampered or invalid tokens are rejected (XCTAssertFalse on validation result)"
	case SecurityTypeDPoP:
		return "Add assertions that verify invalid DPoP proofs are rejected (XCTAssertFalse on verification result)"
	case SecurityTypeJWT:
		return "Add assertions that verify expired or tampered JWTs are rejected (XCTAssertFalse on validation, XCTAssertNotNil on error)"
	case SecurityTypeSSRF:
		return "Add assertions that verify malicious URLs (169.254.169.254, localhost) are rejected (XCTAssertFalse on allowed, XCTAssertNotNil on error)"
	case SecurityTypeInputVal:
		return "Add assertions that verify malformed inputs are rejected (XCTAssertNil on result, XCTAssertNotNil on error)"
	case SecurityTypeRateLimit:
		return "Add assertions that verify requests are blocked after exceeding limit (XCTAssertTrue on isBlocked)"
	default:
		return "Add assertions that verify security properties are enforced"
	}
}
