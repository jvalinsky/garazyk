#import <Foundation/Foundation.h>

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


- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
