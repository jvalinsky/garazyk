// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Debug/GZLogger.h"

@interface GZLoggerPerformanceTests : XCTestCase
@property (nonatomic, copy) NSString *testLogPath;
@end

@implementation GZLoggerPerformanceTests

- (void)setUp {
    [super setUp];
    NSString *tempDir = NSTemporaryDirectory();
    self.testLogPath = [tempDir stringByAppendingPathComponent:@"pds_perf_test.log"];
    [[NSFileManager defaultManager] removeItemAtPath:self.testLogPath error:nil];
}

- (void)tearDown {
    [[GZLogger sharedLogger] flush];
    [[NSFileManager defaultManager] removeItemAtPath:self.testLogPath error:nil];
    [super tearDown];
}

#ifndef GNUSTEP
- (void)testAsyncLoggingPerformance {
    GZLogger *logger = [GZLogger sharedLogger];
    logger.logFilePath = self.testLogPath;
    logger.asyncLogging = YES;
    logger.logLevel = GZLogLevelInfo;
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            GZ_LOG_INFO(@"Performance test message %d", i);
        }
        [logger flush];
    }];
}
#endif

#ifndef GNUSTEP
- (void)testSyncLoggingPerformance {
    GZLogger *logger = [GZLogger sharedLogger];
    logger.logFilePath = self.testLogPath;
    logger.asyncLogging = NO;
    logger.logLevel = GZLogLevelInfo;
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            GZ_LOG_INFO(@"Performance test message %d", i);
        }
    }];
}
#endif

#ifndef GNUSTEP
- (void)testFilteredLoggingPerformance {
    GZLogger *logger = [GZLogger sharedLogger];
    logger.logLevel = GZLogLevelError; // We will log at INFO level, so all should be filtered
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            GZ_LOG_INFO(@"Filtered message %d", i);
        }
    }];
}
#endif

#ifndef GNUSTEP
- (void)testComponentFilteringPerformance {
    GZLogger *logger = [GZLogger sharedLogger];
    logger.logLevel = GZLogLevelDebug;
    logger.enabledComponents = [NSSet setWithObject:GZLogComponentHTTP];
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            GZ_LOG_DB_DEBUG(@"This should be filtered because component is DB");
        }
    }];
}
#endif

@end
