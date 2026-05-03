/*!
 @file AppViewRuntime.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/AppViewRuntime.h"

#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Config/AppViewConfiguration.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/Backfill/AppViewBackfillOrchestrator.h"
#import "AppView/Server/Relevance/AppViewRelevanceSet.h"
#import "AppView/Server/Indexers/AppViewActorIndexer.h"
#import "AppView/Server/Indexers/AppViewFeedIndexer.h"
#import "AppView/Server/Indexers/AppViewGraphIndexer.h"
#import "AppView/Server/Indexers/AppViewNotificationIndexer.h"
#import "AppView/Server/Indexers/AppViewBookmarkIndexer.h"
#import "AppView/Server/Indexers/AppViewGroupIndexer.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "Network/AppViewXRpcRoutePack.h"
#import "AppView/Server/Admin/AppViewAdminRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"

@interface AppViewRuntime () <AppViewIngestEngineDelegate,
                               AppViewBackfillOrchestratorDelegate>

@property (nonatomic, strong, readwrite) AppViewConfiguration *configuration;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong) AppViewBackfillOrchestrator *orchestrator;
@property (nonatomic, strong) AppViewAdminRoutePack *adminRoutePack;
@property (nonatomic, strong) AppViewRelevanceSet *relevanceSet;
@property (nonatomic, strong) NSArray<id<AppViewIndexer>> *indexers;
@property (nonatomic, strong) HttpServer *httpServer;
@property (nonatomic, strong) FeedService *feedService;
@property (nonatomic, strong) ActorService *actorService;
@property (nonatomic, strong) GraphService *graphService;
@property (nonatomic, strong) NotificationService *notificationService;
@property (nonatomic, strong) BookmarkService *bookmarkService;
@property (nonatomic, strong) AgeAssuranceService *ageAssuranceService;
@property (nonatomic, assign, readwrite) BOOL isRunning;

@end


// ---------------------------------------------------------------------------

static AppViewRuntime *_sharedRuntime = nil;

@implementation AppViewRuntime

+ (instancetype)sharedRuntime {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedRuntime = [[AppViewRuntime alloc] init];
    });
    return _sharedRuntime;
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

- (BOOL)loadConfiguration:(NSString *)path error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return NO;

    NSError *jsonErr = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
    if (jsonErr || !dict) {
        if (error) *error = jsonErr ?: [NSError errorWithDomain:@"AppViewRuntime"
                                                           code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"Invalid config file"}];
        return NO;
    }

    AppViewConfiguration *config = [AppViewConfiguration defaultConfiguration];
    // Extract the appview section if nested
    NSDictionary *avSection = dict[@"appview"] ?: dict;
    [config loadFromDictionary:avSection];
    _configuration = config;

    return [config validate:error];
}

- (void)loadConfigurationFromEnvironment {
    _configuration = [AppViewConfiguration configurationFromEnvironment];
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

- (BOOL)startWithError:(NSError **)error {
    if (_isRunning) return YES;

    AppViewConfiguration *config = _configuration ?: [AppViewConfiguration defaultConfiguration];

    NSError *configErr = nil;
    if (![config validate:&configErr]) {
        if (error) *error = configErr;
        return NO;
    }

    // Ensure data directory exists
    NSError *mkdirErr = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:config.dataDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirErr];

    // Open database
    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"appview.db"];
    NSError *dbErr   = nil;
    _database = [[AppViewDatabase alloc] initWithPath:dbPath error:&dbErr];
    if (!_database) {
        if (error) *error = dbErr;
        return NO;
    }

    // Run migrations
    if (![_database runMigrations:error]) return NO;

    // Build relevance set
    _relevanceSet = [[AppViewRelevanceSet alloc]
        initWithDatabase:_database
                seedDIDs:config.partialSeedDIDs
               allowlist:config.partialAllowlist
                ttlHours:config.partialTTLHours];
    [_relevanceSet rebuild];

    // Build indexers
    AppViewActorIndexer *actorIdx   = [[AppViewActorIndexer alloc] initWithDatabase:_database];
    AppViewFeedIndexer  *feedIdx    = [[AppViewFeedIndexer alloc]  initWithDatabase:_database];
    AppViewGraphIndexer *graphIdx   = [[AppViewGraphIndexer alloc] initWithDatabase:_database
                                                                       relevanceSet:_relevanceSet];
    AppViewNotificationIndexer *notifIdx = [[AppViewNotificationIndexer alloc] initWithDatabase:_database];
    AppViewBookmarkIndexer *bookmarkIdx = [[AppViewBookmarkIndexer alloc] initWithDatabase:_database
                                                                  bookmarkService:_bookmarkService];
    AppViewGroupIndexer *groupIdx = [[AppViewGroupIndexer alloc] initWithDatabase:_database];
    _indexers = @[actorIdx, feedIdx, graphIdx, notifIdx, bookmarkIdx, groupIdx];

    // Build ingest engine
    _ingestEngine = [[AppViewIngestEngine alloc]
        initWithDatabase:_database relayURLs:config.relayURLs];
    _ingestEngine.checkpointIntervalMs = config.cursorCheckpointIntervalMs;
    _ingestEngine.delegate = self;

    // Build backfill orchestrator
    if (config.backfillEnabled) {
        _orchestrator = [[AppViewBackfillOrchestrator alloc]
            initWithDatabase:_database indexers:_indexers plcURL:config.plcURL];
        _orchestrator.globalWorkerCap  = config.backfillGlobalWorkers;
        _orchestrator.perHostWorkerCap = config.backfillPerHostWorkers;
        _orchestrator.delegate = self;
    }

    // Build HTTP server for query API + admin
    _httpServer = [HttpServer serverWithPort:(uint16_t)config.httpPort];

    // Root serves ASCII service banner
    [_httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *req, HttpResponse *res) {
        res.statusCode = 200;
        res.contentType = @"text/plain; charset=utf-8";
        [res setBodyString:@"_____                            \n/  ___|                           \n\\ `--. _   _ _ __ ___ _ __   __ _ \n `--. \\ | | | '__/ _ \\ '_ \\ / _` |\n/\\__/ / |_| | | |  __/ | | | (_| |\n\\____/ \\__, |_|  \\___|_| |_|\\__,_|\n        __/ |                     \n       |___/  \n"];
    }];

    [_httpServer addRoute:@"GET" path:@"/favicon.ico" handler:^(HttpRequest *req, HttpResponse *res) {
        res.statusCode = HttpStatusNoContent;
        res.contentType = @"image/x-icon";
        [res setBodyData:[NSData data]];
    }];

    // Initialize Services with AppViewDatabase (which now conforms to PDSQueryDatabase)
    _feedService = [[FeedService alloc] initWithDatabase:_database];
    _actorService = [[ActorService alloc] initWithDatabase:_database];
    _graphService = [[GraphService alloc] initWithDatabase:_database];
    _notificationService = [[NotificationService alloc] initWithDatabase:_database
                                                            actorService:_actorService];
    _ageAssuranceService = [[AgeAssuranceService alloc] initWithDatabase:_database
                                                           emailProvider:nil];
    _bookmarkService = [[BookmarkService alloc] initWithDatabase:_database];

    // Initialize JWTMinter for token verification (using shared master secret)
    JWTMinter *jwtMinter = nil;
    if (config.masterSecret.length > 0) {
        jwtMinter = [[JWTMinter alloc] init];
        jwtMinter.issuer = @"http://localhost:2583"; // The PDS issuer we expect tokens from
    }

// Register XRPC routes
    AppViewXRpcRoutePack *xrpcPack = [[AppViewXRpcRoutePack alloc] initWithFeedService:_feedService
                                                                    actorService:_actorService
                                                                    graphService:_graphService
                                                              notificationService:_notificationService
                                                              ageAssuranceService:_ageAssuranceService
                                                                               database:_database
                                                                              jwtMinter:jwtMinter];
    [xrpcPack registerRoutesWithServer:_httpServer];

    // Register admin routes
    _adminRoutePack = [[AppViewAdminRoutePack alloc]
        initWithOrchestrator:_orchestrator
                ingestEngine:_ingestEngine
                    database:_database
                 adminSecret:config.adminSecret];
    [_adminRoutePack registerRoutesWithServer:_httpServer];

    NSError *listenErr = nil;
    if (![_httpServer startWithError:&listenErr]) {
        PDS_LOG_WARN(@"[AppViewRuntime] HTTP server failed to start on port %lu: %@",
                     (unsigned long)config.httpPort, listenErr.localizedDescription);
        // Non-fatal: admin endpoints unavailable but ingest + backfill can still run
    } else {
        PDS_LOG_INFO(@"[AppViewRuntime] HTTP server listening on port %lu", (unsigned long)config.httpPort);
    }

    // Start all planes
    [_ingestEngine start];
    [_orchestrator start];

    _isRunning = YES;
    PDS_LOG_INFO(@"[AppViewRuntime] Started. Relays: %@", config.relayURLs);
    return YES;
}

// ---------------------------------------------------------------------------
// Stop
// ---------------------------------------------------------------------------

- (void)stop {
    if (!_isRunning) return;
    _isRunning = NO;

    [_ingestEngine stop];
    [_orchestrator stop];
    [_httpServer stop];
    [_database close];

    PDS_LOG_INFO(@"[AppViewRuntime] Stopped.");
}

// ---------------------------------------------------------------------------
// AppViewIngestEngineDelegate
// ---------------------------------------------------------------------------

- (void)ingestEngine:(AppViewIngestEngine *)engine
   didReceiveCommit:(AppViewIngestEvent *)event {
    // Notify orchestrator to ensure repo is scheduled for backfill if new
    [_orchestrator enqueueDIDs:@[event.did]];

    // Dispatch to all capable indexers
    for (id<AppViewIndexer> indexer in _indexers) {
        if ([indexer respondsToSelector:@selector(handleIngestEvent:error:)]) {
            [indexer handleIngestEvent:event error:nil];
        }
    }

    // Interaction expansion for partial mode
    if (_configuration.partialEnabled) {
        for (NSDictionary *op in event.ops) {
            NSString *collection = op[@"collection"];
            NSString *subject    = op[@"record"][@"subject"];
            if (subject && [_relevanceSet isDIDRelevant:event.did]) {
                [_relevanceSet recordInteraction:event.did withDID:subject];
            }
            (void)collection;
        }
    }
}

- (void)ingestEngine:(AppViewIngestEngine *)engine
didReceiveIdentityChange:(AppViewIngestEvent *)event {
    PDS_LOG_DEBUG(@"[AppViewRuntime] Identity change for %@", event.did);
    [_orchestrator enqueueDIDs:@[event.did]];
}

// ---------------------------------------------------------------------------
// AppViewBackfillOrchestratorDelegate
// ---------------------------------------------------------------------------

- (void)orchestrator:(AppViewBackfillOrchestrator *)orchestrator
didCompleteBackfillForDID:(NSString *)did {
    PDS_LOG_DEBUG(@"[AppViewRuntime] Backfill complete for %@", did);
}

- (void)orchestrator:(AppViewBackfillOrchestrator *)orchestrator
didFailBackfillForDID:(NSString *)did
               error:(NSError *)error {
    PDS_LOG_DEBUG(@"[AppViewRuntime] Backfill failed for %@: %@", did, error.localizedDescription);
}

@end
