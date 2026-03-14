// Tests for AuthVerifier and AuthVerifierPrincipal.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "AuthVerifier/AuthVerifier.h"

// ---------------------------------------------------------------------------
// Minimal AccountPolicy stub — always says the account is valid and not admin.
// ---------------------------------------------------------------------------

@interface AlwaysValidAccountPolicy : NSObject <AccountPolicy>
@end

@implementation AlwaysValidAccountPolicy

- (BOOL)isAccountTakenDown:(NSString *)did {
    return NO;
}

- (BOOL)isAccountAdmin:(NSString *)did {
    return NO;
}

@end

// ---------------------------------------------------------------------------

@interface AuthVerifierTests : XCTestCase
@end

@implementation AuthVerifierTests

#pragma mark - AuthVerifierPrincipal

- (void)testPrincipalInitStoresDID {
    AuthVerifierPrincipal *p = [[AuthVerifierPrincipal alloc]
                                initWithDID:@"did:plc:alice"
                             accessTokenJWT:nil
                                tokenClaims:nil
                             dpopThumbprint:nil
                                   usedDPoP:NO
                                    isAdmin:NO];
    XCTAssertEqualObjects(p.did, @"did:plc:alice");
}

- (void)testPrincipalInitStoresAdminFlag {
    AuthVerifierPrincipal *admin = [[AuthVerifierPrincipal alloc]
                                    initWithDID:@"did:plc:admin"
                                 accessTokenJWT:nil
                                    tokenClaims:nil
                                 dpopThumbprint:nil
                                       usedDPoP:NO
                                        isAdmin:YES];
    XCTAssertTrue(admin.isAdmin, @"isAdmin must reflect constructor argument");
}

- (void)testPrincipalInitStoresDPoPFlag {
    AuthVerifierPrincipal *p = [[AuthVerifierPrincipal alloc]
                                initWithDID:@"did:plc:dpop"
                             accessTokenJWT:@"eyXxx"
                                tokenClaims:nil
                             dpopThumbprint:@"abcthumb"
                                   usedDPoP:YES
                                    isAdmin:NO];
    XCTAssertTrue(p.usedDPoP);
    XCTAssertEqualObjects(p.dpopThumbprint, @"abcthumb");
}

- (void)testPrincipalInitStoresTokenClaims {
    NSDictionary *claims = @{@"sub": @"did:plc:test", @"iat": @1234567890};
    AuthVerifierPrincipal *p = [[AuthVerifierPrincipal alloc]
                                initWithDID:@"did:plc:test"
                             accessTokenJWT:nil
                                tokenClaims:claims
                             dpopThumbprint:nil
                                   usedDPoP:NO
                                    isAdmin:NO];
    XCTAssertEqualObjects(p.tokenClaims[@"sub"], @"did:plc:test");
}

#pragma mark - AuthVerifier initialization

- (void)testVerifierInitWithPolicySucceeds {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    XCTAssertNotNil(verifier, @"AuthVerifier must initialize successfully");
}

- (void)testVerifierStoresExpectedAudience {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    verifier.expectedAudience = @"did:web:pds.example.com";
    XCTAssertEqualObjects(verifier.expectedAudience, @"did:web:pds.example.com");
}

- (void)testVerifierStoresRequireDPoP {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    verifier.requireDPoP = YES;
    XCTAssertTrue(verifier.requireDPoP);
}

- (void)testVerifierStoresAllowedIssuers {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    verifier.allowedIssuers = @[@"https://issuer1.example.com", @"https://issuer2.example.com"];
    XCTAssertEqual(verifier.allowedIssuers.count, (NSUInteger)2);
}

#pragma mark - verifyAccessToken: (rejects malformed input)

- (void)testVerifyAccessTokenRejectsNilToken {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    NSError *error = nil;
    AuthVerifierPrincipal *principal = [verifier verifyAccessToken:nil error:&error];
    XCTAssertNil(principal, @"verifyAccessToken: must reject nil token");
    XCTAssertNotNil(error);
}

- (void)testVerifyAccessTokenRejectsGarbageString {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    NSError *error = nil;
    AuthVerifierPrincipal *principal = [verifier verifyAccessToken:@"notAJWT" error:&error];
    XCTAssertNil(principal, @"verifyAccessToken: must reject a non-JWT string");
    XCTAssertNotNil(error);
}

- (void)testVerifyAuthHeaderRejectsMissingBearer {
    AlwaysValidAccountPolicy *policy = [[AlwaysValidAccountPolicy alloc] init];
    AuthVerifier *verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                         accountPolicy:policy
                                                            nonceStore:nil];
    NSError *error = nil;
    AuthVerifierPrincipal *principal = [verifier verifyAuthHeader:nil
                                                        dpopHeader:nil
                                                           request:nil
                                                          response:nil
                                                            error:&error];
    XCTAssertNil(principal, @"Missing auth header must be rejected");
    XCTAssertNotNil(error);
}

@end
