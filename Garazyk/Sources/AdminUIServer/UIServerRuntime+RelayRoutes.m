// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation UIServerRuntime (RelayRoutes)

- (void)registerRelayRoutes {
    __weak typeof(self) weakSelf = self;

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-metrics" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchRelayMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayMetricsPartial:result]];
    }];

    // Relay: Upstreams
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-upstreams" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchRelayUpstreams];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayUpstreamsPartial:result]];
    }];

    // Relay: Health check
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/relay-health" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchRelayHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderRelayHealthPartial:result]];
    }];

    // Relay: Request crawl action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/request-crawl" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *hostname = request.jsonBody[@"hostname"] ?: [request queryParamForKey:@"hostname"];
        NSDictionary *result = [weakSelf.backendClient requestCrawlForHostname:hostname ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Crawl requested.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];
}

@end
