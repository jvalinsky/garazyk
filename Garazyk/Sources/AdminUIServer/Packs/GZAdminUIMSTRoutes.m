// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIMSTPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (MSTRoutes)

- (void)registerMSTRoutes {
    __weak typeof(self) weakSelf = self;

    // Landing pane for shell dynamic tab /admin/partials/mst
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:
         @"<section class=\"admin-section\">"
         @"<h3 class=\"section-title\">Accounts</h3>"
         @"<div id=\"mst-accounts\" hx-get=\"/admin/partials/mst-accounts\" hx-trigger=\"load once\"></div>"
         @"</section>"
         @"<section class=\"admin-section mt-lg\">"
         @"<h3 class=\"section-title\">Inspect Tree</h3>"
         @"<form class=\"d-flex gap-sm\" hx-get=\"/admin/partials/mst-tree\" hx-target=\"#mst-tree\">"
         @"<label class=\"sr-only\" for=\"mst-did\">DID</label>"
         @"<input id=\"mst-did\" class=\"form-input flex-1\" type=\"text\" name=\"did\" placeholder=\"did:plc:...\" required/>"
         @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Load tree</button>"
         @"</form>"
         @"<div id=\"mst-tree\" class=\"mt-sm text-secondary text-sm\">Enter a DID to inspect its MST.</div>"
         @"</section>"];
    }];

    // MST Viewer: Accounts list
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-accounts" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchMSTAccounts];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIMSTPack renderMSTAccountsPartial:result]];
    }];

    // MST Viewer: Tree for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-tree" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTTreeForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIMSTPack renderMSTTreePartial:result]];
    }];

    // MST Viewer: Stats for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-stats" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTStatsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIMSTPack renderMSTStatsPartial:result]];
    }];

    // MST Viewer: Export
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/mst-export" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSString *format = [request queryParamForKey:@"format"] ?: @"json";
        NSData *data = [weakSelf.backendClient fetchMSTExportForDID:did format:format];
        if (data) {
            response.statusCode = 200;
            if ([format isEqualToString:@"dot"]) {
                response.contentType = @"text/vnd.graphviz; charset=utf-8";
            } else if ([format isEqualToString:@"svg"]) {
                response.contentType = @"image/svg+xml";
            } else {
                response.contentType = @"application/json";
            }
            [response setBodyData:data];
        } else {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"Export failed"}];
        }
    }];
}

@end
