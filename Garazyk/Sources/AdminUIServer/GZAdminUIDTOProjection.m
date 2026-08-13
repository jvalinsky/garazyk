// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIDTOProjection.h"

NSDictionary<NSString *, id> *GZAdminUIProjectDictionary(NSDictionary *src,
                                                         NSArray<NSString *> *keys) {
    if (![src isKindOfClass:[NSDictionary class]] || keys.count == 0) {
        return @{};
    }
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = src[key];
        if (value && value != [NSNull null]) {
            row[key] = value;
        }
    }
    return [row copy];
}

NSArray<NSDictionary *> *GZAdminUIProjectDictionaries(id raw, NSArray<NSString *> *keys) {
    if (![raw isKindOfClass:[NSArray class]]) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        [out addObject:GZAdminUIProjectDictionary((NSDictionary *)item, keys)];
    }
    return [out copy];
}
