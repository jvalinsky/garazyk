/*!
 @file NotificationService.h

 @abstract Push notification and notification feed service.

 @discussion Manages push notification registration and provides access to
 notification feeds. Part of AppView layer for notification delivery.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class NotificationService

 @abstract Service for push notifications and notification feeds.

 @discussion Handles push notification device registration and provides
 paginated access to notification feeds. Supports marking notifications as read.
 */
@interface NotificationService : NSObject

/*! Initialize with database connection. */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*! Register device for push notifications. */
- (BOOL)registerPushForActor:(NSString *)actorDID
                 deviceToken:(NSString *)deviceToken
               platformToken:(nullable NSString *)platformToken
               serviceEndpoint:(NSString *)serviceEndpoint
                       error:(NSError **)error;

/*! Unregister push notifications for actor. */
- (BOOL)unregisterPushForActor:(NSString *)actorDID error:(NSError **)error;

/*! Get notification feed with pagination. */
- (nullable NSArray<NSDictionary *> *)getNotificationsForActor:(NSString *)actorDID
                                                          limit:(NSInteger)limit
                                                        cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error;

/*! Mark notifications as read up to limit. */
- (BOOL)markNotificationsAsReadForActor:(NSString *)actorDID
                                  limit:(NSInteger)limit
                                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
