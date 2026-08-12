// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Beskid/AdminUI/BeskidAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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
    return @[
        @{ @"tabIdentifier": @"beskid-metrics", @"displayName": @"Overview" },
        @{ @"tabIdentifier": @"beskid-cache", @"displayName": @"Cache" },
        @{ @"tabIdentifier": @"beskid-upstreams", @"displayName": @"Upstreams" },
    ];
}

#pragma mark - HTML renderers

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *cache = snapshot[@"cache"] ?: @{};
    NSDictionary *overall = cache[@"overall"] ?: @{};
    double hitRatio = [overall[@"hitRatio"] doubleValue];
    NSString *hitRatioStr = [NSString stringWithFormat:@"%d%%", (int)(hitRatio * 100.0)];
    NSString *expiry = [NSString stringWithFormat:@"%@ / %@",
        overall[@"expired"] ?: @0, @([overall[@"entries"] longLongValue] + [overall[@"expired"] longLongValue])];

    int64_t upstreamFailures = 0;
    int64_t totalSuc = 0, totalLat = 0;
    for (NSDictionary *up in snapshot[@"upstreams"] ?: @[]) {
        upstreamFailures += [up[@"failures"] longLongValue];
        int64_t successes = [up[@"successes"] longLongValue];
        totalSuc += successes;
        if ([up[@"averageLatencyMilliseconds"] isKindOfClass:[NSNumber class]]) {
            totalLat += successes * [up[@"averageLatencyMilliseconds"] longLongValue];
        }
    }
    NSString *latencyStr = totalSuc > 0
        ? [NSString stringWithFormat:@"%lld ms", (long long)(totalLat / totalSuc)]
        : @"—";

    NSDictionary *db = snapshot[@"database"] ?: @{};
    NSDictionary *ttl = snapshot[@"ttl"] ?: @{};

    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Service Health"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Health", @"html": [GZHTML healthBadge:snapshot[@"health"]]},
        @{@"label": @"Uptime", @"html": [GZHTML monoValue:[GZHTML formatUptime:[snapshot[@"uptimeSeconds"] longLongValue]]]},
        @{@"label": @"Cache entries", @"html": [GZHTML monoValue:overall[@"entries"]]},
        @{@"label": @"Hit ratio", @"html": [GZHTML monoValue:hitRatioStr]},
        @{@"label": @"Expired reads / total", @"html": [GZHTML monoValue:expiry]},
        @{@"label": @"Upstream failures", @"html": [GZHTML monoValue:@(upstreamFailures)]},
        @{@"label": @"Avg upstream latency", @"html": [GZHTML monoValue:latencyStr]},
        @{@"label": @"Rate-limit rejects", @"html": [GZHTML monoValue:snapshot[@"rateLimitRejects"]]},
        @{@"label": @"Storage", @"html": [GZHTML monoValue:[GZHTML formatMegabytes:[db[@"storageBytes"] longLongValue]]]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Configured TTLs"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Record TTL", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ s", ttl[@"recordSeconds"] ?: @"—"]]},
        @{@"label": @"Identity TTL", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ s", ttl[@"identitySeconds"] ?: @"—"]]},
    ]]];
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)cacheFamilyRowHTML:(NSDictionary *)family ttl:(NSNumber *)ttl {
    NSString *soonestExpiry = @"—";
    if ([family[@"soonestExpiry"] isKindOfClass:[NSNumber class]]) {
        int64_t ts = [family[@"soonestExpiry"] longLongValue];
        soonestExpiry = [[NSISO8601DateFormatter new] stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
    }
    double ratio = [family[@"hitRatio"] doubleValue];
    NSString *ttlDisplay = ttl ? [NSString stringWithFormat:@"%@ s", ttl] : @"—";
    return [GZHTML tableRowWithHtmlCells:@[
        [GZHTML tableCellWithText:family[@"family"] ?: @"" className:nil],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", family[@"entries"] ?: @0] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", family[@"hits"] ?: @0] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", family[@"misses"] ?: @0] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", family[@"expired"] ?: @0] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", family[@"writes"] ?: @0] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", family[@"deletes"] ?: @0] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:[NSString stringWithFormat:@"%d%%", (int)(ratio * 100.0)] className:@"text-right text-mono"],
        [GZHTML tableCellWithText:ttlDisplay className:@"text-right text-mono"],
        [GZHTML tableCellWithText:soonestExpiry className:@"text-mono text-sm"],
    ]];
}

+ (NSString *)cacheHTML:(NSDictionary *)snapshot {
    NSDictionary *cache = snapshot[@"cache"] ?: @{};
    NSDictionary *ttl = snapshot[@"ttl"] ?: @{};
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Cache families"]];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *key in @[@"overall", @"record", @"identity"]) {
        NSDictionary *family = cache[key];
        if (!family) continue;
        NSNumber *familyTTL = nil;
        if ([key isEqualToString:@"record"]) familyTTL = ttl[@"recordSeconds"];
        else if ([key isEqualToString:@"identity"]) familyTTL = ttl[@"identitySeconds"];
        [rows addObject:[self cacheFamilyRowHTML:family ttl:familyTTL]];
    }

    [html appendString:@"<div class=\"table-scroll\">"];
    [html appendString:[GZHTML tableWithHeaders:@[
        @"Family", @"Entries", @"Hits", @"Misses", @"Expired", @"Writes", @"Deletes", @"Hit ratio", @"TTL", @"Soonest expiry"
    ]
                                       htmlRows:rows.count > 0 ? rows : nil
                                  emptyMessage:@"No cache data."]];
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)upstreamsHTML:(NSDictionary *)snapshot {
    NSArray *upstreams = snapshot[@"upstreams"] ?: @[];
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Upstream hosts"]];

    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:upstreams.count];
    for (NSDictionary *entry in upstreams) {
        NSString *lat = [entry[@"averageLatencyMilliseconds"] isKindOfClass:[NSNumber class]]
            ? [NSString stringWithFormat:@"%@ ms", entry[@"averageLatencyMilliseconds"]] : @"—";
        NSString *lastSuccess = [entry[@"lastSuccessAt"] isKindOfClass:[NSString class]]
            ? entry[@"lastSuccessAt"] : @"—";
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:entry[@"host"] ?: @"" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"requests"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"successes"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"failures"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:lat className:@"text-right text-mono"],
            [GZHTML tableCellWithText:lastSuccess className:@"text-mono text-sm"],
        ]]];
    }

    [html appendString:[GZHTML tableWithHeaders:@[@"Host", @"Requests", @"Successes", @"Failures", @"Avg latency", @"Last success"]
                                       htmlRows:rows.count > 0 ? rows : nil
                                  emptyMessage:@"No upstream requests recorded."]];
    return html;
}

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"destructive" message:@"Beskid dashboard is unavailable — embedded listener required."];
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
