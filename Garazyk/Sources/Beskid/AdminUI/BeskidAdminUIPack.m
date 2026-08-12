// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Beskid/AdminUI/BeskidAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "Beskid/AdminUI/BeskidAdminSnapshot.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZBeskidAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZBeskidAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, GZBeskidAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZBeskidAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"beskid"; }
+ (NSString *)displayName { return @"Beskid"; }
+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[@{ @"tabIdentifier": @"beskid", @"displayName": @"Beskid" }];
}

#pragma mark - HTML renderers

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *cache = snapshot[@"cache"] ?: @{};
    NSDictionary *overall = cache[@"overall"] ?: @{};
    double hitRatio = [overall[@"hitRatio"] doubleValue];
    NSString *hitRatioStr = [NSString stringWithFormat:@"%d%%", (int)(hitRatio * 100.0)];
    NSString *expiry = [NSString stringWithFormat:@"%@/%@",
        overall[@"expired"] ?: @0, @([overall[@"entries"] longLongValue] + [overall[@"expired"] longLongValue])];
    
    int64_t upstreamFailures = 0;
    for (NSDictionary *up in snapshot[@"upstreams"] ?: @[]) {
        upstreamFailures += [up[@"failures"] longLongValue];
    }
    
    id avgLatency = [NSNull null];
    int64_t totalSuc = 0, totalLat = 0;
    for (NSDictionary *up in snapshot[@"upstreams"] ?: @[]) {
        totalSuc += [up[@"successes"] longLongValue];
        totalLat += [up[@"successes"] longLongValue] * ([up[@"averageLatencyMilliseconds"] isKindOfClass:[NSNumber class]]
            ? [up[@"averageLatencyMilliseconds"] longLongValue] : 0);
    }
    if (totalSuc > 0) avgLatency = @(totalLat / totalSuc);
    NSString *latencyStr = [avgLatency isKindOfClass:[NSNumber class]]
        ? [NSString stringWithFormat:@"%@ ms", avgLatency] : @"—";
    
    NSDictionary *db = snapshot[@"database"] ?: @{};
    int64_t storageMB = [db[@"storageBytes"] longLongValue] / (1024 * 1024);
    
    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Health</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Uptime</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Cache entries</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Hit ratio</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Expired reads / total</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Upstream failures</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Avg upstream latency</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Rate-limit rejects</span><span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Storage</span><span class=\"metric-value\">%@ MB</span></div>"
        @"</div>",
        GZAdminUIEscaped(snapshot[@"health"] ?: @"unknown"),
        snapshot[@"uptimeSeconds"] ?: @0,
        overall[@"entries"] ?: @0,
        hitRatioStr,
        expiry,
        @(upstreamFailures),
        latencyStr,
        snapshot[@"rateLimitRejects"] ?: @0,
        @(storageMB)
    ];
}

+ (NSString *)cacheFamilyRowHTML:(NSDictionary *)family ttl:(NSNumber *)ttl {
    NSString *soonestExpiry = @"—";
    if ([family[@"soonestExpiry"] isKindOfClass:[NSNumber class]]) {
        int64_t ts = [family[@"soonestExpiry"] longLongValue];
        soonestExpiry = [[NSISO8601DateFormatter new] stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
    }
    double ratio = [family[@"hitRatio"] doubleValue];
    return [NSString stringWithFormat:
        @"<tr>"
        @"<td>%@</td><td>%@</td><td>%@</td><td>%@</td>"
        @"<td>%@</td><td>%@</td><td>%@</td><td>%@</td>"
        @"<td class=\"text-mono text-xs\">%@</td>"
        @"</tr>",
        GZAdminUIEscaped(family[@"family"]),
        family[@"entries"] ?: @0,
        family[@"hits"] ?: @0, family[@"misses"] ?: @0,
        family[@"expired"] ?: @0,
        family[@"writes"] ?: @0, family[@"deletes"] ?: @0,
        [NSString stringWithFormat:@"%d%%", (int)(ratio * 100.0)],
        soonestExpiry
    ];
}

+ (NSString *)cacheHTML:(NSDictionary *)snapshot {
    NSDictionary *cache = snapshot[@"cache"] ?: @{};
    NSDictionary *ttl = snapshot[@"ttl"] ?: @{};
    NSMutableString *html = [NSMutableString stringWithString:
        @"<table class=\"table\">"
        @"<thead><tr>"
        @"<th>Family</th><th>Entries</th><th>Hits</th><th>Misses</th>"
        @"<th>Expired</th><th>Writes</th><th>Deletes</th>"
        @"<th>Hit ratio</th><th>Soonest expiry</th>"
        @"</tr></thead><tbody>"];
    
    for (NSString *key in @[@"overall", @"record", @"identity"]) {
        NSDictionary *family = cache[key];
        if (!family) continue;
        NSNumber *familyTTL = nil;
        if ([key isEqualToString:@"record"]) familyTTL = ttl[@"recordSeconds"];
        else if ([key isEqualToString:@"identity"]) familyTTL = ttl[@"identitySeconds"];
        [html appendString:[self cacheFamilyRowHTML:family ttl:familyTTL]];
    }
    
    if (cache.count == 0) {
        [html appendString:@"<tr><td colspan=\"9\" class=\"text-secondary p-lg\">No cache data.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)upstreamsHTML:(NSDictionary *)snapshot {
    NSArray *upstreams = snapshot[@"upstreams"] ?: @[];
    NSMutableString *html = [NSMutableString stringWithString:
        @"<table class=\"table\">"
        @"<thead><tr>"
        @"<th>Host</th><th>Requests</th><th>Successes</th><th>Failures</th>"
        @"<th>Avg latency</th><th>Last success</th>"
        @"</tr></thead><tbody>"];
    
    for (NSDictionary *entry in upstreams) {
        NSString *lat = [entry[@"averageLatencyMilliseconds"] isKindOfClass:[NSNumber class]]
            ? [NSString stringWithFormat:@"%@ ms", entry[@"averageLatencyMilliseconds"]] : @"—";
        NSString *lastSuccess = [entry[@"lastSuccessAt"] isKindOfClass:[NSString class]]
            ? entry[@"lastSuccessAt"] : @"—";
        [html appendFormat:
            @"<tr>"
            @"<td class=\"text-mono\">%@</td><td>%@</td><td>%@</td><td>%@</td>"
            @"<td>%@</td><td class=\"text-mono text-xs\">%@</td>"
            @"</tr>",
            GZAdminUIEscaped(entry[@"host"]),
            entry[@"requests"] ?: @0, entry[@"successes"] ?: @0,
            entry[@"failures"] ?: @0, lat, GZAdminUIEscaped(lastSuccess)
        ];
    }
    if (upstreams.count == 0) {
        [html appendString:@"<tr><td colspan=\"6\" class=\"text-secondary p-lg\">No upstream requests recorded.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)errorUnavailableHTML {
    return @"<div class=\"alert alert-destructive\">Beskid dashboard is unavailable — embedded listener required.</div>";
}

#pragma mark - Routes

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    GZBeskidAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;
    
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/beskid-metrics" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [response setBodyString:snapshot ? [self metricsHTML:value] : [self errorUnavailableHTML]];
    }];
    
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/beskid-cache" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [response setBodyString:snapshot ? [self cacheHTML:value] : [self errorUnavailableHTML]];
    }];
    
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/beskid-upstreams" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [response setBodyString:snapshot ? [self upstreamsHTML:value] : [self errorUnavailableHTML]];
    }];
}

@end
