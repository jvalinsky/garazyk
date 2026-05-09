#import "AppView/Server/Admin/AppViewAdminRoutePack.h"
#import "AppView/Server/Backfill/AppViewBackfillOrchestrator.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "AppView/Server/Lexicon/AppViewLexiconEndpointGenerator.h"
#import "AppView/Server/Lexicon/AppViewCustomQueryRegistry.h"
#import "AppView/Server/Hooks/AppViewIndexHookRegistry.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"

@interface AppViewAdminRoutePack ()

@property (nonatomic, strong, nullable) AppViewBackfillOrchestrator *orchestrator;
@property (nonatomic, strong) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, copy, nullable) NSString *adminSecret;
@property (nonatomic, strong, nullable) ATProtoLexiconRegistry *lexiconRegistry;
@property (nonatomic, strong, nullable) AppViewIndexHookRegistry *hookRegistry;
@property (nonatomic, strong, nullable) AppViewCustomQueryRegistry *customQueryRegistry;
@property (nonatomic, strong, nullable) AppViewLexiconEndpointGenerator *lexiconEndpointGenerator;

@end

@implementation AppViewAdminRoutePack

- (instancetype)initWithOrchestrator:(nullable AppViewBackfillOrchestrator *)orchestrator
                        ingestEngine:(AppViewIngestEngine *)ingestEngine
                            database:(AppViewDatabase *)database
                         adminSecret:(nullable NSString *)adminSecret {
    self = [super init];
    if (self) {
        _orchestrator = orchestrator;
        _ingestEngine = ingestEngine;
        _database = database;
        _adminSecret = adminSecret;
    }
    return self;
}

#pragma mark - Route Registration

- (void)registerRoutesWithServer:(HttpServer *)server {
    __weak typeof(self) weakSelf = self;

    // GET /admin/backfill/status
    [server addRoute:@"GET"
                path:@"/admin/backfill/status"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleBackfillStatus:response];
             }];

    // GET /admin/backfill/queue
    [server addRoute:@"GET"
                path:@"/admin/backfill/queue"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleBackfillQueue:request response:response];
             }];

    // POST /admin/backfill/repos
    [server addRoute:@"POST"
                path:@"/admin/backfill/repos"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleBackfillEnqueue:request response:response];
             }];

    // POST /admin/backfill/repos/:did/retry
    [server addRoute:@"POST"
                path:@"/admin/backfill/repos/:did/retry"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleBackfillRetry:request response:response];
             }];

    // POST /admin/backfill/repos/:did/cancel
    [server addRoute:@"POST"
                path:@"/admin/backfill/repos/:did/cancel"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleBackfillCancel:request response:response];
             }];

    // POST /admin/backfill/scope/rebuild
    [server addRoute:@"POST"
                path:@"/admin/backfill/scope/rebuild"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleBackfillRebuild:response];
             }];

    // GET /admin/ingest/health
    [server addRoute:@"GET"
                path:@"/admin/ingest/health"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleIngestHealth:response];
             }];

    // GET /admin/appview/metrics/stats
    [server addRoute:@"GET"
                path:@"/admin/appview/metrics/stats"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleMetricsStats:response];
             }];

    // --- Lexicon Admin ---

    // GET /admin/lexicons
    [server addRoute:@"GET"
                path:@"/admin/lexicons"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleLexiconList:response];
             }];

    // GET /admin/lexicons/collections
    [server addRoute:@"GET"
                path:@"/admin/lexicons/collections"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleIndexedCollections:response];
             }];

    // --- Hooks Admin ---

    // GET /admin/hooks
    [server addRoute:@"GET"
                path:@"/admin/hooks"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleHookList:response];
             }];

    // GET /admin/hooks/dead-letter
    [server addRoute:@"GET"
                path:@"/admin/hooks/dead-letter"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleDeadLetterHooks:request response:response];
             }];

    // --- Records Admin ---

    // GET /admin/records
    [server addRoute:@"GET"
                path:@"/admin/records"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleRecordBrowse:request response:response];
             }];

    // --- Custom Handlers Admin ---

    // GET /admin/handlers
    [server addRoute:@"GET"
                path:@"/admin/handlers"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleCustomHandlerList:response];
             }];

    // GET /admin/endpoints
    [server addRoute:@"GET"
                path:@"/admin/endpoints"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 AppViewAdminRoutePack *strongSelf = weakSelf;
                 if (!strongSelf) return;
                 if (![strongSelf validateAuth:request response:response]) return;
                 [strongSelf handleEndpointList:response];
             }];
}

#pragma mark - Auth

- (BOOL)validateAuth:(HttpRequest *)request response:(HttpResponse *)response {
    // If no admin secret is configured, allow all access
    if (!self.adminSecret || self.adminSecret.length == 0) {
        return YES;
    }

    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        response.statusCode = 401;
        [response setJsonBody:@{@"error": @"AuthenticationRequired", @"message": @"Admin secret required"}];
        return NO;
    }

    NSString *token = authHeader;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:@"Bearer ".length];
    }

    if (![token isEqualToString:self.adminSecret]) {
        response.statusCode = 401;
        [response setJsonBody:@{@"error": @"AuthenticationRequired", @"message": @"Invalid admin secret"}];
        return NO;
    }

    return YES;
}

#pragma mark - Handlers

- (void)handleBackfillStatus:(HttpResponse *)response {
    if (!self.orchestrator) {
        response.statusCode = 200;
        [response setJsonBody:@{@"enabled": @(NO)}];
        return;
    }
    NSDictionary *report = [self.orchestrator statusReport];
    response.statusCode = 200;
    [response setJsonBody:report ?: @{}];
}

- (void)handleBackfillQueue:(HttpRequest *)request response:(HttpResponse *)response {
    if (!self.orchestrator) {
        response.statusCode = 200;
        [response setJsonBody:@{@"entries": @[], @"total": @(0)}];
        return;
    }

    NSString *limitStr = [request queryParamForKey:@"limit"] ?: @"25";
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *status = [request queryParamForKey:@"status"];
    NSInteger limit = [limitStr integerValue];
    if (limit <= 0) limit = 25;
    if (limit > 100) limit = 100;

    NSDictionary *result = [self.orchestrator queueWithLimit:limit
                                                      cursor:cursor
                                                      status:status];
    response.statusCode = 200;
    [response setJsonBody:result ?: @{@"entries": @[], @"total": @(0)}];
}

- (void)handleBackfillEnqueue:(HttpRequest *)request response:(HttpResponse *)response {
    if (!self.orchestrator) {
        response.statusCode = 503;
        [response setJsonBody:@{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"}];
        return;
    }

    NSData *bodyData = request.body;
    if (!bodyData) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"BadRequest", @"message": @"Request body required"}];
        return;
    }

    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:nil];
    if (!body || ![body[@"dids"] isKindOfClass:[NSArray class]]) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"BadRequest", @"message": @"Body must contain \"dids\" array"}];
        return;
    }

    NSArray<NSString *> *dids = body[@"dids"];
    [self.orchestrator enqueueDIDs:dids];

    response.statusCode = 200;
    [response setJsonBody:@{@"success": @(YES), @"enqueued": @(dids.count)}];
}

- (void)handleBackfillRetry:(HttpRequest *)request response:(HttpResponse *)response {
    if (!self.orchestrator) {
        response.statusCode = 503;
        [response setJsonBody:@{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"}];
        return;
    }

    NSString *did = request.pathParameters[@"did"];
    if (!did || did.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"BadRequest", @"message": @"DID required in path"}];
        return;
    }

    BOOL success = [self.orchestrator retryRepo:did];
    if (success) {
        response.statusCode = 200;
        [response setJsonBody:@{@"success": @(YES), @"did": did}];
    } else {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound", @"message": @"Repo not found in queue"}];
    }
}

- (void)handleBackfillCancel:(HttpRequest *)request response:(HttpResponse *)response {
    if (!self.orchestrator) {
        response.statusCode = 503;
        [response setJsonBody:@{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"}];
        return;
    }

    NSString *did = request.pathParameters[@"did"];
    if (!did || did.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"BadRequest", @"message": @"DID required in path"}];
        return;
    }

    BOOL success = [self.orchestrator cancelRepo:did];
    if (success) {
        response.statusCode = 200;
        [response setJsonBody:@{@"success": @(YES), @"did": did}];
    } else {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"NotFound", @"message": @"Repo not found in queue"}];
    }
}

- (void)handleBackfillRebuild:(HttpResponse *)response {
    if (!self.orchestrator) {
        response.statusCode = 503;
        [response setJsonBody:@{@"error": @"BackfillDisabled", @"message": @"Backfill orchestrator is not running"}];
        return;
    }

    // Re-enqueue all dirty/pending repos
    [self.orchestrator start];

    response.statusCode = 200;
    [response setJsonBody:@{@"success": @(YES), @"message": @"Backfill scope rebuild triggered"}];
}

- (void)handleIngestHealth:(HttpResponse *)response {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"running"] = @(self.ingestEngine.isRunning);
    result[@"relayHealth"] = self.ingestEngine.relayHealth ?: @{};
    result[@"lagByRelay"] = self.ingestEngine.lagByRelay ?: @{};
    result[@"throughput"] = self.ingestEngine.throughput ?: @{};
    response.statusCode = 200;
    [response setJsonBody:[result copy]];
}

- (void)handleMetricsStats:(HttpResponse *)response {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    // Repo sync state counts
    NSInteger pending = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusPending error:nil];
    NSInteger processing = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusProcessing error:nil];
    NSInteger synced = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusSynced error:nil];
    NSInteger dirty = [self.database countRepoSyncStatesWithStatus:AppViewRepoSyncStatusDirty error:nil];

    result[@"repos"] = @{
        @"pending": @(pending),
        @"processing": @(processing),
        @"synced": @(synced),
        @"dirty": @(dirty),
        @"total": @(pending + processing + synced + dirty)
    };

    if (self.orchestrator) {
        result[@"queue_depth"] = @(self.orchestrator.queueDepth);
        result[@"active_workers"] = @(self.orchestrator.activeWorkers);
    }

    response.statusCode = 200;
    [response setJsonBody:[result copy]];
}

#pragma mark - Setters

- (void)setLexiconRegistry:(nullable ATProtoLexiconRegistry *)registry {
    _lexiconRegistry = registry;
}

- (void)setHookRegistry:(nullable AppViewIndexHookRegistry *)hookRegistry {
    _hookRegistry = hookRegistry;
}

- (void)setCustomQueryRegistry:(nullable AppViewCustomQueryRegistry *)customQueryRegistry {
    _customQueryRegistry = customQueryRegistry;
}

- (void)setLexiconEndpointGenerator:(nullable AppViewLexiconEndpointGenerator *)generator {
    _lexiconEndpointGenerator = generator;
}

#pragma mark - Lexicon Admin Handlers

- (void)handleLexiconList:(HttpResponse *)response {
    if (!self.lexiconRegistry) {
        response.statusCode = 200;
        [response setJsonBody:@{@"nsids": @[], @"count": @(0)}];
        return;
    }

    NSArray<NSString *> *nsids = [self.lexiconRegistry loadedNSIDs];
    response.statusCode = 200;
    [response setJsonBody:@{
        @"nsids": nsids ?: @[],
        @"count": @(nsids.count)
    }];
}

- (void)handleIndexedCollections:(HttpResponse *)response {
    NSError *error = nil;
    NSArray<NSString *> *collections = [self.database indexedCollectionsWithError:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"InternalError",
                                @"message": error.localizedDescription ?: @"unknown"}];
        return;
    }

    NSMutableArray *result = [NSMutableArray array];
    for (NSString *collection in collections) {
        NSInteger count = [self.database recordCountForCollection:collection error:nil];
        [result addObject:@{
            @"collection": collection,
            @"count": @(count)
        }];
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"collections": result}];
}

#pragma mark - Hooks Admin Handlers

- (void)handleHookList:(HttpResponse *)response {
    if (!self.hookRegistry) {
        response.statusCode = 200;
        [response setJsonBody:@{@"hooks": @[], @"count": @(0)}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{
        @"count": @([self.hookRegistry registeredHookCount])
    }];
}

- (void)handleDeadLetterHooks:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *limitStr = [request queryParamForKey:@"limit"] ?: @"25";
    NSInteger limit = [limitStr integerValue];
    if (limit <= 0) limit = 25;
    if (limit > 100) limit = 100;

    NSString *sql = @"SELECT id, hook_id, uri, did, collection, event_type, error_message, created_at "
                     @"FROM dead_letter_hooks ORDER BY created_at DESC LIMIT ?";
    NSError *error = nil;
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[@(limit)] error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"InternalError",
                                @"message": error.localizedDescription ?: @"unknown"}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:@{@"entries": rows ?: @[]}];
}

#pragma mark - Records Admin Handlers

- (void)handleRecordBrowse:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *did = [request queryParamForKey:@"did"];
    NSString *limitStr = [request queryParamForKey:@"limit"] ?: @"25";
    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSInteger limit = [limitStr integerValue];
    if (limit <= 0) limit = 25;
    if (limit > 100) limit = 100;

    if (!collection || collection.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"BadRequest",
                                @"message": @"collection parameter required"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *result = [self.database listRecordsForCollection:collection
                                                              did:did
                                                            limit:limit
                                                           cursor:cursor
                                                            error:&error];
    if (error) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"InternalError",
                                @"message": error.localizedDescription ?: @"unknown"}];
        return;
    }

    response.statusCode = 200;
    [response setJsonBody:result ?: @{ @"records": @[] }];
}

#pragma mark - Custom Handlers Admin Handlers

- (void)handleCustomHandlerList:(HttpResponse *)response {
    if (!self.customQueryRegistry) {
        response.statusCode = 200;
        [response setJsonBody:@{@"handlers": @[], @"count": @(0)}];
        return;
    }

    NSArray<NSString *> *nsids = [self.customQueryRegistry registeredNSIDs];
    response.statusCode = 200;
    [response setJsonBody:@{
        @"nsids": nsids ?: @[],
        @"count": @(nsids.count)
    }];
}

- (void)handleEndpointList:(HttpResponse *)response {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    if (self.lexiconEndpointGenerator) {
        result[@"dynamic_endpoint_count"] = @([self.lexiconEndpointGenerator registeredEndpointCount]);
    } else {
        result[@"dynamic_endpoint_count"] = @(0);
    }

    if (self.customQueryRegistry) {
        result[@"custom_handler_count"] = @([self.customQueryRegistry registeredNSIDs].count);
    } else {
        result[@"custom_handler_count"] = @(0);
    }

    response.statusCode = 200;
    [response setJsonBody:[result copy]];
}

@end
