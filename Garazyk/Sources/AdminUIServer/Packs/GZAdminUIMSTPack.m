// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIMSTPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIMSTPack

+ (NSString *)packIdentifier {
    return @"mst";
}

+ (NSString *)displayName {
    return @"MST";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"mst", @"displayName": @"MST"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerMSTRoutes];
}

+ (NSString *)renderMSTAccountsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"mst-accounts" context:ctx];
}

+ (NSString *)renderMSTTreePartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSArray *nodes = [result[@"nodes"] isKindOfClass:[NSArray class]] ? result[@"nodes"] : @[];
    NSString *rootCID = result[@"rootCID"] ?: @"";
    ctx[@"emptyTree"] = @(nodes.count == 0 && rootCID.length == 0);
    ctx[@"hasNodes"] = @(nodes.count > 0);
    if (nodes.count > 0) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *node in nodes) {
            NSMutableDictionary *mn = [node mutableCopy];
            NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
            mn[@"entriesCount"] = @(entries.count);
            mn[@"hasEntries"] = @(entries.count > 0);
            NSString *cid = node[@"cid"] ?: @"";
            mn[@"shortCid"] = [cid substringToIndex:MIN(16, cid.length)];
            [mapped addObject:mn];
        }
        ctx[@"nodes"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"mst-tree" context:ctx];
}

+ (NSString *)renderMSTStatsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSMutableArray *pairs = [NSMutableArray array];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [pairs addObject:@{@"key": key, @"value": [value description]}];
    }];
    ctx[@"statsPairs"] = pairs;
    return [UITemplateEngine renderTemplate:@"mst-stats" context:ctx];
}

@end
