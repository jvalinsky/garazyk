/*!
 @file CappuccinoUIRouteRegressionTests.m

 @abstract Regression tests for Cappuccino UI handler routing.

 Validates that /ui routes don't shadow existing route families, MIME types for
 Cappuccino-specific file extensions are correct, and SPA fallback handles auth
 callback paths.
 */

#import <XCTest/XCTest.h>
#import "App/CappuccinoUI/CappuccinoUIHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface TestableCappuccinoUIHandlerRegression : CappuccinoUIHandler
@property(nonatomic, copy, nullable) NSString *forcedAssetsPath;
@end

@implementation TestableCappuccinoUIHandlerRegression
- (NSString *)assetsPath {
  return self.forcedAssetsPath;
}
@end

@interface CappuccinoUIRouteRegressionTests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation CappuccinoUIRouteRegressionTests

- (void)setUp {
  [super setUp];
  NSString *uuid = [[NSUUID UUID] UUIDString];
  self.tempDir = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [NSString stringWithFormat:@"cappuccino-regression-tests-%@", uuid]];
  [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

  // Create a minimal index.html for SPA fallback testing.
  NSData *indexData =
      [@"<html>objj-regression</html>" dataUsingEncoding:NSUTF8StringEncoding];
  [indexData writeToFile:[self.tempDir stringByAppendingPathComponent:@"index.html"]
              atomically:YES];
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
  id obj = [NSJSONSerialization JSONObjectWithData:response.body
                                           options:0
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
  return obj;
}

#pragma mark - Route Non-Interference Tests

- (void)testCanHandleRejectsXrpcPaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/xrpc/com.atproto.server.getSession"]]);
}

- (void)testCanHandleRejectsAdminPaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/admin/stats"]]);
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/admin-ui/js/admin.js"]]);
}

- (void)testCanHandleRejectsExplorePaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/api/pds/accounts"]]);
}

- (void)testCanHandleRejectsMSTPaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/api/mst/accounts"]]);
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/mst-viewer"]]);
}

- (void)testCanHandleRejectsOAuthDemoPaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/oauth-demo"]]);
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/oauth-demo/callback"]]);
}

- (void)testCanHandleRejectsOAuthProtocolPaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/oauth/authorize"]]);
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/oauth/token"]]);
}

- (void)testCanHandleRejectsWellKnownPaths {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/.well-known/atproto-did"]]);
}

- (void)testCanHandleRejectsRootPath {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertFalse([handler canHandleRequest:
      [self requestWithPath:@"/"]]);
}

#pragma mark - MIME Type Tests for Cappuccino Files

- (void)testContentTypeForPlistFile {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  NSData *plistData =
      [@"<?xml version=\"1.0\"?><plist></plist>" dataUsingEncoding:NSUTF8StringEncoding];
  [plistData writeToFile:[self.tempDir stringByAppendingPathComponent:@"Info.plist"]
              atomically:YES];

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/Info.plist"] response:response];

  XCTAssertEqual(response.statusCode, HttpStatusOK);
  // .plist has no specific MIME mapping → falls back to octet-stream.
  XCTAssertEqualObjects(response.contentType, @"application/octet-stream");
}

- (void)testContentTypeForMapFile {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  NSData *mapData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
  [mapData writeToFile:[self.tempDir stringByAppendingPathComponent:@"app.map"]
            atomically:YES];

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/app.map"] response:response];

  XCTAssertEqual(response.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(response.contentType, @"application/json; charset=utf-8");
}

- (void)testContentTypeForSVGFile {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  NSData *svgData =
      [@"<svg></svg>" dataUsingEncoding:NSUTF8StringEncoding];
  [svgData writeToFile:[self.tempDir stringByAppendingPathComponent:@"icon.svg"]
            atomically:YES];

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/icon.svg"] response:response];

  XCTAssertEqual(response.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(response.contentType, @"image/svg+xml");
}

#pragma mark - SPA Fallback for Auth Callback Paths

- (void)testSPAFallbackForOAuthDemoCallbackPath {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/oauth-demo/callback"]
                response:response];

  // Extensionless SPA path should fall back to index.html.
  XCTAssertEqual(response.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(response.contentType, @"text/html; charset=utf-8");

  NSString *bodyStr = [[NSString alloc] initWithData:response.body
                                            encoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(bodyStr, @"<html>objj-regression</html>");
}

- (void)testSPAFallbackForExploreDeepPath {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/explore/accounts/did:plc:abc"]
                response:response];

  XCTAssertEqual(response.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(response.contentType, @"text/html; charset=utf-8");
}

#pragma mark - Traversal Edge Cases

- (void)testTraversalWithEncodedDotsBlocked {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/../../../etc/passwd"]
                response:response];

  XCTAssertEqual(response.statusCode, HttpStatusForbidden);
}

- (void)testTraversalMidPathBlocked {
  TestableCappuccinoUIHandlerRegression *handler =
      [[TestableCappuccinoUIHandlerRegression alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/Frameworks/../../secret.txt"]
                response:response];

  XCTAssertEqual(response.statusCode, HttpStatusForbidden);
}

@end
