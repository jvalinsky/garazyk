#import "Network/XrpcAppBskyMethods.h"

#import "App/PDSConfiguration.h"
#import "AppView/ActorService.h"
#import "AppView/BookmarkService.h"
#import "AppView/GraphService.h"
#import "AppView/NotificationService.h"
#import "AppView/RecordLifecycleHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcAppBskyBookmarksPack.h"
#import "Network/XrpcAppBskyDraftsPack.h"
#import "Network/XrpcAppBskyFeedPack.h"
#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcAppBskyNotificationPack.h"
#import "Network/XrpcAppBskyProxyMethodPack.h"
#import "Network/XrpcAppBskyUnspeccedPack.h"
#import "Network/XrpcAppBskyVideoPack.h"
#import "Network/XrpcChatBskyConvoPack.h"

@implementation XrpcAppBskyMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController {
  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase =
      [serviceDatabases serviceDatabaseWithError:&appViewDbError];
  if (!appViewDatabase && appViewDbError) {
    PDS_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                 appViewDbError.localizedDescription ?: @"unknown error");
  }

  [XrpcAppBskyActorPack registerWithDispatcher:dispatcher
                                 appViewDatabase:appViewDatabase
                                      jwtMinter:jwtMinter
                                adminController:adminController];

  [XrpcAppBskyNotificationPack registerPDSLevelMethodsWithDispatcher:dispatcher
                                                     appViewDatabase:appViewDatabase
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController];

  if (![PDSConfiguration sharedConfiguration].localAppViewEnabled) {
    PDS_LOG_INFO(@"Local AppView disabled; skipping registration of app.bsky.* "
                 @"feed/graph/notification handlers.");
    [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
    [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher];
    return;
  }

  NotificationService *notificationService =
      [[NotificationService alloc] initWithDatabase:appViewDatabase
                                       actorService:[[ActorService alloc]
                                                        initWithDatabase:appViewDatabase]];
  GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
  BookmarkService *bookmarkService = [[BookmarkService alloc] initWithDatabase:appViewDatabase];

  __attribute__((unused)) RecordLifecycleHandler *lifecycleHandler =
      [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                  bookmarkService:bookmarkService
                                                     graphService:graphService
                                                         database:appViewDatabase];

  [XrpcAppBskyFeedPack registerWithDispatcher:dispatcher
                               appViewDatabase:appViewDatabase
                                     jwtMinter:jwtMinter
                               adminController:adminController];

  [XrpcAppBskyGraphPack registerWithDispatcher:dispatcher
                              serviceDatabases:serviceDatabases
                                appViewDatabase:appViewDatabase
                                     jwtMinter:jwtMinter
                               adminController:adminController];

  [XrpcAppBskyNotificationPack registerWithDispatcher:dispatcher
                                        appViewDatabase:appViewDatabase
                                             jwtMinter:jwtMinter
                                       adminController:adminController];

  [XrpcAppBskyBookmarksPack registerWithDispatcher:dispatcher
                                   bookmarkService:bookmarkService
                                         jwtMinter:jwtMinter
                                   adminController:adminController];

  [XrpcAppBskyDraftsPack registerWithDispatcher:dispatcher];
  [XrpcAppBskyVideoPack registerWithDispatcher:dispatcher
                                     jwtMinter:jwtMinter
                               adminController:adminController];
  [XrpcAppBskyUnspeccedPack registerWithDispatcher:dispatcher];
  [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
  [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher];
}

@end
