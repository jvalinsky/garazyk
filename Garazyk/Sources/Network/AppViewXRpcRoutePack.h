// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

/**
 * @abstract Defines the PDSQueryDatabase protocol contract.
 */
@protocol PDSQueryDatabase;
@class FeedService;
@class ActorService;
@class GraphService;
@class FeedService;
@class ActorService;
@class GraphService;
@class NotificationService;
@class AgeAssuranceService;
@class DraftService;
@class BookmarkService;
@class ContactService;
@class SearchIndexService;
@class JWTMinter;
@class HttpServer;
@class AppViewWriteProxy;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewXRpcRoutePack : NSObject

/**
 * @abstract Performs the initWithFeedService operation.
 */
- (instancetype)initWithFeedService:(FeedService *)feedService
                       actorService:(ActorService *)actorService
                       graphService:(nullable GraphService *)graphService
                 notificationService:(NotificationService *)notificationService
                ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService
                        draftService:(nullable DraftService *)draftService
                     bookmarkService:(nullable BookmarkService *)bookmarkService
                      contactService:(nullable ContactService *)contactService
                  searchIndexService:(nullable SearchIndexService *)searchIndexService
                         writeProxy:(nullable AppViewWriteProxy *)writeProxy
                          database:(nullable id<PDSQueryDatabase>)database
                         jwtMinter:(nullable JWTMinter *)jwtMinter;


/**
 * @abstract Performs the registerRoutesWithServer operation.
 */
- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
