// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Germ/AdminUI/GermAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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
    return [GZHTML alertWithType:@"warning" message:@"Germ dashboard unavailable — embedded listener required."];
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
        NSDictionary *metrics = [self fetchLocalMetrics];
        if (metrics) {
            [res setBodyString:[GZHTML detailCardWithFields:@[
                @{@"label": @"Status", @"html": [GZHTML healthBadge:@"ok"]},
                @{@"label": @"Pending messages", @"html": [GZHTML monoValue:metrics[@"pendingMessages"]]},
                @{@"label": @"Expired awaiting cleanup", @"html": [GZHTML monoValue:metrics[@"expiredCount"]]},
            ]]];
        } else {
            [res setBodyString:[GZHTML detailCardWithFields:@[
                @{@"label": @"Status", @"html": [GZHTML healthBadge:@"degraded"]},
                @{@"label": @"Metrics", @"value": @"Unavailable — local Germ metrics endpoint did not respond"},
            ]]];
        }
    }];

    // Flow (aggregate-only, live counters)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/germ-flow" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *metrics = [self fetchLocalMetrics];
        if (metrics) {
            [res setBodyString:[self flowHTML:metrics]];
        } else {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:@"Metrics unavailable — Germ service may not be running."]];
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
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:@"Metrics unavailable — Germ service may not be running."]];
        }
    }];
}

+ (NSString *)overviewHTML {
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Operator posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Privacy", @"value": @"Aggregate counters only — no ciphertext, addresses, or agents"},
        @{@"label": @"Encryption", @"value": @"End-to-end encrypted — server cannot decrypt"},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Health"]];
    [html appendString:@"<div id=\"germ-health\" hx-get=\"/admin/partials/germ-health\" hx-trigger=\"revealed, every 30s\"></div></section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Mailbox flow"]];
    [html appendString:@"<div id=\"germ-flow\" hx-get=\"/admin/partials/germ-flow\" hx-trigger=\"revealed, every 30s\"></div></section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Storage"]];
    [html appendString:@"<div id=\"germ-storage\" hx-get=\"/admin/partials/germ-storage\" hx-trigger=\"revealed, every 30s\"></div></section>"];
    return html;
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
    NSMutableArray *fields = [NSMutableArray arrayWithArray:@[
        @{@"label": @"Ephemeral addresses", @"html": [GZHTML monoValue:m[@"ephemeralCount"]]},
        @{@"label": @"Rendezvous addresses", @"html": [GZHTML monoValue:m[@"rendezvousCount"]]},
        @{@"label": @"Pending ephemeral", @"html": [GZHTML monoValue:m[@"pendingEphemeral"]]},
        @{@"label": @"Pending rendezvous", @"html": [GZHTML monoValue:m[@"pendingRendezvous"]]},
        @{@"label": @"Expired (awaiting cleanup)", @"html": [GZHTML monoValue:m[@"expiredCount"]]},
    ]];
    if (m[@"claims"] || m[@"delivers"] || m[@"polls"] || m[@"misses"] || m[@"authFailures"]) {
        [fields addObject:@{@"label": @"Claims / Delivers", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            m[@"claims"] ?: @0, m[@"delivers"] ?: @0]]}];
        [fields addObject:@{@"label": @"Polls / Misses", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            m[@"polls"] ?: @0, m[@"misses"] ?: @0]]}];
        [fields addObject:@{@"label": @"Auth failures", @"html": [GZHTML monoValue:m[@"authFailures"] ?: @0]}];
    }
    return [GZHTML detailCardWithFields:fields];
}

+ (NSString *)storageHTML:(NSDictionary *)m {
    int64_t bytes = [m[@"dbSizeBytes"] longLongValue];
    return [GZHTML detailCardWithFields:@[
        @{@"label": @"Ephemeral addresses", @"html": [GZHTML monoValue:m[@"ephemeralCount"]]},
        @{@"label": @"Rendezvous addresses", @"html": [GZHTML monoValue:m[@"rendezvousCount"]]},
        @{@"label": @"Pending messages", @"html": [GZHTML monoValue:m[@"pendingMessages"]]},
        @{@"label": @"Database size", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ (%lld B)",
            [GZHTML formatMegabytes:bytes], (long long)bytes]]},
    ]];
}

@end
