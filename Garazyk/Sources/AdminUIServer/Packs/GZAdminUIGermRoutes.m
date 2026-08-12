// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIGermPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Germ.h"
#import "AdminUIServer/UITemplateEngine.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (GermRoutes)

- (void)registerGermRoutes {
    __weak typeof(self) weakSelf = self;

    // Germ: Overview dashboard
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/germ" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIGermPack renderGermOverviewHTML]];
    }];

    // Germ: Health
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/germ-health" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchGermHealth];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIGermPack renderGermHealthPartial:result]];
    }];

    // Germ: Mailbox flow (aggregate-only)
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/germ-flow" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchGermFlowMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        NSMutableDictionary *ctx = [result mutableCopy];
        if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
        [response setBodyString:[GZAdminUITemplateEngine renderTemplate:@"germ-flow" context:ctx]];
    }];

    // Germ: Storage pressure (aggregate-only)
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/germ-storage" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchGermStorageMetrics];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        NSMutableDictionary *ctx = [result mutableCopy];
        if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
        [response setBodyString:[GZAdminUITemplateEngine renderTemplate:@"germ-storage" context:ctx]];
    }];
}

@end
