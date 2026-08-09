// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIAppViewPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (AppViewRoutes)

- (void)registerAppViewRoutes {
    __weak typeof(self) weakSelf = self;

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-metrics" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchAppViewMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIAppViewPack renderAppViewMetricsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-ingest" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchIngestHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIAppViewPack renderIngestHealthPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/appview-queue" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *status = [request queryParamForKey:@"status"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchBackfillQueueWithStatus:status limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIAppViewPack renderBackfillQueuePartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-retry-repo" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient retryBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Retry enqueued.";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-success\">%@</div>", GZAdminUIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-cancel-repo" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient cancelBackfillForDID:did ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? result[@"message"] : @"Cancel requested.";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-success\">%@</div>", GZAdminUIEscaped(msg)]];
    }];

    // AppView: Rebuild backfill scope
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-rebuild-scope" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient rebuildBackfillScope];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Rebuilding backfill scope.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];

    // AppView: Enqueue DIDs for backfill
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/appview-enqueue-dids" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = [request.jsonBody[@"dids"] isKindOfClass:[NSArray class]] ? request.jsonBody[@"dids"] : @[];
        NSDictionary *result = [weakSelf.backendClient enqueueBackfillDIDs:dids];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : [NSString stringWithFormat:@"Enqueued %lu DIDs.", dids.count];
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];
}

@end
