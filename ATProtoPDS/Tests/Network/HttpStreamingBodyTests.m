#import <XCTest/XCTest.h>
#import "Network/HttpStreamingBody.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpStreamingBodyTests : XCTestCase
@end

@implementation HttpStreamingBodyTests

- (void)testSmallBodyBuffersInMemory {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:1024];

    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL result = [handler appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertFalse(handler.isComplete);
    XCTAssertNil(handler.filePath);
    XCTAssertEqualObjects(handler.data, data);
    XCTAssertEqual(handler.length, (NSUInteger)11);
}

- (void)testLargeBodyStreamsToFile {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:10];

    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL result = [handler appendData:data error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertNotNil(handler.filePath);
    XCTAssertEqual(handler.length, (NSUInteger)11);

    [handler finalizeWithError:nil];
    XCTAssertEqualObjects(handler.data, data);
}

- (void)testFinalizeCompletes {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:1024];

    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [handler appendData:data error:nil];
    XCTAssertFalse(handler.isComplete);

    NSError *error = nil;
    BOOL result = [handler finalizeWithError:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue(handler.isComplete);
}

- (void)testCreateInputStream {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:1024];

    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [handler appendData:data error:nil];
    [handler finalizeWithError:nil];

    NSInputStream *stream = [handler createInputStream];
    XCTAssertNotNil(stream);

    [stream open];

    NSMutableData *resultData = [NSMutableData data];
    uint8_t buffer[1024];
    NSInteger bytesRead = [stream read:buffer maxLength:sizeof(buffer)];
    while (bytesRead > 0) {
        [resultData appendBytes:buffer length:bytesRead];
        bytesRead = [stream read:buffer maxLength:sizeof(buffer)];
    }

    [stream close];

    XCTAssertEqualObjects(resultData, data);
}

- (void)testMultipleAppends {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:1024];

    NSError *error = nil;
    XCTAssertTrue([handler appendData:[@"Hello " dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertTrue([handler appendData:[@"World" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);

    [handler finalizeWithError:nil];

    XCTAssertEqualObjects(handler.data, [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(handler.length, (NSUInteger)11);
}

- (void)testReset {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:10];

    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [handler appendData:data error:nil];
    XCTAssertNotNil(handler.filePath);

    [handler reset];

    XCTAssertNil(handler.filePath);
    XCTAssertEqual(handler.length, (NSUInteger)0);
    XCTAssertFalse(handler.isComplete);
    XCTAssertEqual(handler.data.length, (NSUInteger)0);
}

- (void)testEmptyData {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] init];

    NSError *error = nil;
    BOOL result = [handler appendData:[NSData data] error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertEqual(handler.length, (NSUInteger)0);
}

- (void)testLargeBodyThreshold {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:5];

    XCTAssertTrue([handler appendData:[@"12345" dataUsingEncoding:NSUTF8StringEncoding] error:nil]);
    XCTAssertNil(handler.filePath);
    XCTAssertEqual(handler.length, (NSUInteger)5);

    XCTAssertTrue([handler appendData:[@"6" dataUsingEncoding:NSUTF8StringEncoding] error:nil]);
    XCTAssertNotNil(handler.filePath);
    XCTAssertEqual(handler.length, (NSUInteger)6);
}

- (void)testBoundaryCondition {
    HttpStreamingBody *handler = [[HttpStreamingBody alloc] initWithMemoryThreshold:10];

    XCTAssertTrue([handler appendData:[@"1234567890" dataUsingEncoding:NSUTF8StringEncoding] error:nil]);
    XCTAssertNil(handler.filePath);

    XCTAssertTrue([handler appendData:[@"1" dataUsingEncoding:NSUTF8StringEncoding] error:nil]);
    XCTAssertNotNil(handler.filePath);
}

@end

NS_ASSUME_NONNULL_END
