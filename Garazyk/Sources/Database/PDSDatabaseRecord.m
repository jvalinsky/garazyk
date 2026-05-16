// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabaseRecord.h"
#import "Core/NSDateFormatter+ATProto.h"

@implementation PDSDatabaseRecord

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _uri = row[@"uri"];
        _did = row[@"did"];
        _collection = row[@"collection"];
        _rkey = row[@"rkey"];
        _cid = row[@"cid"];
        _value = row[@"value"];
        _rev = row[@"rev"];
        _subjectDid = row[@"subject_did"];

        id createdAt = row[@"created_at"];
        if ([createdAt isKindOfClass:[NSString class]]) {
            _createdAt = [NSDateFormatter atproto_dateFromString:createdAt];
        } else {
            _createdAt = [NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]];
        }

        id indexedAt = row[@"indexed_at"];
        if ([indexedAt isKindOfClass:[NSString class]]) {
            _indexedAt = [NSDateFormatter atproto_dateFromString:indexedAt];
        } else {
            _indexedAt = [NSDate dateWithTimeIntervalSince1970:[indexedAt doubleValue]];
        }
    }
    return self;
}

@end
