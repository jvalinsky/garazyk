#import <XCTest/XCTest.h>
#import "App/Services/PDSAccountService.h"
#import "Auth/JWT.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"

@interface PDSAccountServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSAccountService *service;
@end

@implementation PDSAccountServiceTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSAccountService alloc] initWithDatabasePool:self.pool];

    JWTMinter *minter = [[JWTMinter alloc] init];
    minter.issuer = @"http://localhost:8080";
    minter.signingAlgorithm = @"ES256";
    self.service.minter = minter;

    self.service.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.testDirectory
                                                                   serviceMaxSize:1024*1024
                                                                 didCacheMaxSize:1000
                                                               sequencerMaxSize:100];
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testCreateAccount {
    NSError *error = nil;
    NSDictionary *result = [self.service createAccountForEmail:@"test@example.com"
                                                      password:@"password123"
                                                        handle:@"test.example.com"
                                                           did:nil // Let it generate
                                                         error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertNotNil(result[@"did"]);
    XCTAssertEqualObjects(result[@"handle"], @"test.example.com");
    XCTAssertEqualObjects(result[@"email"], @"test@example.com");
}

- (void)testCreateAccountDuplicate {
    NSError *error = nil;
    NSDictionary *firstResult = [self.service createAccountForEmail:@"dup@example.com"
                                                           password:@"password123"
                                                             handle:@"dup.example.com"
                                                                did:nil
                                                              error:&error];
    XCTAssertNotNil(firstResult);
    XCTAssertNil(error);
    
    error = nil;
    NSDictionary *dupResult = [self.service createAccountForEmail:@"dup@example.com"
                                                         password:@"password456"
                                                           handle:@"dup.example.com"
                                                              did:nil
                                                            error:&error];
    XCTAssertNil(dupResult);
    XCTAssertNotNil(error);
}

- (void)testLogin {
    [self.service createAccountForEmail:@"login@example.com"
                               password:@"correctHash"
                                 handle:@"login.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithHandle:@"login.example.com"
                                                 password:@"correctHash"
                                                    error:&error];
    XCTAssertNotNil(session);
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
    XCTAssertNotNil(session[@"refreshJwt"]);
}

- (void)testLoginInvalidPassword {
    [self.service createAccountForEmail:@"fail@example.com"
                               password:@"correctHash"
                                 handle:@"fail.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithHandle:@"fail.example.com"
                                                 password:@"wrongPassword"
                                                    error:&error];
    XCTAssertNil(session);
    XCTAssertNotNil(error);
}

- (void)testRefreshAccessToken_RotatesRefreshToken {
    // Arrange: Create account and login to get initial tokens
    NSError *error = nil;
    NSDictionary *initialSession = [self.service createAccountForEmail:@"rotation@example.com"
                                                              password:@"password123"
                                                                handle:@"rotation.example.com"
                                                                   did:nil
                                                                 error:&error];
    XCTAssertNotNil(initialSession, @"Should create account successfully");
    XCTAssertNil(error, @"Should not have error creating account");
    
    NSString *originalRefreshToken = initialSession[@"refreshJwt"];
    XCTAssertNotNil(originalRefreshToken, @"Should have refresh token");
    
    // Verify original token is valid by looking up account
    PDSDatabaseAccount *accountBefore = [self.service.serviceDatabases getAccountByRefreshToken:originalRefreshToken error:&error];
    XCTAssertNotNil(accountBefore, @"Original refresh token should be valid before rotation");
    
    // Act: Refresh the access token
    error = nil;
    NSDictionary *refreshedSession = [self.service refreshAccessToken:originalRefreshToken error:&error];
    
    // Assert: Should get new tokens
    XCTAssertNotNil(refreshedSession, @"Should return refreshed session");
    XCTAssertNil(error, @"Should not have error refreshing token");
    XCTAssertNotNil(refreshedSession[@"accessJwt"], @"Should return new access token");
    XCTAssertNotNil(refreshedSession[@"refreshJwt"], @"Should return new refresh token");
    XCTAssertNotEqualObjects(refreshedSession[@"refreshJwt"], originalRefreshToken, @"New refresh token should be different from original");
    
    // Assert: Old token should be revoked (no longer valid)
    error = nil;
    PDSDatabaseAccount *accountAfterOldToken = [self.service.serviceDatabases getAccountByRefreshToken:originalRefreshToken error:&error];
    XCTAssertNil(accountAfterOldToken, @"Old refresh token should be revoked after rotation");
    
    // Assert: New token should be valid
    NSString *newRefreshToken = refreshedSession[@"refreshJwt"];
    error = nil;
    PDSDatabaseAccount *accountAfterNewToken = [self.service.serviceDatabases getAccountByRefreshToken:newRefreshToken error:&error];
    XCTAssertNotNil(accountAfterNewToken, @"New refresh token should be valid");
    XCTAssertEqualObjects(accountAfterNewToken.did, accountBefore.did, @"New token should resolve to same account");
}

- (void)testRefreshAccessToken_InvalidTokenReturnsError {
    // Arrange: Use an invalid/non-existent refresh token
    NSString *invalidToken = @"invalid-token-12345";
    
    // Act: Attempt to refresh with invalid token
    NSError *error = nil;
    NSDictionary *session = [self.service refreshAccessToken:invalidToken error:&error];
    
    // Assert: Should fail with error
    XCTAssertNil(session, @"Should not return session for invalid token");
    XCTAssertNotNil(error, @"Should return error for invalid token");
}

- (void)testLoginRejectsDifferentUnicodePassword {
    NSError *error = nil;
    NSDictionary *created = [self.service createAccountForEmail:@"unicode@example.com"
                                                       password:@"éX"
                                                         handle:@"unicode.example.com"
                                                            did:nil
                                                          error:&error];
    XCTAssertNotNil(created);
    XCTAssertNil(error);

    error = nil;
    NSDictionary *session = [self.service loginWithHandle:@"unicode.example.com"
                                                 password:@"éY"
                                                    error:&error];
    XCTAssertNil(session, @"Different Unicode password must not authenticate");
    XCTAssertNotNil(error);
}

- (void)testGeneratedSaltUsesFullEntropyLength {
    NSError *error = nil;
    NSDictionary *created = [self.service createAccountForEmail:@"salt@example.com"
                                                       password:@"password123"
                                                         handle:@"salt.example.com"
                                                            did:nil
                                                          error:&error];
    XCTAssertNotNil(created);
    XCTAssertNil(error);

    PDSDatabaseAccount *account = [self.service.serviceDatabases getAccountByEmail:@"salt@example.com" error:&error];
    XCTAssertNotNil(account);
    XCTAssertNil(error);
    XCTAssertEqual(account.passwordSalt.length, 32u);

    const uint8_t *bytes = account.passwordSalt.bytes;
    BOOL hasNonZeroTailByte = NO;
    for (NSUInteger i = 16; i < account.passwordSalt.length; i++) {
        if (bytes[i] != 0) {
            hasNonZeroTailByte = YES;
            break;
        }
    }
    XCTAssertTrue(hasNonZeroTailByte, @"Salt tail bytes should contain entropy");
}

@end
