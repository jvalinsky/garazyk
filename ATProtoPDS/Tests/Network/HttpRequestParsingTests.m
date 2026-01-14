#import <XCTest/XCTest.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

@interface HttpRequestParsingTests : XCTestCase
@end

@implementation HttpRequestParsingTests

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

@end

NS_ASSUME_NONNULL_END
