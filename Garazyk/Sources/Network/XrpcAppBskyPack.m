// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyPack.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

#import "App/ATProtoServiceConfiguration.h"
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
#import "Database/Schema.h"
#import "Database/Schema/PDSSchemaManager.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
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
#import "Video/VideoLocalBlobUploader.h"
#import "Video/VideoPDSAuthProvider.h"
#import "Blob/PDSBlobProvider.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcToolsOzonePack.h"
#import "Network/Generated/GZXrpcNSID.h"

static PDSRecordLifecycleHandler *_retainedLifecycleHandler = nil;

static void XrpcEnsureLocalAppBskyStateTables(PDSDatabase *database) {
  if (!database) {
    return;
  }

  PDSSchemaManager *schemaManager = [PDSSchemaManager sharedManager];
  NSString *schemaSQL = [NSString stringWithFormat:@"%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;\n%@;",
                                                   [schemaManager serviceActorPreferencesTableSchema],
                                                   [schemaManager serviceActorMutesTableSchema],
                                                   kPDSAdminAuditLogTableCreateSQL,
                                                   [schemaManager ozoneEventsTableSchema],
                                                   [schemaManager ozoneSetsTableSchema],
                                                   [schemaManager ozoneSetMembersTableSchema],
                                                   [schemaManager ozoneTemplatesTableSchema],
                                                   [schemaManager ozoneTeamTableSchema],
                                                   [schemaManager ozoneScheduledActionsTableSchema],
                                                   [schemaManager ozoneSubjectsTableSchema],
                                                   [schemaManager ozoneSafelinksTableSchema],
                                                   [schemaManager bskyDraftsTableSchema],
                                                   @"CREATE INDEX IF NOT EXISTS idx_drafts_did ON drafts(did)",
                                                   [schemaManager bskyBookmarksTableSchema],
                                                   @"CREATE INDEX IF NOT EXISTS idx_bookmarks_did ON bookmarks(did)"];
  NSError *schemaError = nil;
  if (![database executeUnsafeRawSQL:schemaSQL error:&schemaError]) {
    GZ_LOG_ERROR(@"Failed to ensure local app.bsky state tables: %@", schemaError.localizedDescription);
  }
}

@implementation ATProtoXrpcAppBskyPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky";
}

+ (void)setRetainedLifecycleHandler:(PDSRecordLifecycleHandler *)handler {
    _retainedLifecycleHandler = handler;
}

+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  [self registerAppViewMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerPDSLevelMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services {
  PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
  
  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
  XrpcEnsureLocalAppBskyStateTables(appViewDatabase);
  if (!appViewDatabase && appViewDbError) {
    GZ_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                 appViewDbError.localizedDescription ?: @"unknown error");
  }

  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ATProtoXrpcRoutePackServiceBag *mutableServices = (ATProtoXrpcRoutePackServiceBag *)services;
    mutableServices.appViewDatabase = appViewDatabase;
  }

  [ATProtoXrpcAppBskyActorPack registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
  [ATProtoXrpcAppBskyNotificationPack registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_labeler_getServices
                     handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                       id didsParam = request.queryParams[@"dids"];
                       NSArray *dids = nil;
                       if ([didsParam isKindOfClass:[NSArray class]]) {
                         dids = didsParam;
                       } else if ([didsParam isKindOfClass:[NSString class]] && [(NSString *)didsParam length] > 0) {
                         dids = @[didsParam];
                       }
                       if (dids.count == 0) {
                         response.statusCode = HttpStatusBadRequest;
                         [response setJsonBody:@{
                           @"error": @"InvalidRequest",
                           @"message": @"Missing or empty required parameter: dids"
                         }];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"views" : @[]}];
                     }];

  // Bookmarks, chat, and Ozone are PDS-side concerns
  PDSBookmarkService *bookmarkService = [[PDSBookmarkService alloc] initWithDatabase:appViewDatabase];
  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ATProtoXrpcRoutePackServiceBag *mutableServices = (ATProtoXrpcRoutePackServiceBag *)services;
    mutableServices.bookmarkService = bookmarkService;
  }

  [ATProtoXrpcAppBskyBookmarksPack registerWithDispatcher:dispatcher services:services];

  // Only register local chat handlers if a remote chat service is not configured
  if (!dispatcher.chatURL) {
      [ATProtoXrpcChatBskyGroupPack registerWithDispatcher:dispatcher services:services];
      [ATProtoXrpcChatBskyActorPack registerWithDispatcher:dispatcher services:services];
      [ATProtoXrpcChatBskyConvoPack registerWithDispatcher:dispatcher services:services];
  }

  [ATProtoXrpcToolsOzonePack registerWithDispatcher:dispatcher services:services];

  PDSDraftService *draftService = [[PDSDraftService alloc] initWithDatabase:appViewDatabase];
  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ((ATProtoXrpcRoutePackServiceBag *)services).draftService = draftService;
  }
  [ATProtoXrpcAppBskyDraftsPack registerWithDispatcher:dispatcher services:services];
}

+ (void)registerAppViewMethodsWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services {
  [self registerPDSLevelMethodsWithDispatcher:dispatcher services:services];

  PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
  XrpcEnsureLocalAppBskyStateTables(appViewDatabase);

  if ([ATProtoServiceConfiguration sharedConfiguration].appViewURL.length > 0) {
    GZ_LOG_INFO(@"Local AppView disabled; only registering proxy and PDS-side handlers.");
    [ATProtoXrpcAppBskyProxyMethodPack registerWithDispatcher:dispatcher services:services];
    return;
  }

  GZ_LOG_INFO(@"Local AppView enabled; registering full suite of app.bsky.* handlers.");
  
  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ATProtoXrpcRoutePackServiceBag *mutableServices = (ATProtoXrpcRoutePackServiceBag *)services;
    mutableServices.appViewDatabase = appViewDatabase;
  }
  [ATProtoXrpcAppBskyActorPack registerAppViewMethodsWithDispatcher:dispatcher services:services];

  PDSActorService *actorService = [[PDSActorService alloc] initWithDatabase:appViewDatabase];
  PDSNotificationService *notificationService =
      [[PDSNotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];
  PDSGraphService *graphService = [[PDSGraphService alloc] initWithDatabase:appViewDatabase];
  PDSFeedService *feedService = [[PDSFeedService alloc] initWithDatabase:appViewDatabase];
  PDSContactService *contactService = [[PDSContactService alloc] initWithDatabase:appViewDatabase
                                                                actorService:actorService];
  PDSAgeAssuranceService *ageAssuranceService = [[PDSAgeAssuranceService alloc] initWithDatabase:appViewDatabase
                                                                             emailProvider:services.emailProvider];
  
  PDSBookmarkService *bookmarkService = [[PDSBookmarkService alloc] initWithDatabase:appViewDatabase];

  PDSRecordLifecycleHandler *lifecycleHandler =
      [[PDSRecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                   bookmarkService:bookmarkService
                                                      graphService:graphService
                                                       feedService:feedService
                                                          database:appViewDatabase];

  [ATProtoXrpcAppBskyPack setRetainedLifecycleHandler:lifecycleHandler];

  [ATProtoXrpcAppBskyFeedPack registerWithDispatcher:dispatcher services:services];
  [ATProtoXrpcAppBskyGraphPack registerWithDispatcher:dispatcher services:services];

  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ATProtoXrpcRoutePackServiceBag *mutableServices = (ATProtoXrpcRoutePackServiceBag *)services;
    mutableServices.notificationService = notificationService;
  }
  [ATProtoXrpcAppBskyNotificationPack registerAppViewMethodsWithDispatcher:dispatcher services:services];

  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ((ATProtoXrpcRoutePackServiceBag *)services).ageAssuranceService = ageAssuranceService;
    ((ATProtoXrpcRoutePackServiceBag *)services).contactService = contactService;
  }
  [ATProtoXrpcAppBskyAgeAssurancePack registerWithDispatcher:dispatcher services:services];
  [ATProtoXrpcAppBskyContactPack registerWithDispatcher:dispatcher services:services];
  
  // Register video XRPC endpoints (only in internal mode)
  NSString *videoMode = [[[NSProcessInfo processInfo] environment] objectForKey:@"PDS_VIDEO_MODE"];
  BOOL videoInternal = (videoMode == nil || [videoMode isEqualToString:@"internal"]);
  if (videoInternal) {
      id<VideoJobStore> jobStore = services.videoJobStore;
      if (!jobStore) {
        GZ_LOG_WARN(@"Video XRPC routes not registered: no video job store is configured");
      } else {
        id<VideoAuthProvider> authProvider = [[ATProtoVideoPDSAuthProvider alloc] initWithJwtMinter:services.jwtMinter
                                                                                 adminController:services.adminController];
        if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
          ATProtoXrpcRoutePackServiceBag *bag = (ATProtoXrpcRoutePackServiceBag *)services;
          bag.videoJobStore = jobStore;
          bag.videoAuthProvider = authProvider;
        }
        [ATProtoVideoXrpcPack registerWithDispatcher:dispatcher services:services];
      }
  }
  
  // Create and populate search index service
  PDSSearchIndexService *searchIndexService = [[PDSSearchIndexService alloc] initWithDatabase:appViewDatabase];
  [searchIndexService populateIndexIfEmptyWithError:nil];
  if ([services isKindOfClass:[ATProtoXrpcRoutePackServiceBag class]]) {
    ATProtoXrpcRoutePackServiceBag *mutableServices = (ATProtoXrpcRoutePackServiceBag *)services;
    mutableServices.feedService = feedService;
    mutableServices.searchIndexService = searchIndexService;
  }

  [ATProtoXrpcAppBskyUnspeccedPack registerWithDispatcher:dispatcher services:services];
  [ATProtoXrpcAppBskyProxyMethodPack registerWithDispatcher:dispatcher services:services];
}

@end
