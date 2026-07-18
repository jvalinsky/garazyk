// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+AdminConfig.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (AdminConfig)

- (nullable NSString *)getAdminConfigValue:(NSString *)key error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT value FROM admin_config WHERE key = ?";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[key] error:error];
    result = rows.firstObject[@"value"];
    return;
    }];
    return result;
}

- (BOOL)setAdminConfigValue:(NSString *)value forKey:(NSString *)key error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSString *sql = @"INSERT INTO admin_config (key, value, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at";
    result = [self executeParameterizedUpdate:sql params:@[key, value, dateStr] error:error];
    return;
    }];
    return result;
}

@end
