#import <XCTest/XCTest.h>
#import "Network/HttpBufferPool.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpBufferPoolTests : XCTestCase
@end

@implementation HttpBufferPoolTests

- (void)testAcquireReleaseBuffer {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];

    NSMutableData *buffer1 = [pool acquireBufferOfSize:100];
    XCTAssertNotNil(buffer1);
    XCTAssertEqual(buffer1.length, 0);

    [pool releaseBuffer:buffer1];

    NSMutableData *buffer2 = [pool acquireBufferOfSize:100];
    XCTAssertNotNil(buffer2);
    XCTAssertEqual(buffer2.length, 0);

    [pool releaseBuffer:buffer2];
}

- (void)testBufferSizeClasses {
    HttpBufferPool *pool = [[HttpBufferPool alloc] initWithSizeClasses:@[@(256), @(1024)]];

    NSMutableData *smallBuffer = [pool acquireBufferOfSize:100];
    XCTAssertNotNil(smallBuffer);

    NSMutableData *mediumBuffer = [pool acquireBufferOfSize:500];
    XCTAssertNotNil(mediumBuffer);

    NSMutableData *largeBuffer = [pool acquireBufferOfSize:2000];
    XCTAssertNotNil(largeBuffer);

    [pool releaseBuffer:smallBuffer];
    [pool releaseBuffer:mediumBuffer];
    [pool releaseBuffer:largeBuffer];

    XCTAssertEqual([pool bufferCount], 3);
}

- (void)testBufferReuse {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];

    NSMutableData *buffer1 = [pool acquireBufferOfSize:500];
    [buffer1 appendBytes:"hello" length:5];

    [pool releaseBuffer:buffer1];

    NSMutableData *buffer2 = [pool acquireBufferOfSize:500];
    XCTAssertEqual(buffer2.length, 0);

    [pool releaseBuffer:buffer2];
}

- (void)testAcquireReleaseRequest {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];

    HttpRequest *request1 = [pool acquireRequest];
    XCTAssertNil(request1);

    HttpRequest *createdRequest = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                        methodString:@"GET"
                                                                path:@"/test"
                                                         queryString:@""
                                                          queryParams:@{}
                                                              version:@"HTTP/1.1"
                                                              headers:@{}
                                                                 body:[NSData data]
                                                         remoteAddress:@"127.0.0.1"];

    [pool releaseRequest:createdRequest];

    HttpRequest *request2 = [pool acquireRequest];
    XCTAssertNotNil(request2);

    [pool releaseRequest:request2];
}

- (void)testAcquireReleaseResponse {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];

    HttpResponse *response1 = [pool acquireResponse];
    XCTAssertNil(response1);

    HttpResponse *createdResponse = [HttpResponse responseWithStatusCode:HttpStatusOK];

    [pool releaseResponse:createdResponse];

    HttpResponse *response2 = [pool acquireResponse];
    XCTAssertNotNil(response2);
    XCTAssertEqual(response2.statusCode, HttpStatusOK);

    [pool releaseResponse:response2];
}

- (void)testMaxPoolSize {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];
    pool.maxPoolSize = 3;

    NSMutableArray<NSMutableData *> *buffers;
    for (int i = 0; i < 5; i++) {
        NSMutableData *buffer = [pool acquireBufferOfSize:100];
        [buffers addObject:buffer];
        [pool releaseBuffer:buffer];
    }

    XCTAssertLessThanOrEqual([pool bufferCount], pool.maxPoolSize);
}

- (void)testDrainPoolsEmptiesPool {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];

    for (int i = 0; i < 10; i++) {
        NSMutableData *buffer = [pool acquireBufferOfSize:100];
        [pool releaseBuffer:buffer];
    }

    XCTAssertGreaterThan([pool bufferCount], 0);

    [pool drainPools];

    XCTAssertEqual([pool bufferCount], 0);
}

- (void)testZeroSizeBufferReturnsEmptyData {
    HttpBufferPool *pool = [[HttpBufferPool alloc] init];

    NSMutableData *buffer = [pool acquireBufferOfSize:0];
    XCTAssertNotNil(buffer);
    XCTAssertEqual(buffer.length, 0);

    [pool releaseBuffer:buffer];
}

- (void)testLargeBufferExceedingSizeClasses {
    HttpBufferPool *pool = [[HttpBufferPool alloc] initWithSizeClasses:@[@(256), @(1024)]];

    NSMutableData *largeBuffer = [pool acquireBufferOfSize:10000];
    XCTAssertNotNil(largeBuffer);
    XCTAssertEqual(largeBuffer.length, 0U);

    [pool releaseBuffer:largeBuffer];
}

- (void)testSharedPool {
    HttpBufferPool *shared1 = [HttpBufferPool sharedPool];
    HttpBufferPool *shared2 = [HttpBufferPool sharedPool];

    XCTAssertEqualObjects(shared1, shared2);
}

@end

NS_ASSUME_NONNULL_END
