// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file NSDictionary+ATProtoCID.m

 @abstract NSDictionary category for extracting ATProtoCID string values from CBOR-decoded dictionaries.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "Core/NSDictionary+CID.h"
#import "Core/CID.h"

@implementation NSDictionary (CIDAdditions)

- (nullable NSString *)cidStringForKey:(NSString *)key {
    id value = self[key];

    if ([value isKindOfClass:[ATProtoCID class]]) {
        return [(ATProtoCID *)value stringValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }

    // NSNull, nil, or other types → nil
    return nil;
}

- (nullable ATProtoCID *)cidObjectForKey:(NSString *)key {
    id value = self[key];

    if ([value isKindOfClass:[ATProtoCID class]]) {
        return (ATProtoCID *)value;
    } else if ([value isKindOfClass:[NSString class]]) {
        return [ATProtoCID cidFromString:(NSString *)value];
    }

    // NSNull, nil, or other types → nil
    return nil;
}

@end
