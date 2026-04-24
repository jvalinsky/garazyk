#import <XCTest/XCTest.h>
#import "Network/HttpProtocolDriver.h"
#import "Network/HttpRequest.h"

@interface HttpProtocolDriverTests : XCTestCase
@property (nonatomic, strong) HttpProtocolDriver *driver;
@end

@implementation HttpProtocolDriverTests

- (void)setUp {
    [super setUp];
    self.driver = [[HttpProtocolDriver alloc] init];
}

- (void)tearDown {
    self.driver = nil;
    [super tearDown];
}

- (void)testFeedSimpleRequestEmitsRequestReady {
    NSString *reqStr = @"GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    NSArray<NSNumber *> *events = [self.driver feedData:reqData];

    XCTAssertGreaterThan(events.count, 0);
    BOOL foundRequestReady = NO;
    for (NSNumber *eventNum in events) {
        HttpProtocolEvent event = (HttpProtocolEvent)[eventNum integerValue];
        if (event == HttpProtocolEventRequestReady) {
            foundRequestReady = YES;
            break;
        }
    }
    XCTAssertTrue(foundRequestReady);
}

- (void)testNextDispatchableRequestReturnsRequest {
    NSString *reqStr = @"GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    [self.driver feedData:reqData];
    HttpRequest *req = [self.driver nextDispatchableRequest];

    XCTAssertNotNil(req);
    XCTAssertEqualObjects(req.path, @"/ping");
}

- (void)testFeedMalformedRequestEmitsProtocolError {
    NSData *reqData = [@"GARBAGE!!!" dataUsingEncoding:NSUTF8StringEncoding];

    NSArray<NSNumber *> *events = [self.driver feedData:reqData];

    BOOL foundError = NO;
    for (NSNumber *eventNum in events) {
        HttpProtocolEvent event = (HttpProtocolEvent)[eventNum integerValue];
        if (event == HttpProtocolEventProtocolError) {
            foundError = YES;
            break;
        }
    }
    XCTAssertTrue(foundError);

    NSError *error = [self.driver currentParseError];
    XCTAssertNotNil(error);
}

- (void)testUpgradeHeaderEmitsUpgradeEvent {
    NSString *upgradeReq = @"GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
    NSData *reqData = [upgradeReq dataUsingEncoding:NSUTF8StringEncoding];

    NSArray<NSNumber *> *events = [self.driver feedData:reqData];

    BOOL foundUpgrade = NO;
    for (NSNumber *eventNum in events) {
        HttpProtocolEvent event = (HttpProtocolEvent)[eventNum integerValue];
        if (event == HttpProtocolEventUpgradeRequested) {
            foundUpgrade = YES;
            break;
        }
    }
    XCTAssertTrue(foundUpgrade);

    HttpRequest *upgradeReq2 = [self.driver currentUpgradeRequest];
    XCTAssertNotNil(upgradeReq2);
}

- (void)testShouldContinueReadingReturnsFalseOnTimeout {
    NSTimeInterval headerStartTime = [[NSDate date] timeIntervalSince1970] - 10.0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval headerTimeout = 5.0;

    BOOL shouldContinue = [self.driver shouldContinueReading:headerStartTime
                                                outputQueueSize:0
                                                   headerTimeout:headerTimeout
                                                             now:now];

    XCTAssertFalse(shouldContinue);
}

- (void)testShouldContinueReadingReturnsFalseOnHighWaterMark {
    NSTimeInterval headerStartTime = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSUInteger highQueueSize = 11 * 1024 * 1024;

    BOOL shouldContinue = [self.driver shouldContinueReading:headerStartTime
                                                outputQueueSize:highQueueSize
                                                   headerTimeout:10.0
                                                             now:now];

    XCTAssertFalse(shouldContinue);
}

- (void)testPendingRequestCountTracksInFlight {
    NSString *req1 = @"GET /test1 HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *data1 = [req1 dataUsingEncoding:NSUTF8StringEncoding];

    NSString *req2 = @"GET /test2 HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *data2 = [req2 dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableData *combinedData = [NSMutableData data];
    [combinedData appendData:data1];
    [combinedData appendData:data2];

    [self.driver feedData:combinedData];

    NSUInteger count = [self.driver pendingRequestCount];
    XCTAssertGreaterThan(count, 0);

    HttpRequest *req = [self.driver nextDispatchableRequest];
    XCTAssertNotNil(req);
}

@end
