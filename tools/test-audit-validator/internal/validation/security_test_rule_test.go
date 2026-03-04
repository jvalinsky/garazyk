package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestSecurityTestRule_OAuthWithRejection(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testOAuthTokenValidation",
		LineNumber: 10,
		SourceCode: `
			NSString *tamperedToken = [self tamperWithToken:validToken];
			BOOL valid = [verifier verifyToken:tamperedToken];
			XCTAssertFalse(valid, @"Tampered token should be rejected");
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertFalse", Arguments: []string{"valid", "@\"Tampered token should be rejected\""}},
		},
	}

	class := &models.TestClass{Name: "OAuthTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for OAuth test with rejection validation
	if len(findings) != 0 {
		t.Errorf("Expected no findings for OAuth test with rejection, got %d", len(findings))
	}
}

func TestSecurityTestRule_OAuthWithoutRejection(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testOAuthTokenGeneration",
		LineNumber: 10,
		SourceCode: `
			NSString *token = [generator generateToken];
			XCTAssertNotNil(token);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNotNil", Arguments: []string{"token"}},
		},
	}

	class := &models.TestClass{Name: "OAuthTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should report finding for OAuth test without rejection validation
	if len(findings) != 1 {
		t.Fatalf("Expected 1 finding for OAuth test without rejection, got %d", len(findings))
	}

	if findings[0].Severity != CRITICAL {
		t.Errorf("Expected CRITICAL severity, got %v", findings[0].Severity)
	}
}

func TestSecurityTestRule_JWTWithExpiration(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testJWTExpirationCheck",
		LineNumber: 10,
		SourceCode: `
			NSString *expiredToken = [self createExpiredToken];
			NSError *error = nil;
			BOOL valid = [verifier verifyJWT:expiredToken error:&error];
			XCTAssertFalse(valid);
			XCTAssertNotNil(error);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertFalse", Arguments: []string{"valid"}},
			{Type: "XCTAssertNotNil", Arguments: []string{"error"}},
		},
	}

	class := &models.TestClass{Name: "JWTTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for JWT test with expiration check
	if len(findings) != 0 {
		t.Errorf("Expected no findings for JWT test with expiration check, got %d", len(findings))
	}
}

func TestSecurityTestRule_SSRFProtection(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testSSRFProtection",
		LineNumber: 10,
		SourceCode: `
			NSURL *maliciousURL = [NSURL URLWithString:@"http://169.254.169.254/"];
			NSError *error = nil;
			BOOL allowed = [validator validateURL:maliciousURL error:&error];
			XCTAssertFalse(allowed);
			XCTAssertNotNil(error);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertFalse", Arguments: []string{"allowed"}},
			{Type: "XCTAssertNotNil", Arguments: []string{"error"}},
		},
	}

	class := &models.TestClass{Name: "URLValidatorTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for SSRF test with rejection
	if len(findings) != 0 {
		t.Errorf("Expected no findings for SSRF test with rejection, got %d", len(findings))
	}
}

func TestSecurityTestRule_InputValidation(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testInvalidInputRejection",
		LineNumber: 10,
		SourceCode: `
			NSString *malformedInput = @"<script>alert('xss')</script>";
			NSError *error = nil;
			id result = [parser parse:malformedInput error:&error];
			XCTAssertNil(result);
			XCTAssertNotNil(error);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertNil", Arguments: []string{"result"}},
			{Type: "XCTAssertNotNil", Arguments: []string{"error"}},
		},
	}

	class := &models.TestClass{Name: "InputValidationTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for input validation test with rejection
	if len(findings) != 0 {
		t.Errorf("Expected no findings for input validation test with rejection, got %d", len(findings))
	}
}

func TestSecurityTestRule_RateLimiting(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testRateLimitThrottling",
		LineNumber: 10,
		SourceCode: `
			for (int i = 0; i < limit + 1; i++) {
				[limiter checkRequest];
			}
			XCTAssertTrue([limiter isBlocked]);
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertTrue", Arguments: []string{"[limiter isBlocked]"}},
		},
	}

	class := &models.TestClass{Name: "RateLimitTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for rate limiting test with throttling check
	if len(findings) != 0 {
		t.Errorf("Expected no findings for rate limiting test with throttling check, got %d", len(findings))
	}
}

func TestSecurityTestRule_NonSecurityTest(t *testing.T) {
	rule := &SecurityTestRule{}

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

	// Should not report findings for non-security test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for non-security test, got %d", len(findings))
	}
}

func TestSecurityTestRule_DPoPSignatureValidation(t *testing.T) {
	rule := &SecurityTestRule{}

	method := &models.TestMethod{
		Name:       "testDPoPSignatureVerification",
		LineNumber: 10,
		SourceCode: `
			NSString *invalidProof = [self createInvalidDPoPProof];
			BOOL valid = [verifier verifyDPoPProof:invalidProof];
			XCTAssertFalse(valid, @"Invalid DPoP proof should be rejected");
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertFalse", Arguments: []string{"valid", "@\"Invalid DPoP proof should be rejected\""}},
		},
	}

	class := &models.TestClass{Name: "DPoPTests"}
	file := &models.TestFile{Path: "test.m"}

	ctx := ValidationContext{
		TestMethod: method,
		TestClass:  class,
		TestFile:   file,
	}

	findings := rule.Validate(ctx)

	// Should not report findings for DPoP test with signature validation
	if len(findings) != 0 {
		t.Errorf("Expected no findings for DPoP test with signature validation, got %d", len(findings))
	}
}
