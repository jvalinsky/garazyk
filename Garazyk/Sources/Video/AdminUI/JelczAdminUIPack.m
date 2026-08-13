// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/AdminUI/JelczAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
#import "AdminUIServer/Packs/JelczAdminSnapshot.h"
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"
#import "Video/AdminUI/JelczAdminEmbedContext.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZJelczAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZJelczAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, GZJelczAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (NSMapTable<GZAdminUIHost *, GZJelczAdminEmbedContext *> *)embedContexts {
    static NSMapTable<GZAdminUIHost *, GZJelczAdminEmbedContext *> *contexts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contexts = [NSMapTable weakToStrongObjectsMapTable]; });
    return contexts;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZJelczAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (void)configureHost:(GZAdminUIHost *)host embedContext:(GZJelczAdminEmbedContext *)context {
    @synchronized(self) { [[self embedContexts] setObject:context forKey:host]; }
}

+ (GZJelczAdminEmbedContext *)embedContextForHost:(GZAdminUIHost *)host {
    @synchronized(self) { return [[self embedContexts] objectForKey:host]; }
}

+ (GZJelczAdminSnapshot *)snapshotForHost:(GZAdminUIHost *)host {
    GZJelczAdminEmbedContext *context = nil;
    @synchronized(self) { context = [[self embedContexts] objectForKey:host]; }
    if (context) {
        return [[GZJelczAdminSnapshot alloc] initWithWorker:context.worker
                                                 jobStore:context.jobStore
                                                   config:context.config
                                             uptimeSeconds:context.uptimeSeconds];
    }
    @synchronized(self) { return [[self snapshots] objectForKey:host]; }
}

+ (NSString *)packIdentifier { return @"video"; }
+ (NSString *)displayName { return @"Video"; }

+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[
        @{ @"tabIdentifier": @"video-metrics",  @"displayName": @"Overview" },
        @{ @"tabIdentifier": @"video-jobs",     @"displayName": @"Jobs" },
        @{ @"tabIdentifier": @"video-distribution", @"displayName": @"Distribution" },
        @{ @"tabIdentifier": @"video-capacity", @"displayName": @"Capacity" },
    ];
}

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"destructive" message:@"Video dashboard is unavailable — embedded listener required."];
}

#pragma mark - Route registration

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    __weak GZAdminUIHost *weakHost = host;

    // Overview
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-metrics" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        GZJelczAdminSnapshot *snapshot = [GZJelczAdminUIPack snapshotForHost:weakHost];
        if (!snapshot) {
            [res setBodyString:[self errorUnavailableHTML]];
            return;
        }
        NSDictionary *snap = snapshot.snapshot;
        if (!snap) {
            [res setBodyString:[GZHTML alertWithType:@"warning" message:@"No snapshot data."]];
            return;
        }
        // Full overview dashboard with queue breakdown
        [res setBodyString:[GZAdminUIVideoPack renderVideoOverviewPartial:snap]];
    }];

    // Jobs: state summary + recent rows with drill-down detail
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-jobs" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        GZJelczAdminSnapshot *snapshot = [GZJelczAdminUIPack snapshotForHost:weakHost];
        GZJelczAdminEmbedContext *context = [GZJelczAdminUIPack embedContextForHost:weakHost];
        if (!snapshot || !context) {
            [res setBodyString:[self errorUnavailableHTML]];
            return;
        }

        NSMutableString *html = [NSMutableString string];
        NSDictionary *counts = snapshot.countsByState ?: @{};
        NSMutableArray *countRows = [NSMutableArray array];
        NSArray *stateOrder = @[@"JOB_STATE_PENDING", @"JOB_STATE_PROCESSING",
                                 @"JOB_STATE_TRANSCODING", @"JOB_STATE_GENERATING_THUMBNAIL",
                                 @"JOB_STATE_COMPLETED", @"JOB_STATE_FAILED"];
        for (NSString *state in stateOrder) {
            NSNumber *count = counts[state] ?: @0;
            if (count.integerValue > 0) {
                [countRows addObject:@{@"state": state, @"count": count}];
            }
        }
        [html appendString:[self jobsEmbeddedHTML:countRows]];

        // State filter chips (bounded query params only).
        [html appendString:@"<div class=\"search-row mb-md\" role=\"group\" aria-label=\"Filter by job state\">"];
        NSArray *filters = @[
            @[@"All", @""],
            @[@"Pending", @"JOB_STATE_PENDING"],
            @[@"Processing", @"JOB_STATE_PROCESSING"],
            @[@"Completed", @"JOB_STATE_COMPLETED"],
            @[@"Failed", @"JOB_STATE_FAILED"],
        ];
        NSString *stateFilter = [req queryParamForKey:@"state"] ?: @"";
        for (NSArray *pair in filters) {
            NSString *label = pair[0];
            NSString *value = pair[1];
            BOOL active = [stateFilter isEqualToString:value] || (value.length == 0 && stateFilter.length == 0);
            NSString *href = value.length > 0
                ? [NSString stringWithFormat:@"/admin/partials/video-jobs?state=%@", value]
                : @"/admin/partials/video-jobs";
            [html appendFormat:@"<button type=\"button\" class=\"btn btn-sm %@\" hx-get=\"%@\" hx-target=\"closest .admin-partial\" hx-swap=\"innerHTML\">%@</button> ",
             active ? @"btn-primary" : @"btn-secondary", href, label];
        }
        [html appendString:@"</div>"];

        NSArray *jobs = [GZJelczAdminSnapshot recentJobDTOsFromStore:context.jobStore
                                                             limit:25
                                                       stateFilter:stateFilter.length > 0 ? stateFilter : nil];
        [html appendString:[GZHTML sectionTitle:@"Recent jobs"]];
        [html appendString:[GZAdminUIVideoPack renderVideoJobsPartial:@{@"jobs": jobs}]];

        [res setBodyString:html];
    }];

    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-job-detail" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        GZJelczAdminEmbedContext *context = [GZJelczAdminUIPack embedContextForHost:weakHost];
        if (!context) {
            [res setBodyString:[self errorUnavailableHTML]];
            return;
        }
        NSString *jobId = [req queryParamForKey:@"jobId"];
        NSDictionary *dto = [GZJelczAdminSnapshot jobDTOForId:jobId jobStore:context.jobStore];
        if (!dto) {
            [res setBodyString:[GZAdminUIVideoPack renderVideoJobDetailPartial:@{
                @"error": @YES,
                @"message": @"Job not found.",
            }]];
            return;
        }
        NSMutableString *html = [NSMutableString stringWithString:
            [GZAdminUIVideoPack renderVideoJobDetailPartial:@{@"job": dto}]];
        if ([dto[@"state"] isEqualToString:@"JOB_STATE_FAILED"]) {
            [html appendFormat:@"<div class=\"mt-md\"><button class=\"btn btn-primary btn-sm\" data-ui-action=\"retry-video-job\" data-ui-job-id=\"%@\">Retry job</button></div>",
                dto[@"jobId"]];
        }
        [res setBodyString:html];
    }];

    // Capacity
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-capacity" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        GZJelczAdminSnapshot *snapshot = [GZJelczAdminUIPack snapshotForHost:weakHost];
        if (snapshot) {
            [res setBodyString:[GZAdminUIVideoPack renderVideoCapacityPartial:snapshot.snapshot]];
        } else {
            [res setBodyString:[self errorUnavailableHTML]];
        }
    }];

    // Distribution (CA VOD / MUXL / reclaim posture)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-distribution" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        GZJelczAdminSnapshot *snapshot = [GZJelczAdminUIPack snapshotForHost:weakHost];
        if (snapshot) {
            [res setBodyString:[GZAdminUIVideoPack renderVideoDistributionPartial:snapshot.snapshot]];
        } else {
            [res setBodyString:[self errorUnavailableHTML]];
        }
    }];

    [host.httpServer addRoute:@"POST" path:@"/admin/actions/video-retry-job" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *jobId = [req.jsonBody[@"jobId"] isKindOfClass:[NSString class]] ? req.jsonBody[@"jobId"] : @"";
        if (jobId.length == 0) {
            [res setBodyString:[GZHTML alertWithType:@"destructive" message:@"Job ID required."]];
            return;
        }
        GZJelczAdminEmbedContext *context = [GZJelczAdminUIPack embedContextForHost:weakHost];
        id jobStore = context.jobStore;
        SEL retrySel = NSSelectorFromString(@"incrementJobRetry:error:");
        BOOL ok = NO;
        if (jobStore && [jobStore respondsToSelector:retrySel]) {
            NSMethodSignature *sig = [jobStore methodSignatureForSelector:retrySel];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:retrySel];
                [inv setTarget:jobStore];
                NSError *error = nil;
                [inv setArgument:&jobId atIndex:2];
                [inv setArgument:&error atIndex:3];
                [inv invoke];
                [inv getReturnValue:&ok];
            }
        }
        NSString *msg = ok ? @"Job queued for retry." : @"Failed to queue job for retry.";
        [res setBodyString:[GZHTML alertWithType:ok ? @"success" : @"destructive" message:msg]];
    }];
}

+ (NSString *)jobsEmbeddedHTML:(NSArray<NSDictionary *> *)jobRows {
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Job state counts"]];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:jobRows.count];
    for (NSDictionary *row in jobRows) {
        NSString *state = row[@"state"] ?: @"";
        NSString *display = [state stringByReplacingOccurrencesOfString:@"JOB_STATE_" withString:@""];
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:display className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", row[@"count"] ?: @0] className:@"text-right text-mono"],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"State", @"Count"]
                                       htmlRows:rows.count > 0 ? rows : nil
                                  emptyMessage:@"No jobs in the queue."]];
    return html;
}

@end
