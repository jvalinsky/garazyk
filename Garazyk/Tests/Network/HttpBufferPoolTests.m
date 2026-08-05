// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpBufferPool.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpBufferPoolTests : XCTestCase
@end

@implementation HttpBufferPoolTests

- (void)testAcquireReleaseBuffer {
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];

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
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] initWithSizeClasses:@[@(256), @(1024)]];

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
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];

    NSMutableData *buffer1 = [pool acquireBufferOfSize:500];
    [buffer1 appendBytes:"hello" length:5];

    [pool releaseBuffer:buffer1];

    NSMutableData *buffer2 = [pool acquireBufferOfSize:500];
    XCTAssertEqual(buffer2.length, 0);

    [pool releaseBuffer:buffer2];
}

- (void)testAcquireReleaseRequest {
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];

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
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];

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
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];
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
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];

    for (int i = 0; i < 10; i++) {
        NSMutableData *buffer = [pool acquireBufferOfSize:100];
        [pool releaseBuffer:buffer];
    }

    XCTAssertGreaterThan([pool bufferCount], 0);

    [pool drainPools];

    XCTAssertEqual([pool bufferCount], 0);
}

- (void)testZeroSizeBufferReturnsEmptyData {
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] init];

    NSMutableData *buffer = [pool acquireBufferOfSize:0];
    XCTAssertNotNil(buffer);
    XCTAssertEqual(buffer.length, 0);

    [pool releaseBuffer:buffer];
}

- (void)testLargeBufferExceedingSizeClasses {
    ATProtoHttpBufferPool *pool = [[ATProtoHttpBufferPool alloc] initWithSizeClasses:@[@(256), @(1024)]];

    NSMutableData *largeBuffer = [pool acquireBufferOfSize:10000];
    XCTAssertNotNil(largeBuffer);
    XCTAssertEqual(largeBuffer.length, 0U);

    [pool releaseBuffer:largeBuffer];
}

- (void)testSharedPool {
    ATProtoHttpBufferPool *shared1 = [ATProtoHttpBufferPool sharedPool];
    ATProtoHttpBufferPool *shared2 = [ATProtoHttpBufferPool sharedPool];

    XCTAssertEqualObjects(shared1, shared2);
}

@end

NS_ASSUME_NONNULL_END
