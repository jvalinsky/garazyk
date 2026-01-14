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

@end
