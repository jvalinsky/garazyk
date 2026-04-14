#import <XCTest/XCTest.h>
#import "App/CappuccinoUI/CappuccinoUIHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface TestableCappuccinoUIHandler : CappuccinoUIHandler
@property(nonatomic, copy, nullable) NSString *forcedAssetsPath;
@end

@implementation TestableCappuccinoUIHandler
- (NSString *)assetsPath {
  return self.forcedAssetsPath;
}
@end

@interface CappuccinoUIHandlerTests : XCTestCase
@property(nonatomic, strong) NSString *tempDir;
@end

@implementation CappuccinoUIHandlerTests

- (void)setUp {
  [super setUp];
  NSString *uuid = [[NSUUID UUID] UUIDString];
  self.tempDir = [NSTemporaryDirectory()
      stringByAppendingPathComponent:
          [NSString stringWithFormat:@"cappuccino-ui-tests-%@", uuid]];
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
  id obj = [NSJSONSerialization JSONObjectWithData:response.body
                                           options:0
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([obj isKindOfClass:[NSDictionary class]]);
  return obj;
}

- (void)testCanHandleRequestMatchesUiPrefix {
  CappuccinoUIHandler *handler = [[CappuccinoUIHandler alloc] init];
  XCTAssertTrue([handler canHandleRequest:[self requestWithPath:@"/ui"]]);
  XCTAssertTrue([handler canHandleRequest:[self requestWithPath:@"/ui/index.html"]]);
  XCTAssertFalse([handler canHandleRequest:[self requestWithPath:@"/oauth-demo"]]);
}

- (void)testHandleRequestServesIndexForRootAndSpaRoutes {
  NSData *indexData = [@"<html>objj-shell</html>" dataUsingEncoding:NSUTF8StringEncoding];
  [indexData writeToFile:[self.tempDir stringByAppendingPathComponent:@"index.html"]
              atomically:YES];

  TestableCappuccinoUIHandler *handler = [[TestableCappuccinoUIHandler alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *rootResponse = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui"] response:rootResponse];
  XCTAssertEqual(rootResponse.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(rootResponse.contentType, @"text/html; charset=utf-8");
  XCTAssertEqualObjects(rootResponse.body, indexData);

  HttpResponse *spaResponse = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/explore/accounts"]
                response:spaResponse];
  XCTAssertEqual(spaResponse.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(spaResponse.contentType, @"text/html; charset=utf-8");
  XCTAssertEqualObjects(spaResponse.body, indexData);
}

- (void)testHandleRequestServesNestedAssetsWithContentType {
  NSString *frameworkDir =
      [self.tempDir stringByAppendingPathComponent:@"Frameworks/Objective-J"];
  [[NSFileManager defaultManager] createDirectoryAtPath:frameworkDir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

  NSData *scriptData = [@"console.log('objj');" dataUsingEncoding:NSUTF8StringEncoding];
  NSString *scriptPath = [frameworkDir stringByAppendingPathComponent:@"Objective-J.js"];
  [scriptData writeToFile:scriptPath atomically:YES];

  TestableCappuccinoUIHandler *handler = [[TestableCappuccinoUIHandler alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/Frameworks/Objective-J/Objective-J.js"]
                response:response];

  XCTAssertEqual(response.statusCode, HttpStatusOK);
  XCTAssertEqualObjects(response.contentType, @"application/javascript; charset=utf-8");
  XCTAssertEqualObjects(response.body, scriptData);
}

- (void)testHandleRequestReturns404ForMissingAssetWithExtension {
  NSData *indexData = [@"<html>objj-shell</html>" dataUsingEncoding:NSUTF8StringEncoding];
  [indexData writeToFile:[self.tempDir stringByAppendingPathComponent:@"index.html"]
              atomically:YES];

  TestableCappuccinoUIHandler *handler = [[TestableCappuccinoUIHandler alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/missing.js"] response:response];

  NSDictionary *body = [self jsonBodyFromResponse:response];
  XCTAssertEqual(response.statusCode, HttpStatusNotFound);
  XCTAssertEqualObjects(body[@"error"], @"File not found");
  XCTAssertEqualObjects(body[@"path"], @"/ui/missing.js");
}

- (void)testHandleRequestReturns403ForTraversalAttempt {
  TestableCappuccinoUIHandler *handler = [[TestableCappuccinoUIHandler alloc] init];
  handler.forcedAssetsPath = self.tempDir;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui/../../secret.txt"] response:response];

  NSDictionary *body = [self jsonBodyFromResponse:response];
  XCTAssertEqual(response.statusCode, HttpStatusForbidden);
  XCTAssertEqualObjects(body[@"error"], @"Forbidden");
}

- (void)testHandleRequestReturns500WhenAssetsPathMissing {
  TestableCappuccinoUIHandler *handler = [[TestableCappuccinoUIHandler alloc] init];
  handler.forcedAssetsPath = nil;

  HttpResponse *response = [HttpResponse response];
  [handler handleRequest:[self requestWithPath:@"/ui"] response:response];

  NSDictionary *body = [self jsonBodyFromResponse:response];
  XCTAssertEqual(response.statusCode, HttpStatusInternalServerError);
  XCTAssertEqualObjects(body[@"error"], @"Cappuccino UI assets not found");
}

@end
