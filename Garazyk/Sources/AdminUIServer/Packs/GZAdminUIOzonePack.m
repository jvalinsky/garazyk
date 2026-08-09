// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIOzonePack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIOzonePack

+ (NSString *)packIdentifier {
    return @"ozone";
}

+ (NSString *)displayName {
    return @"Ozone";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"ozone", @"displayName": @"Ozone"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerOzoneRoutes];
}

+ (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result {
    if (!result[@"error"] && !result[@"message"]) {
        NSMutableDictionary *ctx = [result mutableCopy];
        if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
        return [GZAdminUITemplateEngine renderTemplate:@"ozone-statuses" context:ctx];
    }
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-statuses" context:result];
}

+ (NSString *)renderOzoneEventsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (result[@"events"]) {
        NSMutableArray *mappedEvents = [NSMutableArray array];
        for (NSDictionary *e in result[@"events"]) {
            NSMutableDictionary *me = [e mutableCopy];
            NSDictionary *subject = e[@"subject"];
            me[@"subject_did"] = subject[@"did"] ?: subject[@"uri"] ?: @"";
            [mappedEvents addObject:me];
        }
        ctx[@"events"] = mappedEvents;
    }
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-events" context:ctx];
}

+ (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-subject" context:ctx];
}

+ (NSString *)renderOzoneTeamPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-team" context:ctx];
}

+ (NSString *)renderOzoneSetsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-sets" context:ctx];
}

+ (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"templates"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *t in result[@"templates"]) {
            NSMutableDictionary *mt = [t mutableCopy];
            NSString *content = t[@"contentMarkdown"] ?: @"";
            if (content.length > 80) content = [[content substringToIndex:80] stringByAppendingString:@"..."];
            mt[@"contentMarkdownShort"] = content;
            [mapped addObject:mt];
        }
        ctx[@"templates"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-templates" context:ctx];
}

+ (NSString *)renderOzoneConfigPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&jsonError];
    NSString *jsonStr = jsonError ? @"" : [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    ctx[@"jsonStr"] = jsonStr;
    NSMutableArray *pairs = [NSMutableArray array];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [pairs addObject:@{@"key": key, @"value": [value description]}];
    }];
    ctx[@"configPairs"] = pairs;
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-config" context:ctx];
}

+ (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"reports"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *report in result[@"reports"]) {
            NSMutableDictionary *mr = [report mutableCopy];
            if (!mr[@"resolvedAt"]) mr[@"resolvedAt"] = @"pending";
            [mapped addObject:mr];
        }
        ctx[@"reports"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-reports" context:ctx];
}

+ (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"actions"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *action in result[@"actions"]) {
            NSMutableDictionary *ma = [action mutableCopy];
            if (!ma[@"status"]) ma[@"status"] = @"pending";
            [mapped addObject:ma];
        }
        ctx[@"actions"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-scheduled" context:ctx];
}

+ (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-verification" context:ctx];
}

+ (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"rules"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *rule in result[@"rules"]) {
            NSMutableDictionary *mr = [rule mutableCopy];
            if (!mr[@"pattern"]) mr[@"pattern"] = @"domain";
            if (!mr[@"action"]) mr[@"action"] = @"block";
            if (!mr[@"reason"]) mr[@"reason"] = @"none";
            [mapped addObject:mr];
        }
        ctx[@"rules"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-safelinks" context:ctx];
}

+ (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-settings" context:ctx];
}

+ (NSString *)renderOzoneSignaturesPartial:(NSDictionary *)result {
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-signatures" context:result ?: @{}];
}

+ (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"related"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSString *did in result[@"related"]) {
            [mapped addObject:@{@"did": did}];
        }
        ctx[@"related"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-signature-results" context:ctx];
}

+ (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (did) ctx[@"did"] = did;
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"ozone-hosting" context:ctx];
}

@end
