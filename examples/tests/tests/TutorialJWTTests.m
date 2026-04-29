#import <XCTest/XCTest.h>
#import "TutorialJWTMinter.h"
#import "TutorialJWTVerifier.h"
#import "TutorialECDSAUtils.h"
#import "TutorialBase64URL.h"

@interface TutorialJWTTests : XCTestCase
@property (nonatomic, strong) TutorialECDSAKeyPair *keyPair;
@property (nonatomic, strong) TutorialJWTMinter *minter;
@property (nonatomic, strong) TutorialJWTVerifier *verifier;
@end

@implementation TutorialJWTTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.keyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    XCTAssertNotNil(self.keyPair);

    self.minter = [[TutorialJWTMinter alloc] initWithIssuer:@"did:web:localhost:2583"];
    self.minter.keyPair = self.keyPair;

    self.verifier = [[TutorialJWTVerifier alloc] initWithIssuer:@"did:web:localhost:2583"
                                                        keyPair:self.keyPair];
}

- (void)tearDown {
    self.keyPair = nil;
    self.minter = nil;
    self.verifier = nil;
    [super tearDown];
}

- (void)testMintAccessToken {
    NSError *error = nil;
    NSString *jwt = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                handle:@"alice.example"
                                                scopes:@[@"atproto_repo"]
                                                 error:&error];
    XCTAssertNotNil(jwt, @"Should mint an access token");
    XCTAssertNil(error);
    XCTAssertTrue(jwt.length > 0, @"JWT should not be empty");
}

- (void)testMintRefreshToken {
    NSError *error = nil;
    NSString *jwt = [self.minter mintRefreshTokenForDID:@"did:web:localhost:~alice"
                                                 handle:@"alice.example"
                                                 scopes:@[@"atproto_refresh"]
                                                  error:&error];
    XCTAssertNotNil(jwt, @"Should mint a refresh token");
    XCTAssertNil(error);
}

- (void)testJWTHeaderFormat {
    NSError *error = nil;
    NSString *jwt = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                handle:@"alice.example"
                                                scopes:@[@"atproto_repo"]
                                                 error:&error];
    NSArray *parts = [jwt componentsSeparatedByString:@"."];
    XCTAssertEqual(parts.count, 3, @"JWT should have 3 dot-separated parts");

    NSData *headerData = [TutorialBase64URL decode:parts[0]];
    XCTAssertNotNil(headerData);
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil];
    XCTAssertEqualObjects(header[@"alg"], @"ES256", @"Algorithm should be ES256");
    XCTAssertEqualObjects(header[@"typ"], @"JWT", @"Type should be JWT");
}

- (void)testVerifyValidToken {
    NSError *error = nil;
    NSString *jwt = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                handle:@"alice.example"
                                                scopes:@[@"atproto_repo"]
                                                 error:&error];
    NSDictionary *claims = [self.verifier verifyToken:jwt error:&error];
    XCTAssertNil(error, @"No error on valid token");
    XCTAssertNotNil(claims, @"Should return claims for valid token");
    XCTAssertEqualObjects(claims[@"sub"], @"did:web:localhost:~alice", @"Subject should match");
}

- (void)testVerifyWithWrongKeyFails {
    NSError *error = nil;
    TutorialECDSAKeyPair *wrongKeyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    TutorialJWTVerifier *wrongVerifier = [[TutorialJWTVerifier alloc] initWithIssuer:@"did:web:localhost:2583"
                                                                             keyPair:wrongKeyPair];

    NSString *jwt = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                handle:@"alice.example"
                                                scopes:@[@"atproto_repo"]
                                                 error:nil];
    NSDictionary *claims = [wrongVerifier verifyToken:jwt error:&error];
    XCTAssertNotNil(error, @"Should fail with wrong key");
    XCTAssertNil(claims, @"Should not return claims with wrong key");
}

- (void)testVerifyWrongIssuerFails {
    NSError *error = nil;
    TutorialECDSAKeyPair *wrongKeyPair = [TutorialECDSAUtils generateKeyPairWithError:&error];
    TutorialJWTVerifier *wrongIssuer = [[TutorialJWTVerifier alloc] initWithIssuer:@"did:web:wrong:issuer"
                                                                          keyPair:wrongKeyPair];

    NSString *jwt = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                handle:@"alice.example"
                                                scopes:@[@"atproto_repo"]
                                                 error:nil];
    NSDictionary *claims = [wrongIssuer verifyToken:jwt error:&error];
    XCTAssertNotNil(error, @"Should fail with wrong issuer");
    XCTAssertNil(claims, @"Should not return claims with wrong issuer");
}

- (void)testVerifyTamperedPayloadFails {
    NSError *error = nil;
    NSString *jwt = [self.minter mintAccessTokenForDID:@"did:web:localhost:~alice"
                                                handle:@"alice.example"
                                                scopes:@[@"atproto_repo"]
                                                 error:nil];
    NSArray *parts = [jwt componentsSeparatedByString:@"."];
    NSString *tampered = [NSString stringWithFormat:@"%@.%@.%@",
                          parts[0], @"aW52YWxpZHBheWxvYWQ", parts[2]];
    NSDictionary *claims = [self.verifier verifyToken:tampered error:&error];
    XCTAssertNotNil(error, @"Should fail with tampered payload");
}

- (void)testToJWKS {
    NSDictionary *jwks = [self.minter toJWKS];
    XCTAssertNotNil(jwks, @"Should return JWKS");
    NSArray *keys = jwks[@"keys"];
    XCTAssertNotNil(keys, @"JWKS should have keys array");
    XCTAssertTrue(keys.count > 0, @"Keys should not be empty");
}

@end
