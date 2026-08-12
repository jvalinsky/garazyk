// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/AdminUI/RelayAdminUIPack.h"
#import "Sync/Relay/AdminUI/RelayAdminSnapshot.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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
    return @[
        @{ @"tabIdentifier": @"relay", @"displayName": @"Overview" },
    ];
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
        return [GZHTML alertWithType:@"destructive"
                             message:value[@"message"] ?: @"Relay status is unavailable."];
    }
    NSDictionary *metrics = value[@"metrics"] ?: @{};
    NSUInteger upstreamCount = [value[@"upstreams"] count];
    NSMutableString *html = [NSMutableString string];

    [html appendString:[GZHTML sectionTitle:@"Service Health"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Health", @"html": [GZHTML healthBadge:value[@"health"]]},
        @{@"label": @"Sources online", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %lu",
            value[@"connectedUpstreams"] ?: @0, (unsigned long)upstreamCount]]},
        @{@"label": @"Events received", @"html": [GZHTML monoValue:metrics[@"eventsReceived"]]},
        @{@"label": @"Events forwarded", @"html": [GZHTML monoValue:metrics[@"eventsForwarded"]]},
        @{@"label": @"Events dropped", @"html": [GZHTML monoValue:metrics[@"eventsDropped"]]},
        @{@"label": @"Sequence", @"html": [GZHTML monoValue:metrics[@"currentSequence"]]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Validation"]];
    [html appendString:[GZHTML tableWithHeaders:@[@"Check", @"Success", @"Failure"]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"MST" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", metrics[@"mstValidationSuccess"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", metrics[@"mstValidationFailure"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Signature" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", metrics[@"signatureValidationSuccess"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", metrics[@"signatureValidationFailure"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Continuity" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", metrics[@"continuityVerified"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", metrics[@"continuityFailures"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Reconnects" className:nil],
            [GZHTML tableCellWithHTML:[GZHTML escapedString:[NSString stringWithFormat:@"%@", metrics[@"reconnectionCount"] ?: @0]] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:@"" className:nil],
        ]],
    ]
                                  emptyMessage:@"No validation metrics."]];
    [html appendString:@"</section>"];

    if (embedded) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Source controls"]];
        [html appendString:@"<div id=\"relay-action-result\" aria-live=\"polite\"></div>"
         @"<div class=\"button-row\">"
         @"<button class=\"btn btn-secondary\" data-ui-action=\"relay-reconnect-all\">Reconnect all</button>"
         @"<button class=\"btn btn-secondary\" data-ui-action=\"relay-disconnect-all\">Disconnect all</button>"
         @"</div>"
         @"<form class=\"form-row mt-md\" data-ui-form=\"relay-request-crawl\">"
         @"<label class=\"form-label\" for=\"relay-crawl-hostname\">Request inventory crawl</label>"
         @"<input id=\"relay-crawl-hostname\" class=\"form-input\" name=\"hostname\" type=\"text\" autocomplete=\"off\" placeholder=\"pds.example.com\">"
         @"<button class=\"btn btn-primary\" type=\"submit\">Request crawl</button>"
         @"</form></section>"];
    }

    NSArray *audit = [value[@"adminAudit"] isKindOfClass:[NSArray class]] ? value[@"adminAudit"] : @[];
    if (audit.count > 0) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Recent admin actions"]];
        NSMutableArray *auditRows = [NSMutableArray array];
        NSUInteger limit = MIN(audit.count, (NSUInteger)10);
        for (NSUInteger i = 0; i < limit; i++) {
            NSDictionary *entry = audit[i];
            NSString *result = [entry[@"succeeded"] boolValue] ? @"ok" : @"failed";
            [auditRows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:entry[@"at"] ?: @"—" className:@"text-mono text-sm"],
                [GZHTML tableCellWithText:entry[@"action"] ?: @"—" className:nil],
                [GZHTML tableCellWithText:entry[@"hostname"] ?: @"—" className:@"text-mono text-sm"],
                [GZHTML tableCellWithText:result className:nil],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Time", @"Action", @"Host", @"Result"]
                                           htmlRows:auditRows
                                      emptyMessage:@"No admin actions."]];
        [html appendString:@"</section>"];
    }

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Sources"]];
    [html appendString:@"<div id=\"relay-sources\" hx-get=\"/admin/partials/relay-sources\" hx-trigger=\"load, every 10s\"></div></section>"];
    return html;
}

+ (NSString *)sourcesHTMLForValue:(NSDictionary *)value {
    if (value[@"error"]) {
        return [GZHTML alertWithType:@"destructive"
                             message:value[@"message"] ?: @"Relay sources are unavailable."];
    }
    NSArray *sources = value[@"upstreams"] ?: @[];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:sources.count];
    for (NSDictionary *entry in sources) {
        NSString *status = entry[@"status"] ?: ([entry[@"connected"] boolValue] ? @"connected" : @"disconnected");
        NSString *crawlError = entry[@"crawlError"];
        NSString *errorDisplay = ([crawlError isKindOfClass:[NSString class]] && crawlError.length > 0)
            ? crawlError : @"—";
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:entry[@"hostname"] ?: @"" className:@"text-mono text-sm"],
            [GZHTML tableCellWithHTML:[GZHTML connectionBadge:status] className:nil],
            [GZHTML tableCellWithText:entry[@"crawlState"] ?: @"—" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"repositories"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"eventsReceived"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"cursor"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", entry[@"reconnectAttempts"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:errorDisplay className:@"text-sm"],
        ]]];
    }
    return [GZHTML tableWithHeaders:@[@"Source", @"Status", @"Crawl", @"Repos", @"Events", @"Cursor", @"Reconnects", @"Last crawl error"]
                           htmlRows:rows.count > 0 ? rows : nil
                      emptyMessage:@"No upstreams configured."];
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
            [response setBodyString:[GZHTML alertWithType:result[@"error"] ? @"destructive" : @"success"
                                                  message:result[@"message"] ?: @""]];
        }];
    }
}
@end
