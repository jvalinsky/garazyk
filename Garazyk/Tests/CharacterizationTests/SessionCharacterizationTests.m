#import "CharacterizationTestBase.h"
#import "Auth/Session.h"
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"

@interface SessionCharacterizationTests : CharacterizationTestBase

@property (nonatomic, strong) Session *subject;

@end

@implementation SessionCharacterizationTests

- (void)setUp {
    [super setUp];
    self.subject = [Session sessionWithDID:@"did:plc:test"
                                    handle:@"test.example"
                                     scope:@"atproto"];
}

- (void)tearDown {
    self.subject = nil;
    [super tearDown];
}

/*
 * Characterization Tests for Session
 * Generated automatically. Please implement specific scenarios.
 */

- (void)testCharacterization_Class_sessionWithDID {
    /* Target Method:
     + (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope;
    */
    
    Session *session = [Session sessionWithDID:@"did:plc:char1"
                                        handle:@"alice.example"
                                         scope:@"atproto"];

    XCTAssertNotNil(session);
    XCTAssertEqualObjects(session.did, @"did:plc:char1");
    XCTAssertEqualObjects(session.handle, @"alice.example");
    XCTAssertEqualObjects(session.scope, @"atproto");
    XCTAssertEqualObjects(session.tokenType, @"Bearer");
    XCTAssertNotNil(session.accessToken);
    XCTAssertNotNil(session.refreshToken);
}

- (void)testCharacterization_Class_sessionWithDID_2 {
    /* Target Method:
     + (nullable instancetype)sessionWithDID:(NSString *)did
                                 handle:(NSString *)handle
                                  scope:(NSString *)scope
                                 minter:(nullable JWTMinter *)minter;
    */
    
    NSError *keyError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
    XCTAssertNotNil(keyPair, @"Failed to generate key pair: %@", keyError);

    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test.issuer";
    minter.signingAlgorithm = @"ES256K";
    minter.privateKey = keyPair.privateKey;
    minter.publicKey = keyPair.publicKey;

    Session *session = [Session sessionWithDID:@"did:plc:char2"
                                        handle:@"bob.example"
                                         scope:@"read write"
                                        minter:minter];

    XCTAssertNotNil(session);
    XCTAssertEqualObjects(session.did, @"did:plc:char2");
    XCTAssertEqualObjects(session.handle, @"bob.example");
    XCTAssertEqualObjects(session.scope, @"read write");
    XCTAssertEqualObjects(session.tokenType, @"DPoP");

    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:session.accessToken error:&parseError];
    XCTAssertNotNil(jwt, @"Expected access token to parse as JWT");
    XCTAssertNil(parseError);
    XCTAssertEqualObjects(jwt.header.alg, @"ES256K");
    XCTAssertEqualObjects(jwt.payload.did, @"did:plc:char2");
    XCTAssertEqualObjects(jwt.payload.handle, @"bob.example");
}

- (void)testCharacterization_initWithDID {
    /* Target Method:
     - (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope;
    */
    
    Session *session = [[Session alloc] initWithDID:@"did:plc:char3"
                                            handle:@"carol.example"
                                             scope:@"atproto"];

    XCTAssertNotNil(session);
    XCTAssertEqualObjects(session.did, @"did:plc:char3");
    XCTAssertEqualObjects(session.handle, @"carol.example");
    XCTAssertEqualObjects(session.tokenType, @"Bearer");
}

- (void)testCharacterization_initWithDID_2 {
    /* Target Method:
     - (instancetype)initWithDID:(NSString *)did
                    handle:(NSString *)handle
                     scope:(NSString *)scope
                    minter:(nullable JWTMinter *)minter;
    */
    
    NSError *keyError = nil;
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:&keyError];
    XCTAssertNotNil(keyPair, @"Failed to generate key pair: %@", keyError);

    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"test.issuer";
    minter.signingAlgorithm = @"ES256K";
    minter.privateKey = keyPair.privateKey;
    minter.publicKey = keyPair.publicKey;

    Session *session = [[Session alloc] initWithDID:@"did:plc:char4"
                                            handle:@"dave.example"
                                             scope:@"read"
                                            minter:minter];
    XCTAssertNotNil(session);
    XCTAssertEqualObjects(session.tokenType, @"DPoP");
}

- (void)testCharacterization_toTokenResponse {
    /* Target Method:
     - (NSDictionary *)toTokenResponse;
    */
    
    NSDictionary *response = [self.subject toTokenResponse];

    XCTAssertTrue([response isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(response[@"access_token"], self.subject.accessToken);
    XCTAssertEqualObjects(response[@"token_type"], self.subject.tokenType);
    XCTAssertEqualObjects(response[@"scope"], self.subject.scope);
    XCTAssertNotNil(response[@"expires_in"]);
    XCTAssertNotNil(response[@"refresh_token"]);
}

- (void)testCharacterization_toBearerTokenResponse {
    /* Target Method:
     - (NSDictionary *)toBearerTokenResponse;
    */
    
    NSDictionary *response = [self.subject toBearerTokenResponse];

    XCTAssertTrue([response isKindOfClass:[NSDictionary class]]);
    XCTAssertEqualObjects(response[@"access_token"], self.subject.accessToken);
    XCTAssertEqualObjects(response[@"token_type"], self.subject.tokenType);
    XCTAssertEqualObjects(response[@"scope"], self.subject.scope);
    XCTAssertNotNil(response[@"expires_in"]);
    XCTAssertNil(response[@"refresh_token"]);
}

- (void)testCharacterization_refreshAccessToken {
    /* Target Method:
     - (NSString *)refreshAccessToken;
    */
    
    NSString *oldAccessToken = self.subject.accessToken;
    NSString *oldRefreshToken = self.subject.refreshToken;

    NSString *newAccessToken = [self.subject refreshAccessToken];
    XCTAssertNotNil(newAccessToken);
    XCTAssertNotEqualObjects(newAccessToken, oldAccessToken);
    XCTAssertNotEqualObjects(self.subject.refreshToken, oldRefreshToken);
    XCTAssertTrue([self.subject isRefreshTokenValid]);
}

@end
