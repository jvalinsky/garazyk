// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase.h"

@implementation PDSDatabaseRecord

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _uri = row[@"uri"];
        _did = row[@"did"];
        _collection = row[@"collection"];
        _rkey = row[@"rkey"];
        _cid = row[@"cid"];
        _createdAt = [NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]];
        _value = row[@"value"];
        _rev = row[@"rev"];
        _subjectDid = row[@"subject_did"];
        _indexedAt = [NSDate dateWithTimeIntervalSince1970:[row[@"indexed_at"] doubleValue]];
    }
    return self;
}

@end
