#import <XCTest/XCTest.h>
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"

@interface PDSControllerTests : XCTestCase

@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSController *controller;

@end

@implementation PDSControllerTests

- (void)setUp {
    [super setUp];
    
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"PDSControllerTests"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    [fm createDirectoryAtPath:self.testDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    self.controller = [[PDSController alloc] initWithDirectory:self.testDirectory
                                                serviceMaxSize:10
                                              userDatabaseSize:20];
}

- (void)tearDown {
    [self.controller stopServer];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.testDirectory error:nil];
    
    [super tearDown];
}

- (void)testControllerInitialization {
    XCTAssertNotNil(self.controller);
    XCTAssertNotNil(self.controller.serviceDatabases);
    XCTAssertNotNil(self.controller.userDatabasePool);
    XCTAssertFalse(self.controller.isRunning);
}

- (void)testCreateAccount {
    __autoreleasing NSError *error = nil;
    
    NSDictionary *result = [self.controller createAccountForEmail:@"test@example.com"
                                                          password:@"password123"
                                                           handle:@"testuser.example.com"
                                                               did:nil
                                                              error:&error];
    
    XCTAssertNotNil(result, @"Create account should return result: %@", error);
    XCTAssertNotNil(result[@"did"]);
    XCTAssertEqualObjects(result[@"handle"], @"testuser.example.com");
    XCTAssertNotNil(result[@"accessJwt"]);
    XCTAssertNotNil(result[@"refreshJwt"]);
}

- (void)testCreateDuplicateAccount {
    __autoreleasing NSError *error = nil;
    
    NSDictionary *first = [self.controller createAccountForEmail:@"dup@example.com" 
                                                        password:@"password" 
                                                         handle:@"dupuser.example.com" 
                                                             did:@"did:plc:testduplicate123"
                                                            error:&error];
    XCTAssertNotNil(first, @"First account should succeed: %@", error);
    
    __autoreleasing NSError *dupError = nil;
    NSDictionary *duplicate = [self.controller createAccountForEmail:@"dup@example.com" 
                                                            password:@"password" 
                                                             handle:@"dupuser2.example.com" 
                                                                 did:@"did:plc:testduplicate123"
                                                                error:&dupError];
    
    XCTAssertNil(duplicate, @"Duplicate account should fail");
    XCTAssertNotNil(dupError, @"Should have error for duplicate");
    XCTAssertEqual(dupError.code, PDSControllerErrorAccountAlreadyExists);
}

- (void)testLogin {
    __autoreleasing NSError *error = nil;
    
    [self.controller createAccountForEmail:@"login@example.com" 
                                  password:@"mypassword" 
                                   handle:@"loginuser.example.com" 
                                       did:nil 
                                      error:&error];
    
    __autoreleasing NSError *loginError = nil;
    NSDictionary *session = [self.controller loginWithHandle:@"loginuser.example.com" 
                                                    password:@"mypassword" 
                                                       error:&loginError];
    
    XCTAssertNotNil(session, @"Login should succeed: %@", loginError);
    XCTAssertNotNil(session[@"accessJwt"]);
    XCTAssertNotNil(session[@"refreshJwt"]);
}

- (void)testLoginInvalidPassword {
    __autoreleasing NSError *error = nil;
    
    [self.controller createAccountForEmail:@"loginfail@example.com" 
                                  password:@"correctpassword" 
                                   handle:@"loginfail.example.com" 
                                       did:nil 
                                      error:&error];
    
    __autoreleasing NSError *loginError = nil;
    NSDictionary *session = [self.controller loginWithHandle:@"loginfail.example.com" 
                                                    password:@"wrongpassword" 
                                                       error:&loginError];
    
    XCTAssertNil(session, @"Login should fail with wrong password");
    XCTAssertNotNil(loginError);
    XCTAssertEqual(loginError.code, PDSControllerErrorInvalidToken);
}

- (void)testRefreshToken {
    __autoreleasing NSError *error = nil;
    
    NSDictionary *create = [self.controller createAccountForEmail:@"refresh@example.com" 
                                                         password:@"password" 
                                                          handle:@"refreshuser.example.com" 
                                                              did:nil 
                                                             error:&error];
    XCTAssertNotNil(create);
    
    NSString *refreshToken = create[@"refreshJwt"];
    XCTAssertNotNil(refreshToken);
    
    __autoreleasing NSError *refreshError = nil;
    NSDictionary *refresh = [self.controller refreshAccessToken:refreshToken error:&refreshError];
    XCTAssertNotNil(refresh, @"Refresh should succeed: %@", refreshError);
    XCTAssertNotNil(refresh[@"accessJwt"]);
}

- (void)testRefreshInvalidToken {
    __autoreleasing NSError *error = nil;
    
    NSDictionary *refresh = [self.controller refreshAccessToken:@"invalid_token" error:&error];
    
    XCTAssertNil(refresh);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSControllerErrorInvalidToken);
}

- (void)testDeleteAccount {
    __autoreleasing NSError *error = nil;
    
    NSDictionary *result = [self.controller createAccountForEmail:@"delete@example.com" 
                                                          password:@"password" 
                                                           handle:@"deleteuser.example.com" 
                                                               did:nil 
                                                              error:&error];
    XCTAssertNotNil(result, @"Account creation should succeed: %@", error);
    NSString *actualDid = result[@"did"];
    XCTAssertNotNil(actualDid, @"Account should have a DID");
    
    __autoreleasing NSError *deleteError = nil;
    BOOL success = [self.controller deleteAccount:actualDid 
                                         password:@"password" 
                                            error:&deleteError];
    
    XCTAssertTrue(success, @"Delete should succeed: %@", deleteError);
}

- (void)testDeleteAccountWrongPassword {
    __autoreleasing NSError *error = nil;
    
    NSDictionary *result = [self.controller createAccountForEmail:@"deletewrong@example.com" 
                                                          password:@"correctpassword" 
                                                           handle:@"deletewrong.example.com" 
                                                               did:nil 
                                                              error:&error];
    XCTAssertNotNil(result, @"Account creation should succeed: %@", error);
    NSString *actualDid = result[@"did"];
    XCTAssertNotNil(actualDid, @"Account should have a DID");
    
    __autoreleasing NSError *deleteError = nil;
    BOOL success = [self.controller deleteAccount:actualDid 
                                         password:@"wrongpassword" 
                                            error:&deleteError];
    
    XCTAssertFalse(success, @"Delete should fail with wrong password");
    XCTAssertNotNil(deleteError);
    XCTAssertEqual(deleteError.code, PDSControllerErrorUnauthorized);
}

- (void)testRecordOperations {
    __autoreleasing NSError *error = nil;
    
    [self.controller createAccountForEmail:@"record@example.com" 
                                  password:@"password" 
                                   handle:@"recorduser.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSString *did = @"did:web:recorduser.example.com";
    
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Hello, ATProto!",
        @"createdAt": @"2026-01-08T00:00:00Z"
    };
    
    __autoreleasing NSError *putError = nil;
    BOOL putResult = [self.controller putRecord:@"app.bsky.feed.post" 
                                           rkey:@"test-post-1" 
                                          value:record 
                                         forDid:did 
                   validationMode:PDSValidationModeRequired
                                          error:&putError];
    
    XCTAssertTrue(putResult, @"Put record should succeed: %@", putError);
    
    __autoreleasing NSError *fetchError = nil;
    NSDictionary *fetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/test-post-1", did] 
                                              forDid:did 
                                                error:&fetchError];
    
    XCTAssertNotNil(fetched, @"Get record should succeed: %@", fetchError);
    XCTAssertEqualObjects(fetched[@"collection"], @"app.bsky.feed.post");
    XCTAssertEqualObjects(fetched[@"rkey"], @"test-post-1");
}

- (void)testDeleteRecord {
    __autoreleasing NSError *error = nil;
    
    [self.controller createAccountForEmail:@"deleterecord@example.com" 
                                  password:@"password" 
                                   handle:@"deleterecord.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSString *did = @"did:web:deleterecord.example.com";
    
    NSDictionary *record = @{
        @"$type": @"app.bsky.feed.post",
        @"text": @"Test",
        @"createdAt": @"2026-01-08T00:00:00Z"
    };
    __autoreleasing NSError *putError = nil;
    [self.controller putRecord:@"app.bsky.feed.post" rkey:@"delete-me" value:record forDid:did validationMode:PDSValidationModeRequired error:&putError];
    
    __autoreleasing NSError *deleteError = nil;
    BOOL deleted = [self.controller deleteRecord:@"app.bsky.feed.post" rkey:@"delete-me" forDid:did error:&deleteError];
    XCTAssertTrue(deleted, @"Delete record should succeed: %@", deleteError);
}

- (void)testListRecords {
    __autoreleasing NSError *error = nil;
    
    [self.controller createAccountForEmail:@"list@example.com" 
                                  password:@"password" 
                                   handle:@"listuser.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSString *did = @"did:web:listuser.example.com";
    
    for (int i = 0; i < 3; i++) {
        NSDictionary *record = @{
            @"$type": @"app.bsky.feed.post",
            @"text": [NSString stringWithFormat:@"Post %d", i],
            @"createdAt": @"2026-01-08T00:00:00Z"
        };
        __autoreleasing NSError *putError = nil;
        [self.controller putRecord:@"app.bsky.feed.post" 
                             rkey:[NSString stringWithFormat:@"list-post-%d", i] 
                            value:record 
                           forDid:did 
                    validationMode:PDSValidationModeRequired
                            error:&putError];
    }
    
    __autoreleasing NSError *listError = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.feed.post" 
                                             forDid:did 
                                               limit:10 
                                              cursor:nil 
                                              error:&listError];
    
    XCTAssertEqual(records.count, 3, @"Should have 3 records");
}

- (void)testHealthCheck {
    NSDictionary *health = [self.controller getHealthCheck];
    
    XCTAssertNotNil(health);
    XCTAssertNotNil(health[@"timestamp"]);
}

- (void)testMetrics {
    NSDictionary *metrics = [self.controller getMetrics];

    XCTAssertNotNil(metrics);
    XCTAssertNotNil(metrics[@"timestamp"]);
    XCTAssertNotNil(metrics[@"user_databases"]);
    XCTAssertNotNil(metrics[@"service_databases"]);
}

- (void)testModerateAccountEndpoint {
    NSDictionary *params = @{@"did": @"did:plc:test", @"reason": @"spam"};

    NSError *error = nil;
    NSDictionary *result = [self.controller moderateAccount:params error:&error];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"not_implemented");
}

- (void)testModerateRecordEndpoint {
    NSDictionary *params = @{@"uri": @"at://did:plc:test/app.bsky.feed.post/123", @"reason": @"spam"};

    NSError *error = nil;
    NSDictionary *result = [self.controller moderateRecord:params error:&error];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"not_implemented");
}

- (void)testCreateLabelEndpoint {
    NSDictionary *params = @{
        @"uri": @"at://did:plc:test/app.bsky.feed.post/123",
        @"val": @"spam",
        @"neg": @NO
    };

    NSError *error = nil;
    NSDictionary *result = [self.controller createLabel:params error:&error];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"not_implemented");
}

- (void)testGetLabelsEndpoint {
    NSDictionary *params = @{
        @"uriPatterns": @[@"at://did:plc:test/app.bsky.feed.post/*"],
        @"sources": @[],
        @"limit": @50
    };

    NSError *error = nil;
    NSDictionary *result = [self.controller getLabels:params error:&error];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"not_implemented");
}

#if 0
- (void)testPasswordHashingMethods {
    NSString *password = @"testpassword";
    NSData *salt = [self.controller generateSalt];

    // Test Argon2-compatible method
    NSData *hash1 = [self.controller hashPasswordArgon2:password salt:salt];
    NSData *hash2 = [self.controller hashPasswordArgon2:password salt:salt];
    XCTAssertEqualObjects(hash1, hash2, @"Same password and salt should produce same hash");

    // Test legacy SHA-256 method
    NSData *legacyHash = [self.controller hashPasswordSHA256:password salt:salt];
    XCTAssertNotEqualObjects(hash1, legacyHash, @"New and legacy hashes should be different");

    // Test verification with new method
    BOOL verified = [self.controller verifyPassword:password hash:hash1 salt:salt];
    XCTAssertTrue(verified, @"Password should verify with correct hash");

    // Test verification with legacy method
    BOOL migrated = NO;
    verified = [self.controller verifyPassword:password hash:legacyHash salt:salt migrated:&migrated];
    XCTAssertTrue(verified, @"Password should verify with legacy hash");
    XCTAssertTrue(migrated, @"Should indicate migration needed");
}
#endif

#if 0
- (void)testPasswordMigration {
    __autoreleasing NSError *error = nil;

    // Create account (will use new hashing)
    NSDictionary *result = [self.controller createAccountForEmail:@"migrate@example.com"
                                                         password:@"migratepass"
                                                          handle:@"migrateuser.example.com"
                                                              did:nil
                                                           error:&error];
    XCTAssertNotNil(result);

    NSString *did = result[@"did"];

    // Simulate old SHA-256 hash in database (manually modify for test)
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByDid:did error:&error];
    XCTAssertNotNil(account);

    // Replace with SHA-256 hash
    NSData *legacyHash = [self.controller hashPasswordSHA256:@"migratepass" salt:account.passwordSalt];
    account.passwordHash = legacyHash;
    [_serviceDatabases updateAccount:account error:nil];

    // Login should succeed and migrate
    NSDictionary *session = [self.controller loginWithHandle:@"migrateuser.example.com"
                                                    password:@"migratepass"
                                                      error:&error];
    XCTAssertNotNil(session, @"Login should succeed after migration");

    // Verify hash was updated
    PDSDatabaseAccount *updatedAccount = [_serviceDatabases getAccountByDid:did error:&error];
    XCTAssertNotNil(updatedAccount);

    NSData *expectedNewHash = [self.controller hashPasswordArgon2:@"migratepass" salt:updatedAccount.passwordSalt];
    XCTAssertEqualObjects(updatedAccount.passwordHash, expectedNewHash, @"Password hash should be migrated to new method");
}
#endif

@end
