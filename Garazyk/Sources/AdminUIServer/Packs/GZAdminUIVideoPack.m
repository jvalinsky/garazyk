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
    // The admin shell expects a single "video" surface tab.
    return @[@{@"tabIdentifier": @"video", @"displayName": @"Video"}];
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
    NSDictionary *distribution = snapshot[@"distribution"] ?: @{};
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
    [html appendString:[GZHTML sectionTitle:@"Service health"]];
    [html appendString:[GZHTML detailCardWithFields:healthFields]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Distribution posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Mode", @"value": distribution[@"summary"] ?: @"—"},
        @{@"label": @"Watch path", @"html": [GZHTML monoValue:distribution[@"watchMode"] ?: @"—"]},
        @{@"label": @"CA manifest", @"html": [GZHTML healthBadge:[distribution[@"caManifestEnabled"] boolValue] ? @"healthy" : @"unknown"]},
        @{@"label": @"CA store", @"value": [distribution[@"caStoreConfigured"] boolValue] ? @"configured" : @"not configured"},
        @{@"label": @"MUXL packaging", @"value": [distribution[@"muxlPresentationEnabled"] boolValue] ? @"enabled" : @"off"},
        @{@"label": @"Mirror fetch", @"value": [distribution[@"mirrorFetchEnabled"] boolValue]
            ? [NSString stringWithFormat:@"enabled (%@ providers)", distribution[@"mirrorProviderCount"] ?: @0]
            : @"off"},
        @{@"label": @"Streamplace mirror", @"value": [distribution[@"streamplaceMirrorConfigured"] boolValue]
            ? ([distribution[@"streamplaceAttributionDIDConfigured"] boolValue]
               ? @"configured (attribution DID set)"
               : @"base set (attribution DID missing)")
            : @"off"},
        @{@"label": @"Streamplace serve compat", @"value": [distribution[@"streamplaceServeCompat"] boolValue] ? @"on" : @"off"},
        @{@"label": @"CA reclaim sweep", @"value": [distribution[@"sweepEnabled"] boolValue] ? @"enabled" : @"off (orphans retained)"},
    ]]];
    [html appendString:@"</section>"];

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
            else if ([state containsString:@"PROCESSING"] || [state containsString:@"TRANSCOD"]) badge = @"badge badge-warning";
            mj[@"badgeClass"] = badge;
            mj[@"state"] = [state stringByReplacingOccurrencesOfString:@"JOB_STATE_" withString:@""];
            id progress = job[@"progress"];
            mj[@"progressLabel"] = progress ? [NSString stringWithFormat:@"%@%%", progress] : @"—";
            NSString *product = [job[@"product"] isKindOfClass:[NSString class]] ? job[@"product"] : @"—";
            mj[@"product"] = product;
            NSString *productBadge = @"badge";
            if ([product isEqualToString:@"CA VOD"]) productBadge = @"badge badge-success";
            else if ([product isEqualToString:@"MUXL"]) productBadge = @"badge badge-warning";
            mj[@"productBadgeClass"] = productBadge;
            NSString *did = [job[@"did"] isKindOfClass:[NSString class]] ? job[@"did"] : @"";
            if (did.length > 28) {
                mj[@"didShort"] = [[did substringToIndex:20] stringByAppendingString:@"…"];
            } else {
                mj[@"didShort"] = did.length > 0 ? did : @"—";
            }
            [mapped addObject:mj];
        }
        ctx[@"jobs"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"video-jobs" context:ctx];
}

#pragma mark - Job detail (Slice 2: allowlisted DTO)

+ (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        NSMutableDictionary *ctx = [result mutableCopy];
        if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"Job not found.";
        return [GZAdminUITemplateEngine renderTemplate:@"video-job-detail" context:ctx];
    }

    NSDictionary *job = result[@"job"];
    if (![job isKindOfClass:[NSDictionary class]]) {
        return [GZAdminUITemplateEngine renderTemplate:@"video-job-detail" context:@{
            @"error": @YES,
            @"message": @"Job not found.",
        }];
    }

    NSSet<NSString *> *allowlist = [GZJelczAdminSnapshot jobDetailAllowlist];
    NSSet<NSString *> *sensitive = [GZJelczAdminSnapshot sensitiveKeys];
    for (NSString *key in sensitive) {
        if (job[key] && ![job[key] isKindOfClass:[NSNull class]]) {
            // Defensive: DTO builder must already have stripped these.
            NSMutableDictionary *safe = [job mutableCopy];
            [safe removeObjectForKey:key];
            job = safe;
        }
    }

    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<div class=\"mb-lg\"><button type=\"button\" class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/video-jobs\" hx-target=\"closest .admin-partial\" hx-swap=\"innerHTML\">&larr; Back to Jobs</button></div>"];

    NSString *state = [job[@"state"] isKindOfClass:[NSString class]] ? job[@"state"] : @"";
    NSString *stateLabel = [state stringByReplacingOccurrencesOfString:@"JOB_STATE_" withString:@""];
    NSString *product = job[@"product"] ?: @"—";

    [html appendString:[GZHTML sectionTitle:@"Identity"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Job ID", @"html": [GZHTML monoValue:job[@"jobId"] ?: @"—"]},
        @{@"label": @"DID", @"html": [GZHTML monoValue:job[@"did"] ?: @"—"]},
        @{@"label": @"Source blob", @"html": [GZHTML monoValue:job[@"blobCid"] ?: @"—"]},
        @{@"label": @"MIME / size", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            job[@"mimeType"] ?: @"—", job[@"fileSize"] ?: @"—"]]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Pipeline"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"State", @"value": stateLabel.length ? stateLabel : @"—"},
        @{@"label": @"Progress", @"html": [GZHTML monoValue:job[@"progress"] ? [NSString stringWithFormat:@"%@%%", job[@"progress"]] : @"—"]},
        @{@"label": @"Stage", @"value": job[@"stage"] ?: @"—"},
        @{@"label": @"Retries", @"html": [GZHTML monoValue:job[@"retryCount"] ?: @0]},
        @{@"label": @"Created", @"html": [GZHTML monoValue:job[@"createdAt"] ?: @"—"]},
        @{@"label": @"Updated", @"html": [GZHTML monoValue:job[@"updatedAt"] ?: @"—"]},
        @{@"label": @"Dimensions", @"html": [GZHTML monoValue:
            (job[@"width"] && job[@"height"])
                ? [NSString stringWithFormat:@"%@×%@", job[@"width"], job[@"height"]]
                : @"—"]},
        @{@"label": @"Duration", @"html": [GZHTML monoValue:job[@"duration"] ? [NSString stringWithFormat:@"%@ s", job[@"duration"]] : @"—"]},
    ]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Distribution"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Product", @"value": product},
        @{@"label": @"Manifest CID", @"html": [GZHTML monoValue:job[@"manifestBlobCid"] ?: @"—"]},
        @{@"label": @"Processed blob", @"html": [GZHTML monoValue:job[@"processedBlobCid"] ?: @"—"]},
        @{@"label": @"Thumbnail blob", @"html": [GZHTML monoValue:job[@"thumbnailBlobCid"] ?: @"—"]},
        @{@"label": @"Bao / outboard", @"value": job[@"hasProofHint"] ?: @"—"},
    ]]];
    [html appendString:@"</section>"];

    if (job[@"errorCategory"]) {
        [html appendString:@"<section class=\"mt-md\">"];
        [html appendString:[GZHTML sectionTitle:@"Failure"]];
        [html appendString:[GZHTML detailCardWithFields:@[
            @{@"label": @"Category", @"value": job[@"errorCategory"]},
        ]]];
        [html appendString:@"</section>"];
    }

    // Ensure only allowlisted keys were considered above (documentation pin).
    (void)allowlist;

    return html;
}

#pragma mark - Capacity

+ (NSString *)renderVideoCapacityPartial:(NSDictionary *)result {
    NSDictionary *config = result[@"config"] ?: @{};
    NSDictionary *storage = result[@"storage"] ?: @{};
    NSDictionary *worker = result[@"worker"] ?: @{};
    NSDictionary *distribution = result[@"distribution"] ?: @{};

    long long maxUpload = [config[@"maxUploadSize"] respondsToSelector:@selector(longLongValue)]
        ? [config[@"maxUploadSize"] longLongValue] : 0;
    NSString *uploadDisplay = maxUpload > 0 ? [GZHTML formatMegabytes:maxUpload] : @"—";

    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Worker capacity"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Active workers", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@",
            worker[@"activeJobs"] ?: @0, worker[@"maxConcurrency"] ?: @0]]},
        @{@"label": @"Max upload size", @"html": [GZHTML monoValue:uploadDisplay]},
        @{@"label": @"Max duration", @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ s", config[@"maxDuration"] ?: @"—"]]},
        @{@"label": @"Max quality", @"value": config[@"maxQuality"] ?: @"auto"},
        @{@"label": @"HLS ladder variants", @"html": [GZHTML monoValue:config[@"hlsVariants"] ?: @3]},
        @{@"label": @"Blob storage backend", @"value": storage[@"backend"] ?: @"—"},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Delivery & reclaim"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Watch mode", @"html": [GZHTML monoValue:distribution[@"watchMode"] ?: @"—"]},
        @{@"label": @"CA object store", @"value": [distribution[@"caStoreConfigured"] boolValue] ? @"configured" : @"not configured"},
        @{@"label": @"MUXL packaging", @"value": [distribution[@"muxlPresentationEnabled"] boolValue] ? @"enabled" : @"off"},
        @{@"label": @"Mirror providers", @"html": [GZHTML monoValue:distribution[@"mirrorProviderCount"] ?: @0]},
        @{@"label": @"Reclaim sweep", @"value": [distribution[@"sweepEnabled"] boolValue]
            ? @"enabled (grace-period orphans deleted)"
            : @"off — disk may grow; data not lost"},
    ]]];
    [html appendString:@"</section>"];
    return html;
}

+ (NSString *)renderVideoDistributionPartial:(NSDictionary *)snapshot {
    NSDictionary *distribution = snapshot[@"distribution"] ?: @{};
    NSMutableString *html = [NSMutableString string];

    [html appendString:[GZHTML sectionTitle:@"What this service serves"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Operator summary", @"value": distribution[@"summary"] ?: @"—"},
        @{@"label": @"/watch behavior", @"html": [GZHTML monoValue:distribution[@"watchMode"] ?: @"—"]},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Feature flags"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"CA MASL manifest (WS12)", @"value": [distribution[@"caManifestEnabled"] boolValue] ? @"on" : @"off"},
        @{@"label": @"CA store attached", @"value": [distribution[@"caStoreConfigured"] boolValue] ? @"yes" : @"no"},
        @{@"label": @"MUXL presentation (WS10)", @"value": [distribution[@"muxlPresentationEnabled"] boolValue] ? @"on" : @"off"},
        @{@"label": @"Verified mirror fetch", @"value": [distribution[@"mirrorFetchEnabled"] boolValue] ? @"on" : @"off"},
        @{@"label": @"Configured mirrors", @"html": [GZHTML monoValue:distribution[@"mirrorProviderCount"] ?: @0]},
        @{@"label": @"Streamplace mirror", @"value": [distribution[@"streamplaceMirrorConfigured"] boolValue] ? @"configured" : @"off"},
        @{@"label": @"Streamplace attribution DID", @"value": [distribution[@"streamplaceAttributionDIDConfigured"] boolValue] ? @"set" : @"missing"},
        @{@"label": @"Streamplace serve compat", @"value": [distribution[@"streamplaceServeCompat"] boolValue] ? @"on" : @"off"},
        @{@"label": @"Streamplace fetch OK / BlobNotFound / fail",
          @"html": [GZHTML monoValue:[NSString stringWithFormat:@"%@ / %@ / %@",
                                      distribution[@"streamplaceFetchSuccessCount"] ?: @0,
                                      distribution[@"streamplaceBlobNotFoundCount"] ?: @0,
                                      distribution[@"streamplaceFetchFailureCount"] ?: @0]]},
        @{@"label": @"Object reclaim sweep", @"value": [distribution[@"sweepEnabled"] boolValue] ? @"on" : @"off"},
    ]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Operator posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Secrets", @"value": @"Job service-auth tokens never render in HTML/JSON"},
        @{@"label": @"Paths", @"value": @"CA store and HLS directories stay server-side"},
        @{@"label": @"Actions", @"value": @"Retry failed jobs only — cancel/purge needs a typed cleanup contract"},
        @{@"label": @"Evidence", @"value": @"Job detail shows Manifest CID when CA VOD completed"},
    ]]];
    [html appendString:@"</section>"];

    return html;
}

#pragma mark - Quotas (legacy, kept for compat)

+ (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"video-quotas" context:ctx];
}

@end
