// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabaseBlob.h"
#import "Core/NSDateFormatter+ATProto.h"

@implementation PDSDatabaseBlob

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _cid = row[@"cid"];
        _did = row[@"did"];
        _mimeType = row[@"mime_type"] ?: row[@"mimeType"];
        _size = [row[@"size"] integerValue];
        
        id createdAt = row[@"created_at"];
        if ([createdAt isKindOfClass:[NSString class]]) {
            _createdAt = [NSDateFormatter atproto_dateFromString:createdAt];
        } else {
            _createdAt = [NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]];
        }
    }
    return self;
}

@end
