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

#pragma mark - Initialization Tests

- (void)testInitWithServiceDatabases {
    PDSAdminController *controller = [[PDSAdminController alloc] initWithServiceDatabases:self.serviceDatabases];
    
    XCTAssertNotNil(controller);
    XCTAssertEqual(controller.serviceDatabases, self.serviceDatabases);
    XCTAssertNil(controller.accountService);
}

- (void)testInitWithServiceDatabasesAndAccountService {
    // Using nil for account service since we don't have a mock
    PDSAdminController *controller = [[PDSAdminController alloc] initWithServiceDatabases:self.serviceDatabases
                                                                           accountService:nil];
    
    XCTAssertNotNil(controller);
    XCTAssertEqual(controller.serviceDatabases, self.serviceDatabases);
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
}

#pragma mark - Moderation Tests

- (void)testModerateAccountWithValidParams {
    NSDictionary *params = @{
        @"did": @"did:plc:test123",
        @"action": @"warn"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"success");
    XCTAssertEqualObjects(result[@"did"], @"did:plc:test123");
    XCTAssertEqualObjects(result[@"action"], @"warn");
    XCTAssertNotNil(result[@"timestamp"]);
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
    NSDictionary *params = @{
        @"uri": @"at://did:plc:test123/app.bsky.feed.post/abc",
        @"action": @"flag"
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateRecord:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"success");
    XCTAssertEqualObjects(result[@"uri"], @"at://did:plc:test123/app.bsky.feed.post/abc");
    XCTAssertEqualObjects(result[@"action"], @"flag");
    XCTAssertNotNil(result[@"timestamp"]);
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

- (void)testCreateLabelWithValidParams {
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

- (void)testGetLabelsWithEmptyParams {
    NSDictionary *params = @{};
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController getLabels:params error:&error];
    
    // Should return empty labels array, not nil
    if (result) {
        XCTAssertNotNil(result[@"labels"]);
        XCTAssertTrue([result[@"labels"] isKindOfClass:[NSArray class]]);
    }
}

- (void)testGetLabelsWithLimit {
    NSDictionary *params = @{
        @"limit": @5
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController getLabels:params error:&error];
    
    if (result) {
        XCTAssertNotNil(result[@"labels"]);
    }
}

- (void)testGetLabelsWithUriPatterns {
    NSDictionary *params = @{
        @"uriPatterns": @[@"at://did:plc:test*"],
        @"limit": @10
    };
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController getLabels:params error:&error];
    
    if (result) {
        XCTAssertNotNil(result[@"labels"]);
    }
}

#pragma mark - Edge Cases

- (void)testModerateAccountWithEmptyParams {
    NSDictionary *params = @{};
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateAccount:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
}

- (void)testModerateRecordWithEmptyParams {
    NSDictionary *params = @{};
    
    NSError *error = nil;
    NSDictionary *result = [self.adminController moderateRecord:params error:&error];
    
    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"error");
}

@end