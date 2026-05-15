// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSBlock.h"

@implementation PDSDatabaseBlock

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _cid = row[@"cid"];
        _repoDid = row[@"repoDid"];
        _blockData = row[@"block"];
        _contentType = row[@"contentType"];
        _size = [row[@"size"] integerValue];
        _createdAt = [NSDate dateWithTimeIntervalSince1970:[row[@"createdAt"] doubleValue]];
        _rev = row[@"rev"];
    }
    return self;
}

@end
