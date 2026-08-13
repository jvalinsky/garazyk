// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUISecurityPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIDTOProjection.h"
#import "AdminUIServer/UITemplateEngine.h"

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
