// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/Http1Parser.h"

@interface Http1ParserTests : XCTestCase
@property (nonatomic, strong) Http1Parser *parser;
@end

@implementation Http1ParserTests

- (void)setUp {
    [super setUp];
    self.parser = [[Http1Parser alloc] init];
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
    
    HttpRequest *req = [self.parser completedRequest];
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
    
    HttpRequest *req = [self.parser completedRequest];
    XCTAssertEqualObjects(req.methodString, @"GET");
}

- (void)testContentLengthBody {
    NSString *body = @"Hello World";
    NSString *reqStr = [NSString stringWithFormat:@"POST / HTTP/1.1\r\nContent-Length: %lu\r\n\r\n%@", (unsigned long)body.length, body];
    NSData *reqData = [reqStr dataUsingEncoding:NSUTF8StringEncoding];
    
    BOOL complete = [self.parser feedData:reqData];
    XCTAssertTrue(complete);
    
    HttpRequest *req = [self.parser completedRequest];
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
    
    HttpRequest *req = [self.parser completedRequest];
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
    
    Http1ParserError *err = [self.parser parseError];
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
    
    Http1ParserError *err = [self.parser parseError];
    XCTAssertNotNil(err);
    XCTAssertEqual(err.statusCode, 411);
    XCTAssertEqualObjects(err.errorCode, @"LengthRequired");
}

- (void)testPipelinedDataRetention {
    NSString *req1 = @"GET /1 HTTP/1.1\r\n\r\n";
    NSString *req2 = @"GET /2 HTTP/1.1\r\n\r\n";
    NSString *combined = [NSString stringWithFormat:@"%@%@", req1, req2];
    
    BOOL complete = [self.parser feedData:[combined dataUsingEncoding:NSUTF8StringEncoding]];
    XCTAssertTrue(complete);
    
    HttpRequest *req = [self.parser completedRequest];
    XCTAssertEqualObjects(req.path, @"/1");
    
    NSData *unconsumed = [self.parser unconsumedData];
    NSString *unconsumedStr = [[NSString alloc] initWithData:unconsumed encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(unconsumedStr, req2);
}

@end
