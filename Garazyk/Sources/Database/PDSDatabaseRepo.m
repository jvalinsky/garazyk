// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabaseRepo.h"
#import "Core/NSDateFormatter+ATProto.h"

@implementation PDSDatabaseRepo

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _ownerDid = row[@"owner_did"];
        _rootCid = row[@"root_cid"];
        _collectionData = row[@"collection_data"];
        
        id createdAt = row[@"created_at"];
        if ([createdAt isKindOfClass:[NSString class]]) {
            _createdAt = [NSDateFormatter atproto_dateFromString:createdAt];
        } else {
            _createdAt = [NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]];
        }

        id updatedAt = row[@"updated_at"];
        if ([updatedAt isKindOfClass:[NSString class]]) {
            _updatedAt = [NSDateFormatter atproto_dateFromString:updatedAt];
        } else {
            _updatedAt = [NSDate dateWithTimeIntervalSince1970:[updatedAt doubleValue]];
        }
    }
    return self;
}

@end
