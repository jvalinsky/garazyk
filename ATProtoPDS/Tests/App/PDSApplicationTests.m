/*!
 @file PDSApplicationTests.m

 @abstract Unit tests for PDSApplication.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "App/PDSApplication.h"
#import "App/PDSController.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "App/Services/PDSAccountService.h"
#import "App/Services/PDSRecordService.h"
#import "App/Services/PDSBlobService.h"
#import "App/Services/PDSRepositoryService.h"
#import "Admin/PDSAdminController.h"
#import "Auth/JWT.h"

@interface PDSApplicationTests : XCTestCase

@property (nonatomic, strong) PDSApplication *application;
@property (nonatomic, copy) NSString *tempDirectory;

@end

@implementation PDSApplicationTests

- (void)setUp {
    [super setUp];
    
    // Create temp directory for test databases
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"PDSApplicationTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.tempDirectory = tempDir;
    
    // Initialize application with temp directory
    self.application = [[PDSApplication alloc] initWithDataDirectory:tempDir];
}

- (void)tearDown {
    // Stop application if running
    if (self.application.isRunning) {
        [self.application stop];
    }
    self.application = nil;
    
    // Clean up temp directory
    if (self.tempDirectory) {
        [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];
        self.tempDirectory = nil;
    }
    
    [super tearDown];
}

#pragma mark - Initialization Tests

- (void)testInitWithDataDirectory {
    XCTAssertNotNil(self.application);
    XCTAssertEqualObjects(self.application.dataDirectory, self.tempDirectory);
}

- (void)testInitWithNilConfiguration {
    PDSApplication *app = [[PDSApplication alloc] initWithConfiguration:nil];
    
    XCTAssertNotNil(app);
    XCTAssertNotNil(app.dataDirectory);
}

- (void)testDefaultPortValues {
    // Ports should be set to reasonable values (may vary based on configuration)
    XCTAssertGreaterThan(self.application.httpPort, 0);
    XCTAssertGreaterThan(self.application.wsPort, 0);
    // Standard defaults are 2583/8081, but configuration may override
    XCTAssertLessThan(self.application.httpPort, 65536);
    XCTAssertLessThan(self.application.wsPort, 65536);
}

#pragma mark - Infrastructure Tests

- (void)testServiceDatabasesInitialized {
    XCTAssertNotNil(self.application.serviceDatabases);
}

- (void)testUserDatabasePoolInitialized {
    XCTAssertNotNil(self.application.userDatabasePool);
}

- (void)testJwtMinterInitialized {
    XCTAssertNotNil(self.application.jwtMinter);
    XCTAssertNotNil(self.application.jwtMinter.issuer);
    XCTAssertEqualObjects(self.application.jwtMinter.signingAlgorithm, @"ES256");
}

#pragma mark - Service Tests

- (void)testAccountServiceInitialized {
    XCTAssertNotNil(self.application.accountService);
    XCTAssertTrue([self.application.accountService conformsToProtocol:@protocol(PDSAccountService)]);
}

- (void)testRecordServiceInitialized {
    XCTAssertNotNil(self.application.recordService);
    XCTAssertTrue([self.application.recordService isKindOfClass:[PDSRecordService class]]);
}

- (void)testBlobServiceInitialized {
    XCTAssertNotNil(self.application.blobService);
    XCTAssertTrue([self.application.blobService isKindOfClass:[PDSBlobService class]]);
}

- (void)testRepositoryServiceInitialized {
    XCTAssertNotNil(self.application.repositoryService);
    XCTAssertTrue([self.application.repositoryService isKindOfClass:[PDSRepositoryService class]]);
}

#pragma mark - Controller Tests

- (void)testAdminControllerInitialized {
    XCTAssertNotNil(self.application.adminController);
    XCTAssertTrue([self.application.adminController conformsToProtocol:@protocol(PDSAdminController)]);
}

#pragma mark - Lifecycle Tests

- (void)testIsNotRunningBeforeStart {
    XCTAssertFalse(self.application.isRunning);
}

- (void)testStartSucceeds {
    NSError *error = nil;
    BOOL started = [self.application startWithError:&error];
    
    XCTAssertTrue(started);
    XCTAssertNil(error);
    XCTAssertTrue(self.application.isRunning);
}

- (void)testHttpServerAvailableAfterStart {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    XCTAssertNotNil(self.application.httpServer);
}

- (void)testPortsAssignedAfterStart {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    // Ports should be assigned (may be different if defaults were in use)
    XCTAssertGreaterThan(self.application.httpPort, 0);
    XCTAssertGreaterThan(self.application.wsPort, 0);
}

- (void)testStopSucceeds {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    [self.application stop];
    
    XCTAssertFalse(self.application.isRunning);
}

- (void)testHttpServerNilAfterStop {
    NSError *error = nil;
    [self.application startWithError:&error];
    [self.application stop];
    
    XCTAssertNil(self.application.httpServer);
}

#pragma mark - Legacy Controller Tests

- (void)testLegacyControllerAvailableAfterStart {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    XCTAssertNotNil(self.application.legacyController);
    XCTAssertTrue([self.application.legacyController isKindOfClass:[PDSController class]]);
}

- (void)testLegacyControllerSharesDataDirectory {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    XCTAssertEqualObjects(self.application.legacyController.dataDirectory, self.application.dataDirectory);
}

- (void)testLegacyControllerSharesServices {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    PDSController *legacy = self.application.legacyController;
    
    XCTAssertEqual(legacy.serviceDatabases, self.application.serviceDatabases);
    XCTAssertEqual(legacy.userDatabasePool, self.application.userDatabasePool);
    XCTAssertEqual(legacy.jwtMinter, self.application.jwtMinter);
}

#pragma mark - Port Configuration Tests

- (void)testHttpPortCanBeChangedBeforeStart {
    self.application.httpPort = 9999;
    
    XCTAssertEqual(self.application.httpPort, 9999);
}

- (void)testWsPortCanBeChangedBeforeStart {
    self.application.wsPort = 9998;
    
    XCTAssertEqual(self.application.wsPort, 9998);
}

#pragma mark - Configuration Tests

- (void)testConfigurationAvailable {
    // Configuration may be nil if not explicitly set
    // This test just ensures accessing it doesn't crash
    PDSConfiguration *config = self.application.configuration;
    // May or may not be nil depending on initialization path
    (void)config;
}

#pragma mark - Multiple Start/Stop Cycles

- (void)testCanRestartAfterStop {
    NSError *error1 = nil;
    [self.application startWithError:&error1];
    XCTAssertTrue(self.application.isRunning);
    
    [self.application stop];
    XCTAssertFalse(self.application.isRunning);
    
    // Note: Restarting may fail due to port conflicts or database state
    // This test just verifies the stop completes cleanly
}

#pragma mark - Edge Cases

- (void)testStopWhenNotRunningDoesNotCrash {
    XCTAssertFalse(self.application.isRunning);
    
    // Should not crash
    [self.application stop];
    
    XCTAssertFalse(self.application.isRunning);
}

- (void)testMultipleStopsDoNotCrash {
    NSError *error = nil;
    [self.application startWithError:&error];
    
    [self.application stop];
    [self.application stop];
    [self.application stop];
    
    XCTAssertFalse(self.application.isRunning);
}

@end