// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIDataExplorerPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (DataExplorerRoutes)

- (void)registerDataExplorerRoutes {
    __weak typeof(self) weakSelf = self;

    // Landing pane for shell dynamic tab /admin/partials/explorer
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/explorer" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:
         @"<section class=\"admin-section\">"
         @"<h3 class=\"section-title\">Describe Repository</h3>"
         @"<form class=\"d-flex gap-sm\" hx-get=\"/admin/partials/describe-repo\" hx-target=\"#explorer-describe\">"
         @"<label class=\"sr-only\" for=\"explorer-did\">DID or handle</label>"
         @"<input id=\"explorer-did\" class=\"form-input flex-1\" type=\"text\" name=\"did\" "
         @"placeholder=\"did:plc:... or handle\" spellcheck=\"false\" autocomplete=\"off\" required/>"
         @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Describe</button>"
         @"</form>"
         @"<div id=\"explorer-describe\" class=\"mt-sm text-secondary text-sm\">Enter a DID or handle.</div>"
         @"</section>"
         @"<section class=\"admin-section mt-lg\">"
         @"<h3 class=\"section-title\">List Records</h3>"
         @"<form class=\"d-flex gap-sm flex-wrap\" hx-get=\"/admin/partials/list-records\" hx-target=\"#explorer-records\">"
         @"<input class=\"form-input flex-1\" type=\"text\" name=\"did\" placeholder=\"did:plc:...\" "
         @"spellcheck=\"false\" autocomplete=\"off\" required/>"
         @"<input class=\"form-input flex-1\" type=\"text\" name=\"collection\" placeholder=\"collection (optional)\" "
         @"spellcheck=\"false\" autocomplete=\"off\"/>"
         @"<button type=\"submit\" class=\"btn btn-secondary btn-sm\">List</button>"
         @"</form>"
         @"<div id=\"explorer-records\" class=\"mt-sm\"></div>"
         @"</section>"];
    }];

    // Explorer: Describe repo
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/describe-repo" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient describeRepo:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIDataExplorerPack renderDescribeRepoPartial:result]];
    }];

    // Explorer: List records
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/list-records" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient listRecordsForDID:did collection:collection limit:25 cursor:cursor];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIDataExplorerPack renderListRecordsPartial:result]];
    }];

    // Explorer: Get record
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/get-record" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSString *collection = [request queryParamForKey:@"collection"] ?: @"";
        NSString *rkey = [request queryParamForKey:@"rkey"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient getRecordForDID:did collection:collection rkey:rkey];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIDataExplorerPack renderGetRecordPartial:result]];
    }];
}

@end
