// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Moderation.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Moderation)

- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason takedownRef:(NSString *)ref error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO admin_takedowns (id, subjectType, subjectId, reason, takedownRef, applied, createdBy, createdAt) VALUES (?, ?, ?, ?, ?, 1, 'admin', ?) ON CONFLICT(id) DO UPDATE SET subjectType=excluded.subjectType, subjectId=excluded.subjectId, reason=excluded.reason, takedownRef=excluded.takedownRef, applied=1, createdBy='admin', createdAt=excluded.createdAt";

    NSString *takedownId = [[NSUUID UUID] UUIDString];
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];

    NSArray *params = @[
        takedownId,
        @"account",
        did,
        reason ?: [NSNull null],
        ref ?: [NSNull null],
        dateStr
    ];

    result = [self executeParameterizedUpdate:sql params:params error:error];

    return;
    }];
    return result;
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE admin_takedowns SET applied = 0 WHERE subjectId = ? AND subjectType = 'account'";
    result = [self executeParameterizedUpdate:sql params:@[did] error:error];
    return;
    }];
    return result;
}

- (BOOL)deactivateAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"UPDATE accounts SET status = 'deactivated', deactivated_at = ?, updated_at = ? WHERE did = ?";
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    result = [self executeParameterizedUpdate:sql params:@[dateStr, @(now), did] error:error];
    return;
    }];
    return result;
}

- (BOOL)activateAccount:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    // "Activate" is the unified reversal: an account can be inactive because
    // it was deactivated (accounts.status) or taken down (admin_takedowns.applied),
    // and this must clear both so isAccountTakedownActive: agrees with the
    // reversal, not just accountStatusForDid:.
    NSString *sql = @"UPDATE accounts SET status = 'active', deactivated_at = NULL, updated_at = ? WHERE did = ?";
    NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
    result = [self executeParameterizedUpdate:sql params:@[now, did] error:error];
    if (!result) {
        return;
    }

    NSString *clearTakedownSql = @"UPDATE admin_takedowns SET applied = 0 WHERE subjectId = ? AND subjectType = 'account'";
    result = [self executeParameterizedUpdate:clearTakedownSql params:@[did] error:error];
    return;
    }];
    return result;
}

- (NSString *)accountStatusForDid:(NSString *)did error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    if (!did) {
        result = nil;
        return;
    }
    NSString *sql = @"SELECT status FROM accounts WHERE did = ?";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) {
        result = nil;
        return;
    }
    result = rows.firstObject[@"status"];
    return;
    }];
    return result;
}

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!did) {
        result = NO;
        return;
    }
    NSString *sql = @"SELECT applied FROM admin_takedowns WHERE subjectId = ? AND subjectType = 'account' ORDER BY createdAt DESC LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[did] error:error];
    if (rows.count == 0) {
        result = NO;
        return;
    }
    NSNumber *applied = rows.firstObject[@"applied"];
    result = applied ? applied.boolValue : NO;
    return;
    }];
    return result;
}

- (BOOL)isRecordTakedownActive:(NSString *)uri error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    if (!uri) {
        result = NO;
        return;
    }
    NSString *sql = @"SELECT applied FROM admin_takedowns WHERE subjectId = ? AND subjectType = 'record' ORDER BY createdAt DESC LIMIT 1";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[uri] error:error];
    if (rows.count == 0) {
        result = NO;
        return;
    }
    NSNumber *applied = rows.firstObject[@"applied"];
    result = applied ? applied.boolValue : NO;
    return;
    }];
    return result;
}

- (BOOL)createLabel:(NSDictionary *)label error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO labels (src, uri, cid, val, neg, cts, exp) VALUES (?, ?, ?, ?, ?, ?, ?)";

    // cts is NOT NULL; stamp it server-side (like created_at elsewhere) so a
    // caller omitting it fails at validation, not with a raw constraint error.
    NSString *cts = label[@"cts"] ?: [NSDateFormatter atproto_stringFromDate:[NSDate date]];

    NSArray *params = @[
        label[@"src"] ?: [NSNull null],
        label[@"uri"] ?: [NSNull null],
        label[@"cid"] ?: [NSNull null],
        label[@"val"] ?: [NSNull null],
        label[@"neg"] ?: @0,
        cts,
        label[@"exp"] ?: [NSNull null]
    ];

    result = [self executeParameterizedUpdate:sql params:params error:error];

    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)getLabelsWithPatterns:(NSArray<NSString *> *)uriPatterns sources:(NSArray<NSString *> *)sources limit:(NSInteger)limit cursor:(NSString *)cursor error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{


    NSMutableString *sql = [@"SELECT * FROM labels WHERE 1=1" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];

    if (sources && sources.count > 0) {
        [sql appendString:@" AND src IN ("];
        for (NSUInteger i = 0; i < sources.count; i++) {
            [sql appendString:i == 0 ? @"?" : @", ?"];
            [params addObject:sources[i]];
        }
        [sql appendString:@")"];
    }

    if (uriPatterns && uriPatterns.count > 0) {
        [sql appendString:@" AND ("];
        for (NSUInteger i = 0; i < uriPatterns.count; i++) {
            if (i > 0) [sql appendString:@" OR "];
            NSString *pat = uriPatterns[i];
            if ([pat containsString:@"*"]) {
                 [sql appendString:@"uri GLOB ?"];
            } else {
                 [sql appendString:@"uri = ?"];
            }
            [params addObject:pat];
        }
        [sql appendString:@")"];
    }

    if (cursor) {
        [sql appendString:@" AND id > ?"];
        [params addObject:cursor];
    }

    [sql appendString:@" ORDER BY id ASC LIMIT ?"];
    [params addObject:@(limit)];

    result = [self executeParameterizedQuery:sql params:params error:error];

    return;
    }];
    return result;
}

@end
