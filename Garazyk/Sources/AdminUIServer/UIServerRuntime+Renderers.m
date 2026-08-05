// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"

#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "Debug/GZLogger.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"
@implementation GZAdminUIHost (Renderers)

#pragma mark - Ozone Render Methods

- (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result {
    if (!result[@"error"] && !result[@"message"]) {
        NSMutableDictionary *ctx = [result mutableCopy];
        if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
        return [UITemplateEngine renderTemplate:@"ozone-statuses" context:ctx];
    }
    return [UITemplateEngine renderTemplate:@"ozone-statuses" context:result];
}

- (NSString *)renderOzoneEventsPartial:(NSDictionary *)result {
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
    return [UITemplateEngine renderTemplate:@"ozone-events" context:ctx];
}

- (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-subject" context:ctx];
}

- (NSString *)renderOzoneTeamPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-team" context:ctx];
}

- (NSString *)renderOzoneSetsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-sets" context:ctx];
}

- (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result {
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
    return [UITemplateEngine renderTemplate:@"ozone-templates" context:ctx];
}

- (NSString *)renderOzoneConfigPartial:(NSDictionary *)result {
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
    return [UITemplateEngine renderTemplate:@"ozone-config" context:ctx];
}

#pragma mark - Render Methods

- (NSString *)renderConnectionsPartial {
    NSDictionary *fields = @{
        @"pdsURL": [self.configuration.pdsBaseURL absoluteString] ?: @"",
        @"pdsToken": self.configuration.pdsAdminToken ?: @"",
        @"appViewURL": [self.configuration.appViewBaseURL absoluteString] ?: @"",
        @"appViewToken": self.configuration.appViewAdminToken ?: @"",
        @"relayURL": [self.configuration.relayBaseURL absoluteString] ?: @"",
        @"relayToken": self.configuration.relayAdminToken ?: @"",
        @"plcURL": [self.configuration.plcBaseURL absoluteString] ?: @"",
        @"plcToken": self.configuration.plcAdminToken ?: @"",
        @"chatURL": [self.configuration.chatBaseURL absoluteString] ?: @"",
        @"chatToken": self.configuration.chatAdminToken ?: @"",
        @"videoURL": [self.configuration.videoBaseURL absoluteString] ?: @"",
        @"videoToken": self.configuration.videoAdminToken ?: @""
    };
    NSArray *order = @[
        @{@"id": @"pds", @"key": @"pds", @"label": @"PDS"},
        @{@"id": @"appview", @"key": @"appView", @"label": @"APPVIEW"},
        @{@"id": @"relay", @"key": @"relay", @"label": @"RELAY"},
        @{@"id": @"plc", @"key": @"plc", @"label": @"PLC"},
        @{@"id": @"chat", @"key": @"chat", @"label": @"CHAT"},
        @{@"id": @"video", @"key": @"video", @"label": @"VIDEO"}
    ];
    NSMutableArray *services = [NSMutableArray array];
    for (NSDictionary *entry in order) {
        NSString *urlKey = [entry[@"key"] stringByAppendingString:@"URL"];
        NSString *tokenKey = [entry[@"key"] stringByAppendingString:@"Token"];
        [services addObject:@{
            @"id": entry[@"id"],
            @"label": entry[@"label"],
            @"urlKey": urlKey,
            @"urlVal": fields[urlKey],
            @"tokenKey": tokenKey,
            @"tokenVal": fields[tokenKey]
        }];
    }
    return [UITemplateEngine renderTemplate:@"connections" context:@{@"services": services}];
}

- (NSString *)renderOverviewPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (result[@"services"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *svc in result[@"services"]) {
            NSMutableDictionary *ms = [svc mutableCopy];
            NSString *name = svc[@"name"] ?: @"unknown";
            ms[@"nameUpper"] = [name uppercaseString];
            NSString *status = svc[@"status"] ?: @"unknown";
            if ([status isEqualToString:@"online"]) ms[@"statusClass"] = @"status-online";
            else if ([status isEqualToString:@"offline"]) ms[@"statusClass"] = @"status-offline";
            else if ([status isEqualToString:@"error"]) ms[@"statusClass"] = @"status-error";
            else ms[@"statusClass"] = @"status-unknown";
            ms[@"url"] = svc[@"url"] ?: @"-";
            [mapped addObject:ms];
        }
        ctx[@"services"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"overview" context:ctx];
}


#pragma mark - Phase 1 Render Methods

- (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result {
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
    return [UITemplateEngine renderTemplate:@"ozone-reports" context:ctx];
}

#pragma mark - Phase 2 Render Methods

#pragma mark - Phase 3 Render Methods

- (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result {
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
    return [UITemplateEngine renderTemplate:@"ozone-scheduled" context:ctx];
}

- (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-verification" context:ctx];
}

- (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result {
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
    return [UITemplateEngine renderTemplate:@"ozone-safelinks" context:ctx];
}

#pragma mark - Phase 6 Render Methods

- (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-settings" context:ctx];
}

- (NSString *)renderOzoneSignaturesPartial:(NSDictionary *)result {
    return [UITemplateEngine renderTemplate:@"ozone-signatures" context:result ?: @{}];
}

- (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"related"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSString *did in result[@"related"]) {
            [mapped addObject:@{@"did": did}];
        }
        ctx[@"related"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"ozone-signature-results" context:ctx];
}

- (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (did) ctx[@"did"] = did;
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-hosting" context:ctx];
}


@end
