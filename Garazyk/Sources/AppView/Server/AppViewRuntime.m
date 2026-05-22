// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "AppView/Server/Indexers/AppViewGenericIndexer.h"
#import "AppView/Server/Lexicon/AppViewLexiconEndpointGenerator.h"
#import "AppView/Server/Lexicon/AppViewCustomQueryRegistry.h"
#import "AppView/Server/WriteProxy/AppViewWriteProxy.h"
#import "AppView/Services/FeedService.h"
#import "AppView/Services/ActorService.h"
#import "AppView/Services/GraphService.h"
#import "AppView/Services/NotificationService.h"
#import "AppView/Services/BookmarkService.h"
#import "AppView/Services/DraftService.h"
#import "AppView/Services/SearchIndexService.h"
#import "AppView/Server/Lexicon/AppViewGraphQueryHandler.h"
#import "AppView/Services/ContactService.h"
#import "AppView/Server/Hooks/AppViewIndexHookRegistry.h"
#import "AppView/Services/AgeAssuranceService.h"
#import "AppView/Services/VideoUriBuilder.h"
#import "Network/AppViewXRpcRoutePack.h"
#import "AppView/Server/Admin/AppViewAdminRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Debug/GZLogger.h"

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
@property (nonatomic, strong) DraftService *draftService;
@property (nonatomic, strong) SearchIndexService *searchIndexService;
@property (nonatomic, strong) ContactService *contactService;
@property (nonatomic, strong) AppViewWriteProxy *writeProxy;
@property (nonatomic, strong) AppViewLexiconEndpointGenerator *lexiconEndpointGenerator;
@property (nonatomic, strong) AppViewCustomQueryRegistry *customQueryRegistry;
@property (nonatomic, strong) ATProtoLexiconRegistry *lexiconRegistry;
@property (nonatomic, strong) ATProtoLexiconValidator *lexiconValidator;
@property (nonatomic, strong) AppViewIndexHookRegistry *hookRegistry;
@property (nonatomic, strong) AppViewVideoUriBuilder *videoUriBuilder;
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

    // Load lexicon schemas
    _lexiconRegistry = [ATProtoLexiconRegistry sharedRegistry];
    NSString *lexiconDataDir = [config.dataDirectory stringByAppendingPathComponent:@"lexicons"];
    NSArray<NSString *> *searchPaths = [_lexiconRegistry searchPathsForDirectory:lexiconDataDir];
    NSError *lexiconErr = nil;
    for (NSString *path in searchPaths) {
        [_lexiconRegistry loadLexiconsFromDirectory:path error:&lexiconErr];
        if (lexiconErr) {
            GZ_LOG_WARN(@"[AppViewRuntime] Lexicon load error from %@: %@",
                         path, lexiconErr.localizedDescription);
            lexiconErr = nil; // Continue loading from other paths
        }
    }
    GZ_LOG_INFO(@"[AppViewRuntime] Loaded %lu lexicon schemas",
                 (unsigned long)[_lexiconRegistry loadedNSIDs].count);

    // Build lexicon validator
    _lexiconValidator = [[ATProtoLexiconValidator alloc] initWithRegistry:_lexiconRegistry];

    // Build relevance set
    _relevanceSet = [[AppViewRelevanceSet alloc]
        initWithDatabase:_database
                seedDIDs:config.partialSeedDIDs
               allowlist:config.partialAllowlist
                ttlHours:config.partialTTLHours];
    [_relevanceSet rebuild];

    // Initialize services before indexers so domain indexers use the same
    // service instances as the HTTP query layer.
    _feedService = [[FeedService alloc] initWithDatabase:_database];
    _actorService = [[ActorService alloc] initWithDatabase:_database];
    _graphService = [[GraphService alloc] initWithDatabase:_database];
    _notificationService = [[NotificationService alloc] initWithDatabase:_database
                                                            actorService:_actorService];
    _ageAssuranceService = [[AgeAssuranceService alloc] initWithDatabase:_database
                                                           emailProvider:nil];
    _bookmarkService = [[BookmarkService alloc] initWithDatabase:_database];
    _draftService = [[DraftService alloc] initWithDatabase:_database];
    _searchIndexService = [[SearchIndexService alloc] initWithDatabase:_database];
    _contactService = [[ContactService alloc] initWithDatabase:_database actorService:_actorService];

    // Initialize video URI builder (for constructing HLS playlist/thumbnail URLs)
    if (config.videoServiceURL.length > 0) {
        _videoUriBuilder = [AppViewVideoUriBuilder builderWithVideoServiceURL:config.videoServiceURL];
        _feedService.videoUriBuilder = _videoUriBuilder;
    }

    // Build indexers
    AppViewActorIndexer *actorIdx   = [[AppViewActorIndexer alloc] initWithDatabase:_database];
    AppViewFeedIndexer  *feedIdx    = [[AppViewFeedIndexer alloc]  initWithDatabase:_database];
    AppViewGraphIndexer *graphIdx   = [[AppViewGraphIndexer alloc] initWithDatabase:_database
                                                                       relevanceSet:_relevanceSet
                                                                       graphService:_graphService];
    AppViewNotificationIndexer *notifIdx = [[AppViewNotificationIndexer alloc] initWithDatabase:_database];
    AppViewBookmarkIndexer *bookmarkIdx = [[AppViewBookmarkIndexer alloc] initWithDatabase:_database
                                                                  bookmarkService:_bookmarkService];
    AppViewGroupIndexer *groupIdx = [[AppViewGroupIndexer alloc] initWithDatabase:_database];

    // Build the set of collections claimed by domain-specific indexers
    // so the generic indexer knows what to skip
    NSSet *domainCollections = [NSSet setWithArray:@[
        @"app.bsky.actor.profile",
        @"app.bsky.feed.post",
        @"app.bsky.feed.repost",
        @"app.bsky.feed.like",
        @"app.bsky.feed.generator",
        @"app.bsky.feed.threadgate",
        @"app.bsky.feed.postgate",
        @"app.bsky.graph.follow",
        @"app.bsky.graph.block",
        @"app.bsky.graph.list",
        @"app.bsky.graph.listitem",
        @"app.bsky.graph.listblock",
        @"app.bsky.graph.starterpack",
        @"app.bsky.graph.verification",
        @"app.bsky.notification.declaration",
        @"app.bsky.bookmark.bookmark",
        @"chat.bsky.convo.message",
        @"chat.bsky.group.message",
    ]];

    AppViewGenericIndexer *genericIdx = [[AppViewGenericIndexer alloc]
        initWithRegistry:_lexiconRegistry
               database:_database
             validator:_lexiconValidator
   domainIndexerCollections:domainCollections];

    _indexers = @[actorIdx, feedIdx, graphIdx, notifIdx, bookmarkIdx, groupIdx, genericIdx];

    _hookRegistry = [[AppViewIndexHookRegistry alloc] initWithDatabase:_database];
    
    // Register SearchIndexService as an internal hook for real-time search updates
    [_hookRegistry registerHook:_searchIndexService];

    // Populate search index from existing records if needed
    [_searchIndexService populateIndexIfEmptyWithError:nil];

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
    [HttpResponse setDefaultServerHeader:@"garazyk-appview/1.0.0"];

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

    _writeProxy = [[AppViewWriteProxy alloc] initWithDatabase:_database plcUrl:config.plcURL];

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
                                                                    draftService:_draftService
                                                                 bookmarkService:_bookmarkService
                                                                  contactService:_contactService
                                                              searchIndexService:_searchIndexService
                                                                      writeProxy:_writeProxy
                                                                               database:_database
                                                                              jwtMinter:jwtMinter];
    [xrpcPack registerRoutesWithServer:_httpServer];

    // Register dynamic lexicon-driven endpoints
    _customQueryRegistry = [[AppViewCustomQueryRegistry alloc] init];

    // Register domain-specific query handlers
    AppViewGraphQueryHandler *graphQueryHandler =
        [[AppViewGraphQueryHandler alloc] initWithGraphService:_graphService];
    [_customQueryRegistry registerHandler:graphQueryHandler
                                  forNSID:@"app.bsky.graph.getStarterPack"];
    [_customQueryRegistry registerHandler:graphQueryHandler
                                  forNSID:@"app.bsky.graph.getStarterPacks"];
    [_customQueryRegistry registerHandler:graphQueryHandler
                                  forNSID:@"app.bsky.graph.getActorStarterPacks"];
    _lexiconEndpointGenerator = [[AppViewLexiconEndpointGenerator alloc]
        initWithRegistry:_lexiconRegistry
               database:_database
            httpServer:_httpServer
       customHandlers:_customQueryRegistry];
    NSError *lexiconRouteErr = nil;
    if (![_lexiconEndpointGenerator registerDynamicEndpointsWithError:&lexiconRouteErr]) {
        GZ_LOG_WARN(@"[AppViewRuntime] Lexicon endpoint registration failed: %@",
                     lexiconRouteErr.localizedDescription ?: @"unknown");
        // Non-fatal: dynamic endpoints unavailable but core routes still work
    }

    // Register admin routes
    _adminRoutePack = [[AppViewAdminRoutePack alloc]
        initWithOrchestrator:_orchestrator
                ingestEngine:_ingestEngine
                    database:_database
                 adminSecret:config.adminSecret];
    [_adminRoutePack setLexiconRegistry:_lexiconRegistry];
    [_adminRoutePack setHookRegistry:_hookRegistry];
    [_adminRoutePack setCustomQueryRegistry:_customQueryRegistry];
    [_adminRoutePack setLexiconEndpointGenerator:_lexiconEndpointGenerator];
    [_adminRoutePack registerRoutesWithServer:_httpServer];


    NSError *listenErr = nil;
    if (![_httpServer startWithError:&listenErr]) {
        NSString *message = listenErr.localizedDescription ?: @"HTTP server failed to start";
        GZ_LOG_WARN(@"[AppViewRuntime] HTTP server failed to start on port %lu: %@",
                     (unsigned long)config.httpPort, message);
        if (error) {
            *error = listenErr ?: [NSError errorWithDomain:@"AppViewRuntime"
                                                      code:2
                                                  userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        [_database close];
        _database = nil;
        _httpServer = nil;
        return NO;
    }
    GZ_LOG_INFO(@"[AppViewRuntime] HTTP server listening on port %lu", (unsigned long)config.httpPort);

    // Start all planes
    [_ingestEngine start];
    [_orchestrator start];

    _isRunning = YES;
    GZ_LOG_INFO(@"[AppViewRuntime] Started. Relays: %@", config.relayURLs);
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

    GZ_LOG_INFO(@"[AppViewRuntime] Stopped.");
}

// ---------------------------------------------------------------------------
// AppViewIngestEngineDelegate
// ---------------------------------------------------------------------------

- (void)ingestEngine:(AppViewIngestEngine *)engine
   didReceiveCommit:(AppViewIngestEvent *)event {
    // Notify orchestrator to ensure repo is scheduled for backfill if new
    [_orchestrator enqueueDIDs:@[event.did]];

    // Single pass over ops: dispatch to indexers, fire hooks, expand partial mode
    for (NSDictionary *op in event.ops) {
        NSString *action = op[@"action"];
        NSString *path   = op[@"path"];

        // Parse collection and rkey from path (format: "collection/rkey")
        NSRange slash = [path rangeOfString:@"/"];
        NSString *collection = (slash.location != NSNotFound)
            ? [path substringToIndex:slash.location] : path;
        NSString *rkey = (slash.location != NSNotFound)
            ? [path substringFromIndex:slash.location + 1] : @"";
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@",
                         event.did, collection, rkey];

        // --- 1. Dispatch to indexers ---
        for (id<AppViewIndexer> indexer in _indexers) {
            if ([indexer respondsToSelector:@selector(handleIngestEvent:error:)]) {
                // Indexers that handle the full event themselves (called once per event)
                // Only call on the first op to avoid duplicate dispatch
                // These indexers iterate over ops internally
                continue;
            }
            if (![indexer canIndexCollection:collection]) continue;

            if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
                NSDictionary *record = op[@"record"];
                NSString *cid = op[@"cid"];
                if (record) {
                    [indexer indexRecord:record
                                     did:event.did
                              collection:collection
                                    rkey:rkey
                                     cid:cid
                                   error:nil];
                }
            } else if ([action isEqualToString:@"delete"]) {
                if ([indexer respondsToSelector:@selector(deleteRecord:did:collection:error:)]) {
                    [indexer deleteRecord:rkey
                                      did:event.did
                               collection:collection
                                    error:nil];
                }
            }
        }

        // --- 2. Fire index hooks ---
        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            [_hookRegistry fireDidIndexRecord:op[@"record"]
                                          uri:uri
                                           did:event.did
                                   collection:collection];
        } else if ([action isEqualToString:@"delete"]) {
            [_hookRegistry fireDidDeleteRecordWithURI:uri
                                                   did:event.did
                                           collection:collection];
        }

        // --- 3. Interaction expansion for partial mode ---
        if (_configuration.partialEnabled) {
            NSDictionary *record = op[@"record"];
            if ([record isKindOfClass:[NSDictionary class]]) {
                NSString *subject = record[@"subject"];
                if (subject && [_relevanceSet isDIDRelevant:event.did]) {
                    [_relevanceSet recordInteraction:event.did withDID:subject];
                }
            }
        }
    }

    // Indexers that handle the full event themselves (called once per event)
    for (id<AppViewIndexer> indexer in _indexers) {
        if ([indexer respondsToSelector:@selector(handleIngestEvent:error:)]) {
            [indexer handleIngestEvent:event error:nil];
        }
    }
}

- (void)ingestEngine:(AppViewIngestEngine *)engine
didReceiveIdentityChange:(AppViewIngestEvent *)event {
    GZ_LOG_DEBUG(@"[AppViewRuntime] Identity change for %@", event.did);
    [_orchestrator enqueueDIDs:@[event.did]];
}

// ---------------------------------------------------------------------------
// AppViewBackfillOrchestratorDelegate
// ---------------------------------------------------------------------------

- (void)orchestrator:(AppViewBackfillOrchestrator *)orchestrator
didCompleteBackfillForDID:(NSString *)did {
    GZ_LOG_DEBUG(@"[AppViewRuntime] Backfill complete for %@", did);
}

- (void)orchestrator:(AppViewBackfillOrchestrator *)orchestrator
didFailBackfillForDID:(NSString *)did
               error:(NSError *)error {
    GZ_LOG_DEBUG(@"[AppViewRuntime] Backfill failed for %@: %@", did, error.localizedDescription);
}

@end
