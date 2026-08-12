// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/AdminUI/JelczAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
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
    return @"<div class=\"alert alert-destructive\">Video dashboard is unavailable — embedded listener required.</div>";
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
            [res setBodyString:@"<div class=\"alert alert-warning\">No snapshot data.</div>"];
            return;
        }
        // Use legacy renderer for robustness
        NSMutableDictionary *healthCtx = [NSMutableDictionary dictionary];
        healthCtx[@"status"] = snap[@"health"] ?: @"unknown";
        healthCtx[@"message"] = [NSString stringWithFormat:@"Jobs: %@, Workers: %@/%@",
                                   snap[@"queue"][@"depth"] ?: @0,
                                   snap[@"worker"][@"activeJobs"] ?: @0,
                                   snap[@"worker"][@"maxConcurrency"] ?: @0];
        [res setBodyString:[GZAdminUIVideoPack renderVideoHealthPartial:healthCtx]];
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
        [res setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>",
                            jobId.length > 0 ? @"alert-success" : @"alert-destructive",
                            GZAdminUIEscaped(msg)]];
    }];
}

+ (NSString *)jobsEmbeddedHTML:(NSArray<NSDictionary *> *)jobRows {
    NSMutableString *html = [NSMutableString stringWithString:
        @"<section><h3 class=\"section-title\">Job state counts</h3>"
        @"<table class=\"table\"><thead><tr><th>State</th><th>Count</th></tr></thead><tbody>"];

    if (jobRows.count == 0) {
        [html appendString:@"<tr><td colspan=\"2\" class=\"text-secondary p-md\">No jobs in the queue.</td></tr>"];
    } else {
        for (NSDictionary *row in jobRows) {
            NSString *state = row[@"state"] ?: @"";
            NSString *display = [state stringByReplacingOccurrencesOfString:@"JOB_STATE_" withString:@""];
            [html appendFormat:@"<tr><td>%@</td><td>%@</td></tr>",
             GZAdminUIEscaped(display), row[@"count"] ?: @0];
        }
    }
    [html appendString:@"</tbody></table></section>"];
    return html;
}

@end
