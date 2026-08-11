// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/AdminUI/PLCAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
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
    return @[@{ @"tabIdentifier": @"plc", @"displayName": @"PLC" }];
}

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *metrics = snapshot[@"metrics"] ?: @{};
    NSDictionary *latency = metrics[@"resolutionLatency"] ?: @{};
    NSMutableString *html = [NSMutableString stringWithFormat:
        @"<div class=\"metric-row\"><div class=\"metric\"><span class=\"metric-label\">Mode</span><span class=\"metric-value\">%@</span></div><div class=\"metric\"><span class=\"metric-label\">Health</span><span class=\"metric-value\">%@</span></div><div class=\"metric\"><span class=\"metric-label\">DIDs</span><span class=\"metric-value\">%@</span></div><div class=\"metric\"><span class=\"metric-label\">Operations</span><span class=\"metric-value\">%@</span></div><div class=\"metric\"><span class=\"metric-label\">Requests / Errors</span><span class=\"metric-value\">%@ / %@</span></div><div class=\"metric\"><span class=\"metric-label\">Resolution avg</span><span class=\"metric-value\">%@ ms</span></div></div>",
        GZAdminUIEscaped(snapshot[@"mode"] ?: @"unknown"), GZAdminUIEscaped(snapshot[@"health"] ?: @"unknown"),
        snapshot[@"didTotal"] ?: @0, snapshot[@"operationTotal"] ?: @0,
        metrics[@"totalRequests"] ?: @0, metrics[@"totalErrors"] ?: @0,
        latency[@"averageMilliseconds"] ?: @0];
    NSDictionary *replication = snapshot[@"replication"];
    if (replication) {
        [html appendFormat:@"<div class=\"detail-card mt-lg\"><div class=\"detail-row\"><span class=\"detail-label\">Replication</span><span>%@</span></div><div class=\"detail-row\"><span class=\"detail-label\">Cursor</span><span>%@</span></div><div class=\"detail-row\"><span class=\"detail-label\">Ingested / Failed</span><span>%@ / %@</span></div><div><button class=\"btn btn-secondary btn-sm\" data-ui-action=\"plc-sync\" data-plc-action=\"pause\">Pause</button> <button class=\"btn btn-secondary btn-sm\" data-ui-action=\"plc-sync\" data-plc-action=\"resume\">Resume</button> <button class=\"btn btn-primary btn-sm\" data-ui-action=\"plc-sync\" data-plc-action=\"sync-once\">Sync once</button></div></div>", GZAdminUIEscaped(replication[@"state"] ?: @"unknown"), replication[@"cursor"] ?: @0, replication[@"ingested"] ?: @0, replication[@"failed"] ?: @0];
    }
    return html;
}

+ (NSString *)errorHTML:(NSDictionary *)result fallback:(NSString *)fallback {
    NSString *message = result[@"message"] ?: result[@"error"] ?: fallback;
    return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(message)];
}

+ (NSString *)remoteDetailHTML:(NSDictionary *)result {
    if (result[@"error"]) return [self errorHTML:result fallback:@"PLC lookup failed"];
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    for (NSString *key in @[ @"did", @"handle", @"service", @"rotationKeys", @"alsoKnownAs", @"createdAt" ]) {
        id value = result[key];
        if (!value) continue;
        NSString *display = [value isKindOfClass:[NSArray class]] ? [(NSArray *)value componentsJoinedByString:@", "] : [value description];
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">%@</span><span class=\"text-mono text-xs\">%@</span></div>", GZAdminUIEscaped(key), GZAdminUIEscaped(display)];
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)remoteLogHTML:(NSDictionary *)result {
    if (result[@"error"]) return [self errorHTML:result fallback:@"PLC log fetch failed"];
    NSArray *entries = [result[@"log"] isKindOfClass:[NSArray class]] ? result[@"log"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Seq</th><th>Type</th><th>Time</th><th>Detail</th></tr></thead><tbody>"];
    for (NSDictionary *entry in entries) {
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td><td>%@</td></tr>", GZAdminUIEscaped([entry[@"seq"] description]), GZAdminUIEscaped([entry[@"type"] description]), GZAdminUIEscaped([entry[@"createdAt"] description]), GZAdminUIEscaped([entry[@"detail"] description])];
    }
    if (entries.count == 0) [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No log entries.</td></tr>"];
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)remoteMetricsHTML:(NSDictionary *)result {
    if (result[@"error"]) return [self errorHTML:result fallback:@"PLC metrics fetch failed"];
    return [NSString stringWithFormat:@"<pre class=\"text-mono text-xs\">%@</pre>", GZAdminUIEscaped(result[@"text"] ?: @"")];
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
            [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(entry[@"message"] ?: entry[@"error"])]];
            return;
        }
        if (!snapshot) {
            [response setBodyString:[self remoteDetailHTML:entry]];
            return;
        }
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"detail-card\"><div class=\"detail-row\"><span class=\"detail-label\">DID</span><span class=\"text-mono\">%@</span></div><div class=\"detail-row\"><span class=\"detail-label\">Operation chain</span><span>%@</span></div><div class=\"detail-row\"><span class=\"detail-label\">Nullified</span><span>%@</span></div><div class=\"detail-row\"><span class=\"detail-label\">Verification</span><span>%@</span></div></div>", GZAdminUIEscaped(entry[@"did"]), entry[@"operationChainLength"] ?: @0, entry[@"nullifiedOperations"] ?: @0, GZAdminUIEscaped(entry[@"verification"][@"status"] ?: @"unknown")]];
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
        [response setBodyString:snapshot ? [self remoteDetailHTML:result] : [self remoteDetailHTML:result]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-log" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        if (snapshot) {
            [response setBodyString:@"<div class=\"alert\">Operation audit is available from the directory lookup.</div>"];
        } else {
            [response setBodyString:[self remoteLogHTML:[weakHost.backendClient fetchPLCLogForDID:[request queryParamForKey:@"did"] ?: @""]]];
        }
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-health" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSDictionary *result = snapshot ? [snapshot snapshot] : [weakHost.backendClient fetchPLCHealth];
        response.contentType = @"text/html; charset=utf-8";
        NSString *status = result[@"health"] ?: result[@"status"] ?: @"unknown";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"metric\"><span class=\"metric-label\">PLC health</span><span class=\"metric-value\">%@</span></div>", GZAdminUIEscaped(status)]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/plc-list" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSDictionary *result = snapshot ? @{ @"dids": @[] } : [weakHost.backendClient fetchPLCList];
        response.contentType = @"text/html; charset=utf-8";
        if (result[@"error"]) { [response setBodyString:[self errorHTML:result fallback:@"PLC list fetch failed"]]; return; }
        NSMutableString *html = [NSMutableString stringWithString:@"<ul class=\"list\">"];
        for (NSString *did in result[@"dids"] ?: @[]) [html appendFormat:@"<li class=\"text-mono\">%@</li>", GZAdminUIEscaped(did)];
        [html appendString:@"</ul>"];
        [response setBodyString:html];
    }];
}

@end
