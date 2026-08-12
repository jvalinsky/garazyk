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
    [html appendString:[GZHTML tableWithHeaders:@[@"Metric", @"Value"]
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
                                  emptyMessage:@"No ingest metrics."]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Index Statistics"]];
    [html appendString:[GZHTML tableWithHeaders:@[@"Family", @"Approx. count", @"Notes"]
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
                                  emptyMessage:@"No index statistics."]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Query Performance"]];
    [html appendString:[GZHTML tableWithHeaders:@[@"Family", @"Requests"]
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
                                  emptyMessage:@"No query metrics."]];
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
            NSString *lagDisplay = lagVal == 0 ? @"—" : [NSString stringWithFormat:@"%lld", (long long)lagVal];
            NSString *lagClass = @"text-right text-mono";
            if (lagVal > 0 && lagVal < 1000) {
                lagClass = @"text-right text-mono text-success";
            } else if (lagVal >= 1000 && lagVal < 10000) {
                lagClass = @"text-right text-mono text-warning";
            } else if (lagVal >= 10000) {
                lagClass = @"text-right text-mono text-destructive";
            }

            double tput = throughputValue ? [throughputValue doubleValue] : 0.0;
            NSString *throughputDisplay = tput > 0 ? [NSString stringWithFormat:@"%.1f events/s", tput] : @"—";

            [rows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:url className:@"text-mono text-sm"],
                [GZHTML tableCellWithHTML:[GZHTML connectionBadge:status] className:nil],
                [GZHTML tableCellWithText:lagDisplay className:lagClass],
                [GZHTML tableCellWithText:throughputDisplay className:@"text-right text-mono"],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Relay", @"Status", @"Lag", @"Throughput"]
                                           htmlRows:rows
                                      emptyMessage:@"No relays configured."]];
    }
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Event Counters"]];
    [html appendString:[GZHTML tableWithHeaders:@[@"Metric", @"Value"]
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
                                  emptyMessage:@"No event counters."]];
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
        [html appendString:@"<div class=\"table-scroll\">"];
        [html appendString:[GZHTML tableWithHeaders:@[@"Time", @"Relay", @"DID", @"Seq", @"Error"]
                                           htmlRows:errorRows
                                      emptyMessage:@"No recent errors."]];
        [html appendString:@"</div></section>"];
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
    [html appendString:[GZHTML tableWithHeaders:@[@"Family", @"Approx. count", @"Description"]
                                       htmlRows:familyRows
                                  emptyMessage:@"No index families."]];
    [html appendString:@"</section>"];

    if (topCollections.count > 0) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Top Collections by Record Count"]];
        NSArray *sortedCollections = [topCollections keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
            return [obj2 compare:obj1];
        }];
        NSMutableArray *collectionRows = [NSMutableArray arrayWithCapacity:sortedCollections.count];
        for (NSString *collection in sortedCollections) {
            NSNumber *count = topCollections[collection];
            [collectionRows addObject:[GZHTML tableRowWithHtmlCells:@[
                [GZHTML tableCellWithText:collection className:@"text-mono"],
                [GZHTML tableCellWithText:[count description] className:@"text-right text-mono"],
            ]]];
        }
        [html appendString:[GZHTML tableWithHeaders:@[@"Collection", @"Records"]
                                           htmlRows:collectionRows
                                      emptyMessage:@"No collections."]];
        [html appendString:@"</section>"];
    }

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
    [html appendString:[GZHTML tableWithHeaders:@[@"Query family", @"Requests", @"Share"]
                                       htmlRows:queryRows
                                  emptyMessage:@"No query activity."]];
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
}

@end
