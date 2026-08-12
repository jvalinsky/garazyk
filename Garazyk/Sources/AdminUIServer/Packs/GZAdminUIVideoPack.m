// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"
#import "AdminUIServer/Packs/JelczAdminSnapshot.h"
#import "AdminUIServer/Packs/GZAdminUIBackendClient+Video.h"

@implementation GZAdminUIVideoPack

+ (NSString *)packIdentifier {
    return @"video";
}

+ (NSString *)displayName {
    return @"Video";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[
        @{@"tabIdentifier": @"video-metrics",  @"displayName": @"Overview"},
        @{@"tabIdentifier": @"video-jobs",     @"displayName": @"Jobs"},
        @{@"tabIdentifier": @"video-capacity", @"displayName": @"Capacity"},
    ];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerVideoRoutes];
}

#pragma mark - Overview (Slice 1: snapshot)

+ (NSString *)renderVideoOverviewPartial:(NSDictionary *)snapshot {
    NSDictionary *worker = snapshot[@"worker"] ?: @{};
    NSDictionary *queue = snapshot[@"queue"] ?: @{};
    NSDictionary *throughput = snapshot[@"throughput"] ?: @{};
    NSDictionary *storage = snapshot[@"storage"] ?: @{};

    NSDictionary *counts = queue[@"countsByState"] ?: @{};

    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Health</span>"
        @"<span class=\"metric-value status-%@\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Active / Capacity</span>"
        @"<span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Queue depth</span>"
        @"<span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Oldest job</span>"
        @"<span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Completed / Failed (24h)</span>"
        @"<span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">PDS upload</span>"
        @"<span class=\"metric-value status-%@\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Storage backend</span>"
        @"<span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Temp / Output</span>"
        @"<span class=\"metric-value text-sm\">%@ MB / %@ MB</span></div>"
        @"</div>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Queue breakdown</h3>"
        @"<table class=\"table\"><thead><tr>"
        @"<th>Pending</th><th>Processing</th><th>Transcoding</th>"
        @"<th>Thumbnail</th><th>Completed</th><th>Failed</th>"
        @"</tr></thead><tbody><tr>"
        @"<td>%@</td><td>%@</td><td>%@</td><td>%@</td><td>%@</td><td>%@</td>"
        @"</tr></tbody></table></section>",

        // Metric row
        GZAdminUIEscaped(snapshot[@"health"]),
        worker[@"activeJobs"] ?: @0, worker[@"maxConcurrency"] ?: @0,
        queue[@"depth"] ?: @0,
        [self formatSeconds:queue[@"oldestAgeSeconds"]],
        throughput[@"completed24h"] ?: @0, throughput[@"failed24h"] ?: @0,
        GZAdminUIEscaped(snapshot[@"pdsUploadHealth"]),
        GZAdminUIEscaped(storage[@"backend"]),
        @([storage[@"tempBytes"] longLongValue] / (1024 * 1024)),
        @([storage[@"outputBytes"] longLongValue] / (1024 * 1024)),

        // Queue breakdown
        counts[@"JOB_STATE_PENDING"] ?: @0,
        counts[@"JOB_STATE_PROCESSING"] ?: @0,
        counts[@"JOB_STATE_TRANSCODING"] ?: @0,
        counts[@"JOB_STATE_GENERATING_THUMBNAIL"] ?: @0,
        counts[@"JOB_STATE_COMPLETED"] ?: @0,
        counts[@"JOB_STATE_FAILED"] ?: @0
    ];
}

+ (NSString *)formatSeconds:(id)secondsValue {
    NSTimeInterval seconds = [secondsValue respondsToSelector:@selector(doubleValue)]
        ? [secondsValue doubleValue] : 0;
    if (seconds <= 0) return @"—";
    if (seconds < 60) return [NSString stringWithFormat:@"%.0fs", seconds];
    if (seconds < 3600) return [NSString stringWithFormat:@"%.0fm", seconds / 60];
    if (seconds < 86400) return [NSString stringWithFormat:@"%.1fh", seconds / 3600];
    return [NSString stringWithFormat:@"%.1fd", seconds / 86400];
}

#pragma mark - Health (legacy, kept for compat)

+ (NSString *)renderVideoHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"status"] = status;
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    return [GZAdminUITemplateEngine renderTemplate:@"video-health" context:ctx];
}

#pragma mark - Jobs

+ (NSString *)renderVideoJobsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"jobs"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *job in result[@"jobs"]) {
            NSMutableDictionary *mj = [job mutableCopy];
            NSString *state = job[@"state"] ?: @"";
            NSString *badge = @"badge";
            if ([state isEqualToString:@"JOB_STATE_COMPLETED"]) badge = @"badge badge-success";
            else if ([state isEqualToString:@"JOB_STATE_FAILED"]) badge = @"badge badge-destructive";
            mj[@"badgeClass"] = badge;
            [mapped addObject:mj];
        }
        ctx[@"jobs"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"video-jobs" context:ctx];
}

#pragma mark - Job detail (Slice 2: allowlisted DTO)

+ (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";

    if (result[@"job"]) {
        NSSet<NSString *> *allowlist = [JelczAdminSnapshot jobDetailAllowlist];
        NSSet<NSString *> *sensitive = [JelczAdminSnapshot sensitiveKeys];

        NSMutableArray *pairs = [NSMutableArray array];
        NSDictionary *job = result[@"job"];
        for (NSString *key in allowlist) {
            id value = job[key];
            if (value && ![value isKindOfClass:[NSNull class]]) {
                [pairs addObject:@{@"key": key, @"value": [value description]}];
            }
        }
        // Append a redaction note if sensitive keys are present
        BOOL hasRedacted = NO;
        for (NSString *key in sensitive) {
            if (job[key] && ![job[key] isKindOfClass:[NSNull class]]) {
                hasRedacted = YES;
                break;
            }
        }
        if (hasRedacted) {
            [pairs addObject:@{@"key": @"_redacted", @"value": @"Sensitive fields omitted (service tokens, paths, credentials)"}];
        }
        ctx[@"detailPairs"] = pairs;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"video-job-detail" context:ctx];
}

#pragma mark - Capacity

+ (NSString *)renderVideoCapacityPartial:(NSDictionary *)result {
    NSDictionary *config = result[@"config"] ?: @{};
    NSDictionary *storage = result[@"storage"] ?: @{};
    NSDictionary *worker = result[@"worker"] ?: @{};

    return [NSString stringWithFormat:
        @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Active workers</span>"
        @"<span class=\"metric-value\">%@ / %@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Max upload size</span>"
        @"<span class=\"metric-value\">%@ bytes</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Max duration</span>"
        @"<span class=\"metric-value\">%@ s</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Max quality</span>"
        @"<span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">HLS variants</span>"
        @"<span class=\"metric-value\">%@</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Storage backend</span>"
        @"<span class=\"metric-value\">%@</span></div>"
        @"</div>",
        worker[@"activeJobs"] ?: @0, worker[@"maxConcurrency"] ?: @0,
        config[@"maxUploadSize"] ?: @"—",
        config[@"maxDuration"] ?: @"—",
        config[@"maxQuality"] ?: @"auto",
        config[@"hlsVariants"] ?: @3,
        GZAdminUIEscaped(storage[@"backend"])
    ];
}

#pragma mark - Quotas (legacy, kept for compat)

+ (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"video-quotas" context:ctx];
}

@end
