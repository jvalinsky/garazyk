#import "AppView/Server/Admin/AppViewAdminRoutePack.h"
#import "AppView/Server/Backfill/AppViewBackfillOrchestrator.h"
#import "AppView/Server/Ingest/AppViewIngestEngine.h"
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/AppViewTypes.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"

@interface AppViewAdminRoutePack ()

@property (nonatomic, strong, nullable) AppViewBackfillOrchestrator *orchestrator;
@property (nonatomic, strong) AppViewIngestEngine *ingestEngine;
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, copy, nullable) NSString *adminSecret;

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

@end
