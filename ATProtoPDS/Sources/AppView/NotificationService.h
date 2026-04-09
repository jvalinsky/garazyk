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
@class ActorService;

/*!
 @class NotificationService

 @abstract Service for push notifications and notification feeds.

 @discussion Handles push notification device registration and provides
 paginated access to notification feeds. Supports marking notifications as read.
 */
@interface NotificationService : NSObject

/*! Initialize with database connection and actor service for profile hydration. */
- (instancetype)initWithDatabase:(PDSDatabase *)database
                    actorService:(nullable ActorService *)actorService;

/*! Convenience initializer (no profile hydration). */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/*! Database connection (exposed for testing). */
@property (nonatomic, strong, readonly) PDSDatabase *database;

/*! Register device for push notifications. */
- (BOOL)registerPushForActor:(NSString *)actorDID
                 deviceToken:(NSString *)deviceToken
               platformToken:(nullable NSString *)platformToken
               serviceEndpoint:(NSString *)serviceEndpoint
                       error:(NSError **)error;

/*! Unregister push notifications for actor (actor-wide). */
- (BOOL)unregisterPushForActor:(NSString *)actorDID error:(NSError **)error;

/*! Unregister a specific push token for actor (token-scoped). */
- (BOOL)unregisterPushToken:(NSString *)deviceToken
                   forActor:(NSString *)actorDID
                      error:(NSError **)error;

/*! Get notification feed with pagination. */
- (nullable NSArray<NSDictionary *> *)getNotificationsForActor:(NSString *)actorDID
                                                          limit:(NSInteger)limit
                                                        cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error;

/*! Mark notifications as read up to limit. */
- (BOOL)markNotificationsAsReadForActor:(NSString *)actorDID
                                  limit:(NSInteger)limit
                                    error:(NSError **)error;

/*! Create a notification for an actor. */
- (BOOL)createNotificationForActor:(NSString *)actorDID
                          authorDID:(NSString *)authorDID
                             reason:(NSString *)reason
                      reasonSubject:(nullable NSString *)reasonSubject
                         subjectURI:(nullable NSString *)subjectURI
                         subjectCID:(nullable NSString *)subjectCID
                              error:(NSError **)error;

/*! Get unread notification count for actor. */
- (NSInteger)getUnreadCountForActor:(NSString *)actorDID error:(NSError **)error;

/*! Delete notifications matching a subject URI (used when a record is deleted). */
- (BOOL)deleteNotificationsForSubjectURI:(NSString *)subjectURI error:(NSError **)error;

/*! Put (upsert) an activity subscription entry keyed by subject DID. */
- (BOOL)putActivitySubscriptionForActor:(NSString *)actorDID
                               subject:(NSString *)subjectDID
                          postEnabled:(BOOL)postEnabled
                          replyEnabled:(BOOL)replyEnabled
                                error:(NSError **)error;

/*! List activity subscriptions for actor with pagination. */
- (nullable NSDictionary *)getActivitySubscriptionsForActor:(NSString *)actorDID
                                                      limit:(NSInteger)limit
                                                    cursor:(nullable NSString *)cursor
                                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
