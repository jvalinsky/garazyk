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
    NSError *error = nil;
    
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
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"dup@example.com" 
                                  password:@"password" 
                                   handle:@"dupuser.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSDictionary *duplicate = [self.controller createAccountForEmail:@"dup@example.com" 
                                                            password:@"password" 
                                                             handle:@"dupuser2.example.com" 
                                                                 did:nil 
                                                                error:&error];
    
    XCTAssertNil(duplicate, @"Duplicate account should fail");
    XCTAssertNotNil(error, @"Should have error for duplicate");
    XCTAssertEqual(error.code, PDSControllerErrorAccountAlreadyExists);
}

- (void)testLogin {
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"login@example.com" 
                                  password:@"mypassword" 
                                   handle:@"loginuser.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSDictionary *session = [self.controller loginWithHandle:@"loginuser.example.com" 
                                                    password:@"mypassword" 
                                                       error:&error];
    
    XCTAssertNotNil(session, @"Login should succeed: %@", error);
    XCTAssertNotNil(session[@"accessJwt"]);
    XCTAssertNotNil(session[@"refreshJwt"]);
}

- (void)testLoginInvalidPassword {
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"loginfail@example.com" 
                                  password:@"correctpassword" 
                                   handle:@"loginfail.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSDictionary *session = [self.controller loginWithHandle:@"loginfail.example.com" 
                                                    password:@"wrongpassword" 
                                                       error:&error];
    
    XCTAssertNil(session, @"Login should fail with wrong password");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSControllerErrorInvalidToken);
}

- (void)testRefreshToken {
    NSError *error = nil;
    
    NSDictionary *create = [self.controller createAccountForEmail:@"refresh@example.com" 
                                                         password:@"password" 
                                                          handle:@"refreshuser.example.com" 
                                                              did:nil 
                                                             error:&error];
    XCTAssertNotNil(create);
    
    NSString *refreshToken = create[@"refreshJwt"];
    XCTAssertNotNil(refreshToken);
    
    NSDictionary *refresh = [self.controller refreshAccessToken:refreshToken error:&error];
    XCTAssertNotNil(refresh, @"Refresh should succeed: %@", error);
    XCTAssertNotNil(refresh[@"accessJwt"]);
}

- (void)testRefreshInvalidToken {
    NSError *error = nil;
    
    NSDictionary *refresh = [self.controller refreshAccessToken:@"invalid_token" error:&error];
    
    XCTAssertNil(refresh);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSControllerErrorInvalidToken);
}

- (void)testDeleteAccount {
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"delete@example.com" 
                                  password:@"password" 
                                   handle:@"deleteuser.example.com" 
                                       did:nil 
                                      error:&error];
    
    BOOL success = [self.controller deleteAccount:@"did:web:deleteuser.example.com" 
                                         password:@"password" 
                                            error:&error];
    
    XCTAssertTrue(success, @"Delete should succeed: %@", error);
}

- (void)testDeleteAccountWrongPassword {
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"deletewrong@example.com" 
                                  password:@"correctpassword" 
                                   handle:@"deletewrong.example.com" 
                                       did:nil 
                                      error:&error];
    
    BOOL success = [self.controller deleteAccount:@"did:web:deletewrong.example.com" 
                                         password:@"wrongpassword" 
                                            error:&error];
    
    XCTAssertFalse(success, @"Delete should fail with wrong password");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, PDSControllerErrorUnauthorized);
}

- (void)testRecordOperations {
    NSError *error = nil;
    
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
    
    BOOL putResult = [self.controller putRecord:@"app.bsky.feed.post" 
                                            rkey:@"test-post-1" 
                                           value:record 
                                          forDid:did 
                                           error:&error];
    
    XCTAssertTrue(putResult, @"Put record should succeed: %@", error);
    
    NSDictionary *fetched = [self.controller getRecord:[NSString stringWithFormat:@"at://%@/app.bsky.feed.post/test-post-1", did] 
                                               forDid:did 
                                                 error:&error];
    
    XCTAssertNotNil(fetched, @"Get record should succeed: %@", error);
    XCTAssertEqualObjects(fetched[@"collection"], @"app.bsky.feed.post");
    XCTAssertEqualObjects(fetched[@"rkey"], @"test-post-1");
}

- (void)testDeleteRecord {
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"deleterecord@example.com" 
                                  password:@"password" 
                                   handle:@"deleterecord.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSString *did = @"did:web:deleterecord.example.com";
    
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": @"Test"};
    [self.controller putRecord:@"app.bsky.feed.post" rkey:@"delete-me" value:record forDid:did error:&error];
    
    BOOL deleted = [self.controller deleteRecord:@"app.bsky.feed.post" rkey:@"delete-me" forDid:did error:&error];
    XCTAssertTrue(deleted, @"Delete record should succeed: %@", error);
}

- (void)testListRecords {
    NSError *error = nil;
    
    [self.controller createAccountForEmail:@"list@example.com" 
                                  password:@"password" 
                                   handle:@"listuser.example.com" 
                                       did:nil 
                                      error:&error];
    
    NSString *did = @"did:web:listuser.example.com";
    
    for (int i = 0; i < 3; i++) {
        NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": [NSString stringWithFormat:@"Post %d", i]};
        [self.controller putRecord:@"app.bsky.feed.post" 
                             rkey:[NSString stringWithFormat:@"list-post-%d", i] 
                            value:record 
                           forDid:did 
                            error:&error];
    }
    
    NSArray *records = [self.controller listRecords:@"app.bsky.feed.post" 
                                             forDid:did 
                                               limit:10 
                                              cursor:nil 
                                              error:&error];
    
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

@end
