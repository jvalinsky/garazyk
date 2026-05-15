// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+AdminAudit.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (AdminAudit)

- (BOOL)insertAuditLogEntry:(NSDictionary *)entry error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSString *sql = @"INSERT INTO admin_audit_log (admin_did, action, subject_type, subject_id, details, ip_address, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)";

    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];

    NSArray *params = @[
        entry[@"admin_did"] ?: [NSNull null],
        entry[@"action"] ?: [NSNull null],
        entry[@"subject_type"] ?: [NSNull null],
        entry[@"subject_id"] ?: [NSNull null],
        entry[@"details"] ?: [NSNull null],
        entry[@"ip_address"] ?: [NSNull null],
        dateStr
    ];

    result = [self executeParameterizedUpdate:sql params:params error:error];

    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)queryAuditLog:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSMutableString *sql = [@"SELECT * FROM admin_audit_log WHERE 1=1" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];

    if (filters[@"admin_did"]) {
        [sql appendString:@" AND admin_did = ?"];
        [params addObject:filters[@"admin_did"]];
    }

    if (filters[@"action"]) {
        [sql appendString:@" AND action = ?"];
        [params addObject:filters[@"action"]];
    }

    if (filters[@"subject_type"]) {
        [sql appendString:@" AND subject_type = ?"];
        [params addObject:filters[@"subject_type"]];
    }

    if (filters[@"subject_id"]) {
        [sql appendString:@" AND subject_id = ?"];
        [params addObject:filters[@"subject_id"]];
    }

    if (filters[@"since"]) {
        [sql appendString:@" AND created_at >= ?"];
        [params addObject:filters[@"since"]];
    }

    if (filters[@"until"]) {
        [sql appendString:@" AND created_at <= ?"];
        [params addObject:filters[@"until"]];
    }

    if (cursor) {
        [sql appendString:@" AND id < ?"];
        [params addObject:cursor];
    }

    [sql appendString:@" ORDER BY id DESC LIMIT ?"];
    [params addObject:@(limit)];

    result = [self executeParameterizedQuery:sql params:params error:error];

    return;
    }];
    return result;
}

- (BOOL)deleteAuditLogsOlderThanDays:(NSInteger)days error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSDate *cutoffDate = [[NSDate date] dateByAddingTimeInterval:-((NSTimeInterval)days * 24 * 60 * 60)];
    NSString *cutoffStr = [[NSDateFormatter atproto_iso8601Formatter] stringFromDate:cutoffDate];

    NSString *sql = @"DELETE FROM admin_audit_log WHERE created_at < ?";
    result = [self executeParameterizedUpdate:sql params:@[cutoffStr] error:error];
    return;
    }];
    return result;
}

@end
