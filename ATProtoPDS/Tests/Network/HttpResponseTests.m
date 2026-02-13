#import <XCTest/XCTest.h>
#import "Network/HttpResponse.h"

@interface HttpResponseTests : XCTestCase
@end

@implementation HttpResponseTests

- (void)testContentTypePropertyDoesNotUpdateHeaders {
    HttpResponse *response = [[HttpResponse alloc] init];
    response.contentType = @"text/html; charset=utf-8";
    XCTAssertNil(response.headers[@"Content-Type"], @"Setting contentType property should NOT update headers directly");
}

- (void)testSetHeaderUpdatesHeadersCorrectly {
    HttpResponse *response = [[HttpResponse alloc] init];
    [response setHeader:@"text/html; charset=utf-8" forKey:@"Content-Type"];
    XCTAssertEqualObjects(response.headers[@"Content-Type"], @"text/html; charset=utf-8", @"setHeader:forKey: should update headers");
}

- (void)testSerializeAddsContentTypeToHeaders {
    HttpResponse *response = [[HttpResponse alloc] init];
    response.contentType = @"text/html; charset=utf-8";
    [response setBody:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSData *serialized = [response serialize];
    NSString *httpString = [[NSString alloc] initWithData:serialized encoding:NSUTF8StringEncoding];
    
    XCTAssertTrue([httpString containsString:@"Content-Type: text/html"], @"Serialization should add Content-Type header from contentType property");
}

- (void)testMSTViewerHandlerPatternWorks {
    HttpResponse *response = [[HttpResponse alloc] init];
    NSString *html = @"<html></html>";
    [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
    response.contentType = @"text/html; charset=utf-8";
    [response setHeader:response.contentType forKey:@"Content-Type"];
    
    XCTAssertNotNil(response.headers[@"Content-Type"], @"MSTViewerHandler pattern: setting contentType then calling setHeader ensures headers are populated");
    XCTAssertEqualObjects(response.headers[@"Content-Type"], @"text/html; charset=utf-8");
}

- (void)testDefaultContentTypeIsApplicationJson {
    HttpResponse *response = [[HttpResponse alloc] init];
    XCTAssertEqualObjects(response.contentType, @"application/json; charset=utf-8", @"Default contentType should be JSON");
}

- (void)testJsonBodySetsContentType {
    HttpResponse *response = [[HttpResponse alloc] init];
    [response setJsonBody:@{@"key": @"value"}];
    XCTAssertEqualObjects(response.contentType, @"application/json; charset=utf-8", @"setJsonBody: should set contentType property");
    XCTAssertNil(response.headers[@"Content-Type"], @"setJsonBody: does NOT update headers - headers only updated during serialize");
}

- (void)testBodyFilePathLazyLoadsBody {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"httpresponse-body-%@.txt", [NSUUID UUID].UUIDString]];
    NSData *payload = [@"streamed-body" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([payload writeToFile:tempPath atomically:YES]);

    HttpResponse *response = [[HttpResponse alloc] init];
    [response setBodyFileAtPath:tempPath deleteAfterSend:NO];

    NSData *loaded = response.body;
    XCTAssertNotNil(loaded);
    XCTAssertEqualObjects(loaded, payload);
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
}

- (void)testSerializeHeadersForBodyLengthDoesNotIncludeBodyBytes {
    HttpResponse *response = [[HttpResponse alloc] init];
    response.contentType = @"application/octet-stream";
    NSData *headers = [response serializeHeadersForBodyLength:12];
    NSString *headerString = [[NSString alloc] initWithData:headers encoding:NSUTF8StringEncoding];
    XCTAssertTrue([headerString containsString:@"Content-Length: 12"]);
    XCTAssertTrue([headerString hasSuffix:@"\r\n\r\n"]);
    XCTAssertFalse([headerString containsString:@"streamed-body"]);
}

@end
