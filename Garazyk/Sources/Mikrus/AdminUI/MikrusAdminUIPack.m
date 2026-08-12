// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Mikrus/AdminUI/MikrusAdminUIPack.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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
    return @[
        @{ @"tabIdentifier": @"mikrus-metrics", @"displayName": @"Overview" },
        @{ @"tabIdentifier": @"mikrus-ingestion", @"displayName": @"Ingestion" },
        @{ @"tabIdentifier": @"mikrus-indexes", @"displayName": @"Indexes" },
        @{ @"tabIdentifier": @"mikrus-explore", @"displayName": @"Explore", @"refreshSeconds": @0 },
    ];
}

#pragma mark - HTML helpers

+ (NSString *)ingestBadgeEnabled:(BOOL)enabled running:(BOOL)running {
    if (!enabled) {
        return [GZHTML badgeWithClass:@"badge badge-secondary" text:@"Disabled"];
    }
    if (running) {
        return [GZHTML badgeWithClass:@"badge badge-success" text:@"Running"];
    }
    return [GZHTML badgeWithClass:@"badge badge-warning" text:@"Stopped"];
}

+ (NSString *)percentEncodedQueryValue:(NSString *)value {
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
        [set addCharactersInString:@"-._~"];
        allowed = [set copy];
    });
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

+ (NSString *)wrappedTable:(NSString *)tableHTML {
    return [NSString stringWithFormat:@"<div class=\"table-fit-wrap\">%@</div>", tableHTML];
}

+ (NSString *)exploreShellHTML {
    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Explore index"]];
    [html appendString:@"<p class=\"text-secondary text-sm mb-md\">Search by <span class=\"text-mono\">at://</span> URI, "
     @"<span class=\"text-mono\">did:</span>, handle, or collection NSID. Click a row to inspect the record JSON and backlinks.</p>"];
    [html appendString:@"<div class=\"search-row\">"];
    [html appendString:@"<form class=\"d-flex gap-sm flex-1\" "
     @"hx-get=\"/admin/partials/mikrus-explore-results\" "
     @"hx-target=\"#mikrus-explore-results\" "
     @"hx-swap=\"innerHTML\">"];
    [html appendString:[GZHTML inputWithType:@"search"
                                        name:@"q"
                                 placeholder:@"at://… · did:… · handle · collection"
                                       value:nil
                                    className:@"form-input flex-1"]];
    [html appendString:@"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Search</button>"];
    [html appendString:@"</form></div>"];
    [html appendString:@"<div id=\"mikrus-explore-results\" data-mikrus-explore-results class=\"mt-md\" hx-preserve>"];
    [html appendString:[GZHTML alertWithType:@"info" message:@"Run a search or open a collection from Indexes to inspect live index rows."]];
    [html appendString:@"</div></section>"];
    return html;
}

+ (NSString *)exploreURIControl:(NSString *)uri {
    if (uri.length == 0) {
        return [GZHTML escapedString:@"—"];
    }
    NSString *encoded = [self percentEncodedQueryValue:uri];
    return [NSString stringWithFormat:
        @"<a href=\"#\" class=\"explore-uri-link text-mono text-sm\" "
        @"hx-get=\"/admin/partials/mikrus-explore-record?uri=%@\" "
        @"hx-target=\"closest [data-mikrus-explore-results]\" "
        @"hx-swap=\"innerHTML\">%@</a>",
        encoded, [GZHTML escapedString:uri]];
}

+ (NSString *)formatIndexedAt:(id)value {
    if (![value respondsToSelector:@selector(longLongValue)]) return @"—";
    return [NSString stringWithFormat:@"%lld", (long long)[value longLongValue]];
}

+ (NSString *)prettyJSONString:(id)object {
    if (!object || object == [NSNull null]) return @"{}";
    if (![NSJSONSerialization isValidJSONObject:object]) {
        return [GZHTML escapedString:[object description]];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
    return [GZHTML escapedString:json ?: @"{}"];
}

+ (NSString *)recordListHTML:(NSArray<NSDictionary *> *)rows
                       title:(NSString *)title
                  nextCursor:(nullable NSString *)nextCursor
                  collection:(nullable NSString *)collection
                       query:(nullable NSString *)query {
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:title]];
    if (rows.count == 0) {
        [html appendString:[GZHTML alertWithType:@"info" message:@"No matching records."]];
        return html;
    }

    NSMutableArray *tableRows = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSString *uri = [row[@"uri"] description] ?: @"";
        [tableRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithHTML:[self exploreURIControl:uri] className:nil],
            [GZHTML tableCellWithText:[row[@"collection"] description] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:[row[@"did"] description] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:[self formatIndexedAt:row[@"indexed_at"]] className:@"text-right text-mono text-sm"],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"URI", @"Collection", @"DID",
                                                  @{@"text": @"Seq", @"className": @"text-right"}]
                                       htmlRows:tableRows
                                  emptyMessage:@"No matching records."]];

    if (nextCursor.length > 0 && collection.length > 0) {
        NSString *href = [NSString stringWithFormat:
            @"/admin/partials/mikrus-explore-results?collection=%@&cursor=%@",
            [self percentEncodedQueryValue:collection],
            [self percentEncodedQueryValue:nextCursor]];
        [html appendFormat:@"<div class=\"mt-sm\"><button type=\"button\" class=\"btn btn-secondary btn-sm\" "
         @"hx-get=\"%@\" hx-target=\"closest [data-mikrus-explore-results]\">Load more</button></div>", href];
    } else if (nextCursor.length > 0 && query.length > 0) {
        // Search path currently returns a single page; keep hook for future paging.
        (void)query;
    }
    return html;
}

+ (NSString *)recordDetailHTML:(NSDictionary<NSString *, id> *)detail {
    if (!detail) {
        return [GZHTML alertWithType:@"warning" message:@"Record not found in the Mikrus index."];
    }

    NSString *currentURI = [detail[@"uri"] description] ?: @"";
    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<div class=\"mb-md\"><button type=\"button\" class=\"btn btn-secondary btn-sm\" "
     @"hx-get=\"/admin/partials/mikrus-explore-results\" "
     @"hx-target=\"closest [data-mikrus-explore-results]\">Back</button></div>"];
    [html appendString:[GZHTML sectionTitle:@"Record"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"URI", @"html": [GZHTML monoValue:detail[@"uri"]]},
        @{@"label": @"DID", @"html": [GZHTML monoValue:detail[@"did"] ?: @"—"]},
        @{@"label": @"Collection", @"html": [GZHTML monoValue:detail[@"collection"] ?: @"—"]},
        @{@"label": @"rkey", @"html": [GZHTML monoValue:detail[@"rkey"] ?: @"—"]},
        @{@"label": @"CID", @"html": [GZHTML monoValue:detail[@"cid"] ?: @"—"]},
        @{@"label": @"Seq", @"html": [GZHTML monoValue:[self formatIndexedAt:detail[@"indexed_at"]]]},
        @{@"label": @"Updated", @"html": [GZHTML monoValue:detail[@"updated_at"] ?: @"—"]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Value"]];
    [html appendFormat:@"<pre class=\"code-block\">%@</pre>", [self prettyJSONString:detail[@"value"]]];
    [html appendString:@"</section>"];

    NSArray *backlinks = detail[@"backlinks"] ?: @[];
    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Related links"]];
    if (backlinks.count == 0) {
        [html appendString:[GZHTML alertWithType:@"info" message:@"No link edges referencing this URI."]];
    } else {
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:backlinks.count];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (NSDictionary *link in backlinks) {
            NSString *linkURI = [link[@"link_uri"] description] ?: @"";
            NSString *subject = [link[@"subject"] description] ?: @"";
            NSString *path = [link[@"source_path"] description] ?: @"";
            NSString *collection = [link[@"source_collection"] description] ?: @"";

            // Outbound edges store this record as link_uri and the target as subject.
            BOOL outbound = currentURI.length > 0 && [linkURI isEqualToString:currentURI];
            NSString *otherURI = outbound ? subject : (linkURI.length > 0 ? linkURI : subject);
            NSString *direction = outbound ? @"Out" : @"In";
            NSString *dedupeKey = [NSString stringWithFormat:@"%@|%@|%@|%@", direction, otherURI, collection, path];
            if ([seen containsObject:dedupeKey]) continue;
            [seen addObject:dedupeKey];

            [rows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:direction className:@"text-sm"],
                [GZHTML tableCellWithHTML:[self exploreURIControl:otherURI] className:nil],
                [GZHTML tableCellWithText:collection.length > 0 ? collection : @"—" className:@"text-mono text-sm"],
                [GZHTML tableCellWithText:path.length > 0 ? path : @"—" className:@"text-mono text-sm"],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Dir", @"URI", @"Source collection", @"Path"]
                                           htmlRows:rows
                                      emptyMessage:@"No link edges."]];
    }
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)exploreResultsHTMLForRequest:(ATProtoHttpRequest *)request
                                  snapshot:(GZMikrusAdminSnapshot *)snapshot {
    NSString *uri = [request queryParamForKey:@"uri"];
    if (uri.length > 0) {
        return [self recordDetailHTML:[snapshot recordDetailForURI:uri]];
    }

    NSString *collection = [request queryParamForKey:@"collection"];
    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSString *query = [request queryParamForKey:@"q"];
    NSString *nextCursor = nil;
    NSArray *rows = nil;
    NSString *title = @"Results";

    if (collection.length > 0) {
        rows = [snapshot listRecordsInCollection:collection limit:40 cursor:cursor nextCursor:&nextCursor];
        title = [NSString stringWithFormat:@"Collection %@", collection];
        return [self recordListHTML:rows title:title nextCursor:nextCursor collection:collection query:nil];
    }

    if (query.length > 0) {
        rows = [snapshot searchIndexWithQuery:query limit:40];
        title = [NSString stringWithFormat:@"Search “%@”", query];
        return [self recordListHTML:rows title:title nextCursor:nil collection:nil query:query];
    }

    return [GZHTML alertWithType:@"info" message:@"Provide a search query or collection to explore."];
}

#pragma mark - HTML renderers

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *db = snapshot[@"database"] ?: @{};
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};

    NSString *health = snapshot[@"health"] ?: @"unknown";
    int64_t uptime = [snapshot[@"uptimeSeconds"] longLongValue];

    BOOL ingestEnabled = [ingest[@"enabled"] boolValue];
    BOOL ingestRunning = [ingest[@"running"] boolValue];

    int64_t totalQueries = [queries[@"backlink"] longLongValue] + [queries[@"manyToMany"] longLongValue]
                         + [queries[@"identity"] longLongValue] + [queries[@"record"] longLongValue];
    int64_t events = [ingest[@"events"] longLongValue];
    int64_t errors = [ingest[@"errors"] longLongValue];
    double errorRate = events > 0 ? (100.0 * errors / events) : 0.0;

    NSDictionary *backlinks = indexes[@"backlinks"] ?: @{};
    NSDictionary *records = indexes[@"records"] ?: @{};
    NSDictionary *identities = indexes[@"identities"] ?: @{};
    NSDictionary *manyToMany = indexes[@"manyToMany"] ?: @{};

    NSMutableString *html = [NSMutableString string];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Service Health"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Status", @"html": [GZHTML healthBadge:health]},
        @{@"label": @"Uptime", @"html": [GZHTML monoValue:[GZHTML formatUptime:uptime]]},
        @{@"label": @"Ingest", @"html": [self ingestBadgeEnabled:ingestEnabled running:ingestRunning]},
        @{@"label": @"Storage", @"html": [GZHTML monoValue:[GZHTML formatMegabytes:[db[@"storageBytes"] longLongValue]]]},
    ]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Ingest Performance"]];
    NSString *errorsCell = [NSString stringWithFormat:@"%@ <span class=\"text-secondary\">(%.2f%%)</span>",
                            [GZHTML escapedString:[@(errors) description]], errorRate];
    [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Metric", @{@"text": @"Value", @"className": @"text-right"}]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Events processed" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"events"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Commits" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"commits"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Records indexed" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"recordsIndexed"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Records deleted" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"recordsDeleted"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Errors" className:nil],
            [GZHTML tableCellWithHTML:errorsCell className:@"text-right text-mono"],
        ]],
    ]
                                  emptyMessage:@"No ingest metrics."]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Index Statistics"]];
    [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Family",
                                                  @{@"text": @"Approx. count", @"className": @"text-right"},
                                                  @"Notes"]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Backlink edges" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backlinks[@"approxEdges"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:backlinks[@"description"] ?: @"" className:@"text-secondary text-sm"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Cached records" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", records[@"approxCount"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:records[@"description"] ?: @"" className:@"text-secondary text-sm"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Identity mappings" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", identities[@"approxCount"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:identities[@"description"] ?: @"" className:@"text-secondary text-sm"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Many-to-many edges" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", manyToMany[@"approxEdges"] ?: @0] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:manyToMany[@"description"] ?: @"" className:@"text-secondary text-sm"],
        ]],
    ]
                                  emptyMessage:@"No index statistics."]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Query Performance"]];
    [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Family", @{@"text": @"Requests", @"className": @"text-right"}]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Total" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%lld", (long long)totalQueries] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Backlink" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", queries[@"backlink"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Many-to-many" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", queries[@"manyToMany"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Identity" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", queries[@"identity"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Record" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", queries[@"record"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Rate limited" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", snapshot[@"rateLimitRejects"] ?: @0] className:@"text-right text-mono"],
        ]],
    ]
                                  emptyMessage:@"No query metrics."]]];
    [html appendString:@"</section>"];

    return html;
}

+ (NSString *)ingestionHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSArray *relayURLs = snapshot[@"config"][@"relayURLs"] ?: @[];
    NSDictionary *relayHealth = ingest[@"relayHealth"] ?: @{};
    NSDictionary *lag = ingest[@"lagByRelay"] ?: @{};
    NSDictionary *throughput = ingest[@"throughput"] ?: @{};
    NSArray *recentErrors = snapshot[@"recentErrors"] ?: @[];

    NSMutableString *html = [NSMutableString string];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Relay Connections"]];

    if (relayURLs.count == 0) {
        [html appendString:[GZHTML alertWithType:@"info" message:@"No relays configured. Ingest is disabled."]];
    } else {
        NSMutableArray *rows = [NSMutableArray arrayWithCapacity:relayURLs.count];
        for (NSString *url in relayURLs) {
            NSString *status = relayHealth[url] ?: @"unknown";
            NSNumber *lagValue = lag[url];
            NSNumber *throughputValue = throughput[url];

            int64_t lagVal = lagValue ? [lagValue longLongValue] : 0;
            NSString *lagDisplay = lagValue ? [NSString stringWithFormat:@"%lld", (long long)lagVal] : @"—";
            NSString *lagClass = @"text-right text-mono";
            if (lagValue && lagVal < 1000) {
                lagClass = @"text-right text-mono text-success";
            } else if (lagVal >= 1000 && lagVal < 10000) {
                lagClass = @"text-right text-mono text-warning";
            } else if (lagVal >= 10000) {
                lagClass = @"text-right text-mono text-destructive";
            }

            double tput = throughputValue ? [throughputValue doubleValue] : 0.0;
            NSString *throughputDisplay = (throughputValue && tput > 0.05)
                ? [NSString stringWithFormat:@"%.1f events/s", tput]
                : (throughputValue ? @"0.0 events/s" : @"—");

            [rows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:url className:@"text-mono text-sm"],
                [GZHTML tableCellWithHTML:[GZHTML connectionBadge:status] className:nil],
                [GZHTML tableCellWithText:lagDisplay className:lagClass],
                [GZHTML tableCellWithText:throughputDisplay className:@"text-right text-mono"],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Relay", @"Status",
                                                      @{@"text": @"Lag", @"className": @"text-right"},
                                                      @{@"text": @"Throughput", @"className": @"text-right"}]
                                           htmlRows:rows
                                      emptyMessage:@"No relays configured."]];
    }
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Event Counters"]];
    [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Metric", @{@"text": @"Value", @"className": @"text-right"}]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Events" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"events"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Commits" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"commits"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Deletes" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"deletes"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Operations" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"ops"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Identities" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"identities"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Records indexed" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"recordsIndexed"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Records deleted" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"recordsDeleted"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Errors" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"errors"] ?: @0] className:@"text-right text-mono text-destructive"],
        ]],
    ]
                                  emptyMessage:@"No event counters."]]];
    [html appendString:@"</section>"];

    if (recentErrors.count > 0) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Recent Errors"]];
        NSMutableArray *errorRows = [NSMutableArray arrayWithCapacity:recentErrors.count];
        for (NSDictionary *error in recentErrors) {
            NSString *timestamp = error[@"timestamp"] ?: @"—";
            NSString *relayURL = error[@"relay_url"] ?: @"—";
            NSString *did = error[@"did"] ?: @"—";
            NSString *seq = error[@"seq"] ? [error[@"seq"] stringValue] : @"—";
            NSString *message = error[@"error_message"] ?: @"Unknown error";
            [errorRows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:timestamp className:@"text-mono"],
                [GZHTML tableCellWithText:relayURL className:@"text-mono text-sm"],
                [GZHTML tableCellWithText:did className:@"text-mono text-sm"],
                [GZHTML tableCellWithText:seq className:@"text-right text-mono"],
                [GZHTML tableCellWithText:message className:nil],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Time", @"Relay", @"DID",
                                                      @{@"text": @"Seq", @"className": @"text-right"},
                                                      @"Error"]
                                           htmlRows:errorRows
                                      emptyMessage:@"No recent errors."]];
        [html appendString:@"</section>"];
    }

    return html;
}

+ (NSString *)indexesHTML:(NSDictionary *)snapshot {
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *topCollections = snapshot[@"topCollections"] ?: @{};

    NSMutableString *html = [NSMutableString string];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Index Families"]];
    NSMutableArray *familyRows = [NSMutableArray array];
    NSArray *families = @[@"backlinks", @"records", @"identities", @"manyToMany"];
    for (NSString *family in families) {
        NSDictionary *familyData = indexes[family] ?: @{};
        NSString *countKey = [family isEqualToString:@"backlinks"] || [family isEqualToString:@"manyToMany"] ? @"approxEdges" : @"approxCount";
        NSNumber *count = familyData[countKey] ?: @0;
        NSString *description = familyData[@"description"] ?: @"";
        [familyRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:[self humanReadableFamily:family] className:nil],
            [GZHTML tableCellWithText:[count description] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:description className:@"text-secondary text-sm"],
        ]]];
    }
    [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Family",
                                                  @{@"text": @"Approx. count", @"className": @"text-right"},
                                                  @"Description"]
                                       htmlRows:familyRows
                                  emptyMessage:@"No index families."]]];
    [html appendString:@"</section>"];

    if (topCollections.count > 0) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Top Collections by Record Count"]];
        [html appendString:@"<p class=\"text-secondary text-sm mb-md\">Click a collection to page through live index rows below.</p>"];
        NSArray *sortedCollections = [topCollections keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
            return [obj2 compare:obj1];
        }];
        NSMutableArray *collectionRows = [NSMutableArray arrayWithCapacity:sortedCollections.count];
        for (NSString *collection in sortedCollections) {
            NSNumber *count = topCollections[collection];
            NSString *encoded = [self percentEncodedQueryValue:collection];
            NSString *openBtn = [NSString stringWithFormat:
                @"<a href=\"#\" class=\"explore-uri-link text-mono\" "
                @"hx-get=\"/admin/partials/mikrus-explore-results?collection=%@\" "
                @"hx-target=\"#mikrus-indexes-explore-results\" "
                @"hx-swap=\"innerHTML\">%@</a>",
                encoded, [GZHTML escapedString:collection]];
            [collectionRows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithHTML:openBtn className:nil],
                [GZHTML tableCellWithText:[count description] className:@"text-right text-mono"],
            ]]];
        }
        [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Collection", @{@"text": @"Records", @"className": @"text-right"}]
                                           htmlRows:collectionRows
                                      emptyMessage:@"No collections."]]];
        [html appendString:@"</section>"];
    }

    [html appendString:@"<div id=\"mikrus-indexes-explore-results\" data-mikrus-explore-results class=\"mt-md\" hx-preserve></div>"];

    int64_t totalQueries = [queries[@"backlink"] longLongValue] + [queries[@"manyToMany"] longLongValue]
                         + [queries[@"identity"] longLongValue] + [queries[@"record"] longLongValue];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Query Activity"]];
    [html appendFormat:@"<p class=\"text-secondary mb-md\">Total <span class=\"text-mono\">%lld</span> queries since process start.</p>",
     (long long)totalQueries];

    NSArray *queryFamilies = @[@"backlink", @"manyToMany", @"identity", @"record"];
    NSArray *queryNames = @[@"Backlinks", @"Many-to-Many", @"Identity Lookups", @"Record Lookups"];
    NSMutableArray *queryRows = [NSMutableArray arrayWithCapacity:queryFamilies.count];
    for (NSUInteger i = 0; i < queryFamilies.count; i++) {
        NSString *family = queryFamilies[i];
        NSString *name = queryNames[i];
        int64_t count = [queries[family] longLongValue];
        double percentage = totalQueries > 0 ? (100.0 * count / totalQueries) : 0.0;
        [queryRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:name className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%lld", (long long)count] className:@"text-right text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%.1f%%", percentage] className:@"text-right text-mono"],
        ]]];
    }
    [html appendString:[self wrappedTable:[GZHTML tableWithHeaders:@[@"Query family",
                                                  @{@"text": @"Requests", @"className": @"text-right"},
                                                  @{@"text": @"Share", @"className": @"text-right"}]
                                       htmlRows:queryRows
                                  emptyMessage:@"No query activity."]]];
    [html appendString:@"</section>"];

    return html;
}

+ (NSString *)humanReadableFamily:(NSString *)family {
    if ([family isEqualToString:@"backlinks"]) return @"Backlinks";
    if ([family isEqualToString:@"records"]) return @"Records";
    if ([family isEqualToString:@"identities"]) return @"Identities";
    if ([family isEqualToString:@"manyToMany"]) return @"Many-to-Many";
    return family;
}

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"destructive" message:@"Mikrus dashboard is unavailable — embedded listener required."];
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
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-explore" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:snapshot ? [self exploreShellHTML] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-explore-results" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:snapshot ? [self exploreResultsHTMLForRequest:req snapshot:snapshot] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-explore-record" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *uri = [req queryParamForKey:@"uri"] ?: @"";
        [res setBodyString:snapshot ? [self recordDetailHTML:[snapshot recordDetailForURI:uri]] : [self errorUnavailableHTML]];
    }];
}

@end
