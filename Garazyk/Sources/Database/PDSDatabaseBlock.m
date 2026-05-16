// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabaseBlock.h"
#import "Core/NSDateFormatter+ATProto.h"

@implementation PDSDatabaseBlock

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _cid = row[@"cid"];
        _repoDid = row[@"repo_did"];
        _blockData = row[@"block_data"];
        _contentType = row[@"content_type"];
        _size = [row[@"size"] integerValue];
        
        id createdAt = row[@"created_at"];
        if ([createdAt isKindOfClass:[NSString class]]) {
            _createdAt = [NSDateFormatter atproto_dateFromString:createdAt];
        } else {
            _createdAt = [NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]];
        }
        
        _rev = row[@"rev"];
    }
    return self;
}

@end
