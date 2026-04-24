#import <XCTest/XCTest.h>
#import "Network/HttpResponseSender.h"

@interface HttpResponseSenderTests : XCTestCase
@property (nonatomic, strong) HttpResponseSender *sender;
@end

@implementation HttpResponseSenderTests

- (void)setUp {
    [super setUp];
    self.sender = [[HttpResponseSender alloc] init];
}

- (void)tearDown {
    self.sender = nil;
    [super tearDown];
}

- (void)testHasBackpressureReturnsFalseBelowMark {
    self.sender.highWaterMark = 1 * 1024 * 1024;
    NSUInteger queueSize = 512 * 1024;

    BOOL hasBackpressure = [self.sender hasBackpressure:queueSize];

    XCTAssertFalse(hasBackpressure);
}

- (void)testHasBackpressureReturnsTrueAtOrAboveMark {
    self.sender.highWaterMark = 1 * 1024 * 1024;
    NSUInteger queueSize = 1 * 1024 * 1024;

    BOOL hasBackpressure = [self.sender hasBackpressure:queueSize];

    XCTAssertTrue(hasBackpressure);
}

- (void)testClampedQueueSizeNeverGoesNegative {
    NSUInteger queueSize = 100;
    NSUInteger itemBytes = 200;

    NSUInteger result = [self.sender clampedQueueSizeAfterDequeue:queueSize itemBytes:itemBytes];

    XCTAssertEqual(result, 0);
}

- (void)testClampedQueueSizeSubtractsCorrectly {
    NSUInteger queueSize = 1000;
    NSUInteger itemBytes = 300;

    NSUInteger result = [self.sender clampedQueueSizeAfterDequeue:queueSize itemBytes:itemBytes];

    XCTAssertEqual(result, 700);
}

- (void)testShouldTrimQueueWithCurrentSize {
    NSUInteger highWaterMark = 1024;

    BOOL shouldTrim1 = [self.sender shouldTrimQueueWithCurrentSize:1025 highWaterMark:highWaterMark];
    XCTAssertTrue(shouldTrim1);

    BOOL shouldTrim2 = [self.sender shouldTrimQueueWithCurrentSize:1023 highWaterMark:highWaterMark];
    XCTAssertFalse(shouldTrim2);
}

- (void)testDefaultHighWaterMarkIs10MB {
    HttpResponseSender *sender = [[HttpResponseSender alloc] init];

    XCTAssertEqual(sender.highWaterMark, 10 * 1024 * 1024);
}

@end
