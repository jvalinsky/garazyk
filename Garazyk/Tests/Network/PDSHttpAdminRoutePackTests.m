// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

- (void)testRegistersAdminRoutesForAllSupportedMethods {
  NSArray<NSString *> *implementedPaths = @[
    @"/admin",
    @"/admin/login",
    @"/admin/logout",
    @"/admin/users",
    @"/admin/users/bulk/takedown",
    @"/admin/users/bulk/delete",
    @"/admin/invites",
    @"/admin/invites/disable",
    @"/admin/blobs",
    @"/admin/metrics",
    @"/admin/health",
    @"/admin/stats",
    @"/admin/audit-log",
    @"/admin/plc/lookup",
    @"/admin/plc/export",
    @"/admin/plc/metrics",
    @"/admin/plc/operations",
    @"/admin/chat/convos",
    @"/admin/chat/messages",
    @"/admin/chat/reports",
    @"/admin/ozone/events",
    @"/admin/ozone/statuses",
    @"/admin/ozone/team",
    @"/admin/ozone/templates",
    @"/admin/ozone/sets",
    @"/admin/ozone/correlations",
    @"/admin/ozone/verification",
    @"/admin/ozone/scheduled",
    @"/admin/ozone/safelinks",
    @"/admin/ozone/config",
    @"/admin/relay/operators",
    @"/admin/security/sessions",
    @"/admin/security/app-passwords"
  ];

  NSArray<NSString *> *methods = @[ @"GET", @"POST", @"PUT", @"DELETE" ];
  for (NSString *path in implementedPaths) {
    for (NSString *method in methods) {
      RequestHandler handler =
          [self.server handlerForRoute:path method:method parameters:nil];
      XCTAssertNotNil(handler, @"Expected %@ handler for %@", method, path);
    }
  }

  for (NSString *method in methods) {
    RequestHandler userWildcard =
        [self.server handlerForRoute:@"/admin/users/did:plc:test/edit-email"
                              method:method
                          parameters:nil];
    XCTAssertNotNil(userWildcard,
                    @"Expected %@ handler for /admin/users/*", method);

    RequestHandler partialWildcard =
        [self.server handlerForRoute:@"/admin/partials/users/search"
                              method:method
                          parameters:nil];
    XCTAssertNotNil(partialWildcard,
                    @"Expected %@ handler for /admin/partials/*", method);
  }

  NSArray<NSString *> *removedPaths =
      @[ @"/admin/capabilities", @"/admin/audit/receipts" ];
  for (NSString *path in removedPaths) {
    for (NSString *method in methods) {
      RequestHandler handler =
          [self.server handlerForRoute:path method:method parameters:nil];
      XCTAssertNil(handler, @"Did not expect %@ handler for %@", method, path);
    }
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

- (void)testAdminLogoutSetsCookieToClearAdminToken {
  RequestHandler postHandler =
      [self.server handlerForRoute:@"/admin/logout"
                            method:@"POST"
                        parameters:nil];
  XCTAssertNotNil(postHandler);

  HttpRequest *request =
      [self requestWithMethod:HttpMethodPOST
                 methodString:@"POST"
                         path:@"/admin/logout"
                      headers:@{}
                         body:[NSData data]];
  HttpResponse *response = [HttpResponse response];
  postHandler(request, response);

  XCTAssertEqual(response.statusCode, HttpStatusOK);

  NSString *setCookie = [response headerForKey:@"Set-Cookie"];
  XCTAssertNotNil(setCookie, @"Logout should set Set-Cookie header");
  XCTAssertTrue([setCookie containsString:@"admin_token="],
                @"Set-Cookie should clear admin_token, got: %@", setCookie);
  XCTAssertTrue([setCookie containsString:@"Max-Age=0"],
                @"Set-Cookie should have Max-Age=0 to clear, got: %@", setCookie);
  XCTAssertTrue([setCookie containsString:@"HttpOnly"],
                @"Set-Cookie should be HttpOnly, got: %@", setCookie);
  XCTAssertTrue([setCookie containsString:@"SameSite=Strict"],
                @"Set-Cookie should be SameSite=Strict, got: %@", setCookie);
  XCTAssertTrue([setCookie containsString:@"Path=/admin"],
                @"Set-Cookie should be scoped to /admin, got: %@", setCookie);
}

@end
