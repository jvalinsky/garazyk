// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAppBskyAgeAssurancePack.h"
#import "Network/XrpcAppBskyBookmarksPack.h"
#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcAppBskyContactPack.h"
#import "Network/XrpcAppBskyDraftsPack.h"
#import "Network/XrpcAppBskyProxyMethodPack.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePack.h"
#import "Network/XrpcRoutePackRegistrar.h"
#import "Network/XrpcRoutePackServices.h"

@interface XrpcRoutePackTests : XCTestCase
@end

@implementation XrpcRoutePackTests

- (void)testChatBskyActorPackConformsToProtocol {
  XCTAssertTrue([XrpcChatBskyActorPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcChatBskyActorPack routePackIdentifier], @"chat.bsky.actor");
}

- (void)testAppBskyProxyPackConformsToProtocol {
  XCTAssertTrue([XrpcAppBskyProxyMethodPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcAppBskyProxyMethodPack routePackIdentifier], @"app.bsky.proxy");
}

- (void)testAppBskyAgeAssurancePackConformsToProtocol {
  XCTAssertTrue([XrpcAppBskyAgeAssurancePack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcAppBskyAgeAssurancePack routePackIdentifier],
                        @"app.bsky.ageassurance");
}

- (void)testAppBskyBookmarksPackConformsToProtocol {
  XCTAssertTrue([XrpcAppBskyBookmarksPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcAppBskyBookmarksPack routePackIdentifier], @"app.bsky.bookmark");
}

- (void)testAppBskyDraftsPackConformsToProtocol {
  XCTAssertTrue([XrpcAppBskyDraftsPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcAppBskyDraftsPack routePackIdentifier], @"app.bsky.draft");
}

- (void)testChatBskyGroupPackConformsToProtocol {
  XCTAssertTrue([XrpcChatBskyGroupPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcChatBskyGroupPack routePackIdentifier], @"chat.bsky.group");
}

- (void)testAppBskyContactPackConformsToProtocol {
  XCTAssertTrue([XrpcAppBskyContactPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcAppBskyContactPack routePackIdentifier], @"app.bsky.contact");
}

- (void)testAppBskyActorPackConformsToProtocol {
  XCTAssertTrue([XrpcAppBskyActorPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([XrpcAppBskyActorPack routePackIdentifier], @"app.bsky.actor");
}

- (void)testRegistrarRegistersConformingPack {
  XrpcDispatcher *dispatcher = [[XrpcDispatcher alloc] init];
  id<XrpcRoutePackServices> services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:nil
                                          adminController:nil
                                             configuration:nil
                                         serviceDatabases:nil
                                               rateLimiter:nil];

  [XrpcRoutePackRegistrar registerRoutePacks:@[ [XrpcChatBskyActorPack class] ]
                                  dispatcher:dispatcher
                                    services:services];

  XCTAssertTrue([dispatcher hasRegisteredMethod:@"chat.bsky.actor.deleteAccount"]);
  XCTAssertTrue([dispatcher hasRegisteredMethod:@"chat.bsky.moderation.getActorMetadata"]);
}

- (void)testHandlerContextRequiresAuthorizationHeader {
  HttpRequest *request =
      [[HttpRequest alloc] initWithMethod:HttpMethodPOST
                             methodString:@"POST"
                                     path:@"/xrpc/chat.bsky.actor.deleteAccount"
                              queryString:@""
                               queryParams:@{}
                                  version:@"HTTP/1.1"
                                  headers:@{}
                                     body:[NSData data]
                              remoteAddress:@"127.0.0.1"];
  HttpResponse *response = [[HttpResponse alloc] init];
  id<XrpcRoutePackServices> services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:nil
                                                jwtMinter:nil
                                          adminController:nil
                                             configuration:nil
                                         serviceDatabases:nil
                                               rateLimiter:nil];
  XrpcHandlerContext *context =
      [[XrpcHandlerContext alloc] initWithRequest:request
                                         response:response
                                         services:services];

  XCTAssertFalse([context requireAuthentication]);
  XCTAssertEqual(response.statusCode, 401);
}

@end
