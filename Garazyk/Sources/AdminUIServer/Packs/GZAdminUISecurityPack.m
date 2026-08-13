// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUISecurityPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

static NSArray<NSDictionary *> *GZAdminUIProjectDictionaries(id raw,
                                                             NSArray<NSString *> *keys) {
    if (![raw isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *src = (NSDictionary *)item;
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            id value = src[key];
            if (value && value != [NSNull null]) {
                row[key] = value;
            }
        }
        [out addObject:row];
    }
    return out;
}

@implementation GZAdminUISecurityPack

+ (NSString *)packIdentifier {
    return @"security";
}

+ (NSString *)displayName {
    return @"Security";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"security", @"displayName": @"Security"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerSecurityRoutes];
}

+ (NSString *)renderSessionsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    if (result[@"error"]) {
        ctx[@"error"] = result[@"error"];
        ctx[@"message"] = result[@"message"] ?: result[@"error"];
    } else {
        ctx[@"sessions"] = GZAdminUIProjectDictionaries(
            result[@"sessions"],
            @[ @"id", @"did", @"deviceInfo", @"createdAt" ]);
    }
    if (!ctx[@"message"]) ctx[@"message"] = @"";
    return [GZAdminUITemplateEngine renderTemplate:@"sessions" context:ctx];
}

+ (NSString *)renderAppPasswordsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [NSMutableDictionary dictionary];
    if (result[@"error"]) {
        ctx[@"error"] = result[@"error"];
        ctx[@"message"] = result[@"message"] ?: result[@"error"];
    } else {
        ctx[@"passwords"] = GZAdminUIProjectDictionaries(
            result[@"passwords"],
            @[ @"name", @"did", @"createdAt" ]);
    }
    if (!ctx[@"message"]) ctx[@"message"] = @"";
    return [GZAdminUITemplateEngine renderTemplate:@"app-passwords" context:ctx];
}

@end
