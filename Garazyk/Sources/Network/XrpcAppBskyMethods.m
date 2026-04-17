#import "Network/XrpcAppBskyMethods.h"

#import "App/PDSConfiguration.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/RecordLifecycleHandler.h"
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
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcToolsOzonePack.h"

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
    // Chat endpoints require database access, skip when AppView is disabled
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
                                serviceDatabases:serviceDatabases
                                    appViewDatabase:appViewDatabase
                                         jwtMinter:jwtMinter
                                   adminController:adminController];
  [XrpcAppBskyUnspeccedPack registerWithDispatcher:dispatcher];
  [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
  [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher
                               appViewDatabase:appViewDatabase
                                    jwtMinter:jwtMinter
                              adminController:adminController];
  [XrpcChatBskyGroupPack registerWithDispatcher:dispatcher
                              appViewDatabase:appViewDatabase
                                   jwtMinter:jwtMinter
                             adminController:adminController];
  [XrpcToolsOzonePack registerWithDispatcher:dispatcher
                            appViewDatabase:appViewDatabase
                                 jwtMinter:jwtMinter
                           adminController:adminController];
}

@end
