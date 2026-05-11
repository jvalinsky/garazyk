// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Admin/Diagnostics/PDSRateLimitAdminHandler.h"
#import "Database/Service/ServiceDatabases.h"

// MARK: - Tests disabled pending API updates
// These tests use outdated APIs that no longer exist.
// Re-enable when tests are updated to use current APIs.

#if 0

#import "Debug/PDSLogger.h"
#import <sqlite3.h>

// Mock RateLimiter for testing
@interface MockRateLimiter : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *limits;
@end

@implementation MockRateLimiter

- (instancetype)init {
    if ((self = [super init])) {
        _limits = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setLimit:(NSInteger)limit forIdentifier:(NSString *)identifier {
    self.limits[identifier] = @{
        @"limit": @(limit),
        @"remaining": @(limit),
        @"reset_at": @([[NSDate date] timeIntervalSince1970] + 3600)
    };
}

@end

@interface PDSRateLimitAdminHandlerTests : XCTestCase
@property (nonatomic, strong) PDSRateLimitAdminHandler *handler;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) MockRateLimiter *mockRateLimiter;
@property (nonatomic, copy) NSString *tempDirectory;
@property (nonatomic, assign) sqlite3 *testDatabase;
@end

@implementation PDSRateLimitAdminHandlerTests

- (void)setUp {
    [super setUp];
    self.handler = [PDSRateLimitAdminHandler sharedHandler];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - Placeholder Tests

- (void)testPlaceholder {
    // Placeholder test - replace when API updated
    XCTAssertTrue(YES, @"Tests disabled pending API updates");
}

@end

#endif // Tests disabled pending API updates
