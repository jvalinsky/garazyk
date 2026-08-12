// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Server/AdminUI/SyrenaAdminUIPack.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AppView/Server/AdminUI/SyrenaAdminSnapshot.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZSyrenaAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZSyrenaAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, GZSyrenaAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZSyrenaAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"appview"; }
+ (NSString *)displayName { return @"AppView"; }
+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[
        @{ @"tabIdentifier": @"appview-metrics", @"displayName": @"Overview" },
        @{ @"tabIdentifier": @"ingest-health",   @"displayName": @"Ingestion" },
        @{ @"tabIdentifier": @"appview-backfill", @"displayName": @"Backfill" },
        @{ @"tabIdentifier": @"appview-indexes",  @"displayName": @"Indexes" },
    ];
}

#pragma mark - HTML renderers

+ (NSString *)overviewHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSDictionary *backfill = snapshot[@"backfill"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *db = snapshot[@"database"] ?: @{};
    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Health</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Uptime</span><span class=\"metric-value\">%@ s</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Ingest</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Events / Errors</span><span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Commits / Deletes</span><span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Queries / Errors</span><span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Rate-limit rejects</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Storage</span><span class=\"metric-value\">%@ MB</span></div>"
        @"</div>",
        GZAdminUIEscaped(snapshot[@"health"] ?: @"unknown"),
        snapshot[@"uptimeSeconds"] ?: @0,
        ingest[@"running"] && [ingest[@"running"] boolValue] ? @"running" : @"stopped",
        ingest[@"events"] ?: @0, ingest[@"errors"] ?: @0,
        ingest[@"commits"] ?: @0, ingest[@"deletes"] ?: @0,
        queries[@"total"] ?: @0, queries[@"errors"] ?: @0,
        snapshot[@"rateLimitRejects"] ?: @0,
        @([db[@"storageBytes"] longLongValue] / (1024 * 1024))
    ];
}

+ (NSString *)ingestionHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSArray *relayURLs = snapshot[@"config"][@"relayURLs"] ?: @[];
    NSDictionary *relayHealth = ingest[@"relayHealth"] ?: @{};
    NSDictionary *lagByRelay = ingest[@"lagByRelay"] ?: @{};
    NSDictionary *throughput = ingest[@"throughput"] ?: @{};

    NSMutableString *html = [NSMutableString stringWithString:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Relay health</h3>"
        @"<table class=\"table\"><thead><tr><th>Relay</th><th>Status</th><th>Lag</th><th>Events/s</th></tr></thead><tbody>"];

    for (NSString *url in relayURLs) {
        NSString *status = relayHealth[url] ?: @"unknown";
        NSNumber *lagValue = lagByRelay[url];
        NSNumber *tput = throughput[url];
        [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td>%@</td><td>%@</td><td>%@</td></tr>",
         GZAdminUIEscaped(url), GZAdminUIEscaped(status),
         lagValue ?: @"—", tput ?: @"—"];
    }
    if (relayURLs.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-secondary p-md\">No relays configured.</td></tr>"];
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
        @"<tr><td>Errors</td><td>%@</td></tr>"
        @"</tbody></table></section>",
        ingest[@"events"] ?: @0, ingest[@"commits"] ?: @0, ingest[@"deletes"] ?: @0,
        ingest[@"ops"] ?: @0, ingest[@"identities"] ?: @0, ingest[@"errors"] ?: @0
    ];

    return html;
}

+ (NSString *)backfillHTML:(NSDictionary *)snapshot {
    NSDictionary *backfill = snapshot[@"backfill"] ?: @{};
    return [NSString stringWithFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Backfill status</h3>"
        @"<table class=\"table\"><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        @"<tr><td>Enabled</td><td>%@</td></tr>"
        @"<tr><td>Queue depth</td><td>%@</td></tr>"
        @"<tr><td>Active workers</td><td>%@</td></tr>"
        @"<tr><td>Pending</td><td>%@</td></tr>"
        @"<tr><td>Processing</td><td>%@</td></tr>"
        @"<tr><td>Synced</td><td>%@</td></tr>"
        @"<tr><td>Dirty</td><td>%@</td></tr>"
        @"<tr><td>Completed (session)</td><td>%@</td></tr>"
        @"<tr><td>Failed (session)</td><td>%@</td></tr>"
        @"<tr><td>Enqueued (session)</td><td>%@</td></tr>"
        @"</tbody></table></section>",
        [backfill[@"enabled"] boolValue] ? @"yes" : @"no",
        backfill[@"queueDepth"] ?: @0,
        backfill[@"activeWorkers"] ?: @0,
        backfill[@"repoPending"] ?: @0,
        backfill[@"repoProcessing"] ?: @0,
        backfill[@"repoSynced"] ?: @0,
        backfill[@"repoDirty"] ?: @0,
        backfill[@"completed"] ?: @0,
        backfill[@"failed"] ?: @0,
        backfill[@"enqueued"] ?: @0
    ];
}

+ (NSString *)indexesHTML:(NSDictionary *)snapshot {
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    NSArray *collections = indexes[@"collections"] ?: @[];

    NSMutableString *html = [NSMutableString stringWithFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Indexed collections (%lu)</h3>"
        @"<table class=\"table\"><thead><tr><th>Collection</th><th>Records</th></tr></thead><tbody>",
        (unsigned long)collections.count];

    for (NSDictionary *col in collections) {
        [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td>%@</td></tr>",
         GZAdminUIEscaped(col[@"collection"] ?: @""), col[@"count"] ?: @0];
    }
    if (collections.count == 0) {
        [html appendString:@"<tr><td colspan=\"2\" class=\"text-secondary p-md\">No indexed collections.</td></tr>"];
    }
    [html appendString:@"</tbody></table></section>"];

    NSDictionary *lexicons = snapshot[@"lexicons"] ?: @{};
    [html appendFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Lexicons</h3>"
        @"<table class=\"table\"><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        @"<tr><td>Filtered collections</td><td>%@</td></tr>"
        @"</tbody></table></section>",
        lexicons[@"count"] ?: @0
    ];

    return html;
}

+ (NSString *)errorUnavailableHTML {
    return @"<div class=\"alert alert-destructive\">AppView dashboard is unavailable — embedded listener required.</div>";
}

#pragma mark - Route registration

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    GZSyrenaAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;

    [host.httpServer addRoute:@"GET" path:@"/admin/partials/appview-metrics" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self overviewHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/ingest-health" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self ingestionHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/appview-backfill" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self backfillHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/appview-indexes" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self indexesHTML:value] : [self errorUnavailableHTML]];
    }];
}

@end
