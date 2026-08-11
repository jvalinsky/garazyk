// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/AdminUI/RelayAdminUIPack.h"
#import "Sync/Relay/AdminUI/RelayAdminSnapshot.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZRelayAdminUIPack

+ (NSMapTable *)snapshots {
    static NSMapTable *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [NSMapTable weakToStrongObjectsMapTable]; });
    return value;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZRelayAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"relay"; }
+ (NSString *)displayName { return @"Relay"; }
+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[@{ @"tabIdentifier": @"relay", @"displayName": @"Relay" }];
}

+ (NSDictionary *)snapshotForHost:(GZAdminUIHost *)host snapshot:(GZRelayAdminSnapshot *)snapshot {
    if (snapshot) return [snapshot snapshot];
    NSDictionary *remote = [host.backendClient fetchRelayMetrics];
    if (remote[@"error"]) return remote;
    NSDictionary *metrics = [remote[@"metrics"] isKindOfClass:NSDictionary.class] ? remote[@"metrics"] : remote;
    NSDictionary *upstreams = [host.backendClient fetchRelayUpstreams];
    if (upstreams[@"error"]) return upstreams;
    NSArray *sourceRows = [upstreams[@"upstreams"] isKindOfClass:NSArray.class] ? upstreams[@"upstreams"] : @[];
    NSUInteger connected = 0;
    NSMutableArray *normalized = [NSMutableArray arrayWithCapacity:sourceRows.count];
    for (NSDictionary *source in sourceRows) {
        BOOL isConnected = [source[@"connected"] boolValue] || [source[@"status"] isEqual:@"connected"];
        if (isConnected) connected++;
        [normalized addObject:@{
            @"hostname": source[@"hostname"] ?: source[@"url"] ?: @"",
            @"connected": @(isConnected),
            @"status": source[@"status"] ?: (isConnected ? @"connected" : @"disconnected"),
            @"repositories": source[@"repositories"] ?: source[@"repositoryCount"] ?: @0,
            @"eventsReceived": source[@"eventsReceived"] ?: @0,
            @"cursor": source[@"cursor"] ?: source[@"seq"] ?: @0,
            @"crawlState": source[@"crawlState"] ?: @"not requested",
            @"reconnectAttempts": source[@"reconnectAttempts"] ?: @0,
            @"crawlError": source[@"crawlError"] ?: @"",
        }];
    }
    return @{
        @"health": connected == 0 && normalized.count > 0 ? @"degraded" : @"healthy",
        @"metrics": metrics ?: @{}, @"upstreams": normalized,
        @"connectedUpstreams": @(connected), @"embedded": @NO,
    };
}

+ (NSString *)metricsHTMLForValue:(NSDictionary *)value embedded:(BOOL)embedded {
    if (value[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>",
                GZAdminUIEscaped(value[@"message"] ?: @"Relay status is unavailable.")];
    }
    NSDictionary *metrics = value[@"metrics"] ?: @{};
    NSMutableString *html = [NSMutableString stringWithFormat:@"<div class=\"metric-row\"><div class=\"metric\"><span class=\"metric-label\">Health</span><span class=\"metric-value\">%@</span></div><div class=\"metric\"><span class=\"metric-label\">Sources online</span><span class=\"metric-value\">%@ / %@</span></div><div class=\"metric\"><span class=\"metric-label\">Events</span><span class=\"metric-value\">%@</span></div><div class=\"metric\"><span class=\"metric-label\">Sequence</span><span class=\"metric-value\">%@</span></div></div>", GZAdminUIEscaped(value[@"health"]), value[@"connectedUpstreams"] ?: @0, @([value[@"upstreams"] count]), metrics[@"eventsReceived"] ?: @0, metrics[@"currentSequence"] ?: @0];
    if (embedded) {
        [html appendString:@"<section class=\"mt-lg\"><h3 class=\"section-title\">Source controls</h3><div id=\"relay-action-result\" aria-live=\"polite\"></div><div class=\"button-row\"><button class=\"btn btn-secondary\" data-ui-action=\"relay-reconnect-all\">Reconnect all</button><button class=\"btn btn-secondary\" data-ui-action=\"relay-disconnect-all\">Disconnect all</button></div><form class=\"form-row mt-md\" data-ui-form=\"relay-request-crawl\"><label for=\"relay-crawl-hostname\">Request inventory crawl</label><input id=\"relay-crawl-hostname\" name=\"hostname\" type=\"text\" autocomplete=\"off\" placeholder=\"pds.example.com\"><button class=\"btn btn-primary\" type=\"submit\">Request crawl</button></form></section>"];
    }
    [html appendString:@"<section class=\"mt-lg\"><h3 class=\"section-title\">Sources</h3><div id=\"relay-sources\" hx-get=\"/admin/partials/relay-sources\" hx-trigger=\"load, every 10s\"></div></section>"];
    return html;
}

+ (NSString *)sourcesHTMLForValue:(NSDictionary *)value {
    if (value[@"error"]) return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(value[@"message"] ?: @"Relay sources are unavailable.")];
    NSArray *sources = value[@"upstreams"] ?: @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Source</th><th>Status</th><th>Crawl</th><th>Repositories</th><th>Events</th><th>Cursor</th></tr></thead><tbody>"];
    for (NSDictionary *entry in sources) {
        NSString *status = entry[@"status"] ?: ([entry[@"connected"] boolValue] ? @"connected" : @"disconnected");
        [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td>%@</td><td>%@</td><td>%@</td><td>%@</td><td>%@</td></tr>", GZAdminUIEscaped(entry[@"hostname"]), GZAdminUIEscaped(status), GZAdminUIEscaped(entry[@"crawlState"]), entry[@"repositories"] ?: @0, entry[@"eventsReceived"] ?: @0, entry[@"cursor"] ?: @0];
    }
    if (sources.count == 0) [html appendString:@"<tr><td colspan=\"6\" class=\"text-secondary\">No upstreams configured.</td></tr>"];
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    GZRelayAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/relay-metrics" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        NSDictionary *value = [self snapshotForHost:weakHost snapshot:snapshot];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[self metricsHTMLForValue:value embedded:snapshot != nil]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/relay-sources" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakHost, request, response);
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[self sourcesHTMLForValue:[self snapshotForHost:weakHost snapshot:snapshot]]];
    }];
    for (NSString *path in @[ @"/admin/actions/relay-reconnect-all", @"/admin/actions/relay-disconnect-all", @"/admin/actions/request-crawl" ]) {
        [host.httpServer addRoute:@"POST" path:path handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
            AUTH_GUARD(weakHost, request, response);
            NSDictionary *result = snapshot ? nil : @{ @"error": @"relay_not_embedded", @"message": @"Relay controls are available on the embedded Relay admin listener." };
            if (!result && [path hasSuffix:@"reconnect-all"]) result = [snapshot performAction:@"reconnect-all" hostname:nil];
            else if (!result && [path hasSuffix:@"disconnect-all"]) result = [snapshot performAction:@"disconnect-all" hostname:nil];
            else if (!result) result = [snapshot performAction:@"request-crawl" hostname:request.jsonBody[@"hostname"]];
            response.statusCode = result[@"error"] ? HttpStatusBadRequest : HttpStatusOK;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", result[@"error"] ? @"alert-destructive" : @"alert-success", GZAdminUIEscaped(result[@"message"])]];
        }];
    }
}
@end
