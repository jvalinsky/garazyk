// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIVideoPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIVideoPack

+ (NSString *)packIdentifier {
    return @"video";
}

+ (NSString *)displayName {
    return @"Video";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"video", @"displayName": @"Video"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerVideoRoutes];
}

+ (NSString *)renderVideoHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"status"] = status;
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    return [GZAdminUITemplateEngine renderTemplate:@"video-health" context:ctx];
}

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

+ (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"job"]) {
        NSMutableArray *pairs = [NSMutableArray array];
        [(NSDictionary *)result[@"job"] enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [pairs addObject:@{@"key": key, @"value": [value description]}];
        }];
        ctx[@"detailPairs"] = pairs;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"video-job-detail" context:ctx];
}

+ (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"video-quotas" context:ctx];
}

@end
