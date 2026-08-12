// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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

    NSString *health = snapshot[@"health"] ?: @"unknown";
    NSString *pdsHealth = snapshot[@"pdsUploadHealth"] ?: @"unknown";
    id activeJobs = worker[@"activeJobs"] ?: @0;
    id maxConcurrency = worker[@"maxConcurrency"] ?: @0;
    id depth = queue[@"depth"] ?: @0;
    NSString *oldest = [self formatSeconds:queue[@"oldestAgeSeconds"]];
    id completed24h = throughput[@"completed24h"] ?: @0;
    id failed24h = throughput[@"failed24h"] ?: @0;
    long long tempMB = [storage[@"tempBytes"] respondsToSelector:@selector(longLongValue)]
        ? [storage[@"tempBytes"] longLongValue] / (1024 * 1024) : 0;
    long long outMB = [storage[@"outputBytes"] respondsToSelector:@selector(longLongValue)]
        ? [storage[@"outputBytes"] longLongValue] / (1024 * 1024) : 0;

    NSMutableArray *healthFields = [NSMutableArray arrayWithArray:@[
        @{@"label": @"Health", @"html": [GZHTML healthBadge:health]},
    ]];
    if (snapshot[@"uptimeSeconds"]) {
        [healthFields addObject:@{@"label": @"Uptime", @"html": [GZHTML monoValue:[GZHTML formatUptime:[snapshot[@"uptimeSeconds"] longLongValue]]]}];
    }
    [healthFields addObjectsFromArray:@[
        @{@"label": @"Active / Capacity", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@", activeJobs, maxConcurrency]]},
        @{@"label": @"Queue depth", @"html": [GZHTML monoValue:depth]},
        @{@"label": @"Oldest job", @"html": [GZHTML monoValue:oldest]},
        @{@"label": @"Completed / Failed (24h)", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@", completed24h, failed24h]]},
        @{@"label": @"PDS upload", @"html": [GZHTML healthBadge:pdsHealth]},
        @{@"label": @"Storage backend", @"value": storage[@"backend"] ?: @"—"},
        @{@"label": @"Temp / Output", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%lld MB / %lld MB", tempMB, outMB]]},
    ]];

    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Service Health"]];
    [html appendString:[GZHTML detailCardWithFields:healthFields]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Queue breakdown"]];
    NSArray *stateOrder = @[
        @[@"Pending", @"JOB_STATE_PENDING"],
        @[@"Processing", @"JOB_STATE_PROCESSING"],
        @[@"Transcoding", @"JOB_STATE_TRANSCODING"],
        @[@"Thumbnail", @"JOB_STATE_GENERATING_THUMBNAIL"],
        @[@"Completed", @"JOB_STATE_COMPLETED"],
        @[@"Failed", @"JOB_STATE_FAILED"],
    ];
    NSMutableArray *stateRows = [NSMutableArray arrayWithCapacity:stateOrder.count];
    for (NSArray *pair in stateOrder) {
        [stateRows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:pair[0] className:nil],
            [GZHTML tableCellWithText:[NSString stringWithFormat:@"%@", counts[pair[1]] ?: @0] className:@"text-right text-mono"],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"State", @"Count"]
                                       htmlRows:stateRows
                                  emptyMessage:@"No queue data."]];
    [html appendString:@"</section>"];

    return html;
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

    long long maxUpload = [config[@"maxUploadSize"] respondsToSelector:@selector(longLongValue)]
        ? [config[@"maxUploadSize"] longLongValue] : 0;
    NSString *uploadDisplay = maxUpload > 0 ? [GZHTML formatMegabytes:maxUpload] : @"—";

    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Capacity"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Active workers", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            worker[@"activeJobs"] ?: @0, worker[@"maxConcurrency"] ?: @0]]},
        @{@"label": @"Max upload size", @"html": [GZHTML monoValue:uploadDisplay]},
        @{@"label": @"Max duration", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ s", config[@"maxDuration"] ?: @"—"]]},
        @{@"label": @"Max quality", @"value": config[@"maxQuality"] ?: @"auto"},
        @{@"label": @"HLS variants", @"html": [GZHTML monoValue:config[@"hlsVariants"] ?: @3]},
        @{@"label": @"Storage backend", @"value": storage[@"backend"] ?: @"—"},
    ]]];
    return html;
}

#pragma mark - Quotas (legacy, kept for compat)

+ (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"video-quotas" context:ctx];
}

@end
