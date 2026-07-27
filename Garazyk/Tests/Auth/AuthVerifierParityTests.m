// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Auth/Verifier/AuthVerifier.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"

@interface AuthParityAdminController : NSObject
@property (nonatomic, assign) BOOL takedownActive;
@property (nonatomic, assign) BOOL admin;
@end

@implementation AuthParityAdminController

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    return self.takedownActive;
}

- (BOOL)isAdmin:(NSString *)did error:(NSError **)error {
    return self.admin;
}

@end

@interface AuthParityAccountPolicy : NSObject <AccountPolicy>
@property (nonatomic, assign) BOOL accountAllowed;
@property (nonatomic, assign) BOOL admin;
@end

@implementation AuthParityAccountPolicy

- (BOOL)isAccountAllowed:(NSString *)did error:(NSError **)error {
    if (!self.accountAllowed && error) {
        *error = [NSError errorWithDomain:@"AuthParity" code:1 userInfo:nil];
    }
    return self.accountAllowed;
}

- (BOOL)isAdmin:(NSString *)did error:(NSError **)error {
    return self.admin;
}

@end

@interface AuthParitySessionRepository : NSObject
@property (nonatomic, assign) BOOL active;
@end

@implementation AuthParitySessionRepository

- (BOOL)isSessionActive:(NSString *)sid forAccountDid:(NSString *)did error:(NSError **)error {
    return self.active;
}

@end

@interface AuthVerifierParityTests : XCTestCase
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, strong) AuthVerifier *verifier;
@property (nonatomic, strong) AuthParityAdminController *adminController;
@property (nonatomic, strong) AuthParityAccountPolicy *accountPolicy;
@property (nonatomic, strong) AuthParitySessionRepository *sessionRepository;
@end

@implementation AuthVerifierParityTests

- (void)setUp {
    [super setUp];
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    self.minter = [[JWTMinter alloc] init];
    self.minter.issuer = @"https://pds.example.com";
    self.minter.audience = self.minter.issuer;
    self.minter.signingAlgorithm = @"ES256K";
    self.minter.privateKey = keyPair.privateKey;
    self.minter.publicKey = keyPair.publicKey;
    self.minter.defaultExpiration = 3600;

    self.adminController = [[AuthParityAdminController alloc] init];
    self.accountPolicy = [[AuthParityAccountPolicy alloc] init];
    self.accountPolicy.accountAllowed = YES;
    self.sessionRepository = [[AuthParitySessionRepository alloc] init];
    self.sessionRepository.active = YES;

    self.verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                accountPolicy:self.accountPolicy
                                                   nonceStore:nil];
    [self.verifier setLocalPublicKey:keyPair.publicKey];
    [self.verifier setLocalIssuer:self.minter.issuer];
    self.verifier.expectedAudience = self.minter.audience;
}

- (HttpRequest *)requestWithAuthorization:(NSString *)authorization dpop:(NSString *)dpop {
    NSMutableDictionary *headers = [@{
        @"Authorization": authorization,
        @"Host": @"pds.example.com"
    } mutableCopy];
    if (dpop) {
        headers[@"DPoP"] = dpop;
    }
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                        path:@"/xrpc/com.atproto.server.getSession"
                                 queryString:@""
                                 queryParams:@{}
                                     version:@"1.1"
                                     headers:headers
                                        body:nil
                               remoteAddress:@"127.0.0.1"];
}

- (NSString *)legacyDIDForAuthorization:(NSString *)authorization request:(HttpRequest *)request {
    return [XrpcAuthHelper extractDIDFromAuthHeader:authorization
                                          jwtMinter:self.minter
                                    adminController:(id)self.adminController
                                  sessionRepository:(id)self.sessionRepository
                                            request:request
                                           response:[[HttpResponse alloc] init]];
}

- (AuthVerifierPrincipal *)newPrincipalForAuthorization:(NSString *)authorization request:(HttpRequest *)request {
    NSError *error = nil;
    return [self.verifier verifyAuthHeader:authorization
                                dpopHeader:[request headerForKey:@"DPoP"]
                                   request:request
                                  response:[[HttpResponse alloc] init]
                                     error:&error];
}

- (void)assertParityForToken:(NSString *)token expectedDID:(nullable NSString *)expectedDID {
    NSString *authorization = [@"Bearer " stringByAppendingString:token];
    HttpRequest *request = [self requestWithAuthorization:authorization dpop:nil];
    NSString *legacyDID = [self legacyDIDForAuthorization:authorization request:request];
    AuthVerifierPrincipal *principal = [self newPrincipalForAuthorization:authorization request:request];
    XCTAssertEqualObjects(legacyDID, expectedDID);
    XCTAssertEqualObjects(principal.did, expectedDID);
}

- (void)testParityValidSessionToken {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                          sessionID:@"session-1"
                                  dpopKeyThumbprint:nil
                                               error:&error];
    XCTAssertNotNil(token, @"Token minting failed: %@", error);
    [self assertParityForToken:token.encodedToken expectedDID:@"did:plc:alice"];
}

- (void)testParityExpiredToken {
    NSError *error = nil;
    NSString *token = [self.minter signPayload:@{
        @"sub": @"did:plc:alice", @"iss": self.minter.issuer,
        @"aud": self.minter.audience,
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:-60] timeIntervalSince1970])
    } error:&error];
    XCTAssertNotNil(token, @"Token signing failed: %@", error);
    [self assertParityForToken:token expectedDID:nil];
}

- (void)testParitySuspendedAndTakenDownAccount {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                          sessionID:@"session-1"
                                  dpopKeyThumbprint:nil
                                               error:&error];
    XCTAssertNotNil(token);

    self.sessionRepository.active = NO;
    self.accountPolicy.accountAllowed = NO;
    [self assertParityForToken:token.encodedToken expectedDID:nil];

    self.sessionRepository.active = YES;
    self.adminController.takedownActive = YES;
    [self assertParityForToken:token.encodedToken expectedDID:nil];
}

- (void)testParityRejectsDpopBoundTokenWithoutProofAndOnRequestlessPath {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                  dpopKeyThumbprint:@"bound-thumbprint"
                                               error:&error];
    XCTAssertNotNil(token);
    [self assertParityForToken:token.encodedToken expectedDID:nil];

    NSError *verificationError = nil;
    XCTAssertNil([self.verifier verifyAccessToken:token.encodedToken error:&verificationError]);
    XCTAssertEqual(verificationError.code, AuthVerifierErrorDPoPRequired);
}

- (void)testParitySupportsDidWebSubjectAndCapturesAdminScope {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:web:pds.example.com%3A8443"
                                             handle:@"alice.example.com"
                                             scopes:@[@"admin:write"]
                                               error:&error];
    XCTAssertNotNil(token);
    self.accountPolicy.admin = YES;
    [self assertParityForToken:token.encodedToken expectedDID:@"did:web:pds.example.com%3A8443"];

    NSString *authorization = [@"Bearer " stringByAppendingString:token.encodedToken];
    AuthVerifierPrincipal *principal = [self newPrincipalForAuthorization:authorization
                                                                    request:[self requestWithAuthorization:authorization dpop:nil]];
    XCTAssertTrue(principal.isAdmin);
}

@end
