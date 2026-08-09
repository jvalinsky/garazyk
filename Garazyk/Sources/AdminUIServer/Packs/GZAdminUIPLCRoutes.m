// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIPLCPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (PLCRoutes)

- (void)registerPLCRoutes {
    __weak typeof(self) weakSelf = self;

    // PLC: DID lookup
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-did" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient lookupDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPLCPack renderPLCDIDPartial:result]];
    }];

    // PLC: DID log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-log" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchPLCLogForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPLCPack renderPLCLogPartial:result]];
    }];

    // PLC: Health check
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-health" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchPLCHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPLCPack renderPLCHealthPartial:result]];
    }];

    // PLC: Metrics
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-metrics" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchPLCMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPLCPack renderPLCMetricsPartial:result]];
    }];

    // PLC: List DIDs
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/plc-list" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchPLCList];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPLCPack renderPLCListPartial:result cursor:cursor]];
    }];

    // PLC: Export action
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/plc-export" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *after = [request queryParamForKey:@"after"];
        NSString *countStr = [request queryParamForKey:@"count"] ?: @"1000";
        NSUInteger count = [countStr integerValue] ?: 1000;
        NSDictionary *result = [weakSelf.backendClient fetchPLCExportWithAfter:after count:count];
        if (result[@"error"]) {
            response.statusCode = 400;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])]];
        } else {
            response.statusCode = 200;
            response.contentType = @"text/plain; charset=utf-8";
            [response setBodyString:result[@"text"] ?: @""];
        }
    }];
}

@end
