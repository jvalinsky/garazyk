// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/OAuthClientAuthPolicy.h"

@interface OAuthClientAuthPolicyTests : XCTestCase
@end

@implementation OAuthClientAuthPolicyTests

#pragma mark - Supported Methods

- (void)testSupportedTokenEndpointAuthMethodsLegacyEnabled {
    // In DEBUG builds, legacyOAuthEnabled returns YES
#ifdef DEBUG
    NSArray *methods = [OAuthClientAuthPolicy supportedTokenEndpointAuthMethods];
    XCTAssertTrue([methods containsObject:@"none"]);
    XCTAssertTrue([methods containsObject:@"private_key_jwt"]);
    XCTAssertTrue([methods containsObject:@"client_secret_post"]);
    XCTAssertTrue([methods containsObject:@"client_secret_basic"]);
    XCTAssertEqual(methods.count, 4u);
#endif
}

- (void)testSupportedGrantTypesLegacyEnabled {
#ifdef DEBUG
    NSArray *types = [OAuthClientAuthPolicy supportedGrantTypes];
    XCTAssertTrue([types containsObject:@"authorization_code"]);
    XCTAssertTrue([types containsObject:@"refresh_token"]);
    XCTAssertTrue([types containsObject:@"client_credentials"]);
    XCTAssertEqual(types.count, 3u);
#endif
}

- (void)testLegacyOAuthEnabled {
#ifdef DEBUG
    XCTAssertTrue([OAuthClientAuthPolicy legacyOAuthEnabled]);
#endif
}

#pragma mark - Client Secret Validation

- (void)testValidateClientSecretMatching {
    XCTAssertTrue([OAuthClientAuthPolicy validateClientSecret:@"secret123" againstExpected:@"secret123"]);
}

- (void)testValidateClientSecretMismatch {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"wrong" againstExpected:@"correct"]);
}

- (void)testValidateClientSecretProvidedNil {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:nil againstExpected:@"expected"]);
}

- (void)testValidateClientSecretExpectedNil {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"provided" againstExpected:nil]);
}

- (void)testValidateClientSecretBothNil {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:nil againstExpected:nil]);
}

- (void)testValidateClientSecretEmptyProvided {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"" againstExpected:@"expected"]);
}

- (void)testValidateClientSecretEmptyExpected {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"provided" againstExpected:@""]);
}

- (void)testValidateClientSecretBothEmpty {
    XCTAssertFalse([OAuthClientAuthPolicy validateClientSecret:@"" againstExpected:@""]);
}

- (void)testValidateClientSecretLongStrings {
    NSString *longSecret = [@"" stringByPaddingToLength:1000 withString:@"a" startingAtIndex:0];
    XCTAssertTrue([OAuthClientAuthPolicy validateClientSecret:longSecret againstExpected:longSecret]);
}

#pragma mark - Client Metadata Validation

- (void)testValidateClientMetadataMissingAuthMethod {
    NSDictionary *metadata = @{
        @"client_id": @"test-client",
        @"redirect_uris": @[@"https://example.com/cb"]
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"token_endpoint_auth_method"]);
}

- (void)testValidateClientMetadataUnsupportedAuthMethod {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"client_secret_jwt"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testValidateClientMetadataPublicClientValid {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"none"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testValidateClientMetadataPublicClientWithJWKSRejected {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"none",
        @"jwks": @{@"kty": @"EC", @"crv": @"P-256"}
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testValidateClientMetadataPublicClientWithJWKSURIRejected {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"none",
        @"jwks_uri": @"https://example.com/jwks"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testValidateClientMetadataPublicClientWithSigningAlgRejected {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"none",
        @"token_endpoint_auth_signing_alg": @"ES256"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testValidateClientMetadataPrivateKeyJWTRequiresJWKS {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"token_endpoint_auth_signing_alg": @"ES256"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"jwks"]);
}

- (void)testValidateClientMetadataPrivateKeyJWTRequiresExactlyOneJWKS {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"jwks": @{@"kty": @"EC"},
        @"jwks_uri": @"https://example.com/jwks",
        @"token_endpoint_auth_signing_alg": @"ES256"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
}

- (void)testValidateClientMetadataPrivateKeyJWTWithInlineJWKS {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"jwks": @{@"kty": @"EC", @"crv": @"P-256"},
        @"token_endpoint_auth_signing_alg": @"ES256"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertTrue(result);
}

- (void)testValidateClientMetadataPrivateKeyJWTWithJWKSURI {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"jwks_uri": @"https://example.com/jwks",
        @"token_endpoint_auth_signing_alg": @"ES256"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertTrue(result);
}

- (void)testValidateClientMetadataPrivateKeyJWTWrongAlg {
    NSDictionary *metadata = @{
        @"token_endpoint_auth_method": @"private_key_jwt",
        @"jwks": @{@"kty": @"EC"},
        @"token_endpoint_auth_signing_alg": @"RS256"
    };
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateClientMetadata:metadata error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"ES256"]);
}

#pragma mark - Request Parameter Validation

- (void)testValidateRequestParametersMissingDPoP {
    NSDictionary *params = @{};
    NSDictionary *client = @{@"token_endpoint_auth_method": @"none"};
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:NO error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"DPoP"]);
}

- (void)testValidateRequestParametersPrivateKeyJWTMissingAssertion {
    NSDictionary *params = @{};
    NSDictionary *client = @{@"token_endpoint_auth_method": @"private_key_jwt"};
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:YES error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"client_assertion"]);
}

- (void)testValidateRequestParametersPrivateKeyJWTWithAssertion {
    NSDictionary *params = @{@"client_assertion": @"jwt-assertion"};
    NSDictionary *client = @{@"token_endpoint_auth_method": @"private_key_jwt"};
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:YES error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testValidateRequestParametersPublicClientNoAssertion {
    NSDictionary *params = @{};
    NSDictionary *client = @{@"token_endpoint_auth_method": @"none"};
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:YES error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

- (void)testValidateRequestParametersPublicClientWithAssertionRejected {
    NSDictionary *params = @{@"client_assertion": @"some-jwt"};
    NSDictionary *client = @{@"token_endpoint_auth_method": @"none"};
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:YES error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"Public clients must not send client_assertion"]);
}

- (void)testValidateRequestParametersClientSecretInNonLegacyRejected {
#ifdef DEBUG
    NSDictionary *params = @{@"client_secret": @"secret"};
    NSDictionary *client = @{@"token_endpoint_auth_method": @"client_secret_basic"};
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:YES error:&error];
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.userInfo[NSLocalizedDescriptionKey] containsString:@"client_secret is not supported"]);
#endif
}

- (void)testValidateRequestParametersClientMetadataInheritsNone {
    NSDictionary *params = @{};
    NSDictionary *client = @{};  // No auth method set, defaults to "none"
    NSError *error = nil;
    BOOL result = [OAuthClientAuthPolicy validateRequestParameters:params client:client hasDPoPProof:YES error:&error];
    XCTAssertTrue(result);
    XCTAssertNil(error);
}

@end
