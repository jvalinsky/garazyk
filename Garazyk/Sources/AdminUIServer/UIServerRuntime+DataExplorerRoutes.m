// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation UIServerRuntime (DataExplorerRoutes)

- (void)registerDataExplorerRoutes {
    __weak typeof(self) weakSelf = self;

    // Explorer: Describe repo
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/describe-repo" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient describeRepo:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderDescribeRepoPartial:result]];
    }];

    // Explorer: List records
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/list-records" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient listRecordsForDID:did collection:collection limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderListRecordsPartial:result]];
    }];

    // Explorer: Get record
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/get-record" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"] ?: @"";
        NSString *rkey = [request queryParamForKey:@"rkey"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient getRecordForDID:did collection:collection rkey:rkey];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderGetRecordPartial:result]];
    }];
}

@end
