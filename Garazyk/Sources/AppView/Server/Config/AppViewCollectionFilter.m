// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewCollectionFilter.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Config/AppViewCollectionFilter.h"

@implementation AppViewCollectionFilter

- (instancetype)initWithAllowlist:(NSArray<NSString *> *)allowlist {
    self = [super init];
    if (!self) return nil;
    _allowlist = [allowlist copy] ?: @[];
    return self;
}

- (BOOL)shouldIndexCollection:(NSString *)collection {
    if (!collection || collection.length == 0) return NO;

    // Empty allowlist = allow all
    if (_allowlist.count == 0) return YES;

    for (NSString *entry in _allowlist) {
        if (entry.length == 0) continue;

        if ([entry hasSuffix:@"."]) {
            // Prefix match: entry "site.standard." matches "site.standard.document"
            if ([collection hasPrefix:entry]) return YES;
        } else {
            // Exact match
            if ([collection isEqualToString:entry]) return YES;
        }
    }

    return NO;
}

@end
