// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

/**
 * @abstract Defines the PDSQueryDatabase protocol contract.
 */
@protocol PDSQueryDatabase;
@class PDSFeedService;
@class PDSActorService;
@class PDSGraphService;
@class PDSFeedService;
@class PDSActorService;
@class PDSGraphService;
@class PDSNotificationService;
@class PDSAgeAssuranceService;
@class PDSDraftService;
@class PDSBookmarkService;
@class PDSContactService;
@class PDSSearchIndexService;
@class ATProtoJWTMinter;
@class ATProtoHttpServer;
@class AppViewWriteProxy;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoAppViewXRpcRoutePack : NSObject

/**
 * @abstract Performs the initWithFeedService operation.
 */
- (instancetype)initWithFeedService:(PDSFeedService *)feedService
                       actorService:(PDSActorService *)actorService
                       graphService:(nullable PDSGraphService *)graphService
                 notificationService:(PDSNotificationService *)notificationService
                ageAssuranceService:(nullable PDSAgeAssuranceService *)ageAssuranceService
                        draftService:(nullable PDSDraftService *)draftService
                     bookmarkService:(nullable PDSBookmarkService *)bookmarkService
                      contactService:(nullable PDSContactService *)contactService
                  searchIndexService:(nullable PDSSearchIndexService *)searchIndexService
                         writeProxy:(nullable AppViewWriteProxy *)writeProxy
                          database:(nullable id<PDSQueryDatabase>)database
                         jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter;


/**
 * @abstract Performs the registerRoutesWithServer operation.
 */
- (void)registerRoutesWithServer:(ATProtoHttpServer *)server;

@end

NS_ASSUME_NONNULL_END
