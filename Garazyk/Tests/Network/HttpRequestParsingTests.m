// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpRequestParsingTests : XCTestCase
@end

@implementation HttpRequestParsingTests

- (NSString *)_savedEnvValueForKey:(const char *)key {
    const char *value = getenv(key);
    return value ? [NSString stringWithUTF8String:value] : nil;
}

- (void)_restoreEnvKey:(const char *)key toValue:(NSString *)savedValue {
    if (savedValue) {
        setenv(key, savedValue.UTF8String, 1);
    } else {
        unsetenv(key);
    }
}

- (void)testParseGetWithQueryAndHeaders {
    NSString *raw = @"GET /xrpc/test?foo=bar&empty=&flag HTTP/1.1\r\n"
                    "Host: example.com\r\n"
                    "X-Request-Id: req-123\r\n"
                    "\r\n";
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    HttpRequest *request = [HttpRequest requestWithData:data];

    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, HttpMethodGET);
    XCTAssertEqualObjects(request.path, @"/xrpc/test");
    XCTAssertEqualObjects(request.queryString, @"foo=bar&empty=&flag");
    XCTAssertEqualObjects(request.queryParams[@"foo"], @"bar");
    XCTAssertEqualObjects(request.queryParams[@"empty"], @"");
    XCTAssertEqualObjects(request.queryParams[@"flag"], @"");
    XCTAssertEqualObjects([request headerForKey:@"Host"], @"example.com");
    XCTAssertEqualObjects(request.correlationID, @"req-123");
}

- (void)testParseJsonBody {
    NSString *raw = @"POST /xrpc/test HTTP/1.1\r\n"
                    "Content-Type: application/json\r\n"
                    "\r\n"
                    "{\"name\":\"test\"}";
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    HttpRequest *request = [HttpRequest requestWithData:data];

    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, HttpMethodPOST);
    XCTAssertNotNil(request.jsonBody);
    XCTAssertEqualObjects(request.jsonBody[@"name"], @"test");
}

- (void)testParseMultipartFormData {
    NSString *boundary = @"boundary123";
    NSString *body = [NSString stringWithFormat:@"--%@\r\n"
                      "Content-Disposition: form-data; name=\"text\"\r\n"
                      "\r\n"
                      "hello\r\n"
                      "--%@\r\n"
                      "Content-Disposition: form-data; name=\"blob\"\r\n"
                      "\r\n"
                      "blobdata\r\n"
                      "--%@--\r\n", boundary, boundary, boundary];
    NSString *raw = [NSString stringWithFormat:@"POST /upload HTTP/1.1\r\n"
                     "Content-Type: multipart/form-data; boundary=%@\r\n"
                     "\r\n"
                     "%@", boundary, body];
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    HttpRequest *request = [HttpRequest requestWithData:data];

    XCTAssertNotNil(request);
    XCTAssertNotNil(request.multipartFormData);
    XCTAssertEqualObjects(request.multipartFormData[@"text"], @"hello");

    NSData *blob = request.multipartFormData[@"blob"];
    NSData *expected = [@"blobdata" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(blob, expected);
}

- (void)testParseChunkedTransferEncodingHeader {
    NSString *raw = @"POST /upload HTTP/1.1\r\n"
                    "Host: example.com\r\n"
                    "Transfer-Encoding: chunked\r\n"
                    "\r\n"
                    "5\r\nHello\r\n"
                    "0\r\n\r\n";
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    HttpRequest *request = [HttpRequest requestWithData:data];

    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, HttpMethodPOST);
    XCTAssertEqualObjects([request headerForKey:@"Transfer-Encoding"], @"chunked");
}

- (void)testParseChunkedTransferEncodingCaseInsensitive {
    NSString *raw = @"POST /upload HTTP/1.1\r\n"
                    "Transfer-Encoding: CHUNKED\r\n"
                    "\r\n"
                    "3\r\nBye\r\n"
                    "0\r\n\r\n";
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    HttpRequest *request = [HttpRequest requestWithData:data];

    XCTAssertNotNil(request);
    XCTAssertEqualObjects([request headerForKey:@"Transfer-Encoding"], @"CHUNKED");
}

- (void)testForwardedHeadersIgnoredWhenProxyTrustDisabledMatchesRemoteAddress {
    NSString *savedTrustProxy = [self _savedEnvValueForKey:"PDS_TRUST_PROXY_HEADERS"];
    unsetenv("PDS_TRUST_PROXY_HEADERS");

    @try {
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                       methodString:@"GET"
                                                               path:@"/xrpc/test"
                                                        queryString:@""
                                                        queryParams:@{}
                                                            version:@"1.1"
                                                            headers:@{@"x-forwarded-for": @"203.0.113.42"}
                                                               body:[NSData data]
                                                     remoteAddress:@"198.51.100.10"];
        XCTAssertEqualObjects(request.remoteAddress, @"198.51.100.10");
    } @finally {
        [self _restoreEnvKey:"PDS_TRUST_PROXY_HEADERS" toValue:savedTrustProxy];
    }
}

- (void)testForwardedHeadersIgnoredForUntrustedProxySourceMatchesRemoteAddress {
    NSString *savedTrustProxy = [self _savedEnvValueForKey:"PDS_TRUST_PROXY_HEADERS"];
    setenv("PDS_TRUST_PROXY_HEADERS", "1", 1);

    @try {
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                       methodString:@"GET"
                                                               path:@"/xrpc/test"
                                                        queryString:@""
                                                        queryParams:@{}
                                                            version:@"1.1"
                                                            headers:@{@"x-forwarded-for": @"203.0.113.42"}
                                                               body:[NSData data]
                                                     remoteAddress:@"198.51.100.10"];
        XCTAssertEqualObjects(request.remoteAddress, @"198.51.100.10");
    } @finally {
        [self _restoreEnvKey:"PDS_TRUST_PROXY_HEADERS" toValue:savedTrustProxy];
    }
}

- (void)testForwardedHeadersHonoredForTrustedProxySourceMatchesRemoteAddress {
    NSString *savedTrustProxy = [self _savedEnvValueForKey:"PDS_TRUST_PROXY_HEADERS"];
    setenv("PDS_TRUST_PROXY_HEADERS", "1", 1);

    @try {
        HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                                       methodString:@"GET"
                                                               path:@"/xrpc/test"
                                                        queryString:@""
                                                        queryParams:@{}
                                                            version:@"1.1"
                                                            headers:@{@"x-forwarded-for": @"203.0.113.42, 198.51.100.1"}
                                                               body:[NSData data]
                                                     remoteAddress:@"127.0.0.1"];
        XCTAssertEqualObjects(request.remoteAddress, @"203.0.113.42");
    } @finally {
        [self _restoreEnvKey:"PDS_TRUST_PROXY_HEADERS" toValue:savedTrustProxy];
    }
}

@end

NS_ASSUME_NONNULL_END
