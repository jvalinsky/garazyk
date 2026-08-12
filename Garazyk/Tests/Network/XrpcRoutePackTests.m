// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAppBskyAgeAssurancePack.h"
#import "Network/XrpcAppBskyBookmarksPack.h"
#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcAppBskyNotificationPack.h"
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
  XCTAssertTrue([ATProtoXrpcChatBskyActorPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcChatBskyActorPack routePackIdentifier], @"chat.bsky.actor");
}

- (void)testAppBskyProxyPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyProxyMethodPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyProxyMethodPack routePackIdentifier], @"app.bsky.proxy");
}

- (void)testAppBskyAgeAssurancePackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyAgeAssurancePack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyAgeAssurancePack routePackIdentifier],
                        @"app.bsky.ageassurance");
}

- (void)testAppBskyBookmarksPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyBookmarksPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyBookmarksPack routePackIdentifier], @"app.bsky.bookmark");
}

- (void)testAppBskyDraftsPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyDraftsPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyDraftsPack routePackIdentifier], @"app.bsky.draft");
}

- (void)testChatBskyGroupPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcChatBskyGroupPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcChatBskyGroupPack routePackIdentifier], @"chat.bsky.group");
}

- (void)testAppBskyContactPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyContactPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyContactPack routePackIdentifier], @"app.bsky.contact");
}

- (void)testAppBskyActorPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyActorPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyActorPack routePackIdentifier], @"app.bsky.actor");
}

- (void)testAppBskyNotificationPackConformsToProtocol {
  XCTAssertTrue([ATProtoXrpcAppBskyNotificationPack conformsToProtocol:@protocol(XrpcRoutePack)]);
  XCTAssertEqualObjects([ATProtoXrpcAppBskyNotificationPack routePackIdentifier], @"app.bsky.notification");
}

- (void)testRegistrarRegistersConformingPack {
  ATProtoXrpcDispatcher *dispatcher = [[ATProtoXrpcDispatcher alloc] init];
  id<XrpcRoutePackServices> services =
      [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:nil
                                          adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];

  [ATProtoXrpcRoutePackRegistrar registerRoutePacks:@[ [ATProtoXrpcChatBskyActorPack class] ]
                                  dispatcher:dispatcher
                                    services:services];

  XCTAssertTrue([dispatcher hasRegisteredMethod:@"chat.bsky.actor.deleteAccount"]);
  XCTAssertTrue([dispatcher hasRegisteredMethod:@"chat.bsky.moderation.getActorMetadata"]);
}

- (void)testHandlerContextRequiresAuthorizationHeader {
  ATProtoHttpRequest *request =
      [[ATProtoHttpRequest alloc] initWithMethod:HttpMethodPOST
                             methodString:@"POST"
                                     path:@"/xrpc/chat.bsky.actor.deleteAccount"
                              queryString:@""
                               queryParams:@{}
                                  version:@"HTTP/1.1"
                                  headers:@{}
                                     body:[NSData data]
                              remoteAddress:@"127.0.0.1"];
  ATProtoHttpResponse *response = [[ATProtoHttpResponse alloc] init];
  id<XrpcRoutePackServices> services =
      [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:nil
                                                jwtMinter:nil
                                          adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  ATProtoXrpcHandlerContext *context =
      [[ATProtoXrpcHandlerContext alloc] initWithRequest:request
                                         response:response
                                         services:services];

  XCTAssertFalse([context requireAuthentication]);
  XCTAssertEqual(response.statusCode, 401);
}

@end
