// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase.h"

@implementation PDSDatabaseRepo

- (instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row {
    self = [super init];
    if (self) {
        _ownerDid = row[@"ownerDid"];
        _rootCid = row[@"rootCid"];
        _collectionData = row[@"collectionData"];
        _createdAt = [NSDate dateWithTimeIntervalSince1970:[row[@"createdAt"] doubleValue]];
        _updatedAt = [NSDate dateWithTimeIntervalSince1970:[row[@"updatedAt"] doubleValue]];
    }
    return self;
}

@end
