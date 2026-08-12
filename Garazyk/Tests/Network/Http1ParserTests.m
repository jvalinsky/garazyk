// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/Http1Parser.h"

@interface Http1ParserTests : XCTestCase
@property (nonatomic, strong) ATProtoHttp1Parser *parser;
@end

@implementation Http1ParserTests

- (void)setUp {
    [super setUp];
    self.parser = [[ATProtoHttp1Parser alloc] init];
    self.parser.remoteAddress = @"127.0.0.1";
}

- (void)tearDown {
    self.parser = nil;
    [super tearDown];
}

- (void)testSimpleGetRequest {
    NSString *reqStr = @"GET /test?foo=bar HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    
    ATProtoHttpRequest *req = [self.parser completedRequest];
    XCTAssertNotNil(req);
    XCTAssertNil([self.parser parseError]);
    
    XCTAssertEqualObjects(req.methodString, @"GET");
    XCTAssertEqualObjects(req.path, @"/test");
    XCTAssertEqualObjects(req.queryString, @"foo=bar");
    XCTAssertEqualObjects(req.headers[@"host"], @"localhost");
    XCTAssertEqualObjects(req.remoteAddress, @"127.0.0.1");
}

- (void)testPartialHeaderDelivery {
    NSString *reqStr = @"GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete1 = [self.parser feedData:[reqData subdataWithRange:NSMakeRange(0, 10)]];
    XCTAssertFalse(complete1);
    XCTAssertEqual(self.parser.state, Http1ParserStateReadingHeaders);
    
    BOOL complete2 = [self.parser feedData:[reqData subdataWithRange:NSMakeRange(10, reqData.length - 10)]];
    XCTAssertTrue(complete2);
    XCTAssertEqual(self.parser.state, Http1ParserStateComplete);
    
    ATProtoHttpRequest *req = [self.parser completedRequest];
    XCTAssertEqualObjects(req.methodString, @"GET");
}

- (void)testContentLengthBody {
    NSString *body = @"Hello World";
    NSString *reqStr = [NSString stringWithFormat:@"POST / HTTP/1.1\r\nContent-Length: %lu\r\n\r\n%@", (unsigned long)body.length, body];
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    
    ATProtoHttpRequest *req = [self.parser completedRequest];
    XCTAssertNotNil(req);
    XCTAssertEqualObjects(req.methodString, @"POST");
    
    NSString *parsedBody = [[NSString alloc] initWithData:req.body encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(parsedBody, @"Hello World");
}

- (void)testPartialBodyDelivery {
    NSString *reqStr = @"POST / HTTP/1.1\r\nContent-Length: 11\r\n\r\nHello ";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete1 = [self.parser feedData:reqData];
    XCTAssertFalse(complete1);
    XCTAssertEqual(self.parser.state, Http1ParserStateReadingBody);
    
    NSData *restData = [@"World" dataUsingEncoding:NSUTF8StringEncoding];
    BOOL complete2 = [self.parser feedData:restData];
    XCTAssertTrue(complete2);
    XCTAssertEqual(self.parser.state, Http1ParserStateComplete);
    
    ATProtoHttpRequest *req = [self.parser completedRequest];
    NSString *parsedBody = [[NSString alloc] initWithData:req.body encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(parsedBody, @"Hello World");
}

- (void)testOversizedHeader {
    self.parser.maxHeaderBytes = 50; // Small limit
    
    NSString *reqStr = @"GET / HTTP/1.1\r\nX-Custom-Header: extremely-long-value-that-exceeds-the-limit\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);
    
    ATProtoHttp1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 413);
    XCTAssertEqualObjects(err.errorCode, @"RequestTooLarge");
}

- (void)testLengthRequired {
    // POST without Content-Length
    NSString *reqStr = @"POST / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);
    
    ATProtoHttp1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 411);
    XCTAssertEqualObjects(err.errorCode, @"LengthRequired");
}

- (void)testConflictingContentLengthHeadersRejected {
    // RFC 7230 §3.3.3: multiple Content-Length headers with different
    // values must be rejected, not silently resolved to the first value.
    NSString *reqStr = @"POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 10\r\n\r\nhello";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);

    ATProtoHttp1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 400);
}

- (void)testDuplicateIdenticalContentLengthHeadersRejected {
    // Even identical duplicates are rejected -- RFC 7230 §3.3.3 permits
    // treating identical duplicates as valid, but this codebase takes the
    // stricter reject-duplicates reading.
    NSString *reqStr = @"POST / HTTP/1.1\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);

    ATProtoHttp1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 400);
}

- (void)testContentLengthWithSignRejected {
    NSString *reqStr = @"POST / HTTP/1.1\r\nContent-Length: +5\r\n\r\nhello";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);

    ATProtoHttp1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 400);
}

- (void)testContentLengthWithTrailingGarbageRejected {
    NSString *reqStr = @"POST / HTTP/1.1\r\nContent-Length: 5x\r\n\r\nhello";
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];

    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);

    ATProtoHttp1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 400);
}

- (void)testBodySizeLimitProviderOverridesGenericCapForMatchingPath {
    // Route-specific caps (e.g. com.atproto.repo.importRepo admitting large
    // bodies) must override the generic parser limit for that path only.
    self.parser.maxBodyBytes = 8; // tiny generic cap
    self.parser.bodySizeLimitProvider = ^NSUInteger(NSString *path) {
        if ([path isEqualToString:@"/xrpc/com.atproto.repo.importRepo"]) {
            return 1024 * 1024;
        }
        return 0; // fall back to maxBodyBytes
    };

    NSString *body = [@"" stringByPaddingToLength:64 withString:@"x" startingAtIndex:0];
    NSString *reqStr = [NSString stringWithFormat:
        @"POST /xrpc/com.atproto.repo.importRepo HTTP/1.1\r\n"
        @"Host: localhost\r\n"
        @"Content-Type: application/vnd.ipld.car\r\n"
        @"Content-Length: %lu\r\n\r\n%@",
        (unsigned long)body.length, body];

    BOOL complete = [self.parser feedData:[reqStr dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertTrue(complete, @"%@", [self.parser parseError]);
    XCTAssertEqual(self.parser.state, Http1ParserStateComplete);
    XCTAssertNil([self.parser parseError]);
    XCTAssertEqualObjects([self.parser completedRequest].path, @"/xrpc/com.atproto.repo.importRepo");
}

- (void)testBodySizeLimitProviderFallbackKeepsGenericCapForOtherPaths {
    // A provider returning 0 for a path must fall back to maxBodyBytes, so
    // the route-specific relaxation never widens unrelated endpoints.
    self.parser.maxBodyBytes = 8;
    self.parser.bodySizeLimitProvider = ^NSUInteger(NSString *path) {
        if ([path isEqualToString:@"/xrpc/com.atproto.repo.importRepo"]) {
            return 1024 * 1024;
        }
        return 0;
    };

    NSString *body = [@"" stringByPaddingToLength:64 withString:@"x" startingAtIndex:0];
    NSString *reqStr = [NSString stringWithFormat:
        @"POST /xrpc/com.atproto.repo.getRecord HTTP/1.1\r\n"
        @"Content-Length: %lu\r\n\r\n%@",
        (unsigned long)body.length, body];

    BOOL complete = [self.parser feedData:[reqStr dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertTrue(complete);
    XCTAssertEqual(self.parser.state, Http1ParserStateError);
    XCTAssertEqual([self.parser parseError].statusCode, 413);
    XCTAssertEqualObjects([self.parser parseError].errorCode, @"RequestTooLarge");
}

- (void)testPipelinedDataRetention {
    NSString *req1 = @"GET /1 HTTP/1.1\r\n\r\n";
    NSString *req2 = @"GET /2 HTTP/1.1\r\n\r\n";
    NSString *combined = [NSString stringWithFormat:@"%@%@", req1, req2];
    
    BOOL complete = [self.parser feedData:[combined dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertTrue(complete);
    
    ATProtoHttpRequest *req = [self.parser completedRequest];
    XCTAssertEqualObjects(req.path, @"/1");
    
    NSData *unconsumed = [self.parser unconsumedData];
    NSString *unconsumedStr = [[NSString alloc] initWithData:unconsumed encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(unconsumedStr, req2);
}

@end
