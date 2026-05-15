// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase.h"

@implementation PDSDatabaseBlob

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _cid = row[@"cid"];
        _did = row[@"did"];
        _mimeType = row[@"mimeType"];
        _size = [row[@"size"] integerValue];
        _createdAt = [NSDate dateWithTimeIntervalSince1970:[row[@"created_at"] doubleValue]];
    }
    return self;
}

@end
