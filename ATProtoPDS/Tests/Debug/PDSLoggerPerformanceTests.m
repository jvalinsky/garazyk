#import <XCTest/XCTest.h>
#import "Debug/PDSLogger.h"

@interface PDSLoggerPerformanceTests : XCTestCase
@property (nonatomic, copy) NSString *testLogPath;
@end

@implementation PDSLoggerPerformanceTests

- (void)setUp {
    [super setUp];
    NSString *tempDir = NSTemporaryDirectory();
    self.testLogPath = [tempDir stringByAppendingPathComponent:@"pds_perf_test.log"];
    [[NSFileManager defaultManager] removeItemAtPath:self.testLogPath error:nil];
}

- (void)tearDown {
    [[PDSLogger sharedLogger] flush];
    [[NSFileManager defaultManager] removeItemAtPath:self.testLogPath error:nil];
    [super tearDown];
}

#ifndef GNUSTEP
- (void)testAsyncLoggingPerformance {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logFilePath = self.testLogPath;
    logger.asyncLogging = YES;
    logger.logLevel = PDSLogLevelInfo;
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            PDS_LOG_INFO(@"Performance test message %d", i);
        }
        [logger flush];
    }];
}
#endif

#ifndef GNUSTEP
- (void)testSyncLoggingPerformance {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logFilePath = self.testLogPath;
    logger.asyncLogging = NO;
    logger.logLevel = PDSLogLevelInfo;
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            PDS_LOG_INFO(@"Performance test message %d", i);
        }
    }];
}
#endif

#ifndef GNUSTEP
- (void)testFilteredLoggingPerformance {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logLevel = PDSLogLevelError; // We will log at INFO level, so all should be filtered
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            PDS_LOG_INFO(@"Filtered message %d", i);
        }
    }];
}
#endif

#ifndef GNUSTEP
- (void)testComponentFilteringPerformance {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logLevel = PDSLogLevelDebug;
    logger.enabledComponents = [NSSet setWithObject:PDSLogComponentHTTP];
    logger.printToStdout = NO;

    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            PDS_LOG_DB_DEBUG(@"This should be filtered because component is DB");
        }
    }];
}
#endif

- (void)testLoggerDoesNotCrashOnNilMessageFormat {
    // Logging a nil-safe format string must not crash.
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.printToStdout = NO;
    XCTAssertNoThrow([logger logWithLevel:PDSLogLevelInfo
                                     file:__FILE__
                                     line:__LINE__
                                   format:@"%@", nil]);
}

- (void)testLogLevelFilteringDropsBelowThreshold {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logLevel = PDSLogLevelError;
    logger.printToStdout = NO;
    logger.logFilePath = nil;

    // These should be silently dropped — must not crash.
    XCTAssertNoThrow([logger logWithLevel:PDSLogLevelDebug
                                     file:__FILE__
                                     line:__LINE__
                                   format:@"debug: should be filtered"]);
    XCTAssertNoThrow([logger logWithLevel:PDSLogLevelInfo
                                     file:__FILE__
                                     line:__LINE__
                                   format:@"info: should be filtered"]);
}

- (void)testLogLevelFilteringAcceptsAtOrAboveThreshold {
    PDSLogger *logger = [PDSLogger sharedLogger];
    logger.logLevel = PDSLogLevelWarn;
    logger.printToStdout = NO;
    logger.logFilePath = nil;

    XCTAssertNoThrow([logger logWithLevel:PDSLogLevelWarn
                                     file:__FILE__
                                     line:__LINE__
                                   format:@"warn: should be logged"]);
    XCTAssertNoThrow([logger logWithLevel:PDSLogLevelError
                                     file:__FILE__
                                     line:__LINE__
                                   format:@"error: should be logged"]);
}

- (void)testSharedLoggerIsSingleton {
    PDSLogger *a = [PDSLogger sharedLogger];
    PDSLogger *b = [PDSLogger sharedLogger];
    XCTAssertEqual(a, b, @"sharedLogger must return the same instance");
}

@end
