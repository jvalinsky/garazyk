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
#import "Video/VideoWorker.h"
#import "Video/PDSLocalVideoJobStore.h"
#import "Video/VideoLocalBlobUploader.h"
#import "Video/VideoPDSAuthProvider.h"
#import "Blob/PDSBlobProvider.h"
#import "Network/XrpcChatBskyGroupPack.h"
#import "Network/XrpcChatBskyActorPack.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcToolsOzonePack.h"
#import "Network/Generated/GZXrpcNSID.h"

static RecordLifecycleHandler *_retainedLifecycleHandler = nil;

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

@implementation XrpcAppBskyPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky";
}

+ (void)setRetainedLifecycleHandler:(RecordLifecycleHandler *)handler {
    _retainedLifecycleHandler = handler;
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  [self registerAppViewMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services {
  PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
  
  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
  XrpcEnsureLocalAppBskyStateTables(appViewDatabase);
  if (!appViewDatabase && appViewDbError) {
    GZ_LOG_WARN(@"Failed to open service database for app.bsky handlers: %@",
                 appViewDbError.localizedDescription ?: @"unknown error");
  }

  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    XrpcRoutePackServiceBag *mutableServices = (XrpcRoutePackServiceBag *)services;
    mutableServices.appViewDatabase = appViewDatabase;
  }

  [XrpcAppBskyActorPack registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
  [XrpcAppBskyNotificationPack registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_labeler_getServices
                     handler:^(HttpRequest *request, HttpResponse *response) {
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
  BookmarkService *bookmarkService = [[BookmarkService alloc] initWithDatabase:appViewDatabase];
  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    XrpcRoutePackServiceBag *mutableServices = (XrpcRoutePackServiceBag *)services;
    mutableServices.bookmarkService = bookmarkService;
  }

  [XrpcAppBskyBookmarksPack registerWithDispatcher:dispatcher services:services];

  // Only register local chat handlers if a remote chat service is not configured
  if (!dispatcher.chatURL) {
      [XrpcChatBskyGroupPack registerWithDispatcher:dispatcher services:services];
      [XrpcChatBskyActorPack registerWithDispatcher:dispatcher services:services];
      [XrpcChatBskyConvoPack registerWithDispatcher:dispatcher services:services];
  }

  [XrpcToolsOzonePack registerWithDispatcher:dispatcher services:services];

  DraftService *draftService = [[DraftService alloc] initWithDatabase:appViewDatabase];
  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    ((XrpcRoutePackServiceBag *)services).draftService = draftService;
  }
  [XrpcAppBskyDraftsPack registerWithDispatcher:dispatcher services:services];
}

+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services {
  [self registerPDSLevelMethodsWithDispatcher:dispatcher services:services];

  PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
  NSError *appViewDbError = nil;
  PDSDatabase *appViewDatabase = [serviceDatabases serviceDatabaseWithError:&appViewDbError];
  XrpcEnsureLocalAppBskyStateTables(appViewDatabase);

  if ([ATProtoServiceConfiguration sharedConfiguration].appViewURL.length > 0) {
    GZ_LOG_INFO(@"Local AppView disabled; only registering proxy and PDS-side handlers.");
    [XrpcAppBskyProxyMethodPack registerWithDispatcher:dispatcher services:services];
    return;
  }

  GZ_LOG_INFO(@"Local AppView enabled; registering full suite of app.bsky.* handlers.");
  
  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    XrpcRoutePackServiceBag *mutableServices = (XrpcRoutePackServiceBag *)services;
    mutableServices.appViewDatabase = appViewDatabase;
  }
  [XrpcAppBskyActorPack registerAppViewMethodsWithDispatcher:dispatcher services:services];

  ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
  NotificationService *notificationService =
      [[NotificationService alloc] initWithDatabase:appViewDatabase actorService:actorService];
  GraphService *graphService = [[GraphService alloc] initWithDatabase:appViewDatabase];
  FeedService *feedService = [[FeedService alloc] initWithDatabase:appViewDatabase];
  ContactService *contactService = [[ContactService alloc] initWithDatabase:appViewDatabase
                                                                actorService:actorService];
  AgeAssuranceService *ageAssuranceService = [[AgeAssuranceService alloc] initWithDatabase:appViewDatabase
                                                                             emailProvider:services.emailProvider];
  
  BookmarkService *bookmarkService = [[BookmarkService alloc] initWithDatabase:appViewDatabase];

  RecordLifecycleHandler *lifecycleHandler =
      [[RecordLifecycleHandler alloc] initWithNotificationService:notificationService
                                                   bookmarkService:bookmarkService
                                                      graphService:graphService
                                                       feedService:feedService
                                                          database:appViewDatabase];

  [XrpcAppBskyPack setRetainedLifecycleHandler:lifecycleHandler];

  [XrpcAppBskyFeedPack registerWithDispatcher:dispatcher services:services];
  [XrpcAppBskyGraphPack registerWithDispatcher:dispatcher services:services];

  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    XrpcRoutePackServiceBag *mutableServices = (XrpcRoutePackServiceBag *)services;
    mutableServices.notificationService = notificationService;
  }
  [XrpcAppBskyNotificationPack registerAppViewMethodsWithDispatcher:dispatcher services:services];

  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    ((XrpcRoutePackServiceBag *)services).ageAssuranceService = ageAssuranceService;
    ((XrpcRoutePackServiceBag *)services).contactService = contactService;
  }
  [XrpcAppBskyAgeAssurancePack registerWithDispatcher:dispatcher services:services];
  [XrpcAppBskyContactPack registerWithDispatcher:dispatcher services:services];
  
  // Register video XRPC endpoints (only in internal mode)
  NSString *videoMode = [[[NSProcessInfo processInfo] environment] objectForKey:@"PDS_VIDEO_MODE"];
  BOOL videoInternal = (videoMode == nil || [videoMode isEqualToString:@"internal"]);
  if (videoInternal) {
      id<VideoJobStore> jobStore = [[PDSLocalVideoJobStore alloc] initWithDatabase:appViewDatabase];
      id<VideoAuthProvider> authProvider = [[VideoPDSAuthProvider alloc] initWithJwtMinter:services.jwtMinter
                                                                               adminController:services.adminController];
      if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
        XrpcRoutePackServiceBag *bag = (XrpcRoutePackServiceBag *)services;
        bag.videoJobStore = jobStore;
        bag.videoAuthProvider = authProvider;
        bag.blobProvider = [ATProtoVideoWorker sharedWorker].blobProvider;
      }
      [ATProtoVideoXrpcPack registerWithDispatcher:dispatcher services:services];
  }
  
  // Create and populate search index service
  SearchIndexService *searchIndexService = [[SearchIndexService alloc] initWithDatabase:appViewDatabase];
  [searchIndexService populateIndexIfEmptyWithError:nil];
  if ([services isKindOfClass:[XrpcRoutePackServiceBag class]]) {
    XrpcRoutePackServiceBag *mutableServices = (XrpcRoutePackServiceBag *)services;
    mutableServices.feedService = feedService;
    mutableServices.searchIndexService = searchIndexService;
  }

  [XrpcAppBskyUnspeccedPack registerWithDispatcher:dispatcher services:services];
  [XrpcAppBskyProxyMethodPack registerWithDispatcher:dispatcher services:services];
}

@end
