package validation

import (
	"regexp"
	"strings"

	"github.com/september-pds/test-audit-validator/internal/models"
)

// SecurityTestRule validates security tests
type SecurityTestRule struct{}

// Name returns the rule name
func (r *SecurityTestRule) Name() string {
	return "SecurityTestRule"
}

// Description returns the rule description
func (r *SecurityTestRule) Description() string {
	return "Validates that security tests actually test security properties"
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

	// Check if this is a security test
	securityType := r.detectSecurityTestType(ctx.TestMethod)
	if securityType == "" {
		return nil
	}

	// Verify the test validates rejection/security properties
	if !r.validatesSecurityProperty(ctx.TestMethod, securityType) {
		findings = append(findings, Finding{
			RuleName:       r.Name(),
			Severity:       r.Severity(),
			TestMethod:     ctx.TestMethod.Name,
			TestClass:      ctx.TestClass.Name,
			FilePath:       ctx.TestFile.Path,
			LineNumber:     ctx.TestMethod.LineNumber,
			Message:        "Security test does not verify rejection of malicious/invalid inputs",
			Recommendation: r.getRecommendation(securityType),
			Confidence:     0.8,
		})
	}

	return findings
}

// detectSecurityTestType identifies the type of security test
func (r *SecurityTestRule) detectSecurityTestType(method *models.TestMethod) string {
	nameLower := strings.ToLower(method.Name)
	sourceCode := strings.ToLower(method.SourceCode)

	// OAuth/DPoP tests
	if strings.Contains(nameLower, "oauth") || strings.Contains(nameLower, "dpop") ||
		strings.Contains(sourceCode, "oauth") || strings.Contains(sourceCode, "dpop") {
		return "oauth_dpop"
	}

	// JWT tests
	if strings.Contains(nameLower, "jwt") || strings.Contains(nameLower, "token") {
		if strings.Contains(sourceCode, "jwt") || strings.Contains(sourceCode, "token") {
			return "jwt"
		}
	}

	// SSRF protection tests
	if strings.Contains(nameLower, "ssrf") || strings.Contains(nameLower, "urlvalidation") {
		return "ssrf"
	}

	// Input validation tests
	if (strings.Contains(nameLower, "validation") || strings.Contains(nameLower, "invalid")) &&
		(strings.Contains(nameLower, "input") || strings.Contains(nameLower, "malformed")) {
		return "input_validation"
	}

	// Rate limiting tests
	if strings.Contains(nameLower, "ratelimit") || strings.Contains(nameLower, "throttle") {
		return "rate_limiting"
	}

	return ""
}

// validatesSecurityProperty checks if the test validates security properties
func (r *SecurityTestRule) validatesSecurityProperty(method *models.TestMethod, securityType string) bool {
	sourceCode := strings.ToLower(method.SourceCode)

	switch securityType {
	case "oauth_dpop":
		return r.validatesOAuthDPoP(method, sourceCode)
	case "jwt":
		return r.validatesJWT(method, sourceCode)
	case "ssrf":
		return r.validatesSSRF(method, sourceCode)
	case "input_validation":
		return r.validatesInputValidation(method, sourceCode)
	case "rate_limiting":
		return r.validatesRateLimiting(method, sourceCode)
	}

	return false
}

// validatesOAuthDPoP checks OAuth/DPoP signature validation
func (r *SecurityTestRule) validatesOAuthDPoP(method *models.TestMethod, sourceCode string) bool {
	// Check for signature validation
	signatureKeywords := []string{
		"verify", "signature", "invalid", "tampered", "reject",
	}

	hasSignatureCheck := false
	for _, keyword := range signatureKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasSignatureCheck = true
			break
		}
	}

	if !hasSignatureCheck {
		return false
	}

	// Check for rejection assertions
	return r.hasRejectionAssertion(method)
}

// validatesJWT checks JWT expiration and signature validation
func (r *SecurityTestRule) validatesJWT(method *models.TestMethod, sourceCode string) bool {
	// Check for expiration or signature checks
	jwtKeywords := []string{
		"expir", "signature", "invalid", "verify", "reject",
	}

	hasJWTCheck := false
	for _, keyword := range jwtKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasJWTCheck = true
			break
		}
	}

	if !hasJWTCheck {
		return false
	}

	// Check for rejection assertions
	return r.hasRejectionAssertion(method)
}

// validatesSSRF checks SSRF protection
func (r *SecurityTestRule) validatesSSRF(method *models.TestMethod, sourceCode string) bool {
	// Check for URL rejection
	ssrfKeywords := []string{
		"reject", "block", "deny", "invalid", "malicious",
	}

	hasSSRFCheck := false
	for _, keyword := range ssrfKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasSSRFCheck = true
			break
		}
	}

	if !hasSSRFCheck {
		return false
	}

	// Check for rejection assertions
	return r.hasRejectionAssertion(method)
}

// validatesInputValidation checks input validation
func (r *SecurityTestRule) validatesInputValidation(method *models.TestMethod, sourceCode string) bool {
	// Check for malformed input rejection
	validationKeywords := []string{
		"malformed", "invalid", "reject", "error", "fail",
	}

	hasValidationCheck := false
	for _, keyword := range validationKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasValidationCheck = true
			break
		}
	}

	if !hasValidationCheck {
		return false
	}

	// Check for rejection assertions
	return r.hasRejectionAssertion(method)
}

// validatesRateLimiting checks rate limiting
func (r *SecurityTestRule) validatesRateLimiting(method *models.TestMethod, sourceCode string) bool {
	// Check for throttling verification
	rateLimitKeywords := []string{
		"throttle", "block", "limit", "exceed", "reject",
	}

	hasRateLimitCheck := false
	for _, keyword := range rateLimitKeywords {
		if strings.Contains(sourceCode, keyword) {
			hasRateLimitCheck = true
			break
		}
	}

	if !hasRateLimitCheck {
		return false
	}

	// Check for rejection assertions
	return r.hasRejectionAssertion(method)
}

// hasRejectionAssertion checks if the test has assertions that verify rejection
func (r *SecurityTestRule) hasRejectionAssertion(method *models.TestMethod) bool {
	// Check for assertions that verify rejection
	rejectionPatterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)xctassertfalse`),
		regexp.MustCompile(`(?i)xctassertnil`),
		regexp.MustCompile(`(?i)xctassertthrows`),
		regexp.MustCompile(`(?i)xctassertnotnilwitherror`),
		regexp.MustCompile(`(?i)xctassertequal.*false`),
		regexp.MustCompile(`(?i)xctassertequal.*nil`),
		regexp.MustCompile(`(?i)xctasserttrue.*block`), // For rate limiting: isBlocked
		regexp.MustCompile(`(?i)xctasserttrue.*reject`),
	}

	for _, assertion := range method.Assertions {
		assertionType := strings.ToLower(assertion.Type)
		
		// Check if assertion type indicates rejection
		if strings.Contains(assertionType, "false") ||
			strings.Contains(assertionType, "nil") ||
			strings.Contains(assertionType, "throws") {
			return true
		}

		// Check assertion arguments for rejection indicators
		for _, arg := range assertion.Arguments {
			argLower := strings.ToLower(arg)
			if strings.Contains(argLower, "false") ||
				strings.Contains(argLower, "nil") ||
				strings.Contains(argLower, "error") ||
				strings.Contains(argLower, "reject") ||
				strings.Contains(argLower, "block") { // For rate limiting
				return true
			}
		}
	}

	// Check source code for rejection patterns
	sourceCode := strings.ToLower(method.SourceCode)
	for _, pattern := range rejectionPatterns {
		if pattern.MatchString(sourceCode) {
			return true
		}
	}

	return false
}

// getRecommendation returns a recommendation based on security test type
func (r *SecurityTestRule) getRecommendation(securityType string) string {
	switch securityType {
	case "oauth_dpop":
		return "Add assertions to verify that tampered tokens are rejected (XCTAssertFalse for validation result)"
	case "jwt":
		return "Add assertions to verify that expired or invalid JWTs are rejected (XCTAssertThrows or XCTAssertFalse)"
	case "ssrf":
		return "Add assertions to verify that malicious URLs are rejected (XCTAssertFalse for validation result)"
	case "input_validation":
		return "Add assertions to verify that malformed inputs are rejected (XCTAssertThrows or XCTAssertNotNil for error)"
	case "rate_limiting":
		return "Add assertions to verify that requests are throttled after limits (XCTAssertTrue for isBlocked)"
	default:
		return "Add assertions to verify that security properties are enforced"
	}
}
