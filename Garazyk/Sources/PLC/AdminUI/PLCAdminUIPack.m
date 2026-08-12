// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/AdminUI/PLCAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/GZHTML.h"
#import "PLC/AdminUI/GZAdminUIBackendClient+PLC.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "PLC/AdminUI/PLCAdminSnapshot.h"

@implementation GZPLCAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZPLCAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, GZPLCAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZPLCAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"plc"; }
+ (NSString *)displayName { return @"PLC"; }
+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[@{ @"tabIdentifier": @"plc", @"displayName": @"Overview" }];
}

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *metrics = snapshot[@"metrics"] ?: @{};
    NSDictionary *latency = metrics[@"resolutionLatency"] ?: @{};

    int64_t hits = [metrics[@"cacheHits"] longLongValue] + [metrics[@"memcacheHits"] longLongValue];
    int64_t misses = [metrics[@"cacheMisses"] longLongValue] + [metrics[@"memcacheMisses"] longLongValue];
    int64_t cacheTotal = hits + misses;
    NSString *hitRatio = cacheTotal > 0
        ? [NSString stringWithFormat:@"%d%%", (int)(100.0 * hits / cacheTotal)]
        : @"—";

    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Directory"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Mode", @"value": snapshot[@"mode"] ?: @"unknown"},
        @{@"label": @"Health", @"html": [GZHTML healthBadge:snapshot[@"health"]]},
        @{@"label": @"DIDs", @"html": [GZHTML monoValue:snapshot[@"didTotal"]]},
        @{@"label": @"Operations", @"html": [GZHTML monoValue:snapshot[@"operationTotal"]]},
        @{@"label": @"Requests / Errors", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            metrics[@"totalRequests"] ?: @0, metrics[@"totalErrors"] ?: @0]]},
        @{@"label": @"Cache hit ratio", @"html": [GZHTML monoValue:hitRatio]},
        @{@"label": @"Verification failures", @"html": [GZHTML monoValue:metrics[@"verificationFailures"]]},
        @{@"label": @"Resolution avg", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ ms",
            latency[@"averageMilliseconds"] ?: @0]]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Resolution latency"]];
    [html appendString:[GZHTML tableWithHeaders:@[@"Samples", @"Avg", @"Min", @"Max"]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", latency[@"samples"] ?: @0] className:@"text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@ ms", latency[@"averageMilliseconds"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@ ms", latency[@"minimumMilliseconds"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@ ms", latency[@"maximumMilliseconds"] ?: @0] className:@"text-right text-mono"],
        ]],
    ]
                                  emptyMessage:@"No latency samples."]];
    [html appendString:@"</section>"];

    NSDictionary *replication = snapshot[@"replication"];
    if (replication) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Replication"]];
        [html appendString:[GZHTML detailCardWithFields:@[
            @{@"label": @"State", @"value": replication[@"state"] ?: @"unknown"},
            @{@"label": @"Cursor", @"html": [GZHTML monoValue:replication[@"cursor"]]},
            @{@"label": @"Last sync", @"html": [GZHTML monoValue:replication[@"lastSync"] ?: @"—"]},
            @{@"label": @"Ingested / Failed", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
                replication[@"ingested"] ?: @0, replication[@"failed"] ?: @0]]},
            @{@"label": @"Workers / Batch", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
                replication[@"workers"] ?: @0, replication[@"batchSize"] ?: @0]]},
        ]]];
        [html appendString:@"<div class=\"action-row mt-md\">"
         @"<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"plc-sync\" data-plc-action=\"pause\">Pause</button>"
         @"<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"plc-sync\" data-plc-action=\"resume\">Resume</button>"
         @"<button class=\"btn btn-primary btn-sm\" data-ui-action=\"plc-sync\" data-plc-action=\"sync-once\">Sync once</button>"
         @"</div></section>"];
    }

    NSDictionary *opCounts = [metrics[@"operationCounts"] isKindOfClass:[NSDictionary class]] ? metrics[@"operationCounts"] : nil;
    if (opCounts.count > 0) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Operation counts"]];
        NSArray *keys = [[opCounts allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:keys.count];
        for (NSString *key in keys) {
            [rows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:key className:@"text-mono"],
                [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", opCounts[key] ?: @0] className:@"text-right text-mono"],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Operation", @"Count"]
                                           htmlRows:rows
                                      emptyMessage:@"No operation counts."]];
        [html appendString:@"</section>"];
    }

    return html;
}

+ (NSString *)errorHTML:(NSDictionary *)result fallback:(NSString *)fallback {
    NSString *message = result[@"message"] ?: result[@"error"] ?: fallback;
    return [GZHTML alertWithType:@"destructive" message:message];
}

+ (NSString *)remoteDetailHTML:(NSDictionary *)result {
    if (result[@"error"]) return [self errorHTML:result fallback:@"PLC lookup failed"];
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *key in @[ @"did", @"handle", @"service", @"rotationKeys", @"alsoKnownAs", @"createdAt",
                             @"operationChainLength", @"nullifiedOperations" ]) {
        id value = result[key];
        if (!value) continue;
        NSString *display = [value isKindOfClass:[NSArray class]] ? [(NSArray *)value componentsJoinedByString:@", "] : [value description];
        [fields addObject:@{@"label": key, @"html": [GZHTML monoValue:display]}];
    }
    NSDictionary *verification = result[@"verification"];
    if ([verification isKindOfClass:[NSDictionary class]]) {
        [fields addObject:@{@"label": @"Verification", @"value": verification[@"status"] ?: @"unknown"}];
    }
    return [GZHTML detailCardWithFields:fields];
}

+ (NSString *)remoteLogHTML:(NSDictionary *)result {
    if (result[@"error"]) return [self errorHTML:result fallback:@"PLC log fetch failed"];
    NSArray *entries = [result[@"log"] isKindOfClass:[NSArray class]] ? result[@"log"] : @[];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:[entry[@"seq"] description] ?: @"" className:@"text-mono"],
            [GZHTML tableCellWithText:[entry[@"type"] description] ?: @"" className:nil],
            [GZHTML tableCellWithText:[entry[@"createdAt"] description] ?: @"" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:[entry[@"detail"] description] ?: @"" className:nil],
        ]]];
    }
    return [GZHTML tableWithHeaders:@[@"Seq", @"Type", @"Time", @"Detail"]
                           htmlRows:rows.count > 0 ? rows : nil
                      emptyMessage:@"No log entries."];
}

+ (NSString *)remoteMetricsHTML:(NSDictionary *)result {
    if (result[@"error"]) return [self errorHTML:result fallback:@"PLC metrics fetch failed"];
    // Compatibility host may only have Prometheus text — keep searchable but avoid a raw dump chrome.
    NSString *text = result[@"text"] ?: @"";
    return [NSString stringWithFormat:
            @"<section>%@"
            @"<p class=\"text-secondary text-sm mb-md\">Remote Prometheus scrape (compatibility host).</p>"
            @"<pre class=\"text-mono text-sm\">%@</pre></section>",
            [GZHTML sectionTitle:@"Metrics"],
            [GZHTML escapedString:text]];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    GZPLCAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-metrics" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        NSDictionary *result = snapshot ? [snapshot snapshot] : [weakHost.backendClient fetchPLCMetrics];
        [response setBodyString:snapshot ? [self metricsHTML:result] : [self remoteMetricsHTML:result]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-resolve" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *entry = snapshot ? [snapshot directoryEntryForDID:did] : [weakHost.backendClient lookupDID:did];
        response.contentType = @"text/html; charset=utf-8";
        if (entry[@"error"]) {
            [response setBodyString:[GZHTML alertWithType:@"destructive"
                                                  message:entry[@"message"] ?: entry[@"error"]]];
            return;
        }
        if (!snapshot) {
            [response setBodyString:[self remoteDetailHTML:entry]];
            return;
        }
        [response setBodyString:[GZHTML detailCardWithFields:@[
            @{@"label": @"DID", @"html": [GZHTML monoValue:entry[@"did"]]},
            @{@"label": @"Operation chain", @"html": [GZHTML monoValue:entry[@"operationChainLength"]]},
            @{@"label": @"Nullified", @"html": [GZHTML monoValue:entry[@"nullifiedOperations"]]},
            @{@"label": @"Verification", @"value": entry[@"verification"][@"status"] ?: @"unknown"},
        ]]];
    }];
    [host.httpServer addRoute:@"POST" path:@"/admin/actions/plc-sync" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSString *action = [request stringBodyForKey:@"action"];
        NSError *error = nil;
        BOOL succeeded = snapshot && [snapshot performReplicaAction:action error:&error];
        if (!snapshot && !error) error = [NSError errorWithDomain:@"GZPLCAdminUIPack" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Replica controls require the embedded PLC admin listener"}];
        response.statusCode = succeeded ? 200 : 400;
        [response setJsonBody:@{ @"ok": @(succeeded), @"error": error.localizedDescription ?: @"" }];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-did" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSDictionary *result = snapshot ? [snapshot directoryEntryForDID:[request queryParamForKey:@"did"] ?: @""] : [weakHost.backendClient lookupDID:[request queryParamForKey:@"did"] ?: @""];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[self remoteDetailHTML:result]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-log" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        if (snapshot) {
            [response setBodyString:@"<div class=\"alert alert-info\">Operation audit is available from the directory lookup.</div>"];
        } else {
            [response setBodyString:[self remoteLogHTML:[weakHost.backendClient fetchPLCLogForDID:[request queryParamForKey:@"did"] ?: @""]]];
        }
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-health" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSDictionary *result = snapshot ? [snapshot snapshot] : [weakHost.backendClient fetchPLCHealth];
        response.contentType = @"text/html; charset=utf-8";
        NSString *status = result[@"health"] ?: result[@"status"] ?: @"unknown";
        [response setBodyString:[GZHTML detailCardWithFields:@[
            @{@"label": @"PLC health", @"html": [GZHTML healthBadge:status]},
        ]]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-list" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSDictionary *result = snapshot ? @{ @"dids": @[] } : [weakHost.backendClient fetchPLCList];
        response.contentType = @"text/html; charset=utf-8";
        if (result[@"error"]) { [response setBodyString:[self errorHTML:result fallback:@"PLC list fetch failed"]]; return; }
        NSArray *dids = result[@"dids"] ?: @[];
        if (dids.count == 0) {
            [response setBodyString:[GZHTML alertWithType:@"info" message:@"No directory entries in this view."]];
            return;
        }
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:dids.count];
        for (NSString *did in dids) {
            [rows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:did className:@"text-mono"],
            ]]];
        }
        [response setBodyString:[GZHTML tableWithHeaders:@[@"DID"]
                                                htmlRows:rows
                                           emptyMessage:@"No directory entries."]];
    }];
}

@end
