/*!
 @file AppViewAdminRoutePack.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppViewServer/Admin/AppViewAdminRoutePack.h"

#import "AppViewServer/Backfill/AppViewBackfillOrchestrator.h"
#import "AppViewServer/Relevance/AppViewRelevanceSet.h"
#import "AppViewServer/Ingest/AppViewIngestEngine.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/PDSLogger.h"

@implementation AppViewAdminRoutePack

+ (void)registerWithServer:(HttpServer *)server
              orchestrator:(AppViewBackfillOrchestrator *)orchestrator
              relevanceSet:(AppViewRelevanceSet *)relevanceSet
              ingestEngine:(AppViewIngestEngine *)ingestEngine
               adminSecret:(NSString *)adminSecret {

    // -----------------------------------------------------------------
    // GET /admin/backfill/status
    // -----------------------------------------------------------------
    [server addRoute:@"GET"
                path:@"/admin/backfill/status"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSDictionary *status = [orchestrator statusReport];
                 NSDictionary *lag    = ingestEngine.lagByRelay;

                 NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:status];
                 body[@"ingest_lag_by_relay"] = lag ?: @{};

                 response.statusCode = 200;
                 [response setJsonBody:[body copy]];
             }];

    // -----------------------------------------------------------------
    // POST /admin/backfill/repos
    // Body: { "dids": ["did:plc:xxx", ...] }
    // -----------------------------------------------------------------
    [server addRoute:@"POST"
                path:@"/admin/backfill/repos"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSError *jsonErr = nil;
                 NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.body ?: [NSData data]
                                                                      options:0
                                                                        error:&jsonErr];
                 if (jsonErr || !body) {
                     response.statusCode = 400;
                     [response setJsonBody:@{@"error": @"Invalid JSON body"}];
                     return;
                 }

                 NSArray<NSString *> *dids = body[@"dids"];
                 if (![dids isKindOfClass:[NSArray class]] || dids.count == 0) {
                     response.statusCode = 400;
                     [response setJsonBody:@{@"error": @"'dids' array required"}];
                     return;
                 }

                 // Validate DID format loosely
                 NSMutableArray<NSString *> *validDIDs = [NSMutableArray array];
                 for (id did in dids) {
                     if ([did isKindOfClass:[NSString class]] &&
                         ([did hasPrefix:@"did:plc:"] || [did hasPrefix:@"did:web:"])) {
                         [validDIDs addObject:did];
                     }
                 }

                 [orchestrator enqueueDIDs:validDIDs];
                 PDS_LOG_INFO(@"[AppView Admin] Enqueued %lu DIDs for backfill via admin API",
                              (unsigned long)validDIDs.count);

                 response.statusCode = 202;
                 [response setJsonBody:@{
                     @"enqueued": @(validDIDs.count),
                     @"skipped":  @(dids.count - validDIDs.count),
                 }];
             }];

    // -----------------------------------------------------------------
    // POST /admin/backfill/scope/rebuild
    // Recomputes the relevance set from seeds + allowlist
    // -----------------------------------------------------------------
    [server addRoute:@"POST"
                path:@"/admin/backfill/scope/rebuild"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 [relevanceSet rebuild];
                 NSArray<NSString *> *allDIDs = [relevanceSet allRelevantDIDs];

                 PDS_LOG_INFO(@"[AppView Admin] Relevance set rebuilt, %lu DIDs in scope.",
                              (unsigned long)allDIDs.count);

                 response.statusCode = 200;
                 [response setJsonBody:@{@"relevance_set_size": @(allDIDs.count)}];
             }];

    // -----------------------------------------------------------------
    // GET /admin/backfill/queue
    // Returns paginated queue entries for table display
    // -----------------------------------------------------------------
    [server addRoute:@"GET"
                path:@"/admin/backfill/queue"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSInteger limit = 50;
                 NSString *limitStr = request.queryParams[@"limit"];
                 if (limitStr) limit = [limitStr integerValue] ?: 50;

                 NSString *cursor = request.queryParams[@"cursor"];
                 NSString *status = request.queryParams[@"status"];

                 NSDictionary *queueResult = [orchestrator queueWithLimit:limit cursor:cursor status:status];

                 response.statusCode = 200;
                 [response setJsonBody:queueResult];
             }];

    // -----------------------------------------------------------------
    // GET /admin/backfill/repos/{did}
    // Returns detail for a specific repo
    // -----------------------------------------------------------------
    [server addRoute:@"GET"
                path:@"/admin/backfill/repos/*"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSString *path = request.path;
                 NSString *did = nil;
                 if ([path hasPrefix:@"/admin/backfill/repos/"]) {
                     did = [path substringFromIndex:@"/admin/backfill/repos/".length];
                 }

                 if (!did || did.length == 0) {
                     response.statusCode = 400;
                     [response setJsonBody:@{@"error": @"DID required"}];
                     return;
                 }

                 NSDictionary *detail = [orchestrator repoDetail:did];

                 response.statusCode = 200;
                 [response setJsonBody:detail ?: @{}];
             }];

    // -----------------------------------------------------------------
    // POST /admin/backfill/repos/{did}/retry
    // Retry a specific failed repo
    // -----------------------------------------------------------------
    [server addRoute:@"POST"
                path:@"/admin/backfill/repos/*/retry"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSString *path = request.path;
                 NSString *did = nil;
                 if ([path hasPrefix:@"/admin/backfill/repos/"]) {
                     NSRange slashRange = [path rangeOfString:@"/retry"];
                     if (slashRange.location != NSNotFound) {
                         NSString *afterRepos = [path substringFromIndex:@"/admin/backfill/repos/".length];
                         did = [afterRepos substringToIndex:slashRange.location - @"/admin/backfill/repos/".length];
                     }
                 }

                 if (!did || did.length == 0) {
                     response.statusCode = 400;
                     [response setJsonBody:@{@"error": @"DID required"}];
                     return;
                 }

                 BOOL success = [orchestrator retryRepo:did];

                 response.statusCode = success ? 200 : 404;
                 [response setJsonBody:@{@"success": @(success), @"did": did}];
             }];

    // -----------------------------------------------------------------
    // POST /admin/backfill/repos/{did}/cancel
    // Cancel a specific repo backfill
    // -----------------------------------------------------------------
    [server addRoute:@"POST"
                path:@"/admin/backfill/repos/*/cancel"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSString *path = request.path;
                 NSString *did = nil;
                 if ([path hasPrefix:@"/admin/backfill/repos/"]) {
                     NSRange slashRange = [path rangeOfString:@"/cancel"];
                     if (slashRange.location != NSNotFound) {
                         NSString *afterRepos = [path substringFromIndex:@"/admin/backfill/repos/".length];
                         did = [afterRepos substringToIndex:slashRange.location - @"/admin/backfill/repos/".length];
                     }
                 }

                 if (!did || did.length == 0) {
                     response.statusCode = 400;
                     [response setJsonBody:@{@"error": @"DID required"}];
                     return;
                 }

                 BOOL success = [orchestrator cancelRepo:did];

                 response.statusCode = success ? 200 : 404;
                 [response setJsonBody:@{@"success": @(success), @"did": did}];
             }];

    // -----------------------------------------------------------------
    // GET /admin/ingest/health
    // Returns relay connectivity and lag info
    // -----------------------------------------------------------------
    [server addRoute:@"GET"
                path:@"/admin/ingest/health"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 NSDictionary *health = @{
                     @"relays": ingestEngine.relayHealth ?: @{},
                     @"lag_by_relay": ingestEngine.lagByRelay ?: @{},
                     @"throughput": ingestEngine.throughput ?: @{},
                 };

                 response.statusCode = 200;
                 [response setJsonBody:health];
             }];

    // -----------------------------------------------------------------
    // GET /admin/capabilities
    // Returns feature flags for UI gating
    // -----------------------------------------------------------------
    [server addRoute:@"GET"
                path:@"/admin/capabilities"
             handler:^(HttpRequest *request, HttpResponse *response) {
                 if (![self _validateAdminToken:request secret:adminSecret response:response]) return;

                 response.statusCode = 200;
                 [response setJsonBody:@{
                     @"success": @YES,
                     @"capabilities": @{
                         @"queue_view": @YES,
                         @"retry_repo": @YES,
                         @"cancel_repo": @YES,
                         @"rebuild_scope": @YES,
                         @"ingest_health": @YES,
                     },
                     @"version": @"1.0.0"
                 }];
             }];
}

// ---------------------------------------------------------------------------
// Auth helper
// ---------------------------------------------------------------------------

+ (BOOL)_validateAdminToken:(HttpRequest *)request
                     secret:(NSString *)secret
                   response:(HttpResponse *)response {
    NSString *authHeader = request.headers[@"Authorization"]
                        ?: request.headers[@"authorization"];
    NSString *expected = [NSString stringWithFormat:@"Bearer %@", secret];

    if (![authHeader isEqualToString:expected]) {
        response.statusCode = 401;
        [response setJsonBody:@{@"error": @"Unauthorized"}];
        return NO;
    }
    return YES;
}

@end
