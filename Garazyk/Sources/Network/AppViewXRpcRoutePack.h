#import <Foundation/Foundation.h>

@class FeedService;
@class ActorService;
@class NotificationService;
@class HttpServer;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewXRpcRoutePack : NSObject

- (instancetype)initWithFeedService:(FeedService *)feedService
                      actorService:(ActorService *)actorService
                notificationService:(NotificationService *)notificationService;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
