// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSAccountService.h"
#import "Auth/JWT.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Auth/Base32Utils.h"
#import "Auth/PDSSecondFactorService.h"
#import "Auth/TOTPGenerator.h"
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
    minter.signingAlgorithm = @"RS256";
    
    self.service.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.testDirectory
                                                                    serviceMaxSize:1024*1024
                                                                  didCacheMaxSize:1000
                                                                sequencerMaxSize:100];
    
    id<PDSKeyManager> keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:[self.service.serviceDatabases serviceDatabaseWithError:nil]];
    minter.keyManager = keyManager;
    self.service.minter = minter;
}

- (void)tearDown {
    [self.pool closeAll];
    [self.service.serviceDatabases closeAll];
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

- (void)testLoginRequiresAuthFactorTokenWhenTOTPEnabled {
    NSError *error = nil;
    [self.service createAccountForEmail:@"mfa-required@example.com"
                               password:@"password123"
                                 handle:@"mfa-required.example.com"
                                    did:nil
                                  error:&error];
    XCTAssertNil(error);

    PDSDatabaseAccount *account = [self.service.serviceDatabases getAccountByEmail:@"mfa-required@example.com" error:&error];
    account.tfaEnabled = YES;
    account.tfaSecret = [@"JBSWY3DPEHPK3PXP" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([self.service.serviceDatabases updateAccount:account error:&error]);

    error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"mfa-required.example.com"
                                                     password:@"password123"
                                                        error:&error];
    XCTAssertNil(session);
    XCTAssertEqualObjects(error.domain, PDSSecondFactorErrorDomain);
    XCTAssertEqual(error.code, PDSSecondFactorErrorRequired);
}

- (void)testLoginWithValidTOTPFallbackMintsSession {
    NSError *error = nil;
    [self.service createAccountForEmail:@"mfa-totp@example.com"
                               password:@"password123"
                                 handle:@"mfa-totp.example.com"
                                    did:nil
                                  error:&error];
    XCTAssertNil(error);

    NSString *base32Secret = @"JBSWY3DPEHPK3PXP";
    PDSDatabaseAccount *account = [self.service.serviceDatabases getAccountByEmail:@"mfa-totp@example.com" error:&error];
    account.tfaEnabled = YES;
    account.tfaSecret = [base32Secret dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([self.service.serviceDatabases updateAccount:account error:&error]);

    TOTPGenerator *generator = [[TOTPGenerator alloc] initWithSecret:[Base32Utils dataFromBase32String:base32Secret]];
    NSString *code = [generator generateOTP];

    error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"mfa-totp.example.com"
                                                     password:@"password123"
                                              authFactorToken:code
                                                        error:&error];
    XCTAssertNotNil(session);
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
    XCTAssertNotNil(session[@"refreshJwt"]);
}

- (void)testInvalidAuthFactorTokenDoesNotMintSession {
    NSError *error = nil;
    [self.service createAccountForEmail:@"mfa-invalid@example.com"
                               password:@"password123"
                                 handle:@"mfa-invalid.example.com"
                                    did:nil
                                  error:&error];
    XCTAssertNil(error);

    PDSDatabaseAccount *account = [self.service.serviceDatabases getAccountByEmail:@"mfa-invalid@example.com" error:&error];
    account.tfaEnabled = YES;
    account.tfaSecret = [@"JBSWY3DPEHPK3PXP" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([self.service.serviceDatabases updateAccount:account error:&error]);

    error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"mfa-invalid.example.com"
                                                     password:@"password123"
                                              authFactorToken:@"000000"
                                                        error:&error];
    XCTAssertNil(session);
    XCTAssertNotNil(error);
    NSArray *sessions = [self.service.serviceDatabases listRefreshTokenSessionsForAccountDid:account.did error:nil];
    XCTAssertEqual(sessions.count, 1U, @"Only the account-creation refresh token should exist");
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

#pragma mark - Login with Identifier

- (void)testLoginWithIdentifierUsingHandle {
    [self.service createAccountForEmail:@"idhandle@example.com"
                               password:@"password123"
                                 handle:@"idhandle.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"idhandle.example.com"
                                                     password:@"password123"
                                                        error:&error];
    XCTAssertNotNil(session);
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
}

- (void)testLoginWithIdentifierUsingEmail {
    [self.service createAccountForEmail:@"idemail@example.com"
                               password:@"password123"
                                 handle:@"idemail.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"idemail@example.com"
                                                     password:@"password123"
                                                        error:&error];
    XCTAssertNotNil(session);
    XCTAssertNil(error);
    XCTAssertNotNil(session[@"accessJwt"]);
}

- (void)testLoginWithIdentifierInvalidPassword {
    [self.service createAccountForEmail:@"idfail@example.com"
                               password:@"correct"
                                 handle:@"idfail.example.com"
                                    did:nil
                                  error:nil];

    NSError *error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"idfail.example.com"
                                                     password:@"wrong"
                                                        error:&error];
    XCTAssertNil(session);
    XCTAssertNotNil(error);
}

- (void)testLoginWithIdentifierNonexistentIdentifier {
    NSError *error = nil;
    NSDictionary *session = [self.service loginWithIdentifier:@"nonexistent.example.com"
                                                     password:@"password123"
                                                        error:&error];
    XCTAssertNil(session);
    XCTAssertNotNil(error);
}

#pragma mark - Get Account

- (void)testGetAccountForDidReturnsAccount {
    NSError *error = nil;
    NSDictionary *created = [self.service createAccountForEmail:@"getdid@example.com"
                                                        password:@"password123"
                                                          handle:@"getdid.example.com"
                                                             did:nil
                                                           error:&error];
    XCTAssertNotNil(created);
    NSString *did = created[@"did"];
    XCTAssertNotNil(did);

    error = nil;
    NSDictionary *account = [self.service getAccountForDid:did error:&error];
    XCTAssertNotNil(account);
    XCTAssertNil(error);
    XCTAssertEqualObjects(account[@"did"], did);
    XCTAssertEqualObjects(account[@"handle"], @"getdid.example.com");
}

- (void)testGetAccountForNonexistentDidReturnsNil {
    NSError *error = nil;
    NSDictionary *account = [self.service getAccountForDid:@"did:web:nonexistent.example.com" error:&error];
    XCTAssertNil(account);
}

#pragma mark - Get All Accounts

- (void)testGetAllAccountsReturnsCreatedAccounts {
    [self.service createAccountForEmail:@"all1@example.com"
                                password:@"password123"
                                  handle:@"all1.example.com"
                                     did:nil
                                   error:nil];

    [self.service createAccountForEmail:@"all2@example.com"
                                password:@"password123"
                                  handle:@"all2.example.com"
                                     did:nil
                                   error:nil];

    NSError *error = nil;
    NSArray *accounts = [self.service getAllAccountsWithError:&error];
    XCTAssertNotNil(accounts);
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(accounts.count, 2);
}

#pragma mark - Delete Account

- (void)testDeleteAccountSucceedsWithCorrectPassword {
    NSError *error = nil;
    NSDictionary *created = [self.service createAccountForEmail:@"delete@example.com"
                                                        password:@"deletepass"
                                                          handle:@"delete.example.com"
                                                             did:nil
                                                           error:&error];
    XCTAssertNotNil(created);
    NSString *did = created[@"did"];

    error = nil;
    BOOL deleted = [self.service deleteAccount:did password:@"deletepass" error:&error];
    XCTAssertTrue(deleted);
    XCTAssertNil(error);

    // Verify account is gone
    error = nil;
    NSDictionary *account = [self.service getAccountForDid:did error:&error];
    XCTAssertNil(account);
}

- (void)testDeleteAccountFailsWithWrongPassword {
    NSError *error = nil;
    NSDictionary *created = [self.service createAccountForEmail:@"deletewrong@example.com"
                                                        password:@"correctpass"
                                                          handle:@"deletewrong.example.com"
                                                             did:nil
                                                           error:&error];
    XCTAssertNotNil(created);
    NSString *did = created[@"did"];

    error = nil;
    BOOL deleted = [self.service deleteAccount:did password:@"wrongpass" error:&error];
    XCTAssertFalse(deleted);
    XCTAssertNotNil(error);

    // Verify account still exists
    NSDictionary *account = [self.service getAccountForDid:did error:nil];
    XCTAssertNotNil(account);
}

- (void)testDeleteAccountNonexistentFails {
    NSError *error = nil;
    BOOL deleted = [self.service deleteAccount:@"did:web:nonexistent.example.com"
                                       password:@"password123"
                                          error:&error];
    XCTAssertFalse(deleted);
    XCTAssertNotNil(error);
}

@end
