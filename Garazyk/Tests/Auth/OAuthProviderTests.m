// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/OAuthProvider/OAuthProvider.h"
#import "Auth/OAuthProvider/OAuthProviderProtocols.h"

#pragma mark - Mock Storage

@interface MockOAuthProviderStorage : NSObject <OAuthProviderStorage>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *storedPARs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *storedCodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *storedRefreshTokens;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *revokedTokens;
@end

@implementation MockOAuthProviderStorage

- (instancetype)init {
    self = [super init];
    if (self) {
        _storedPARs = [NSMutableDictionary dictionary];
        _storedCodes = [NSMutableDictionary dictionary];
        _storedRefreshTokens = [NSMutableDictionary dictionary];
        _revokedTokens = [NSMutableArray array];
    }
    return self;
}

- (BOOL)storePAR:(NSDictionary *)par forRequestURI:(NSString *)requestURI expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    self.storedPARs[requestURI] = [@{@"data": par, @"expires": expiresAt} mutableCopy];
    return YES;
}

- (nullable NSDictionary *)loadPARForRequestURI:(NSString *)requestURI error:(NSError **)error {
    return self.storedPARs[requestURI][@"data"];
}

- (BOOL)deletePARForRequestURI:(NSString *)requestURI error:(NSError **)error {
    [self.storedPARs removeObjectForKey:requestURI];
    return YES;
}

- (BOOL)storeAuthCode:(NSString *)code data:(NSDictionary *)data expiresAt:(NSDate *)expiresAt error:(NSError **)error {
    self.storedCodes[code] = data;
    return YES;
}

- (nullable NSDictionary *)consumeAuthCode:(NSString *)code error:(NSError **)error {
    NSDictionary *data = self.storedCodes[code];
    if (data) {
        [self.storedCodes removeObjectForKey:code];
    }
    return data;
}

- (BOOL)storeRefreshToken:(NSString *)tokenID data:(NSDictionary *)data error:(NSError **)error {
    self.storedRefreshTokens[tokenID] = data;
    return YES;
}

- (nullable NSDictionary *)loadRefreshToken:(NSString *)tokenID error:(NSError **)error {
    return self.storedRefreshTokens[tokenID];
}

- (BOOL)rotateRefreshToken:(NSString *)oldTokenID toNewToken:(NSString *)newTokenID withData:(NSDictionary *)newData error:(NSError **)error {
    [self.storedRefreshTokens removeObjectForKey:oldTokenID];
    self.storedRefreshTokens[newTokenID] = newData;
    return YES;
}

- (BOOL)revokeRefreshToken:(NSString *)tokenID error:(NSError **)error {
    [self.storedRefreshTokens removeObjectForKey:tokenID];
    [self.revokedTokens addObject:@{@"token": tokenID ?: @""}];
    return YES;
}

- (BOOL)hasConsentForAccountDID:(NSString *)accountDID clientID:(NSString *)clientID scope:(NSString *)scope error:(NSError **)error {
    return NO;
}

- (BOOL)recordConsentForAccountDID:(NSString *)accountDID clientID:(NSString *)clientID scope:(NSString *)scope error:(NSError **)error {
    return YES;
}

@end

#pragma mark - Mock Client Registry

@interface MockOAuthProviderClientRegistry : NSObject <OAuthProviderClientRegistry>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *clients;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray *> *allowedRedirectURIs;
@end

@implementation MockOAuthProviderClientRegistry

- (instancetype)init {
    self = [super init];
    if (self) {
        _clients = [NSMutableDictionary dictionary];
        _allowedRedirectURIs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable NSDictionary *)getClientByID:(NSString *)clientID error:(NSError **)error {
    NSDictionary *client = self.clients[clientID];
    if (!client && error) {
        *error = [NSError errorWithDomain:OAuthProviderErrorDomain
                                     code:OAuthProviderErrorInvalidClient
                                 userInfo:@{NSLocalizedDescriptionKey: @"Client not found"}];
    }
    return client;
}

- (BOOL)validateRedirectURI:(NSString *)redirectURI forClient:(NSDictionary *)client error:(NSError **)error {
    NSString *clientID = client[@"client_id"];
    NSArray *allowed = self.allowedRedirectURIs[clientID];
    if ([allowed containsObject:redirectURI]) return YES;
    if (error) {
        *error = [NSError errorWithDomain:OAuthProviderErrorDomain
                                     code:OAuthProviderErrorInvalidRedirectURI
                                 userInfo:@{NSLocalizedDescriptionKey: @"Invalid redirect_uri"}];
    }
    return NO;
}

@end

#pragma mark - Mock Token Signer

@interface MockOAuthProviderTokenSigner : NSObject <OAuthProviderTokenSigner>
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSDictionary *jwks;
@property (nonatomic, assign) BOOL shouldFailMinting;
@end

@implementation MockOAuthProviderTokenSigner

- (instancetype)init {
    self = [super init];
    if (self) {
        _issuer = @"https://test.example.com";
        _jwks = @{};
        _shouldFailMinting = NO;
    }
    return self;
}

- (nullable NSString *)mintAccessTokenWithClaims:(NSDictionary *)claims error:(NSError **)error {
    if (self.shouldFailMinting) {
        if (error) *error = [NSError errorWithDomain:OAuthProviderErrorDomain code:OAuthProviderErrorServerError userInfo:@{NSLocalizedDescriptionKey: @"Signing failed"}];
        return nil;
    }
    return [NSString stringWithFormat:@"access_token_%@", claims[@"sub"] ?: @"unknown"];
}

- (nullable NSString *)mintRefreshTokenWithClaims:(NSDictionary *)claims error:(NSError **)error {
    if (self.shouldFailMinting) {
        if (error) *error = [NSError errorWithDomain:OAuthProviderErrorDomain code:OAuthProviderErrorServerError userInfo:@{NSLocalizedDescriptionKey: @"Signing failed"}];
        return nil;
    }
    return [NSString stringWithFormat:@"refresh_token_%@", claims[@"sub"] ?: @"unknown"];
}

- (nullable NSDictionary *)verifyAccessToken:(NSString *)token forAudience:(NSString *)audience error:(NSError **)error {
    if ([token hasPrefix:@"access_token_"]) {
        NSString *sub = [token stringByReplacingOccurrencesOfString:@"access_token_" withString:@""];
        return @{@"sub": sub, @"aud": audience, @"client_id": @"test-client", @"iat": @([[NSDate date] timeIntervalSince1970]), @"exp": @([[NSDate date] timeIntervalSince1970] + 3600)};
    }
    return nil;
}

- (nullable NSDictionary *)verifyRefreshToken:(NSString *)token error:(NSError **)error {
    if ([token hasPrefix:@"refresh_token_"]) {
        NSString *sub = [token stringByReplacingOccurrencesOfString:@"refresh_token_" withString:@""];
        return @{@"sub": sub, @"client_id": @"test-client", @"iat": @([[NSDate date] timeIntervalSince1970])};
    }
    return nil;
}

@end

#pragma mark - Mock User Authenticator

@interface MockOAuthProviderUserAuthenticator : NSObject <OAuthProviderUserAuthenticator>
@end

@implementation MockOAuthProviderUserAuthenticator

- (nullable NSString *)authenticateLogin:(NSString *)login password:(NSString *)password tfaCode:(nullable NSString *)tfaCode error:(NSError **)error {
    return @"did:plc:test123";
}

- (nullable NSString *)handleForDID:(NSString *)did error:(NSError **)error {
    return @"user.example.com";
}

@end

#pragma mark - Tests

@interface OAuthProviderTests : XCTestCase
@property (nonatomic, strong) MockOAuthProviderStorage *storage;
@property (nonatomic, strong) MockOAuthProviderClientRegistry *clientRegistry;
@property (nonatomic, strong) MockOAuthProviderTokenSigner *tokenSigner;
@property (nonatomic, strong) MockOAuthProviderUserAuthenticator *userAuthenticator;
@property (nonatomic, strong) OAuthProviderServer *server;
@end

@implementation OAuthProviderTests

- (void)setUp {
    [super setUp];
    self.storage = [[MockOAuthProviderStorage alloc] init];
    self.clientRegistry = [[MockOAuthProviderClientRegistry alloc] init];
    self.tokenSigner = [[MockOAuthProviderTokenSigner alloc] init];
    self.userAuthenticator = [[MockOAuthProviderUserAuthenticator alloc] init];

    self.clientRegistry.clients[@"test-client"] = @{
        @"client_id": @"test-client",
        @"redirect_uris": @[@"https://app.example.com/callback"],
        @"token_endpoint_auth_method": @"private_key_jwt"
    };
    self.clientRegistry.allowedRedirectURIs[@"test-client"] = @[@"https://app.example.com/callback"];

    self.server = [[OAuthProviderServer alloc] initWithStorage:self.storage
                                                clientRegistry:self.clientRegistry
                                                  tokenSigner:self.tokenSigner
                                          userAuthenticator:self.userAuthenticator
                                                didResolver:nil
                                            handleResolver:nil];
    self.server.issuer = @"https://test.example.com";
}

#pragma mark - Model Instantiation

- (void)testAuthorizationRequestDefaults {
    OAuthProviderAuthorizationRequest *req = [[OAuthProviderAuthorizationRequest alloc] init];
    req.clientID = @"client-1";
    req.redirectURI = @"https://example.com/cb";
    req.responseType = @"code";
    XCTAssertNotNil(req);
    XCTAssertEqualObjects(req.clientID, @"client-1");
}

- (void)testTokenResponseDefaults {
    OAuthProviderTokenResponse *resp = [[OAuthProviderTokenResponse alloc] init];
    resp.accessToken = @"at";
    resp.refreshToken = @"rt";
    resp.tokenType = @"Bearer";
    resp.expiresIn = 3600;
    XCTAssertEqualObjects(resp.tokenType, @"Bearer");
    XCTAssertEqual(resp.expiresIn, 3600);
}

- (void)testTokenRequestDefaults {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    req.authorizationCode = @"auth-code-1";
    req.redirectURI = @"https://example.com/cb";
    XCTAssertEqualObjects(req.grantType, @"authorization_code");
}

- (void)testAuthorizationResponseDefaults {
    OAuthProviderAuthorizationResponse *resp = [[OAuthProviderAuthorizationResponse alloc] init];
    resp.state = @"my-state";
    resp.authorizationCode = @"code-123";
    XCTAssertEqualObjects(resp.state, @"my-state");
    XCTAssertEqualObjects(resp.authorizationCode, @"code-123");
}

#pragma mark - Client Metadata Parsing

- (void)testClientMetadataFromValidDictionary {
    NSDictionary *dict = @{
        @"client_id": @"my-client",
        @"redirect_uris": @[@"https://example.com/cb"],
        @"token_endpoint_auth_method": @"private_key_jwt"
    };
    NSError *error = nil;
    OAuthProviderClientMetadata *metadata = [OAuthProviderClientMetadata metadataFromDictionary:dict error:&error];
    XCTAssertNotNil(metadata);
    XCTAssertNil(error);
    XCTAssertEqualObjects(metadata.clientID, @"my-client");
    XCTAssertEqualObjects(metadata.redirectURIs.firstObject, @"https://example.com/cb");
}

- (void)testClientMetadataMissingClientID {
    NSDictionary *dict = @{@"redirect_uris": @[@"https://example.com/cb"]};
    NSError *error = nil;
    OAuthProviderClientMetadata *metadata = [OAuthProviderClientMetadata metadataFromDictionary:dict error:&error];
    XCTAssertNil(metadata);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, OAuthProviderErrorInvalidClient);
}

- (void)testClientMetadataMissingRedirectURIs {
    NSDictionary *dict = @{@"client_id": @"my-client"};
    NSError *error = nil;
    OAuthProviderClientMetadata *metadata = [OAuthProviderClientMetadata metadataFromDictionary:dict error:&error];
    XCTAssertNil(metadata);
    XCTAssertNotNil(error);
}

- (void)testClientMetadataToDictionaryRoundTrip {
    NSDictionary *dict = @{
        @"client_id": @"my-client",
        @"redirect_uris": @[@"https://example.com/cb"],
        @"token_endpoint_auth_method": @"none",
        @"client_name": @"Test App"
    };
    NSError *error = nil;
    OAuthProviderClientMetadata *metadata = [OAuthProviderClientMetadata metadataFromDictionary:dict error:&error];
    XCTAssertNotNil(metadata);

    NSDictionary *output = [metadata toDictionary];
    XCTAssertEqualObjects(output[@"client_id"], @"my-client");
    XCTAssertEqualObjects(output[@"client_name"], @"Test App");
    XCTAssertNotNil(output[@"redirect_uris"]);
    // Optional fields with nil values should not appear
    XCTAssertNil(output[@"logo_uri"]);
}

#pragma mark - Server Metadata

- (void)testServerMetadataContainsRequiredFields {
    NSDictionary *metadata = [self.server serverMetadata];
    XCTAssertEqualObjects(metadata[@"issuer"], @"https://test.example.com");
    XCTAssertEqualObjects(metadata[@"authorization_endpoint"], @"https://test.example.com/oauth/authorize");
    XCTAssertEqualObjects(metadata[@"token_endpoint"], @"https://test.example.com/oauth/token");
    XCTAssertEqualObjects(metadata[@"jwks_uri"], @"https://test.example.com/.well-known/jwks.json");
    XCTAssertNotNil(metadata[@"response_types_supported"]);
    XCTAssertNotNil(metadata[@"grant_types_supported"]);
    XCTAssertNotNil(metadata[@"token_endpoint_auth_methods_supported"]);
    XCTAssertNotNil(metadata[@"code_challenge_methods_supported"]);
}

- (void)testServerMetadataDefaultIssuer {
    OAuthProviderServer *server = [[OAuthProviderServer alloc] initWithStorage:self.storage
                                                              clientRegistry:self.clientRegistry
                                                                tokenSigner:self.tokenSigner
                                                        userAuthenticator:self.userAuthenticator
                                                              didResolver:nil
                                                          handleResolver:nil];
    // issuer is nil by default
    NSDictionary *metadata = [server serverMetadata];
    XCTAssertEqualObjects(metadata[@"issuer"], @"https://example.com");
}

#pragma mark - PAR Processing

- (void)testProcessPARMissingClientID {
    NSDictionary *requestData = @{@"response_type": @"code"};
    XCTestExpectation *expectation = [self expectationWithDescription:@"PAR completion"];
    [self.server processPAR:requestData completion:^(NSString *requestURI, NSDate *expiresIn, NSError *error) {
        XCTAssertNil(requestURI);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidRequest);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessPARUnsupportedResponseType {
    NSDictionary *requestData = @{@"client_id": @"test-client", @"response_type": @"token"};
    XCTestExpectation *expectation = [self expectationWithDescription:@"PAR completion"];
    [self.server processPAR:requestData completion:^(NSString *requestURI, NSDate *expiresIn, NSError *error) {
        XCTAssertNil(requestURI);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorUnsupportedResponseType);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessPARUnknownClient {
    NSDictionary *requestData = @{@"client_id": @"unknown", @"response_type": @"code"};
    XCTestExpectation *expectation = [self expectationWithDescription:@"PAR completion"];
    [self.server processPAR:requestData completion:^(NSString *requestURI, NSDate *expiresIn, NSError *error) {
        XCTAssertNil(requestURI);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidClient);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessPARSuccess {
    NSDictionary *requestData = @{
        @"client_id": @"test-client",
        @"response_type": @"code",
        @"redirect_uri": @"https://app.example.com/callback"
    };
    XCTestExpectation *expectation = [self expectationWithDescription:@"PAR completion"];
    [self.server processPAR:requestData completion:^(NSString *requestURI, NSDate *expiresIn, NSError *error) {
        XCTAssertNotNil(requestURI);
        XCTAssertNil(error);
        XCTAssertTrue([requestURI hasPrefix:@"urn:ietf:params:oauth:request_uri:"]);
        XCTAssertNotNil(expiresIn);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessPARInvalidRedirectURI {
    self.clientRegistry.allowedRedirectURIs[@"test-client"] = @[@"https://app.example.com/correct"];
    NSDictionary *requestData = @{
        @"client_id": @"test-client",
        @"response_type": @"code",
        @"redirect_uri": @"https://evil.example.com/steal"
    };
    XCTestExpectation *expectation = [self expectationWithDescription:@"PAR completion"];
    [self.server processPAR:requestData completion:^(NSString *requestURI, NSDate *expiresIn, NSError *error) {
        XCTAssertNil(requestURI);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidRedirectURI);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

#pragma mark - Authorization Request

- (void)testProcessAuthorizationMissingParams {
    OAuthProviderAuthorizationRequest *req = [[OAuthProviderAuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    // missing redirectURI and responseType
    XCTestExpectation *expectation = [self expectationWithDescription:@"auth completion"];
    [self.server processAuthorizationRequest:req completion:^(NSURL *redirectURI, NSString *authCode, NSError *error) {
        XCTAssertNil(redirectURI);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidRequest);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessAuthorizationUnsupportedResponseType {
    OAuthProviderAuthorizationRequest *req = [[OAuthProviderAuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"https://app.example.com/callback";
    req.responseType = @"token";
    XCTestExpectation *expectation = [self expectationWithDescription:@"auth completion"];
    [self.server processAuthorizationRequest:req completion:^(NSURL *redirectURI, NSString *authCode, NSError *error) {
        XCTAssertNil(redirectURI);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorUnsupportedResponseType);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessAuthorizationSuccess {
    OAuthProviderAuthorizationRequest *req = [[OAuthProviderAuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"https://app.example.com/callback";
    req.responseType = @"code";
    req.state = @"my-state";
    req.scope = @"atproto";

    XCTestExpectation *expectation = [self expectationWithDescription:@"auth completion"];
    [self.server processAuthorizationRequest:req completion:^(NSURL *redirectURI, NSString *authCode, NSError *error) {
        XCTAssertNotNil(redirectURI);
        XCTAssertNotNil(authCode);
        XCTAssertNil(error);
        // Verify redirect contains code and state
        NSString *urlString = redirectURI.absoluteString;
        XCTAssertTrue([urlString containsString:@"code="]);
        XCTAssertTrue([urlString containsString:@"state=my-state"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessAuthorizationWithIssuerAddsIssParam {
    self.server.issuer = @"https://test.example.com";
    OAuthProviderAuthorizationRequest *req = [[OAuthProviderAuthorizationRequest alloc] init];
    req.clientID = @"test-client";
    req.redirectURI = @"https://app.example.com/callback";
    req.responseType = @"code";

    XCTestExpectation *expectation = [self expectationWithDescription:@"auth completion"];
    [self.server processAuthorizationRequest:req completion:^(NSURL *redirectURI, NSString *authCode, NSError *error) {
        XCTAssertNotNil(redirectURI);
        XCTAssertTrue([redirectURI.absoluteString containsString:@"iss="]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

#pragma mark - Token Exchange

- (void)testProcessTokenMissingGrantType {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    XCTestExpectation *expectation = [self expectationWithDescription:@"token completion"];
    [self.server processTokenRequest:req completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidRequest);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenUnsupportedGrantType {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    req.grantType = @"implicit";
    XCTestExpectation *expectation = [self expectationWithDescription:@"token completion"];
    [self.server processTokenRequest:req completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorUnsupportedGrantType);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenAuthCodeGrantMissingParams {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    // Missing authorization_code and redirect_uri
    XCTestExpectation *expectation = [self expectationWithDescription:@"token completion"];
    [self.server processTokenRequest:req completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidGrant);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenAuthCodeGrantInvalidCode {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    req.grantType = @"authorization_code";
    req.authorizationCode = @"nonexistent-code";
    req.redirectURI = @"https://app.example.com/callback";
    req.clientID = @"test-client";

    XCTestExpectation *expectation = [self expectationWithDescription:@"token completion"];
    [self.server processTokenRequest:req completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidGrant);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenAuthCodeGrantSuccess {
    // First authorize to get a valid code
    OAuthProviderAuthorizationRequest *authReq = [[OAuthProviderAuthorizationRequest alloc] init];
    authReq.clientID = @"test-client";
    authReq.redirectURI = @"https://app.example.com/callback";
    authReq.responseType = @"code";
    authReq.scope = @"atproto";
    authReq.state = @"test-state";

    XCTestExpectation *authExpectation = [self expectationWithDescription:@"auth"];
    __block NSString *authCode;
    [self.server processAuthorizationRequest:authReq completion:^(NSURL *redirectURI, NSString *code, NSError *error) {
        authCode = code;
        [authExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertNotNil(authCode);

    // Exchange the code for tokens
    OAuthProviderTokenRequest *tokenReq = [[OAuthProviderTokenRequest alloc] init];
    tokenReq.grantType = @"authorization_code";
    tokenReq.authorizationCode = authCode;
    tokenReq.redirectURI = @"https://app.example.com/callback";
    tokenReq.clientID = @"test-client";

    XCTestExpectation *tokenExpectation = [self expectationWithDescription:@"token"];
    [self.server processTokenRequest:tokenReq completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNotNil(response);
        XCTAssertNil(error);
        XCTAssertNotNil(response.accessToken);
        XCTAssertNotNil(response.refreshToken);
        XCTAssertEqualObjects(response.tokenType, @"Bearer");
        XCTAssertEqual(response.expiresIn, 3600);
        XCTAssertEqualObjects(response.scope, @"atproto");
        [tokenExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenAuthCodeGrantRedirectURIMismatch {
    OAuthProviderAuthorizationRequest *authReq = [[OAuthProviderAuthorizationRequest alloc] init];
    authReq.clientID = @"test-client";
    authReq.redirectURI = @"https://app.example.com/callback";
    authReq.responseType = @"code";

    XCTestExpectation *authExpectation = [self expectationWithDescription:@"auth"];
    __block NSString *authCode;
    [self.server processAuthorizationRequest:authReq completion:^(NSURL *redirectURI, NSString *code, NSError *error) {
        authCode = code;
        [authExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    OAuthProviderTokenRequest *tokenReq = [[OAuthProviderTokenRequest alloc] init];
    tokenReq.grantType = @"authorization_code";
    tokenReq.authorizationCode = authCode;
    tokenReq.redirectURI = @"https://evil.example.com/different";
    tokenReq.clientID = @"test-client";

    XCTestExpectation *tokenExpectation = [self expectationWithDescription:@"token"];
    [self.server processTokenRequest:tokenReq completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidGrant);
        [tokenExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenRefreshGrantMissingToken {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    req.grantType = @"refresh_token";
    // Missing refresh_token
    XCTestExpectation *expectation = [self expectationWithDescription:@"token completion"];
    [self.server processTokenRequest:req completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        XCTAssertEqual(error.code, OAuthProviderErrorInvalidGrant);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testProcessTokenRefreshGrantInvalidToken {
    OAuthProviderTokenRequest *req = [[OAuthProviderTokenRequest alloc] init];
    req.grantType = @"refresh_token";
    req.refreshToken = @"invalid-refresh-token";

    XCTestExpectation *expectation = [self expectationWithDescription:@"token completion"];
    [self.server processTokenRequest:req completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testTokenMintingFailure {
    self.tokenSigner.shouldFailMinting = YES;

    OAuthProviderAuthorizationRequest *authReq = [[OAuthProviderAuthorizationRequest alloc] init];
    authReq.clientID = @"test-client";
    authReq.redirectURI = @"https://app.example.com/callback";
    authReq.responseType = @"code";

    XCTestExpectation *authExpectation = [self expectationWithDescription:@"auth"];
    __block NSString *authCode;
    [self.server processAuthorizationRequest:authReq completion:^(NSURL *redirectURI, NSString *code, NSError *error) {
        authCode = code;
        [authExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    OAuthProviderTokenRequest *tokenReq = [[OAuthProviderTokenRequest alloc] init];
    tokenReq.grantType = @"authorization_code";
    tokenReq.authorizationCode = authCode;
    tokenReq.redirectURI = @"https://app.example.com/callback";
    tokenReq.clientID = @"test-client";

    XCTestExpectation *tokenExpectation = [self expectationWithDescription:@"token"];
    [self.server processTokenRequest:tokenReq completion:^(OAuthProviderTokenResponse *response, NSError *error) {
        XCTAssertNil(response);
        XCTAssertNotNil(error);
        [tokenExpectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

#pragma mark - Token Introspection

- (void)testIntrospectActiveToken {
    NSString *accessToken = @"access_token_did:plc:test123";
    XCTestExpectation *expectation = [self expectationWithDescription:@"introspect"];
    [self.server introspectToken:accessToken completion:^(NSDictionary *introspection, NSError *error) {
        XCTAssertNotNil(introspection);
        XCTAssertNil(error);
        XCTAssertEqualObjects(introspection[@"active"], @YES);
        XCTAssertEqualObjects(introspection[@"sub"], @"did:plc:test123");
        XCTAssertNotNil(introspection[@"exp"]);
        XCTAssertNotNil(introspection[@"iat"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

- (void)testIntrospectInvalidToken {
    XCTestExpectation *expectation = [self expectationWithDescription:@"introspect"];
    [self.server introspectToken:@"invalid-token" completion:^(NSDictionary *introspection, NSError *error) {
        XCTAssertNotNil(introspection);
        XCTAssertEqualObjects(introspection[@"active"], @NO);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
}

#pragma mark - Token Revocation

- (void)testRevokeTokenCallsStorage {
    XCTestExpectation *expectation = [self expectationWithDescription:@"revoke"];
    [self.server revokeToken:@"some-token" tokenTypeHint:@"refresh_token" completion:^(NSError *error) {
        XCTAssertNil(error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertEqual(self.storage.revokedTokens.count, 1u);
}

#pragma mark - Error Domain

- (void)testErrorDomainConstant {
    XCTAssertEqualObjects(OAuthProviderErrorDomain, @"com.atproto.oauthprovider");
}

@end
