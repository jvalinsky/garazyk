#import <XCTest/XCTest.h>

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/PDSHttpAdminRoutePack.h"

@interface HttpServer (PDSHttpAdminRoutePackTesting)
- (nullable RequestHandler)handlerForRoute:
                            (NSString *)path
                                method:(NSString *)method
                            parameters:
                                (NSDictionary<NSString *, NSString *> *_Nullable *_Nullable)
                                    parameters;
@end

@interface PDSHttpAdminRoutePackTests : XCTestCase
@property(nonatomic, strong) HttpServer *server;
@end

@implementation PDSHttpAdminRoutePackTests

- (void)setUp {
  [super setUp];
  self.server = [HttpServer serverWithPort:0];
  [PDSHttpAdminRoutePack registerAdminRoutesWithServer:self.server];
}

- (void)tearDown {
  self.server = nil;
  [super tearDown];
}

- (HttpRequest *)requestWithMethod:(HttpMethod)method
                      methodString:(NSString *)methodString
                              path:(NSString *)path
                           headers:(NSDictionary<NSString *, NSString *> *)headers
                              body:(nullable NSData *)body {
  return [[HttpRequest alloc] initWithMethod:method
                                methodString:methodString
                                        path:path
                                 queryString:@""
                                  queryParams:@{}
                                      version:@"HTTP/1.1"
                                      headers:headers ?: @{}
                                         body:body ?: [NSData data]
                                 remoteAddress:@"127.0.0.1"];
}

- (nullable NSDictionary *)jsonBodyFromResponse:(HttpResponse *)response {
  if (response.body.length == 0) {
    return nil;
  }

  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:response.body
                                            options:0
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
  return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (void)testRegistersOnlyImplementedAdminRoutes {
  NSArray<NSString *> *implementedPaths = @[
    @"/admin",
    @"/admin/login",
    @"/admin/logout",
    @"/admin/users",
    @"/admin/invites",
    @"/admin/invites/disable",
    @"/admin/blobs",
    @"/admin/metrics",
    @"/admin/health",
    @"/admin/stats",
    @"/admin/audit-log"
  ];

  for (NSString *path in implementedPaths) {
    RequestHandler getHandler =
        [self.server handlerForRoute:path method:@"GET" parameters:nil];
    XCTAssertNotNil(getHandler, @"Expected GET handler for %@", path);

    RequestHandler postHandler =
        [self.server handlerForRoute:path method:@"POST" parameters:nil];
    XCTAssertNotNil(postHandler, @"Expected POST handler for %@", path);
  }

  NSArray<NSString *> *removedPaths =
      @[ @"/admin/capabilities", @"/admin/audit/receipts" ];
  for (NSString *path in removedPaths) {
    RequestHandler getHandler =
        [self.server handlerForRoute:path method:@"GET" parameters:nil];
    XCTAssertNil(getHandler, @"Did not expect GET handler for %@", path);

    RequestHandler postHandler =
        [self.server handlerForRoute:path method:@"POST" parameters:nil];
    XCTAssertNil(postHandler, @"Did not expect POST handler for %@", path);
  }
}

- (void)testAdminLoginInvalidJSONReturnsHTTP400 {
  RequestHandler postHandler =
      [self.server handlerForRoute:@"/admin/login"
                            method:@"POST"
                        parameters:nil];
  XCTAssertNotNil(postHandler);

  HttpRequest *request =
      [self requestWithMethod:HttpMethodPOST
                 methodString:@"POST"
                         path:@"/admin/login"
                      headers:@{@"Content-Type" : @"application/json"}
                         body:[@"{" dataUsingEncoding:NSUTF8StringEncoding]];
  HttpResponse *response = [HttpResponse response];
  postHandler(request, response);

  XCTAssertEqual(response.statusCode, HttpStatusBadRequest);
  XCTAssertEqualObjects([response headerForKey:@"Content-Type"],
                        @"application/json");

  NSDictionary *json = [self jsonBodyFromResponse:response];
  XCTAssertEqualObjects(json[@"error"], @"Invalid JSON");
}

@end
