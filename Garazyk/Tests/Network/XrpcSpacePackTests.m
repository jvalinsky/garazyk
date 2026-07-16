// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/XrpcSpacePack.h"
#import "Services/PDS/PDSSpaceStore.h"

@interface XrpcSpacePackTests : XCTestCase
@property(nonatomic, copy) NSString *temporaryDirectory;
@property(nonatomic, strong) PDSSpaceStore *store;
@end

@implementation XrpcSpacePackTests

- (void)setUp {
  [super setUp];
  self.temporaryDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"xrpc-space-pack-%@", NSUUID.UUID.UUIDString]];
  self.store = [[PDSSpaceStore alloc] initWithDatabasePath:[self.temporaryDirectory stringByAppendingPathComponent:@"spaces.sqlite"] error:nil];
  XCTAssertTrue([self.store createSpace:[self space] owner:YES policy:@"member-list" managingApp:nil appAccessType:@"open" appAllowed:@[] error:nil]);
}

- (void)tearDown {
  [self.store close];
  [[NSFileManager defaultManager] removeItemAtPath:self.temporaryDirectory error:nil];
  [super tearDown];
}

- (void)testFeatureDoesNotRegisterRoutesWithoutIsolatedStore {
  XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
  XrpcRoutePackServiceBag *services = [self servicesForDispatcher:dispatcher];
  services.spaceStore = nil;
  [XrpcSpacePack registerWithDispatcher:dispatcher services:services];
  XCTAssertFalse([dispatcher hasRegisteredMethod:@"com.atproto.space.getSpace"]);
}

- (void)testRegistersImplementedExperimentalContractAndProtectsSpaceMetadata {
  XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
  [XrpcSpacePack registerWithDispatcher:dispatcher services:[self servicesForDispatcher:dispatcher]];
  for (NSString *method in @[
      @"com.atproto.space.getSpace", @"com.atproto.space.applyWrites",
      @"com.atproto.space.getRepo", @"com.atproto.space.getBlob", @"com.atproto.space.getSpaceCredential",
      @"com.atproto.space.notifyWrite", @"com.atproto.space.registerNotify",
      @"com.atproto.simplespace.createSpace", @"com.atproto.simplespace.updateSpace",
      @"com.atproto.simplespace.addMember", @"com.atproto.simplespace.removeMember",
      @"com.atproto.simplespace.checkUserAccess",
  ]) {
    XCTAssertTrue([dispatcher hasRegisteredMethod:method], @"%@ should be registered", method);
  }
  HttpRequest *request = [[HttpRequest alloc] initWithMethod:HttpMethodGET methodString:@"GET"
      path:@"/xrpc/com.atproto.space.getSpace" queryString:@"" queryParams:@{ @"space" : [self space] }
      version:@"HTTP/1.1" headers:@{} body:[NSData data] remoteAddress:@"127.0.0.1"];
  HttpResponse *response = [HttpResponse response];
  [dispatcher handleRequest:request response:response];
  XCTAssertEqual(response.statusCode, HttpStatusUnauthorized);
  XCTAssertEqualObjects(response.jsonBody[@"error"], @"AuthRequired");
}

- (XrpcRoutePackServiceBag *)servicesForDispatcher:(XrpcDispatcher *)dispatcher {
  XrpcRoutePackServiceBag *services = [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher jwtMinter:nil adminController:nil configuration:nil adminSecret:nil serviceDatabases:nil userDatabasePool:nil rateLimiter:nil];
  services.spaceStore = self.store;
  return services;
}

- (NSString *)space { return @"at://did:example:authority/space/com.example.group/default"; }

@end
