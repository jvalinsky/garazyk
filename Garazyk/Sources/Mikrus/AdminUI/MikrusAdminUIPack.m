// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Mikrus/AdminUI/MikrusAdminUIPack.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "Mikrus/AdminUI/MikrusAdminSnapshot.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZMikrusAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZMikrusAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, GZMikrusAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZMikrusAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"mikrus"; }
+ (NSString *)displayName { return @"Mikrus"; }
+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[@{ @"tabIdentifier": @"mikrus", @"displayName": @"Mikrus" }];
}

#pragma mark - HTML renderers

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *db = snapshot[@"database"] ?: @{};
    int64_t totalQueries = [queries[@"backlink"] longLongValue] + [queries[@"manyToMany"] longLongValue]
                         + [queries[@"identity"] longLongValue] + [queries[@"record"] longLongValue];
    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Health</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Uptime</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Ingest</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Events / Errors</span><span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Records indexed / deleted</span><span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Queries</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Rate-limit rejects</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Storage</span><span class=\"metric-value\">%@ MB</span></div>"
        @"</div>",
        GZAdminUIEscaped(snapshot[@"health"] ?: @"unknown"),
        snapshot[@"uptimeSeconds"] ?: @0,
        ingest[@"enabled"] && [ingest[@"enabled"] boolValue] ? (ingest[@"running"] && [ingest[@"running"] boolValue] ? @"running" : @"stopped") : @"disabled",
        ingest[@"events"] ?: @0, ingest[@"errors"] ?: @0,
        ingest[@"recordsIndexed"] ?: @0, ingest[@"recordsDeleted"] ?: @0,
        @(totalQueries),
        snapshot[@"rateLimitRejects"] ?: @0,
        @([db[@"storageBytes"] longLongValue] / (1024 * 1024))
    ];
}

+ (NSString *)ingestionHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSArray *relayURLs = snapshot[@"config"][@"relayURLs"] ?: @[];
    NSDictionary *relayHealth = ingest[@"relayHealth"] ?: @{};
    NSDictionary *lag = ingest[@"lagByRelay"] ?: @{};
    
    NSMutableString *html = [NSMutableString stringWithString:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Relay health</h3>"
        @"<table class=\"table\"><thead><tr><th>Relay</th><th>Status</th><th>Lag</th></tr></thead><tbody>"];
    
    for (NSString *url in relayURLs) {
        NSString *status = relayHealth[url] ?: @"unknown";
        NSNumber *lagValue = lag[url];
        [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td>%@</td><td>%@</td></tr>",
         GZAdminUIEscaped(url), GZAdminUIEscaped(status), lagValue ?: @"—"];
    }
    if (relayURLs.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\" class=\"text-secondary p-md\">No relays configured.</td></tr>"];
    }
    [html appendString:@"</tbody></table></section>"];
    
    [html appendFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Event counters</h3>"
        @"<table class=\"table\"><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        @"<tr><td>Events</td><td>%@</td></tr>"
        @"<tr><td>Commits</td><td>%@</td></tr>"
        @"<tr><td>Deletes</td><td>%@</td></tr>"
        @"<tr><td>Ops (creates/updates)</td><td>%@</td></tr>"
        @"<tr><td>Identities</td><td>%@</td></tr>"
        @"<tr><td>Records indexed</td><td>%@</td></tr>"
        @"<tr><td>Records deleted</td><td>%@</td></tr>"
        @"<tr><td>Errors</td><td>%@</td></tr>"
        @"</tbody></table></section>",
        ingest[@"events"] ?: @0, ingest[@"commits"] ?: @0, ingest[@"deletes"] ?: @0,
        ingest[@"ops"] ?: @0, ingest[@"identities"] ?: @0,
        ingest[@"recordsIndexed"] ?: @0, ingest[@"recordsDeleted"] ?: @0, ingest[@"errors"] ?: @0
    ];
    
    return html;
}

+ (NSString *)indexesHTML:(NSDictionary *)snapshot {
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    
    NSMutableString *html = [NSMutableString stringWithFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Index families</h3>"
        @"<table class=\"table\"><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        @"<tr><td>Approximate total edges</td><td>%@</td></tr>"
        @"</tbody></table></section>",
        indexes[@"approxEdges"] ?: @0
    ];
    
    [html appendFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Query activity</h3>"
        @"<table class=\"table\"><thead><tr><th>Family</th><th>Requests</th></tr></thead><tbody>"
        @"<tr><td>Backlinks</td><td>%@</td></tr>"
        @"<tr><td>Many-to-many</td><td>%@</td></tr>"
        @"<tr><td>Identity</td><td>%@</td></tr>"
        @"<tr><td>Record lookup</td><td>%@</td></tr>"
        @"</tbody></table></section>",
        queries[@"backlink"] ?: @0, queries[@"manyToMany"] ?: @0,
        queries[@"identity"] ?: @0, queries[@"record"] ?: @0
    ];
    
    return html;
}

+ (NSString *)errorUnavailableHTML {
    return @"<div class=\"alert alert-destructive\">Mikrus dashboard is unavailable — embedded listener required.</div>";
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    GZMikrusAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;
    
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-metrics" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self metricsHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-ingestion" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self ingestionHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-indexes" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self indexesHTML:value] : [self errorUnavailableHTML]];
    }];
}

@end
