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
