// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation UIServerRuntime (MSTRoutes)

- (void)registerMSTRoutes {
    __weak typeof(self) weakSelf = self;

    // MST Viewer: Accounts list
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-accounts" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchMSTAccounts];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTAccountsPartial:result]];
    }];

    // MST Viewer: Tree for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-tree" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTTreeForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTTreePartial:result]];
    }];

    // MST Viewer: Stats for DID
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/mst-stats" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchMSTStatsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderMSTStatsPartial:result]];
    }];

    // MST Viewer: Export
    [self.httpServer addRoute:@"GET" path:@"/admin/actions/mst-export" handler:^(HttpRequest *request, HttpResponse *response) {
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
