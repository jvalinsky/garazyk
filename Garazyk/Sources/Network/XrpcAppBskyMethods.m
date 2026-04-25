#import "Network/XrpcAppBskyMethods.h"

#import "App/PDSConfiguration.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/ContactService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "AppView/Services/ChatModerationService.h"
#import "AppView/Services/RecordLifecycleHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import "Network/XrpcAppBskyActorPack.h"
#import "Network/XrpcAppBskyAgeAssurancePack.h"
#import "Network/XrpcAppBskyBookmarksPack.h"
#import "Network/XrpcAppBskyContactPack.h"
#import "Network/XrpcAppBskyDraftsPack.h"
#import "Network/XrpcAppBskyFeedPack.h"
#import "Network/XrpcAppBskyGraphPack.h"
#import "Network/XrpcAppBskyNotificationPack.h"
#import "Network/XrpcAppBskyProxyMethodPack.h"
#import "Network/XrpcAppBskyUnspeccedPack.h"
#import "Network/XrpcAppBskyVideoPack.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcToolsOzonePack.h"

static RecordLifecycleHandler *_retainedLifecycleHandler = nil;

@implementation XrpcAppBskyMethods

+ (void)setRetainedLifecycleHandler:(RecordLifecycleHandler *)handler {
    _retainedLifecycleHandler = handler;
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       jwtMinter:(JWTMinter *)jwtMinter
                 adminController:(id<PDSAdminController>)adminController
                   emailProvider:(nullable id<PDSEmailProvider>)emailProvider {
  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase =
      [serviceDatabases serviceDatabaseWithError:&appViewDbError];
  if (!appViewDatabase && appViewDbError) {
    PDS_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                 appViewDbError.localizedDescription ?: @"unknown error");
  }

  [XrpcAppBskyActorPack registerPDSLevelMethodsWithDispatcher:dispatcher
                                               appViewDatabase:appViewDatabase
                                                     jwtMinter:jwtMinter
                                               adminController:adminController];

  [XrpcAppBskyNotificationPack registerPDSLevelMethodsWithDispatcher:dispatcher
                                                     appViewDatabase:appViewDatabase
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController];

  // Bookmarks, chat, and Ozone are PDS-side concerns: bookmarks are private
  // user state stored on the PDS, chat is bundled into the PDS in this
  // codebase (vs. a separate service in upstream Bluesky), and Ozone admin/
  // moderation queries operate on PDS-local report and account data.
  // Register them unconditionally so a remote-AppView deployment still has
  // these endpoints available.
  BookmarkService *bookmarkService =
      [[BookmarkService alloc] initWithDatabase:appViewDatabase];
  ChatModerationService *chatModerationService =
      [[ChatModerationService alloc] initWithDatabase:appViewDatabase];

  [XrpcAppBskyBookmarksPack registerWithDispatcher:dispatcher
                                    bookmarkService:bookmarkService
                                          jwtMinter:jwtMinter
                                    adminController:adminController];

  [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher
                                 appViewDatabase:appViewDatabase
                                      jwtMinter:jwtMinter
                                adminController:adminController];
  [XrpcChatBskyGroupPack registerWithDispatcher:dispatcher
                                 appViewDatabase:appViewDatabase
                                      jwtMinter:jwtMinter
                                adminController:adminController];
  [XrpcChatBskyActorPack registerWithDispatcher:dispatcher
                          chatModerationService:chatModerationService];

  [XrpcToolsOzonePack registerWithDispatcher:dispatcher
                             appViewDatabase:appViewDatabase
                                   jwtMinter:jwtMinter
                             adminController:adminController];

  if (![PDSConfiguration sharedConfiguration].localAppViewEnabled) {
    PDS_LOG_INFO(@"Local AppView disabled; only registering proxy and PDS-side handlers.");
    [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
    return;
  }

  PDS_LOG_INFO(@"Local AppView enabled; registering full suite of app.bsky.* handlers.");
  [XrpcAppBskyActorPack registerWithDispatcher:dispatcher
                                 appViewDatabase:appViewDatabase
                                       jwtMinter:jwtMinter
                                 adminController:adminController];

  NotificationService *notificationService =
      [[NotificationService alloc] initWithDatabase:appViewDatabase
                                       actorService:[[ActorService alloc]
                                                        initWithDatabase:appViewDatabase]];
  GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
  FeedService *feedService = [[FeedService alloc] initWithDatabase:appViewDatabase];
  ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
  ContactService *contactService = [[ContactService alloc] initWithDatabase:appViewDatabase
                                                                actorService:actorService];
  AgeAssuranceService *ageAssuranceService = [[AgeAssuranceService alloc] initWithDatabase:appViewDatabase
                                                                             emailProvider:emailProvider];

  RecordLifecycleHandler *lifecycleHandler =
      [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                   bookmarkService:bookmarkService
                                                      graphService:graphService
                                                       feedService:feedService
                                                          database:appViewDatabase];

  // Store the lifecycle handler in the registry so it is retained for the
  // process lifetime. NSNotificationCenter does not retain observers, so
  // the handler must be kept alive to receive PDSRecordDidChangeNotification.
  [XrpcAppBskyMethods setRetainedLifecycleHandler:lifecycleHandler];

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

  [XrpcAppBskyDraftsPack registerWithDispatcher:dispatcher];
  [XrpcAppBskyAgeAssurancePack registerWithDispatcher:dispatcher ageAssuranceService:ageAssuranceService];
  [XrpcAppBskyContactPack registerWithDispatcher:dispatcher contactService:contactService jwtMinter:jwtMinter adminController:adminController];
  [XrpcAppBskyVideoPack registerWithDispatcher:dispatcher
                                 serviceDatabases:serviceDatabases
                                     appViewDatabase:appViewDatabase
                                          jwtMinter:jwtMinter
                                    adminController:adminController];
  [XrpcAppBskyUnspeccedPack registerWithDispatcher:dispatcher ageAssuranceService:ageAssuranceService];
  [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
}

@end
