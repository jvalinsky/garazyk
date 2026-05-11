// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Network/PDSHttpServerBuilder.h"
#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "App/PDSController.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface TestableOAuthDemoHandler : OAuthDemoHandler
@property (nonatomic, copy) NSString *forcedAssetsPath;
@end

@implementation TestableOAuthDemoHandler
- (NSString *)assetsPath {
    return self.forcedAssetsPath;
}
@end

@interface OAuthDemoHandlerConfigurationTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@end

@implementation OAuthDemoHandlerConfigurationTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"oauth-demo-tests-%@", uuid]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (HttpRequest *)requestWithPath:(NSString *)path {
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                          path:path
                                   queryString:@""
                                    queryParams:@{}
                                        version:@"HTTP/1.1"
                                        headers:@{}
                                           body:[NSData data]
                                   remoteAddress:@"127.0.0.1"];
}

- (NSDictionary *)jsonBodyFromResponse:(HttpResponse *)response {
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
    return obj;
}

- (void)testBuilderSetsDataDirectoryOnOAuthDemoHandler {
    PDSHttpServerBuilder *builder = [[PDSHttpServerBuilder alloc] init];
    NSString *testDir = @"/tmp/test-data-dir";
    builder.dataDirectory = testDir;

    NSError *error = nil;
    [builder buildWithError:&error];
    XCTAssertNil(error);

    OAuthDemoHandler *handler = [OAuthDemoHandler sharedHandler];
    NSString *handlerDataDir = [handler valueForKey:@"dataDirectory"];
    XCTAssertEqualObjects(handlerDataDir, testDir);
}

- (void)testCanHandleRequestMatchesOAuthDemoPrefix {
    OAuthDemoHandler *handler = [[OAuthDemoHandler alloc] init];
    XCTAssertTrue([handler canHandleRequest:[self requestWithPath:@"/oauth-demo"]]);
    XCTAssertTrue([handler canHandleRequest:[self requestWithPath:@"/oauth-demo/index.html"]]);
    XCTAssertFalse([handler canHandleRequest:[self requestWithPath:@"/xrpc/com.atproto.server.describeServer"]]);
}

- (void)testHandleRequestServesIndexForRootAndCallbackPaths {
    NSString *indexPath = [self.tempDir stringByAppendingPathComponent:@"index.html"];
    NSData *indexData = [@"<html>ok</html>" dataUsingEncoding:NSUTF8StringEncoding];
    [indexData writeToFile:indexPath atomically:YES];

    TestableOAuthDemoHandler *handler = [[TestableOAuthDemoHandler alloc] init];
    handler.forcedAssetsPath = self.tempDir;

    HttpResponse *rootResponse = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo"] response:rootResponse];
    XCTAssertEqual(rootResponse.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(rootResponse.contentType, @"text/html; charset=utf-8");
    XCTAssertEqualObjects(rootResponse.body, indexData);

    HttpResponse *callbackResponse = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo/callback"] response:callbackResponse];
    XCTAssertEqual(callbackResponse.statusCode, HttpStatusOK);
    XCTAssertEqualObjects(callbackResponse.contentType, @"text/html; charset=utf-8");
    XCTAssertEqualObjects(callbackResponse.body, indexData);
}

- (void)testHandleRequestServesJsCssAndBinaryTypes {
    NSData *jsData = [@"console.log('x');" dataUsingEncoding:NSUTF8StringEncoding];
    [jsData writeToFile:[self.tempDir stringByAppendingPathComponent:@"app.js"] atomically:YES];
    NSData *cssData = [@"body{color:red;}" dataUsingEncoding:NSUTF8StringEncoding];
    [cssData writeToFile:[self.tempDir stringByAppendingPathComponent:@"app.css"] atomically:YES];
    NSData *binData = [@"\x01\x02\x03" dataUsingEncoding:NSUTF8StringEncoding];
    [binData writeToFile:[self.tempDir stringByAppendingPathComponent:@"file.bin"] atomically:YES];

    TestableOAuthDemoHandler *handler = [[TestableOAuthDemoHandler alloc] init];
    handler.forcedAssetsPath = self.tempDir;

    HttpResponse *jsResponse = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo/app.js"] response:jsResponse];
    XCTAssertEqualObjects(jsResponse.contentType, @"application/javascript; charset=utf-8");
    XCTAssertEqualObjects(jsResponse.body, jsData);

    HttpResponse *cssResponse = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo/app.css"] response:cssResponse];
    XCTAssertEqualObjects(cssResponse.contentType, @"text/css; charset=utf-8");
    XCTAssertEqualObjects(cssResponse.body, cssData);

    HttpResponse *binResponse = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo/file.bin"] response:binResponse];
    XCTAssertEqualObjects(binResponse.contentType, @"application/octet-stream");
    XCTAssertEqualObjects(binResponse.body, binData);
}

- (void)testHandleRequestReturns500WhenAssetsPathMissing {
    TestableOAuthDemoHandler *handler = [[TestableOAuthDemoHandler alloc] init];
    handler.forcedAssetsPath = nil;

    HttpResponse *response = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo/index.html"] response:response];

    NSDictionary *body = [self jsonBodyFromResponse:response];
    XCTAssertEqual(response.statusCode, HttpStatusInternalServerError);
    XCTAssertEqualObjects(body[@"error"], @"OAuth Demo assets not found");
}

- (void)testHandleRequestReturns404WhenFileMissing {
    TestableOAuthDemoHandler *handler = [[TestableOAuthDemoHandler alloc] init];
    handler.forcedAssetsPath = self.tempDir;

    HttpResponse *response = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo/missing.js"] response:response];

    NSDictionary *body = [self jsonBodyFromResponse:response];
    XCTAssertEqual(response.statusCode, HttpStatusNotFound);
    XCTAssertEqualObjects(body[@"error"], @"File not found");
    XCTAssertEqualObjects(body[@"path"], @"/oauth-demo/missing.js");
    XCTAssertTrue([body[@"checked"] hasSuffix:@"missing.js"]);
}

- (void)testHandleRequestReturns500WhenReadFails {
    NSString *pathThatIsDirectory = [self.tempDir stringByAppendingPathComponent:@"index.html"];
    [[NSFileManager defaultManager] createDirectoryAtPath:pathThatIsDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    TestableOAuthDemoHandler *handler = [[TestableOAuthDemoHandler alloc] init];
    handler.forcedAssetsPath = self.tempDir;

    HttpResponse *response = [HttpResponse response];
    [handler handleRequest:[self requestWithPath:@"/oauth-demo"] response:response];

    NSDictionary *body = [self jsonBodyFromResponse:response];
    XCTAssertEqual(response.statusCode, HttpStatusInternalServerError);
    XCTAssertEqualObjects(body[@"error"], @"Failed to read file");
    XCTAssertNotNil(body[@"details"]);
}

@end
