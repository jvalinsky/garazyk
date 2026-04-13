/*!
 @file AppViewRuntime.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/AppViewRuntime.h"

#import "AppViewServer/AppViewDatabase.h"
#import "AppViewServer/AppViewTypes.h"
#import "AppViewServer/Config/AppViewConfiguration.h"
#import "AppViewServer/Ingest/AppViewIngestEngine.h"
#import "AppViewServer/Backfill/AppViewBackfillOrchestrator.h"
#import "AppViewServer/Relevance/AppViewRelevanceSet.h"
#import "AppViewServer/Indexers/AppViewActorIndexer.h"
#import "AppViewServer/Indexers/AppViewFeedIndexer.h"
#import "AppViewServer/Indexers/AppViewGraphIndexer.h"
#import "AppViewServer/Indexers/AppViewNotificationIndexer.h"
#import "AppViewServer/Admin/AppViewAdminRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"

// ---------------------------------------------------------------------------

@interface AppViewRuntime () <AppViewIngestEngineDelegate,
                               AppViewBackfillOrchestratorDelegate>

@property (nonatomic, strong, readwrite) AppViewConfiguration *configuration;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong) AppViewBackfillOrchestrator *orchestrator;
@property (nonatomic, strong) AppViewRelevanceSet *relevanceSet;
@property (nonatomic, strong) NSArray<id<AppViewIndexer>> *indexers;
@property (nonatomic, strong) HttpServer *httpServer;
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
    _indexers = @[actorIdx, feedIdx, graphIdx, notifIdx];

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

    // Root health/info endpoint
    [_httpServer addRoute:@"GET" path:@"/" handler:^(HttpRequest *req, HttpResponse *res) {
        NSDictionary *info = @{
            @"service": @"syrena",
            @"version": @"1.0.0",
            @"type": @"app.bsky.appview",
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
        [res setHeader:@"application/json" forKey:@"Content-Type"];
        res.statusCode = 200;
        [res setBody:json];
    }];

    if (config.adminSecret.length > 0) {
        [AppViewAdminRoutePack registerWithServer:_httpServer
                                    orchestrator:_orchestrator
                                    relevanceSet:_relevanceSet
                                    ingestEngine:_ingestEngine
                                     adminSecret:config.adminSecret];
    }

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
