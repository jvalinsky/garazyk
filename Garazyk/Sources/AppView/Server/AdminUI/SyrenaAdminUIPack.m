// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppView/Server/AdminUI/SyrenaAdminUIPack.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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
    BOOL running = [ingest[@"running"] boolValue];

    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Service Health"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Health", @"html": [GZHTML healthBadge:snapshot[@"health"]]},
        @{@"label": @"Uptime", @"html": [GZHTML monoValue:[GZHTML formatUptime:[snapshot[@"uptimeSeconds"] longLongValue]]]},
        @{@"label": @"Ingest", @"html": [GZHTML connectionBadge:running ? @"running" : @"stopped"]},
        @{@"label": @"Events / Errors", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            ingest[@"events"] ?: @0, ingest[@"errors"] ?: @0]]},
        @{@"label": @"Commits / Deletes", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            ingest[@"commits"] ?: @0, ingest[@"deletes"] ?: @0]]},
        @{@"label": @"Queries / Errors", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            queries[@"total"] ?: @0, queries[@"errors"] ?: @0]]},
        @{@"label": @"Rate-limit rejects", @"html": [GZHTML monoValue:snapshot[@"rateLimitRejects"]]},
        @{@"label": @"Backfill queue", @"html": [GZHTML monoValue:backfill[@"queueDepth"]]},
        @{@"label": @"Storage", @"html": [GZHTML monoValue:[GZHTML formatMegabytes:[db[@"storageBytes"] longLongValue]]]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Query families"]];
    NSMutableArray *queryRows = [NSMutableArray array];
    for (NSArray *pair in @[
         @[@"Backlink", @"backlink"], @[@"Many-to-many", @"manyToMany"],
         @[@"Identity", @"identity"], @[@"Record", @"record"], @[@"Other", @"other"] ]) {
        [queryRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:pair[0] className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", queries[pair[1]] ?: @0] className:@"text-right text-mono"],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"Family", @"Requests"]
                                       htmlRows:queryRows
                                  emptyMessage:@"No query families."]];
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)ingestionHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSArray *relayURLs = snapshot[@"config"][@"relayURLs"] ?: @[];
    NSDictionary *relayHealth = ingest[@"relayHealth"] ?: @{};
    NSDictionary *lagByRelay = ingest[@"lagByRelay"] ?: @{};
    NSDictionary *throughput = ingest[@"throughput"] ?: @{};

    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Relay health"]];
    NSMutableArray *relayRows = [NSMutableArray arrayWithCapacity:relayURLs.count];
    for (NSString *url in relayURLs) {
        NSString *status = relayHealth[url] ?: @"unknown";
        NSNumber *lagValue = lagByRelay[url];
        NSNumber *tput = throughput[url];
        NSString *lagDisplay = lagValue ? [lagValue description] : @"—";
        NSString *tputDisplay = tput ? [tput description] : @"—";
        [relayRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:url className:@"text-mono text-sm"],
            [GZHTML tableCellWithHTML:[GZHTML connectionBadge:status] className:nil],
            [GZHTML tableCellWithText:lagDisplay className:@"text-right text-mono"],
            [GZHTML tableCellWithText:tputDisplay className:@"text-right text-mono"],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"Relay", @"Status", @"Lag", @"Events/s"]
                                       htmlRows:relayRows.count > 0 ? relayRows : nil
                                  emptyMessage:@"No relays configured."]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Event counters"]];
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
            [GZHTML tableCellWithText:@"Ops (creates/updates)" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"ops"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Identities" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"identities"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Errors" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", ingest[@"errors"] ?: @0] className:@"text-right text-mono"],
        ]],
    ]
                                  emptyMessage:@"No event counters."]];
    [html appendString:@"</section>"];

    return html;
}

+ (NSString *)backfillHTML:(NSDictionary *)snapshot {
    NSDictionary *backfill = snapshot[@"backfill"] ?: @{};
    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Backfill status"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Enabled", @"value": [backfill[@"enabled"] boolValue] ? @"yes" : @"no"},
        @{@"label": @"Queue depth", @"html": [GZHTML monoValue:backfill[@"queueDepth"]]},
        @{@"label": @"Active workers", @"html": [GZHTML monoValue:backfill[@"activeWorkers"]]},
    ]]];

    [html appendString:[GZHTML tableWithHeaders:@[@"Repo state", @"Count"]
                                       htmlRows:@[
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Pending" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"repoPending"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Processing" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"repoProcessing"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Synced" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"repoSynced"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Dirty" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"repoDirty"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Completed (session)" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"completed"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Failed (session)" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"failed"] ?: @0] className:@"text-right text-mono"],
        ]],
        [GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:@"Enqueued (session)" className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", backfill[@"enqueued"] ?: @0] className:@"text-right text-mono"],
        ]],
    ]
                                  emptyMessage:@"No backfill data."]];
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)indexesHTML:(NSDictionary *)snapshot {
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    NSArray *collections = indexes[@"collections"] ?: @[];

    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<section class=\"mt-md\">"];
    [html appendFormat:@"%@%@", [GZHTML sectionTitle:@"Indexed collections"],
     [NSString stringWithFormat:@"<p class=\"text-secondary text-sm mb-md\">%lu collections</p>", (unsigned long)collections.count]];
    NSMutableArray *collectionRows = [NSMutableArray arrayWithCapacity:collections.count];
    for (NSDictionary *col in collections) {
        [collectionRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:col[@"collection"] ?: @"" className:@"text-mono"],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", col[@"count"] ?: @0] className:@"text-right text-mono"],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"Collection", @"Records"]
                                       htmlRows:collectionRows.count > 0 ? collectionRows : nil
                                  emptyMessage:@"No indexed collections."]];
    [html appendString:@"</section>"];

    NSDictionary *lexicons = snapshot[@"lexicons"] ?: @{};
    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Lexicons"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Filtered collections", @"html": [GZHTML monoValue:lexicons[@"count"]]},
    ]]];
    [html appendString:@"</section>"];

    return html;
}

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"destructive" message:@"AppView dashboard is unavailable — embedded listener required."];
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
