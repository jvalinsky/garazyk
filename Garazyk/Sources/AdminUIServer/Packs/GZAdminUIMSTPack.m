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
    return [GZAdminUITemplateEngine renderTemplate:@"mst-accounts" context:ctx];
}

+ (NSString *)renderMSTTreePartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSArray *nodes = [result[@"nodes"] isKindOfClass:[NSArray class]] ? result[@"nodes"] : @[];
    NSString *rootCID = [result[@"rootCID"] isKindOfClass:[NSString class]] ? result[@"rootCID"] : @"";
    ctx[@"emptyTree"] = @(nodes.count == 0 && rootCID.length == 0);
    ctx[@"hasNodes"] = @(nodes.count > 0);
    ctx[@"rootCID"] = rootCID;
    ctx[@"rootCIDShort"] = rootCID.length > 20
        ? [[rootCID substringToIndex:20] stringByAppendingString:@"…"]
        : rootCID;
    ctx[@"nodeCount"] = result[@"nodeCount"] ?: @(nodes.count);

    NSUInteger entryCount = 0;
    NSInteger maxDepth = 0;
    NSMutableArray *mapped = [NSMutableArray array];
    NSMutableArray *jsonNodes = [NSMutableArray array];
    for (NSDictionary *node in nodes) {
        if (![node isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSMutableDictionary *mn = [node mutableCopy];
        NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
        entryCount += entries.count;
        NSInteger level = [node[@"level"] respondsToSelector:@selector(integerValue)]
            ? [node[@"level"] integerValue]
            : 0;
        if (level > maxDepth) {
            maxDepth = level;
        }
        mn[@"entriesCount"] = @(entries.count);
        mn[@"hasEntries"] = @(entries.count > 0);
        NSString *cid = [node[@"cid"] isKindOfClass:[NSString class]] ? node[@"cid"] : @"";
        mn[@"shortCid"] = cid.length > 16 ? [cid substringToIndex:16] : cid;
        [mapped addObject:mn];

        NSMutableDictionary *jn = [NSMutableDictionary dictionary];
        if (cid.length > 0) jn[@"cid"] = cid;
        if (node[@"left"]) jn[@"left"] = node[@"left"];
        if (node[@"kind"]) jn[@"kind"] = node[@"kind"];
        if (node[@"level"]) jn[@"level"] = node[@"level"];
        if (entries.count > 0) {
            NSMutableArray *je = [NSMutableArray array];
            for (NSDictionary *entry in entries) {
                if (![entry isKindOfClass:[NSDictionary class]]) continue;
                NSMutableDictionary *e = [NSMutableDictionary dictionary];
                if (entry[@"fullKey"]) e[@"fullKey"] = entry[@"fullKey"];
                if (entry[@"key"]) e[@"key"] = entry[@"key"];
                if (entry[@"value"]) e[@"value"] = entry[@"value"];
                if (entry[@"tree"]) e[@"tree"] = entry[@"tree"];
                [je addObject:e];
            }
            jn[@"entries"] = je;
        }
        [jsonNodes addObject:jn];
    }
    ctx[@"nodes"] = mapped;
    ctx[@"entryCount"] = result[@"entryCount"] ?: @(entryCount);
    ctx[@"maxDepth"] = result[@"maxDepth"] ?: @(maxDepth);

    NSDictionary *payload = @{
        @"rootCID": rootCID ?: @"",
        @"nodes": jsonNodes,
    };
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
    // Escaped for a hidden <pre>: HTMX innerHTML swaps drop <script> text bodies.
    ctx[@"mstJson"] = jsonError ? @"{}" : json;

    return [GZAdminUITemplateEngine renderTemplate:@"mst-tree" context:ctx];
}

+ (NSString *)renderMSTStatsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSMutableArray *pairs = [NSMutableArray array];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [pairs addObject:@{@"key": key, @"value": [value description]}];
    }];
    ctx[@"statsPairs"] = pairs;
    return [GZAdminUITemplateEngine renderTemplate:@"mst-stats" context:ctx];
}

@end
