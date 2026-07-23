// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@class HttpRequest;
@class HttpResponse;

@class FeedService;
@class ActorService;
@class GraphService;
@class NotificationService;
@class AgeAssuranceService;
@class DraftService;
@class BookmarkService;
@class ContactService;
@class SearchIndexService;
@class AppViewWriteProxy;
@protocol PDSQueryDatabase;
@class JWTMinter;

@interface AppViewXRpcRoutePack ()

@property (nonatomic, strong, readonly) FeedService *feedService;
@property (nonatomic, strong, readonly) ActorService *actorService;
@property (nonatomic, strong, readonly) GraphService *graphService;
@property (nonatomic, strong, readonly) NotificationService *notificationService;
@property (nonatomic, strong, readonly) AgeAssuranceService *ageAssuranceService;
@property (nonatomic, strong, readonly) DraftService *draftService;
@property (nonatomic, strong, readonly) BookmarkService *bookmarkService;
@property (nonatomic, strong, readonly) ContactService *contactService;
@property (nonatomic, strong, readonly) SearchIndexService *searchIndexService;
@property (nonatomic, strong, readonly) AppViewWriteProxy *writeProxy;
@property (nonatomic, strong, readonly) id<PDSQueryDatabase> database;
@property (nonatomic, strong, readonly) JWTMinter *jwtMinter;

- (NSString *)requireAuth:(HttpRequest *)request response:(HttpResponse *)response;
- (NSString *)extractDIDFromAuth:(NSString *)authHeader request:(HttpRequest *)request;

@end

NSInteger parseLimitParam(HttpRequest *request, NSInteger defaultLimit, NSInteger maxLimit);