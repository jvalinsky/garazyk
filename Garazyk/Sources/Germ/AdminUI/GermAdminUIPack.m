// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Germ/AdminUI/GermAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GermAdminUIPack

+ (NSString *)packIdentifier { return @"germ"; }
+ (NSString *)displayName { return @"Germ"; }

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"germ", @"displayName": @"Mailbox"}];
}

+ (NSString *)errorUnavailableHTML {
    return @"<div class=\"alert alert-warning\">Germ dashboard unavailable — embedded listener required.</div>";
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    __weak GZAdminUIHost *weakHost = host;

    // Overview
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:[self overviewHTML]];
    }];

    // Health
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ-health" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:@"<div class=\"detail-card\"><div class=\"detail-row\">"
                          @"<span class=\"detail-label\">Status</span>"
                          @"<span class=\"badge badge-success\">ok</span></div></div>"];
    }];

    // Flow (aggregate-only placeholder)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ-flow" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:@"<div class=\"alert alert-info\">"
                          @"Flow metrics will be available when aggregate counters are added to GermMailboxService."
                          @"</div>"];
    }];

    // Storage (aggregate-only placeholder)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ-storage" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:@"<div class=\"alert alert-info\">"
                          @"Storage metrics will be available when aggregate counters are added to GermMailboxService."
                          @"</div>"];
    }];
}

+ (NSString *)overviewHTML {
    return @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Privacy</span>"
        @"<span class=\"metric-value\">Aggregate counters only — no ciphertext, addresses, or agent data</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Encryption</span>"
        @"<span class=\"metric-value\">End-to-end encrypted — server cannot decrypt</span></div>"
        @"</div>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Health</h3>"
        @"<div id=\"germ-health\" hx-get=\"/admin/partials/germ-health\" hx-trigger=\"revealed, every 30s\"></div></section>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Mailbox Flow</h3>"
        @"<div id=\"germ-flow\" hx-get=\"/admin/partials/germ-flow\" hx-trigger=\"revealed, every 30s\"></div></section>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Storage</h3>"
        @"<div id=\"germ-storage\" hx-get=\"/admin/partials/germ-storage\" hx-trigger=\"revealed, every 30s\"></div></section>";
}

@end
