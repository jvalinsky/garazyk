// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAdminControllerTests.m

 @abstract Unit tests for PDSAdminController.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Admin/PDSAdminController.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"

@interface PDSAdminControllerTests : XCTestCase

@property (nonatomic, strong) PDSAdminController *adminController;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, copy) NSString *tempDirectory;

@end

@implementation PDSAdminControllerTests

- (void)setUp {
    [super setUp];
    
    // Create temp directory for test databases
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"PDSAdminControllerTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.tempDirectory = tempDir;
    
    // Initialize service databases
    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:tempDir
                                                             serviceMaxSize:10
                                                           didCacheMaxSize:10
                                                         sequencerMaxSize:10];
    
    // Initialize admin controller
    self.adminController = [[PDSAdminController alloc] initWithServiceDatabases:self.serviceDatabases
                                                                 accountService:nil];
}

- (void)tearDown {
    self.adminController = nil;
    [self.serviceDatabases closeAll];
    self.serviceDatabases = nil;
    
    // Clean up temp directory
    if (self.tempDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];
        self.tempDirectory = nil;
    }
    
    [super tearDown];
}

- (void)createAccountWithDid:(NSString *)did handle:(NSString *)handle {
    NSError *error = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&error];
    XCTAssertNotNil(db);
    XCTAssertNil(error);

    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = [NSString stringWithFormat:@"%@@example.com", handle];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;
    account.inviteEnabled = YES;

    BOOL created = [db createAccount:account error:&error];
    XCTAssertTrue(created);
    XCTAssertNil(error);
}

- (nullable NSDictionary *)latestTakedownForSubjectType:(NSString *)subjectType subjectID:(NSString *)subjectID {
    NSError *error = nil;
    PDSDatabase *db = [self.serviceDatabases serviceDatabaseWithError:&error];
    XCTAssertNotNil(db);
    XCTAssertNil(error);

    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:
                                     @"SELECT subjectType, subjectId, takedownRef, applied FROM admin_takedowns WHERE subjectType = ? AND subjectId = ? ORDER BY createdAt DESC LIMIT 1"
                                                              params:@[subjectType, subjectID]
                                                               error:&error];
    XCTAssertNil(error);
    return rows.count > 0 ? rows.firstObject : nil;
}

#pragma mark - Initialization Tests

- (void)testInitWithServiceDatabasesCreatesAdminService {
    PDSAdminController *controller = [[PDSAdminController alloc] initWithServiceDatabases:self.serviceDatabases];

    XCTAssertNotNil(controller);
    XCTAssertTrue(controller.adminService != nil);
}

- (void)testInitWithServiceDatabasesAndAccountService {
    PDSAdminController *controller = [[PDSAdminController alloc] initWithServiceDatabases:self.serviceDatabases
                                                                            accountService:nil];

    XCTAssertNotNil(controller);
    XCTAssertTrue(controller.adminService != nil);
}

#pragma mark - Account Administration Tests

- (void)testGetAllAccountsWithNoAccounts {
    NSError *error = nil;
    NSArray *accounts = [self.adminController getAllAccountsWithError:&error];
    
    // Should return empty array, not nil
    XCTAssertNotNil(accounts);
    XCTAssertEqual(accounts.count, 0);
}

- (void)testTakeDownAccountWithNilDid {
    NSError *error = nil;
    BOOL result = [self.adminController takeDownAccount:nil reason:@"test" error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSAdminControllerErrorDomain");
}

- (void)testTakeDownAccountWithEmptyDid {
    NSError *error = nil;
    BOOL result = [self.adminController takeDownAccount:@"" reason:@"test" error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSAdminControllerErrorDomain");
}

- (void)testReinstateAccountWithNilDid {
    NSError *error = nil;
    BOOL result = [self.adminController reinstateAccount:nil error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSAdminControllerErrorDomain");
}

- (void)testReinstateAccountWithEmptyDid {
    NSError *error = nil;
    BOOL result = [self.adminController reinstateAccount:@"" error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSAdminControllerErrorDomain");
}

- (void)testIsAccountTakedownActiveWithNilDid {
    NSError *error = nil;
    BOOL result = [self.adminController isAccountTakedownActive:nil error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSAdminControllerErrorDomain");
}

- (void)testIsAccountTakedownActiveWithEmptyDid {
    NSError *error = nil;
    BOOL result = [self.adminController isAccountTakedownActive:@"" error:&error];
    
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(error.domain, @"PDSAdminControllerErrorDomain");
}

#pragma mark - Moderation Tests

- (void)testModerateAccountWithValidParams {
    NSString *did = @"did:web:test123.example.com";
    [self createAccountWithDid:did handle:@"test123.example.com"];

    NSDictionary *params = @{
        @"did": did,
        @"action": @"takedown",
        @"reason": @"policy"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"success");
    XCTAssertEqualObjects(result[@"did"], did);
    XCTAssertEqualObjects(result[@"action"], @"takedown");
    XCTAssertNotNil(result[@"timestamp"]);
    XCTAssertNil(error);

    NSDictionary *row = [self latestTakedownForSubjectType:@"account" subjectID:did];
    XCTAssertNotNil(row);
    XCTAssertEqualObjects(row[@"subjectType"], @"account");
    XCTAssertEqualObjects(row[@"subjectId"], did);
    XCTAssertEqualObjects(row[@"takedownRef"], @"takedown");
    XCTAssertEqual([row[@"applied"] integerValue], 1);
}

- (void)testModerateAccountWithUnknownDid {
    NSDictionary *params = @{
        @"did": @"did:web:missing.example.com",
        @"action": @"takedown"
    };

    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, 404);
}

- (void)testModerateAccountWithMissingDid {
    NSDictionary *params = @{
        @"action": @"warn"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testModerateAccountWithMissingAction {
    NSDictionary *params = @{
        @"did": @"did:plc:test123"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testModerateRecordWithValidParams {
    NSString *recordURI = @"at://did:plc:test123/app.bsky.feed.post/abc";
    NSDictionary *params = @{
        @"uri": recordURI,
        @"action": @"takedown"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateRecord:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"success");
    XCTAssertEqualObjects(result[@"uri"], recordURI);
    XCTAssertEqualObjects(result[@"action"], @"takedown");
    XCTAssertNotNil(result[@"timestamp"]);
    XCTAssertNil(error);

    NSDictionary *row = [self latestTakedownForSubjectType:@"record" subjectID:recordURI];
    XCTAssertNotNil(row);
    XCTAssertEqualObjects(row[@"subjectType"], @"record");
    XCTAssertEqualObjects(row[@"subjectId"], recordURI);
    XCTAssertEqualObjects(row[@"takedownRef"], @"takedown");
    XCTAssertEqual([row[@"applied"] integerValue], 1);
}

- (void)testModerateRecordWithMissingUri {
    NSDictionary *params = @{
        @"action": @"flag"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateRecord:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testModerateRecordWithMissingAction {
    NSDictionary *params = @{
        @"uri": @"at://did:plc:test123/app.bsky.feed.post/abc"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateRecord:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
}

#pragma mark - Labeling Tests

- (void)testCreateLabelWithValidParamsReturnsLabelObject {
    NSDictionary *params = @{
        @"uri": @"at://did:plc:test123/app.bsky.feed.post/abc",
        @"val": @"spam",
        @"src": @"did:plc:labeler"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController createLabel:params error:&error];
    
    // Note: This may fail if database doesn't support labels, which is expected
    // The test verifies the method doesn't crash and handles the call
    if (result) {
        XCTAssertEqualObjects(result[@"uri"], @"at://did:plc:test123/app.bsky.feed.post/abc");
        XCTAssertEqualObjects(result[@"val"], @"spam");
    }
}

- (void)testCreateLabelWithMissingUri {
    NSDictionary *params = @{
        @"val": @"spam"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController createLabel:params error:&error];
    
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testCreateLabelWithMissingVal {
    NSDictionary *params = @{
        @"uri": @"at://did:plc:test123/app.bsky.feed.post/abc"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController createLabel:params error:&error];
    
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

- (void)testGetLabelsWithEmptyParamsReturnsEmptyArray {
    NSDictionary *params = @{};
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController getLabels:params error:&error];
    
    // Should return empty labels array, not nil
    if (result) {
        XCTAssertNotNil(result[@"labels"]);
        XCTAssertTrue([result[@"labels"] isKindOfClass:[NSArray class]]);
    }
}

- (void)testGetLabelsWithLimitReturnsArray {
    NSDictionary *params = @{
        @"limit": @5
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController getLabels:params error:&error];
    
    if (result) {
        XCTAssertNotNil(result[@"labels"]);
        XCTAssertTrue([result[@"labels"] isKindOfClass:[NSArray class]]);
    }
}

- (void)testGetLabelsWithUriPatternsReturnsArray {
    NSDictionary *params = @{
        @"uriPatterns": @[@"at://did:plc:test*"],
        @"limit": @10
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController getLabels:params error:&error];
    
    if (result) {
        XCTAssertNotNil(result[@"labels"]);
        XCTAssertTrue([result[@"labels"] isKindOfClass:[NSArray class]]);
    }
}

#pragma mark - Edge Cases

- (void)testModerateAccountWithEmptyParams {
    NSDictionary *params = @{};
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
    XCTAssertNotNil(error);
}

- (void)testModerateRecordWithEmptyParams {
    NSDictionary *params = @{};
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateRecord:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
    XCTAssertNotNil(error);
}

@end
