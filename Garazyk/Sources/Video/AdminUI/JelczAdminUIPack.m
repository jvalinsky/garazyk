// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/AdminUI/JelczAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
#import "AdminUIServer/Packs/JelczAdminSnapshot.h"
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation JelczAdminUIPack

+ (NSMapTable<GZAdminUIHost *, JelczAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, JelczAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(JelczAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"video"; }
+ (NSString *)displayName { return @"Video"; }

+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[
        @{ @"tabIdentifier": @"video-metrics",  @"displayName": @"Overview" },
        @{ @"tabIdentifier": @"video-jobs",     @"displayName": @"Jobs" },
        @{ @"tabIdentifier": @"video-capacity", @"displayName": @"Capacity" },
    ];
}

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"destructive" message:@"Video dashboard is unavailable — embedded listener required."];
}

#pragma mark - Route registration

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    JelczAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;

    // Overview
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-metrics" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
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

    // Jobs (delegates to centralized pack's renderer for consistency)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-jobs" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        if (snapshot) {
            NSDictionary *counts = snapshot.countsByState ?: @{};
            NSMutableArray *jobRows = [NSMutableArray array];
            NSArray *stateOrder = @[@"JOB_STATE_PENDING", @"JOB_STATE_PROCESSING",
                                     @"JOB_STATE_TRANSCODING", @"JOB_STATE_GENERATING_THUMBNAIL",
                                     @"JOB_STATE_COMPLETED", @"JOB_STATE_FAILED"];
            for (NSString *state in stateOrder) {
                NSNumber *count = counts[state] ?: @0;
                if (count.integerValue > 0) {
                    [jobRows addObject:@{@"state": state, @"count": count}];
                }
            }
            [res setBodyString:[self jobsEmbeddedHTML:jobRows]];
        } else {
            [res setBodyString:[self errorUnavailableHTML]];
        }
    }];

    // Capacity
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/video-capacity" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        if (snapshot) {
            [res setBodyString:[GZAdminUIVideoPack renderVideoCapacityPartial:snapshot.snapshot]];
        } else {
            [res setBodyString:[self errorUnavailableHTML]];
        }
    }];

    // Retry action (same as centralized)
    [host.httpServer addRoute:@"POST" path:@"/admin/actions/video-retry-job" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *jobId = [req.jsonBody[@"jobId"] isKindOfClass:[NSString class]] ? req.jsonBody[@"jobId"] : @"";
        NSString *msg = jobId.length > 0 ? @"Job queued for retry (embedded — direct access)."
                                         : @"Job ID required.";
        [res setBodyString:[GZHTML alertWithType:jobId.length > 0 ? @"success" : @"destructive" message:msg]];
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
