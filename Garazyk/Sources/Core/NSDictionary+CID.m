/*!
 @file NSDictionary+CID.m

 @abstract NSDictionary category for extracting CID string values from CBOR-decoded dictionaries.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import "Core/NSDictionary+CID.h"
#import "Core/CID.h"

@implementation NSDictionary (CIDAdditions)

- (nullable NSString *)cidStringForKey:(NSString *)key {
    id value = self[key];

    if ([value isKindOfClass:[CID class]]) {
        return [(CID *)value stringValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }

    // NSNull, nil, or other types → nil
    return nil;
}

- (nullable CID *)cidObjectForKey:(NSString *)key {
    id value = self[key];

    if ([value isKindOfClass:[CID class]]) {
        return (CID *)value;
    } else if ([value isKindOfClass:[NSString class]]) {
        return [CID cidFromString:(NSString *)value];
    }

    // NSNull, nil, or other types → nil
    return nil;
}

@end
