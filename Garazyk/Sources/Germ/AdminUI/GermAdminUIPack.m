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

    // Flow (aggregate-only, live counters)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ-flow" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *metrics = [self fetchLocalMetrics];
        if (metrics) {
            [res setBodyString:[self flowHTML:metrics]];
        } else {
            [res setBodyString:@"<div class=\"alert alert-warning\">Metrics unavailable — Germ service may not be running.</div>"];
        }
    }];

    // Storage (aggregate-only, live counters)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ-storage" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *metrics = [self fetchLocalMetrics];
        if (metrics) {
            [res setBodyString:[self storageHTML:metrics]];
        } else {
            [res setBodyString:@"<div class=\"alert alert-warning\">Metrics unavailable — Germ service may not be running.</div>"];
        }
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

+ (NSDictionary *)fetchLocalMetrics {
    // Query the Germ service's admin metrics endpoint on localhost.
    // The metrics response is aggregate-only — no addresses, agents, or ciphertext.
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:8082/_admin/metrics"];
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

+ (NSString *)flowHTML:(NSDictionary *)m {
    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Ephemeral addrs</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Rendezvous addrs</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Pending ephemeral</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Pending rendezvous</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Expired (awaiting cleanup)</span><span class=\"metric-value\">%@</span></div>"
        @"</div>",
        m[@"ephemeralCount"] ?: @0, m[@"rendezvousCount"] ?: @0,
        m[@"pendingEphemeral"] ?: @0, m[@"pendingRendezvous"] ?: @0,
        m[@"expiredCount"] ?: @0];
}

+ (NSString *)storageHTML:(NSDictionary *)m {
    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Ephemeral addresses</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Rendezvous addresses</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Pending messages</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Database size</span><span class=\"metric-value\">%@ bytes</span></div>"
        @"</div>",
        m[@"ephemeralCount"] ?: @0, m[@"rendezvousCount"] ?: @0,
        m[@"pendingMessages"] ?: @0, m[@"dbSizeBytes"] ?: @0];
}

@end
