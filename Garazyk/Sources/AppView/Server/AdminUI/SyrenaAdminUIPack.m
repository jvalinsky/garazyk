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
        @{ @"tabIdentifier": @"appview-serving",  @"displayName": @"Serving" },
        @{ @"tabIdentifier": @"appview-firehose", @"displayName": @"Firehose" },
        @{ @"tabIdentifier": @"appview-reposync", @"displayName": @"Repo sync" },
        @{ @"tabIdentifier": @"appview-coverage", @"displayName": @"Coverage" },
    ];
}

#pragma mark - Helpers

+ (NSString *)laneBadge:(NSString *)lane {
    NSString *label = lane ?: @"unknown";
    NSString *cls = @"badge badge-secondary";
    if ([lane isEqualToString:@"ok"] || [lane isEqualToString:@"active"]) {
        cls = @"badge badge-success";
    } else if ([lane isEqualToString:@"warn"] || [lane isEqualToString:@"idle"]) {
        cls = @"badge badge-warning";
    } else if ([lane isEqualToString:@"down"]) {
        cls = @"badge badge-destructive";
    }
    return [GZHTML badgeWithClass:cls text:[label uppercaseString]];
}

+ (NSString *)lanesStripHTML:(NSDictionary *)snapshot {
    NSDictionary *lanes = snapshot[@"lanes"] ?: @{};
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Pipeline"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Firehose", @"html": [self laneBadge:lanes[@"firehose"]]},
        @{@"label": @"Repo sync", @"html": [self laneBadge:lanes[@"sync"]]},
        @{@"label": @"Serving", @"html": [self laneBadge:lanes[@"serving"]]},
    ]]];
    return html;
}

+ (NSString *)statusBadgeForRepo:(NSString *)status {
    NSString *s = status ?: @"";
    NSString *cls = @"badge badge-secondary";
    if ([s isEqualToString:@"synced"]) cls = @"badge badge-success";
    else if ([s isEqualToString:@"processing"]) cls = @"badge badge-success";
    else if ([s isEqualToString:@"dirty"]) cls = @"badge badge-warning";
    else if ([s isEqualToString:@"pending"]) cls = @"badge badge-secondary";
    return [GZHTML badgeWithClass:cls text:s.length ? s : @"unknown"];
}

+ (NSUInteger)entryCountInQueue:(NSDictionary *)queue {
    id entries = queue[@"entries"];
    return [entries isKindOfClass:[NSArray class]] ? [entries count] : 0;
}

+ (NSDictionary *)preferredQueueFromSnapshot:(GZSyrenaAdminSnapshot *)snapshot {
    NSDictionary *queue = [snapshot queueWithStatus:@"dirty" limit:25 cursor:nil];
    if ([self entryCountInQueue:queue] == 0) {
        queue = [snapshot queueWithStatus:@"pending" limit:25 cursor:nil];
    }
    if ([self entryCountInQueue:queue] == 0) {
        queue = [snapshot queueWithStatus:@"all" limit:25 cursor:nil];
    }
    return queue ?: @{@"entries": @[], @"enabled": @NO};
}

#pragma mark - HTML renderers

+ (NSString *)servingHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSDictionary *backfill = snapshot[@"backfill"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *exceptions = snapshot[@"exceptions"] ?: @{};
    NSDictionary *coverage = snapshot[@"coverage"] ?: @{};
    NSDictionary *db = snapshot[@"database"] ?: @{};
    BOOL running = [ingest[@"running"] boolValue];

    NSMutableString *html = [NSMutableString string];
    [html appendString:[self lanesStripHTML:snapshot]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Serving health"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Health", @"html": [GZHTML healthBadge:snapshot[@"health"]]},
        @{@"label": @"Uptime", @"html": [GZHTML monoValue:[GZHTML formatUptime:[snapshot[@"uptimeSeconds"] longLongValue]]]},
        @{@"label": @"Ingest", @"html": [GZHTML connectionBadge:running ? @"running" : @"stopped"]},
        @{@"label": @"Queries / errors", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            queries[@"total"] ?: @0, queries[@"errors"] ?: @0]]},
        @{@"label": @"Rate-limit rejects", @"html": [GZHTML monoValue:snapshot[@"rateLimitRejects"]]},
        @{@"label": @"Backfill queue", @"html": [GZHTML monoValue:backfill[@"queueDepth"]]},
        @{@"label": @"Handles / posts", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            coverage[@"handles"] ?: @0, coverage[@"posts"] ?: @0]]},
        @{@"label": @"Storage", @"html": [GZHTML monoValue:[GZHTML formatMegabytes:[db[@"storageBytes"] longLongValue]]]},
    ]]];
    [html appendString:@"</section>"];

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

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Exceptions"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Validation dead letters", @"html": [GZHTML monoValue:exceptions[@"deadLetter"]]},
        @{@"label": @"Hook dead letters", @"html": [GZHTML monoValue:exceptions[@"hookDeadLetter"]]},
        @{@"label": @"Pending index events", @"html": [GZHTML monoValue:exceptions[@"pendingIndex"]]},
    ]]];
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)firehoseHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSArray *relayURLs = snapshot[@"config"][@"relayURLs"] ?: @[];
    NSDictionary *relayHealth = ingest[@"relayHealth"] ?: @{};
    NSDictionary *lagByRelay = ingest[@"lagByRelay"] ?: @{};
    NSDictionary *throughput = ingest[@"throughput"] ?: @{};

    NSMutableString *html = [NSMutableString string];
    [html appendString:[self lanesStripHTML:snapshot]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Relay health"]];
    NSMutableArray *relayRows = [NSMutableArray arrayWithCapacity:relayURLs.count];
    for (NSString *url in relayURLs) {
        NSString *status = relayHealth[url] ?: @"unknown";
        NSNumber *lagValue = lagByRelay[url];
        NSNumber *tput = throughput[url];
        NSString *lagDisplay = lagValue ? [lagValue description] : @"—";
        NSString *tputDisplay = tput ? [NSString stringWithFormat:@"%.2f", [tput doubleValue]] : @"—";
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

+ (NSString *)queueTableHTML:(NSDictionary *)queue {
    NSArray *entries = [queue[@"entries"] isKindOfClass:[NSArray class]] ? queue[@"entries"] : @[];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *did = [entry[@"did"] isKindOfClass:[NSString class]] ? entry[@"did"] : @"";
        NSString *status = [entry[@"status"] isKindOfClass:[NSString class]] ? entry[@"status"] : @"";
        NSString *err = [entry[@"last_error"] isKindOfClass:[NSString class]] ? entry[@"last_error"] : @"";
        if (err.length > 80) err = [[err substringToIndex:80] stringByAppendingString:@"…"];
        NSString *actions = [NSString stringWithFormat:@"%@ %@",
            [GZHTML buttonWithClass:@"btn btn-sm btn-primary" text:@"Retry" action:@"appview-retry-repo" data:@{@"ui-did": did}],
            [GZHTML buttonWithClass:@"btn btn-secondary btn-sm" text:@"Cancel" action:@"appview-cancel-repo" data:@{@"ui-did": did}]];
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:did className:@"text-mono text-xs"],
            [GZHTML tableCellWithHTML:[self statusBadgeForRepo:status] className:nil],
            [GZHTML tableCellWithText:err.length ? err : @"—" className:@"text-sm text-secondary"],
            [GZHTML tableCellWithHTML:actions className:nil],
        ]]];
    }
    return [GZHTML tableWithHeaders:@[@"DID", @"Status", @"Last error", @"Actions"]
                           htmlRows:rows.count > 0 ? rows : nil
                      emptyMessage:@"Queue is empty for this filter."];
}

+ (NSString *)repoSyncHTML:(NSDictionary *)snapshot queue:(NSDictionary *)queue {
    NSDictionary *backfill = snapshot[@"backfill"] ?: @{};
    BOOL enabled = [backfill[@"enabled"] boolValue];

    NSMutableString *html = [NSMutableString string];
    [html appendString:[self lanesStripHTML:snapshot]];
    [html appendString:@"<div id=\"appview-result\" aria-live=\"polite\"></div>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Repo sync funnel"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Enabled", @"value": enabled ? @"yes" : @"no"},
        @{@"label": @"Queue depth", @"html": [GZHTML monoValue:backfill[@"queueDepth"]]},
        @{@"label": @"Active workers", @"html": [GZHTML monoValue:backfill[@"activeWorkers"]]},
        @{@"label": @"Pending", @"html": [GZHTML monoValue:backfill[@"repoPending"]]},
        @{@"label": @"Processing", @"html": [GZHTML monoValue:backfill[@"repoProcessing"]]},
        @{@"label": @"Synced", @"html": [GZHTML monoValue:backfill[@"repoSynced"]]},
        @{@"label": @"Dirty", @"html": [GZHTML monoValue:backfill[@"repoDirty"]]},
        @{@"label": @"Session completed / failed", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            backfill[@"completed"] ?: @0, backfill[@"failed"] ?: @0]]},
    ]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Actions"]];
    [html appendString:[GZHTML buttonWithClass:@"btn btn-secondary btn-sm" text:@"Rebuild scope"
                                        action:@"rebuild-appview-scope" data:nil]];
    [html appendString:@"<form class=\"form mt-md\" data-ui-form=\"enqueue-backfill\">"];
    [html appendString:@"<div class=\"form-group\">"];
    [html appendString:@"<label for=\"enqueue-dids-input\">Enqueue DIDs (one per line)</label>"];
    [html appendString:@"<textarea id=\"enqueue-dids-input\" class=\"form-input\" rows=\"3\" "
         "placeholder=\"did:plc:…\"></textarea>"];
    [html appendString:@"</div>"];
    [html appendString:@"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Enqueue</button>"];
    [html appendString:@"</form>"];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\" id=\"appview-queue\">"];
    [html appendString:[GZHTML sectionTitle:@"Queue (dirty / pending first)"]];
    if (!enabled) {
        [html appendString:[GZHTML alertWithType:@"warning" message:@"Backfill orchestrator is not running."]];
    }
    [html appendString:[self queueTableHTML:queue]];
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)coverageHTML:(NSDictionary *)snapshot {
    NSDictionary *coverage = snapshot[@"coverage"] ?: @{};
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    NSArray *collections = indexes[@"collections"] ?: @[];
    NSDictionary *lexicons = snapshot[@"lexicons"] ?: @{};
    NSDictionary *exceptions = snapshot[@"exceptions"] ?: @{};

    NSMutableString *html = [NSMutableString string];
    [html appendString:[self lanesStripHTML:snapshot]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Social coverage"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Resolved handles", @"html": [GZHTML monoValue:coverage[@"handles"]]},
        @{@"label": @"Profile records", @"html": [GZHTML monoValue:coverage[@"profiles"]]},
        @{@"label": @"Post records", @"html": [GZHTML monoValue:coverage[@"posts"]]},
        @{@"label": @"Repos synced / total", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            coverage[@"reposSynced"] ?: @0, coverage[@"reposTotal"] ?: @0]]},
        @{@"label": @"Pending index backlog", @"html": [GZHTML monoValue:exceptions[@"pendingIndex"]]},
        @{@"label": @"Filtered lexicons", @"html": [GZHTML monoValue:lexicons[@"count"]]},
    ]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendFormat:@"%@%@", [GZHTML sectionTitle:@"Indexed collections"],
     [NSString stringWithFormat:@"<p class=\"text-secondary text-sm mb-md\">%lu collections — likes-heavy mixes often mean empty author feeds</p>",
      (unsigned long)collections.count]];
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
    return html;
}

+ (NSString *)overviewHTML:(NSDictionary *)snapshot { return [self servingHTML:snapshot]; }
+ (NSString *)ingestionHTML:(NSDictionary *)snapshot { return [self firehoseHTML:snapshot]; }
+ (NSString *)backfillHTML:(NSDictionary *)snapshot {
    return [self repoSyncHTML:snapshot queue:@{@"entries": @[], @"enabled": snapshot[@"backfill"][@"enabled"] ?: @NO}];
}
+ (NSString *)indexesHTML:(NSDictionary *)snapshot { return [self coverageHTML:snapshot]; }

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"destructive" message:@"AppView dashboard is unavailable — embedded listener required."];
}

+ (NSString *)actionResultHTML:(NSDictionary *)result successFallback:(NSString *)fallback {
    if (result[@"error"]) {
        NSString *msg = result[@"message"] ?: result[@"error"];
        return [GZHTML alertWithType:@"destructive" message:msg];
    }
    NSString *msg = result[@"message"];
    if (!msg && result[@"enqueued"]) {
        msg = [NSString stringWithFormat:@"Enqueued %@ DID(s).", result[@"enqueued"]];
    }
    if (!msg) msg = fallback;
    return [GZHTML alertWithType:@"success" message:msg];
}

#pragma mark - Route registration

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    __weak GZAdminUIHost *weakHost = host;

    GZSyrenaAdminSnapshot *(^snap)(void) = ^{
        GZSyrenaAdminSnapshot *s = nil;
        @synchronized(self) { s = [[self snapshots] objectForKey:weakHost]; }
        return s;
    };

    void (^getPartial)(NSString *, NSString *(^)(GZSyrenaAdminSnapshot *)) =
    ^(NSString *path, NSString *(^render)(GZSyrenaAdminSnapshot *)) {
        [host.httpServer addRoute:@"GET" path:path handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
            AUTH_GUARD(weakHost, req, res);
            res.contentType = @"text/html; charset=utf-8";
            GZSyrenaAdminSnapshot *snapshot = snap();
            [res setBodyString:snapshot ? render(snapshot) : [self errorUnavailableHTML]];
        }];
    };

    getPartial(@"/admin/partials/appview-serving", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self servingHTML:[s snapshot]];
    });
    getPartial(@"/admin/partials/appview-firehose", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self firehoseHTML:[s snapshot]];
    });
    getPartial(@"/admin/partials/appview-reposync", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self repoSyncHTML:[s snapshot] queue:[self preferredQueueFromSnapshot:s]];
    });
    getPartial(@"/admin/partials/appview-coverage", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self coverageHTML:[s snapshot]];
    });

    // HTMX refresh target used by admin-ui.js after retry/cancel.
    getPartial(@"/admin/partials/appview-queue", ^NSString *(GZSyrenaAdminSnapshot *s) {
        NSMutableString *html = [NSMutableString string];
        [html appendString:[GZHTML sectionTitle:@"Queue (dirty / pending first)"]];
        [html appendString:[self queueTableHTML:[self preferredQueueFromSnapshot:s]]];
        return html;
    });

    // Compatibility aliases for older bookmarks / tests.
    getPartial(@"/admin/partials/appview-metrics", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self servingHTML:[s snapshot]];
    });
    getPartial(@"/admin/partials/ingest-health", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self firehoseHTML:[s snapshot]];
    });
    getPartial(@"/admin/partials/appview-backfill", ^NSString *(GZSyrenaAdminSnapshot *s) {
        NSDictionary *queue = [s queueWithStatus:@"all" limit:25 cursor:nil];
        return [self repoSyncHTML:[s snapshot] queue:queue];
    });
    getPartial(@"/admin/partials/appview-indexes", ^NSString *(GZSyrenaAdminSnapshot *s) {
        return [self coverageHTML:[s snapshot]];
    });

    void (^postAction)(NSString *, NSDictionary *(^)(GZSyrenaAdminSnapshot *, ATProtoHttpRequest *)) =
    ^(NSString *path, NSDictionary *(^handler)(GZSyrenaAdminSnapshot *, ATProtoHttpRequest *)) {
        [host.httpServer addRoute:@"POST" path:path handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
            AUTH_GUARD(weakHost, req, res);
            res.contentType = @"text/html; charset=utf-8";
            GZSyrenaAdminSnapshot *snapshot = snap();
            if (!snapshot) {
                [res setBodyString:[self errorUnavailableHTML]];
                return;
            }
            NSDictionary *result = handler(snapshot, req);
            NSString *fallback = @"OK";
            if ([path containsString:@"enqueue"]) fallback = @"Enqueue requested.";
            else if ([path containsString:@"retry"]) fallback = @"Retry enqueued.";
            else if ([path containsString:@"cancel"]) fallback = @"Cancel requested.";
            else if ([path containsString:@"rebuild"]) fallback = @"Rebuild triggered.";
            res.statusCode = result[@"error"] ? 400 : 200;
            [res setBodyString:[self actionResultHTML:result successFallback:fallback]];
        }];
    };

    postAction(@"/admin/actions/appview-enqueue-dids", ^NSDictionary *(GZSyrenaAdminSnapshot *s, ATProtoHttpRequest *req) {
        NSArray *dids = [req.jsonBody[@"dids"] isKindOfClass:[NSArray class]] ? req.jsonBody[@"dids"] : @[];
        return [s enqueueDIDs:dids];
    });
    postAction(@"/admin/actions/appview-retry-repo", ^NSDictionary *(GZSyrenaAdminSnapshot *s, ATProtoHttpRequest *req) {
        NSString *did = [req.jsonBody[@"did"] isKindOfClass:[NSString class]] ? req.jsonBody[@"did"] : @"";
        return [s retryDID:did];
    });
    postAction(@"/admin/actions/appview-cancel-repo", ^NSDictionary *(GZSyrenaAdminSnapshot *s, ATProtoHttpRequest *req) {
        NSString *did = [req.jsonBody[@"did"] isKindOfClass:[NSString class]] ? req.jsonBody[@"did"] : @"";
        return [s cancelDID:did];
    });
    postAction(@"/admin/actions/appview-rebuild-scope", ^NSDictionary *(GZSyrenaAdminSnapshot *s, ATProtoHttpRequest *req) {
        (void)req;
        return [s rebuildScope];
    });
}

@end
