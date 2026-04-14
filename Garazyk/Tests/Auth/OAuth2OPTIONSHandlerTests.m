#import <XCTest/XCTest.h>
#import "Network/HttpResponse.h"

/**
 * Unit tests for OPTIONS handler responses (204 No Content with CORS headers)
 * 
 * **Validates: Requirements 2.5** (CORS support for ATProto clients)
 * 
 * These tests verify that OPTIONS responses:
 * 1. Return 204 No Content status
 * 2. Include proper CORS headers
 * 3. Have no Content-Length or Content-Type headers (per HTTP spec)
 * 4. Have empty body
 * 5. Serialize correctly without causing server crashes
 */

@interface OAuth2OPTIONSHandlerTests : XCTestCase
@end

@implementation OAuth2OPTIONSHandlerTests

- (void)testOPTIONSResponseSerialization {
    // Create a 204 No Content response like the OPTIONS handler does
    HttpResponse *response = [[HttpResponse alloc] init];
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"GET, POST, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Authorization, Content-Type, DPoP, DPoP-Nonce" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
    response.statusCode = 204;
    response.statusMessage = @"No Content";
    
    // Verify response can be serialized without crashing
    NSData *serialized = [response serialize];
    XCTAssertNotNil(serialized, @"Response should serialize successfully");
    XCTAssertGreaterThan(serialized.length, 0, @"Serialized response should have content");
    
    // Verify serialized response is valid HTTP
    NSString *responseString = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
    XCTAssertTrue([responseString hasPrefix:@"HTTP/1.1 204"], @"Response should start with HTTP/1.1 204");
    XCTAssertTrue([responseString containsString:@"access-control-allow-origin: *"], @"Should contain CORS header");
    
    // Verify no Content-Length header for 204
    XCTAssertFalse([responseString containsString:@"Content-Length:"], @"204 response should not have Content-Length");
    
    // Verify no Content-Type header for 204
    XCTAssertFalse([responseString containsString:@"Content-Type:"], @"204 response should not have Content-Type");
    
    // Verify response ends with double CRLF (no body)
    XCTAssertTrue([responseString hasSuffix:@"\r\n\r\n"], @"Response should end with double CRLF and no body");
}

- (void)testOPTIONSResponseWithExplicitEmptyBody {
    // Test setting an explicit empty body (potential fix)
    HttpResponse *response = [[HttpResponse alloc] init];
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"GET, POST, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Authorization, Content-Type, DPoP, DPoP-Nonce" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
    response.statusCode = 204;
    response.statusMessage = @"No Content";
    
    // Set explicit empty body
    [response setBodyData:[NSData data]];
    
    // Verify response can be serialized
    NSData *serialized = [response serialize];
    XCTAssertNotNil(serialized);
    
    NSString *responseString = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
    XCTAssertTrue([responseString hasPrefix:@"HTTP/1.1 204"]);
    XCTAssertTrue([responseString hasSuffix:@"\r\n\r\n"], @"Response should end with double CRLF and no body");
}

- (void)testOPTIONSResponseHeaders {
    HttpResponse *response = [[HttpResponse alloc] init];
    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setHeader:@"GET, POST, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Authorization, Content-Type, DPoP, DPoP-Nonce" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
    response.statusCode = 204;
    response.statusMessage = @"No Content";
    
    // Verify headers are set correctly
    XCTAssertEqualObjects([response headerForKey:@"Access-Control-Allow-Origin"], @"*");
    XCTAssertEqualObjects([response headerForKey:@"Access-Control-Allow-Methods"], @"GET, POST, OPTIONS");
    XCTAssertEqualObjects([response headerForKey:@"Access-Control-Allow-Headers"], @"Authorization, Content-Type, DPoP, DPoP-Nonce");
    XCTAssertEqualObjects([response headerForKey:@"Access-Control-Max-Age"], @"86400");
}

- (void)test200ResponseWithEmptyBodyForComparison {
    // Test that 200 OK with empty body works differently than 204
    HttpResponse *response = [[HttpResponse alloc] init];
    response.statusCode = 200;
    response.statusMessage = @"OK";
    [response setBodyData:[NSData data]];
    
    NSData *serialized = [response serialize];
    XCTAssertNotNil(serialized);
    
    NSString *responseString = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
    XCTAssertTrue([responseString hasPrefix:@"HTTP/1.1 200"]);
    // 200 OK should have Content-Length: 0
    XCTAssertTrue([responseString containsString:@"content-length: 0"], @"200 OK with empty body should have Content-Length: 0");
}

@end
