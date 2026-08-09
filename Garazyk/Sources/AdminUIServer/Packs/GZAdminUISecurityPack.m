// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUISecurityPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
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
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"sessions" context:ctx];
}

+ (NSString *)renderAppPasswordsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [GZAdminUITemplateEngine renderTemplate:@"app-passwords" context:ctx];
}

@end
