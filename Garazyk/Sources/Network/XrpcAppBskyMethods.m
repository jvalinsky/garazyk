// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyMethods.h"
#import "Network/XrpcHandler.h"

#import "App/PDSConfiguration.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/ContactService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "AppView/Services/DraftService.h"
#import "AppView/Services/RecordLifecycleHandler.h"
#import "AppView/Services/SearchIndexService.h"
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
#import "Video/VideoXrpcPack.h"
#import "Video/VideoWorker.h"
#import "Video/PDSLocalVideoJobStore.h"
#import "Video/VideoLocalBlobUploader.h"
#import "Video/VideoPDSAuthProvider.h"
#import "Blob/PDSBlobProvider.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcToolsOzonePack.h"

static RecordLifecycleHandler *_retainedLifecycleHandler = nil;

@implementation XrpcAppBskyMethods

+ (void)setRetainedLifecycleHandler:(RecordLifecycleHandler *)handler {
    _retainedLifecycleHandler = handler;
}

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                      jwtMinter:(nullable JWTMinter *)jwtMinter
                                adminController:(nullable id<PDSAdminController>)adminController
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

  // Bookmarks, chat, and Ozone are PDS-side concerns
  BookmarkService *bookmarkService =
      [[BookmarkService alloc] initWithDatabase:appViewDatabase];

  [XrpcAppBskyBookmarksPack registerWithDispatcher:dispatcher
                                    bookmarkService:bookmarkService
                                          jwtMinter:jwtMinter
                                    adminController:adminController];

  // Only register local chat handlers if a remote chat service is not configured
  if (!dispatcher.chatURL) {
      [XrpcChatBskyGroupPack registerWithDispatcher:dispatcher
                                     appViewDatabase:appViewDatabase
                                          jwtMinter:jwtMinter
                                    adminController:adminController];
      [XrpcChatBskyActorPack registerWithDispatcher:dispatcher];
      [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher
                                    appViewDatabase:appViewDatabase
                                  serviceDatabase:appViewDatabase
                                         jwtMinter:jwtMinter
                                   adminController:adminController
                                      adminSecret:nil];
  }

  [XrpcToolsOzonePack registerWithDispatcher:dispatcher
                             appViewDatabase:appViewDatabase
                                   jwtMinter:jwtMinter
                             adminController:adminController];

  DraftService *draftService = [[DraftService alloc] initWithDatabase:appViewDatabase];
  [XrpcAppBskyDraftsPack registerWithDispatcher:dispatcher
                                    draftService:draftService
                                       jwtMinter:jwtMinter
                                 adminController:adminController];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                       jwtMinter:(nullable JWTMinter *)jwtMinter
                 adminController:(nullable id<PDSAdminController>)adminController
                   emailProvider:(nullable id<PDSEmailProvider>)emailProvider {

  [self registerPDSLevelMethodsWithDispatcher:dispatcher
                              serviceDatabases:serviceDatabases
                                     jwtMinter:jwtMinter
                               adminController:adminController
                                 emailProvider:emailProvider];

  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase =
      [serviceDatabases serviceDatabaseWithError:&appViewDbError];

  if ([PDSConfiguration sharedConfiguration].appViewURL.length > 0) {
    PDS_LOG_INFO(@"Local AppView disabled; only registering proxy and PDS-side handlers.");
    [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
    return;
  }

  PDS_LOG_INFO(@"Local AppView enabled; registering full suite of app.bsky.* handlers.");
  
  [XrpcAppBskyActorPack registerAppViewMethodsWithDispatcher:dispatcher
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
  
  BookmarkService *bookmarkService = [[BookmarkService alloc] initWithDatabase:appViewDatabase];

  RecordLifecycleHandler *lifecycleHandler =
      [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                   bookmarkService:bookmarkService
                                                      graphService:graphService
                                                       feedService:feedService
                                                          database:appViewDatabase];

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

  [XrpcAppBskyNotificationPack registerAppViewMethodsWithDispatcher:dispatcher
                                                        appViewDatabase:appViewDatabase
                                                              jwtMinter:jwtMinter
                                                        adminController:adminController];

  [XrpcAppBskyAgeAssurancePack registerWithDispatcher:dispatcher ageAssuranceService:ageAssuranceService];
  [XrpcAppBskyContactPack registerWithDispatcher:dispatcher contactService:contactService jwtMinter:jwtMinter adminController:adminController];
  // Register video XRPC endpoints (only in internal mode)
  NSString *videoMode = [[[NSProcessInfo processInfo] environment] objectForKey:@"PDS_VIDEO_MODE"];
  BOOL videoInternal = (videoMode == nil || [videoMode isEqualToString:@"internal"]);
  if (videoInternal) {
      PDSDatabase *serviceDB = [serviceDatabases serviceDatabaseWithError:nil];
      id<VideoJobStore> jobStore = [[PDSLocalVideoJobStore alloc] initWithDatabase:serviceDB];
      id<VideoAuthProvider> authProvider = [[VideoPDSAuthProvider alloc] initWithJwtMinter:jwtMinter
                                                                               adminController:adminController];
      [ATProtoVideoXrpcPack registerWithDispatcher:dispatcher
                                           jobStore:jobStore
                                       authProvider:authProvider
                                      blobProvider:[ATProtoVideoWorker sharedWorker].blobProvider];
  }
  // Create and populate search index service
  SearchIndexService *searchIndexService = [[SearchIndexService alloc] initWithDatabase:appViewDatabase];
  [searchIndexService populateIndexIfEmptyWithError:nil];

  [XrpcAppBskyUnspeccedPack registerWithDispatcher:dispatcher
                                ageAssuranceService:ageAssuranceService
                                   searchIndexService:searchIndexService
                                         feedService:feedService];
  [XrpcAppBskyProxyMethodPack registerProxyOnlyMethodsWithDispatcher:dispatcher];
}


@end
