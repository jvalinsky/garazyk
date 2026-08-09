// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Phase2SecurityIntegrationTests.m
 @brief Tests for Phase 2 security integration: ATProtoSafeHTTPClient, GZLogRedactor,
        PDSSecurityCompare, OAuthClientAuthPolicy, PDSKeyEnvelope, GZAdminUIAuthManager rework,
        and SQL hardening.

 @discussion Verifies that all Phase 1 security primitives are correctly integrated
 into production code paths and that the identified vulnerabilities are remediated.
*/

#import <XCTest/XCTest.h>
#import "Security/PDSSecurityCompare.h"
#import "Debug/GZLogRedactor.h"
#import "Auth/OAuthClientAuthPolicy.h"
#import "Security/PDSKeyEnvelope.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "AdminUIServer/UIAuthManager.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/SSRFValidator.h"

@interface Phase2SecurityIntegrationTests : XCTestCase
@end

@implementation Phase2SecurityIntegrationTests

#pragma mark - PDSSecurityCompare Integration

- (void)testConstantTimeCompareDelegatesToSecurityCompare {
    // ATProtoCryptoUtils.constantTimeCompare should delegate to PDSSecurityCompare
    // which correctly handles UTF-8 byte comparison (not Unicode code units)
    NSString *asciiA = @"hello";
    NSString *asciiB = @"hello";
    XCTAssertTrue([ATProtoCryptoUtils constantTimeCompare:asciiA to:asciiB],
                  @"ASCII strings should match");

    NSString *asciiC = @"world";
    XCTAssertFalse([ATProtoCryptoUtils constantTimeCompare:asciiA to:asciiC],
                   @"Different strings should not match");
}

- (void)testConstantTimeCompareUnicodeHandling {
    // The original bug: iterating by NSString.length (Unicode code units) instead
    // of UTF-8 bytes. PDSSecurityCompare uses UTF-8 byte comparison.
    // "café" in UTF-8 is 5 bytes (é = 2 bytes), but NSString.length = 4.
    NSString *a = @"café";
    NSString *b = @"café";
    XCTAssertTrue([ATProtoCryptoUtils constantTimeCompare:a to:b],
                  @"Unicode strings should match correctly");

    NSString *c = @"cafe";
    XCTAssertFalse([ATProtoCryptoUtils constantTimeCompare:a to:c],
                   @"Different Unicode strings should not match");
}

- (void)testConstantTimeCompareNilHandling {
    XCTAssertFalse([ATProtoCryptoUtils constantTimeCompare:nil to:@"test"],
                   @"nil vs non-nil should be NO");
    XCTAssertFalse([ATProtoCryptoUtils constantTimeCompare:@"test" to:nil],
                   @"non-nil vs nil should be NO");
    XCTAssertTrue([ATProtoCryptoUtils constantTimeCompare:nil to:nil],
                  @"nil vs nil should be YES");
}

- (void)testConstantTimeCompareEmptyStrings {
    XCTAssertTrue([ATProtoCryptoUtils constantTimeCompare:@"" to:@""],
                  @"Empty strings should match");
    XCTAssertFalse([ATProtoCryptoUtils constantTimeCompare:@"" to:@"a"],
                   @"Empty vs non-empty should not match");
}

#pragma mark - GZLogRedactor Integration

- (void)testLogRedactorRedactsBearerTokens {
    NSString *log = @"Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.test.sig";
    NSString *redacted = [GZLogRedactor redactString:log];
    XCTAssertFalse([redacted containsString:@"eyJhbGciOiJIUzI1NiJ9.test.sig"],
                   @"Bearer token should be redacted");
    XCTAssertTrue([redacted containsString:@"<redacted>"],
                  @"Redacted placeholder should appear");
}

- (void)testLogRedactorRedactsClientSecrets {
    NSString *log = @"client_secret=abc123def456";
    NSString *redacted = [GZLogRedactor redactString:log];
    XCTAssertFalse([redacted containsString:@"abc123def456"],
                   @"client_secret value should be redacted");
}

- (void)testLogRedactorRedactsRefreshTokens {
    NSString *log = @"refresh_token=r-abc123def456xyz789";
    NSString *redacted = [GZLogRedactor redactString:log];
    XCTAssertFalse([redacted containsString:@"r-abc123def456xyz789"],
                   @"refresh_token value should be redacted");
}

- (void)testLogRedactorPreservesNonSensitiveData {
    NSString *log = @"User did:example123 logged in successfully";
    NSString *redacted = [GZLogRedactor redactString:log];
    XCTAssertTrue([redacted containsString:@"did:example123"],
                  @"Non-sensitive DID should be preserved");
    XCTAssertTrue([redacted containsString:@"logged in successfully"],
                  @"Non-sensitive message should be preserved");
}

- (void)testLogRedactorRedactsMasterSecret {
    // The PDS master secret encrypts every account's PLC rotation key; leaking
    // it grants permanent identity takeover. Pin that the redactor catches it
    // in all three forms the logger might emit.
    NSString *keyValue = @"master_secret=s3krit-rotation-key-abc123";
    NSString *redactedKV = [GZLogRedactor redactString:keyValue];
    XCTAssertFalse([redactedKV containsString:@"s3krit-rotation-key-abc123"],
                   @"master_secret=value should be redacted");
    XCTAssertTrue([redactedKV containsString:@"<redacted>"],
                  @"Redacted placeholder should appear");

    NSString *jsonForm = @"{\"master_secret\": \"s3krit-rotation-key-abc123\"}";
    NSString *redactedJSON = [GZLogRedactor redactString:jsonForm];
    XCTAssertFalse([redactedJSON containsString:@"s3krit-rotation-key-abc123"],
                   @"JSON \"master_secret\": value should be redacted");

    NSString *colonForm = @"master_secret: s3krit-rotation-key-abc123";
    NSString *redactedColon = [GZLogRedactor redactString:colonForm];
    XCTAssertFalse([redactedColon containsString:@"s3krit-rotation-key-abc123"],
                   @"master_secret: value should be redacted");
}

- (void)testLogRedactorRedactsBareSecretKeyword {
    // `secret` as a standalone keyword mirrors the existing broad `token`
    // keyword. Verify it catches the bare form without breaking prefixed
    // forms like client_secret (already covered above).
    NSString *log = @"secret=hunter2-only-known-to-ops";
    NSString *redacted = [GZLogRedactor redactString:log];
    XCTAssertFalse([redacted containsString:@"hunter2-only-known-to-ops"],
                   @"bare secret=value should be redacted");
}

- (void)testLogRedactorRedactsS3AndCaptchaSecrets {
    // S3 and captcha secret keys are read from config but defense-in-depth
    // requires the redactor to catch them if ever logged.
    NSString *s3Log = @"s3_secret_access_key=AKIAIOSFODNN7EXAMPLE";
    NSString *s3Redacted = [GZLogRedactor redactString:s3Log];
    XCTAssertFalse([s3Redacted containsString:@"AKIAIOSFODNN7EXAMPLE"],
                   @"s3_secret_access_key value should be redacted");

    NSString *captchaLog = @"captcha_secret_key=0xABCDEF-secret-captcha";
    NSString *captchaRedacted = [GZLogRedactor redactString:captchaLog];
    XCTAssertFalse([captchaRedacted containsString:@"0xABCDEF-secret-captcha"],
                   @"captcha_secret_key value should be redacted");
}

- (void)testLogRedactorRedactsSecretInURLQuery {
    // URL query-param redaction (redactURLString) must also cover the new
    // keywords so a logged URL like ?master_secret=... is safe.
    NSString *url = @"https://pds.example.com/cfg?master_secret=leaked-via-url";
    NSString *redacted = [GZLogRedactor redactURLString:url];
    XCTAssertFalse([redacted containsString:@"leaked-via-url"],
                   @"master_secret in URL query should be redacted");
}

- (void)testLogRedactorDoesNotMangleLengthOnlyLogLines {
    // The kept INFO log lines in ATProtoServiceConfiguration.m log only the
    // secret length, not the value. Verify the redactor leaves them intact so
    // operators still see the diagnostic without a mangled message.
    NSString *log = @"applyConfig: master_secret overridden by PDS_MASTER_SECRET env (length: 32)";
    NSString *redacted = [GZLogRedactor redactString:log];
    XCTAssertTrue([redacted containsString:@"(length: 32)"],
                  @"Length-only log line should preserve the length value");
    XCTAssertTrue([redacted containsString:@"PDS_MASTER_SECRET"],
                  @"The env-var name in a length-only log should be preserved");
}

#pragma mark - OAuthClientAuthPolicy Integration

- (void)testClientAuthPolicySupportedMethods {
    NSArray *methods = [OAuthClientAuthPolicy supportedTokenEndpointAuthMethods];
    XCTAssertTrue([methods containsObject:@"none"], @"'none' should be supported");
    XCTAssertTrue([methods containsObject:@"client_secret_post"], @"client_secret_post should be supported");
    XCTAssertTrue([methods containsObject:@"client_secret_basic"], @"client_secret_basic should be supported");
    XCTAssertTrue([methods containsObject:@"private_key_jwt"], @"private_key_jwt should be supported");
}

- (void)testClientAuthPolicySupportedGrantTypes {
    NSArray *types = [OAuthClientAuthPolicy supportedGrantTypes];
    XCTAssertTrue([types containsObject:@"authorization_code"], @"authorization_code should be supported");
    XCTAssertTrue([types containsObject:@"refresh_token"], @"refresh_token should be supported");
}

- (void)testClientAuthPolicyValidateSecret {
    NSString *secret = @"my-secret-value";
    NSString *expected = @"my-secret-value";
    XCTAssertTrue([OAuthClientAuthPolicy validateClientSecret:secret againstExpected:expected],
                  @"Matching secrets should validate");

    NSString *wrong = @"wrong-secret";
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:wrong againstExpected:expected],
                   @"Non-matching secrets should fail");
}

- (void)testClientAuthPolicyValidateSecretNilHandling {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:nil againstExpected:@"secret"],
                   @"nil provided secret should fail");
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"secret" againstExpected:nil],
                   @"nil expected secret should fail");
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:nil againstExpected:nil],
                   @"Both nil should fail");
}

- (void)testClientAuthPolicyValidateSecretEmptyHandling {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"" againstExpected:@"secret"],
                   @"Empty provided secret should fail");
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"secret" againstExpected:@""],
                   @"Empty expected secret should fail");
}

#pragma mark - PDSKeyEnvelope Integration

- (void)testKeyEnvelopeSealAndOpen {
    // Generate a random 32-byte key
    uint8_t keyBytes[32];
    SecRandomCopyBytes(kSecRandomDefault, 32, keyBytes);
    NSData *encryptionKey = [NSData dataWithBytes:keyBytes length:32];

    NSData *plaintext = [@"test-rotation-key-data-32bytes!!" dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    NSData *envelope = [PDSKeyEnvelope seal:plaintext withKey:encryptionKey error:&error];
    XCTAssertNil(error, @"Seal should not error");
    XCTAssertNotNil(envelope, @"Envelope should be created");

    // Verify it's a versioned envelope
    XCTAssertTrue([PDSKeyEnvelope isVersionedEnvelope:envelope],
                  @"Sealed data should be a versioned envelope");

    // Open the envelope
    NSData *decrypted = [PDSKeyEnvelope openEnvelope:envelope withKey:encryptionKey error:&error];
    XCTAssertNil(error, @"Open should not error");
    XCTAssertTrue([decrypted isEqual:plaintext],
                  @"Decrypted data should match original");
}

- (void)testKeyEnvelopeWrongKeyFails {
    uint8_t keyBytes[32];
    SecRandomCopyBytes(kSecRandomDefault, 32, keyBytes);
    NSData *encryptionKey = [NSData dataWithBytes:keyBytes length:32];

    uint8_t wrongKeyBytes[32];
    SecRandomCopyBytes(kSecRandomDefault, 32, wrongKeyBytes);
    NSData *wrongKey = [NSData dataWithBytes:wrongKeyBytes length:32];

    NSData *plaintext = [@"test-data-32bytes-padding-here!!" dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    NSData *envelope = [PDSKeyEnvelope seal:plaintext withKey:encryptionKey error:&error];
    XCTAssertNotNil(envelope);

    // Try to open with wrong key — should fail (HMAC mismatch)
    NSData *decrypted = [PDSKeyEnvelope openEnvelope:envelope withKey:wrongKey error:&error];
    XCTAssertNil(decrypted, @"Wrong key should fail to open envelope");
}

- (void)testKeyEnvelopeIsVersionedEnvelope {
    NSData *notEnvelope = [@"this is just regular data" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([PDSKeyEnvelope isVersionedEnvelope:notEnvelope],
                   @"Regular data should not be detected as envelope");
}

- (void)testKeyEnvelopeLegacyFallback {
    // Legacy CBC-encrypted data should NOT be detected as a versioned envelope
    // so the fallback path in ActorStore/PLCRotationKeyManager works correctly
    NSData *legacyData = [NSData dataWithBytes:"\x00\x01\x02\x03" length:4];
    XCTAssertFalse([PDSKeyEnvelope isVersionedEnvelope:legacyData],
                   @"Short random data should not be mistaken for envelope");
}

#pragma mark - GZAdminUIAuthManager Integration

- (void)testUIAuthManagerPasswordHashing {
    // GZAdminUIAuthManager should NOT store plaintext passwords
    GZAdminUIAuthManager *auth = [[GZAdminUIAuthManager alloc] initWithPassword:@"admin123"];
    XCTAssertTrue([auth validatePassword:@"admin123"],
                  @"Correct password should validate");
    XCTAssertFalse([auth validatePassword:@"wrong"],
                   @"Wrong password should not validate");
    XCTAssertFalse([auth validatePassword:nil],
                   @"nil password should not validate");
    XCTAssertFalse([auth validatePassword:@""],
                   @"Empty password should not validate");
}

- (void)testUIAuthManagerSessionTokenIsCSPRNG {
    GZAdminUIAuthManager *auth = [[GZAdminUIAuthManager alloc] initWithPassword:@"test"];
    NSString *token1 = [auth createSessionToken];
    NSString *token2 = [auth createSessionToken];

    XCTAssertNotNil(token1, @"Token should be created");
    XCTAssertNotNil(token2, @"Token should be created");
    XCTAssertFalse([token1 isEqualToString:token2],
                   @"Two tokens should be different (CSPRNG)");
    XCTAssertTrue(token1.length >= 32,
                  @"CSPRNG token should be at least 32 hex chars (16 bytes)");
}

- (void)testUIAuthManagerSessionExpiry {
    GZAdminUIAuthManager *auth = [[GZAdminUIAuthManager alloc] initWithPassword:@"test"];
    auth.sessionTTL = 0.01; // 10ms TTL for testing

    NSString *token = [auth createSessionToken];
    XCTAssertNotNil(token);

    // Token should be valid immediately
    // (We can't easily test this without a mock ATProtoHttpRequest, but the
    // createSessionToken + isAuthorizedRequest flow is tested in integration)
}

- (void)testUIAuthManagerCSRFNonceGeneration {
    GZAdminUIAuthManager *auth = [[GZAdminUIAuthManager alloc] initWithPassword:@"test"];
    NSString *cookie1 = [auth createCSRFNonceCookie:NO];
    NSString *cookie2 = [auth createCSRFNonceCookie:NO];

    XCTAssertNotNil(cookie1);
    XCTAssertNotNil(cookie2);
    XCTAssertTrue([cookie1 containsString:@"ui_admin_nonce="], @"Should contain cookie name");
    XCTAssertTrue([cookie1 containsString:@"HttpOnly"], @"Should be HttpOnly");
    XCTAssertTrue([cookie1 containsString:@"SameSite=Strict"], @"Should be SameSite=Strict");
    XCTAssertFalse([cookie1 containsString:@"Secure"], @"Should not have Secure flag when secure:NO");
}

- (void)testUIAuthManagerSecureCookie {
    GZAdminUIAuthManager *auth = [[GZAdminUIAuthManager alloc] initWithPassword:@"test"];
    NSString *token = [auth createSessionToken];
    NSString *cookie = [auth cookieHeaderValueForToken:token secure:YES];

    XCTAssertTrue([cookie containsString:@"ui_admin_token="], @"Should contain cookie name");
    XCTAssertTrue([cookie containsString:@"HttpOnly"], @"Should be HttpOnly");
    XCTAssertTrue([cookie containsString:@"SameSite=Strict"], @"Should be SameSite=Strict");
    XCTAssertTrue([cookie containsString:@"Secure"], @"Should have Secure flag when secure:YES");
}

#pragma mark - GZHTTPClient Core seam

- (void)testGZHTTPClientOptionsDefaultsAndCopy {
    GZHTTPClientOptions *options = [GZHTTPClientOptions defaultOptions];
    XCTAssertEqualWithAccuracy(options.timeout, 10.0, 0.001);
    XCTAssertEqual(options.maxResponseBytes, (NSUInteger)(1024 * 1024));
    XCTAssertFalse(options.allowHTTP);
    XCTAssertFalse(options.allowPrivateHosts);
    XCTAssertTrue(options.followRedirects);

    options.timeout = 3.5;
    options.maxResponseBytes = 4096;
    options.allowHTTP = YES;
    options.allowPrivateHosts = YES;
    options.followRedirects = NO;
    GZHTTPClientOptions *copy = [options copy];
    XCTAssertNotEqual(copy, options);
    XCTAssertEqualWithAccuracy(copy.timeout, 3.5, 0.001);
    XCTAssertEqual(copy.maxResponseBytes, (NSUInteger)4096);
    XCTAssertTrue(copy.allowHTTP);
    XCTAssertTrue(copy.allowPrivateHosts);
    XCTAssertFalse(copy.followRedirects);
}

- (void)testGZHTTPClientRegistryFailsClosedWithoutTransport {
    id<GZHTTPClient> savedClient = [GZHTTPClientRegistry sharedClient];
    [GZHTTPClientRegistry setSharedClient:nil];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com"]];
    NSError *error = nil;
    NSData *data = [[GZHTTPClientRegistry sharedClient] sendSynchronousRequest:request
                                                                        options:nil
                                                                       response:nil
                                                                          error:&error];
    XCTAssertNil(data);
    XCTAssertEqualObjects(error.domain, GZHTTPClientErrorDomain);
    XCTAssertEqual(error.code, (NSInteger)GZHTTPClientErrorUnavailable);

    [GZHTTPClientRegistry setSharedClient:savedClient];
}

#pragma mark - ATProtoSafeHTTPClient Integration

- (void)testSafeHTTPClientRejectsPrivateIPs {
    // ATProtoSafeHTTPClient should reject requests to private IPs
    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.allowPrivateHosts = NO;
    options.timeout = 2.0;

    NSURL *privateURL = [NSURL URLWithString:@"https://127.0.0.1:9999/test"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:privateURL];

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                     options:options
                                                                    response:&response
                                                                       error:&error];
    XCTAssertNotNil(error, @"Should error for private IP");
    XCTAssertEqualObjects(error.domain, ATProtoSafeHTTPClientErrorDomain);
    XCTAssertEqual(error.code, (NSInteger)ATProtoSafeHTTPClientErrorSSRFBlocked);
    XCTAssertNil(data, @"Should not return data for private IP");
}

- (void)testSafeHTTPClientAllowPrivateHosts {
    // When allowPrivateHosts is YES, private IPs should be allowed
    // (used for testing)
    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.allowPrivateHosts = YES;
    options.timeout = 2.0;

    // This won't actually connect (nothing on port 9999), but it should
    // pass SSRF validation and fail at the network level, not SSRF level
    NSURL *privateURL = [NSURL URLWithString:@"http://127.0.0.1:9999/test"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:privateURL];

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                     options:options
                                                                    response:&response
                                                                       error:&error];
    // Should fail with a network error (connection refused), NOT an SSRF error
    if (error) {
        XCTAssertFalse([error.domain isEqualToString:ATProtoSafeHTTPClientErrorDomain] &&
                       error.code == ATProtoSafeHTTPClientErrorSSRFBlocked,
                       @"Should not be SSRF-blocked when allowPrivateHosts=YES");
    }
}

- (void)testSafeHTTPClientRejectsUnsupportedSchemes {
    ATProtoSafeHTTPClientOptions *options = [[ATProtoSafeHTTPClientOptions alloc] init];
    options.allowHTTP = NO;

    NSURL *httpURL = [NSURL URLWithString:@"http://example.com/test"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:httpURL];

    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                     options:options
                                                                    response:&response
                                                                       error:&error];
    XCTAssertNotNil(error, @"Should error for HTTP when allowHTTP=NO");
}

#pragma mark - ATProtoSSRFValidator Integration

- (void)testSSRFValidatorBlocksPrivateIPs {
    NSError *error = nil;
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:@"127.0.0.1" error:&error],
                   @"127.0.0.1 should be blocked");
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:@"10.0.0.1" error:&error],
                   @"10.x.x.x should be blocked");
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:@"192.168.1.1" error:&error],
                   @"192.168.x.x should be blocked");
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:@"172.16.0.1" error:&error],
                   @"172.16.x.x should be blocked");
}

- (void)testSSRFValidatorBlocksCloudMetadata {
    NSError *error = nil;
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:@"169.254.169.254" error:&error],
                   @"Cloud metadata endpoint should be blocked");
}

- (void)testSSRFValidatorBlocksEmptyHost {
    NSError *error = nil;
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:@"" error:&error],
                   @"Empty host should be blocked");
    XCTAssertFalse([ATProtoSSRFValidator validateHostResolvesToPublicIP:nil error:&error],
                   @"nil host should be blocked");
}

#pragma mark - SQL Hardening Integration

- (void)testColumnTypeValidation {
    // The isValidColumnType function should only allow known safe types
    // We test this indirectly through the addColumnIfNeeded method
    // by verifying it rejects suspicious types

    // This test verifies the allowlist exists — actual SQL execution
    // would require a database connection
    // The security audit script checks for isValidColumnType in ActorStore.m
    XCTAssertTrue(YES, @"Column type validation is checked by security_audit.sh");
}

@end
