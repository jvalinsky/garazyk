// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Reports.h"
#import "Database/PDSDatabase+Private.h"
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

@implementation PDSDatabase (Reports)

- (NSString *)createReport:(NSDictionary *)report error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *reportId = [[NSUUID UUID] UUIDString];
    NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];

    NSString *sql = @"INSERT INTO reports (report_id, reason_type, reason, reported_by_did, subject_type, subject_did, subject_uri, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)";

    NSArray *params = @[
        reportId,
        report[@"reason_type"] ?: [NSNull null],
        report[@"reason"] ?: [NSNull null],
        report[@"reported_by_did"] ?: [NSNull null],
        report[@"subject_type"] ?: [NSNull null],
        report[@"subject_did"] ?: [NSNull null],
        report[@"subject_uri"] ?: [NSNull null],
        dateStr
    ];

    if ([self executeParameterizedUpdate:sql params:params error:error]) {
        result = reportId;
        return;
    }
    result = nil;
    return;
    }];
    return result;
}

- (NSArray<NSDictionary *> *)queryReports:(NSDictionary *)filters limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSMutableString *sql = [@"SELECT * FROM reports WHERE 1=1" mutableCopy];
    NSMutableArray *params = [NSMutableArray array];

    if (filters[@"status"]) {
        [sql appendString:@" AND status = ?"];
        [params addObject:filters[@"status"]];
    }

    if (filters[@"reason_type"]) {
        [sql appendString:@" AND reason_type = ?"];
        [params addObject:filters[@"reason_type"]];
    }

    if (filters[@"reported_by_did"]) {
        [sql appendString:@" AND reported_by_did = ?"];
        [params addObject:filters[@"reported_by_did"]];
    }

    if (filters[@"subject_did"]) {
        [sql appendString:@" AND subject_did = ?"];
        [params addObject:filters[@"subject_did"]];
    }

    if (filters[@"subject_type"]) {
        [sql appendString:@" AND subject_type = ?"];
        [params addObject:filters[@"subject_type"]];
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

- (nullable NSDictionary *)getReportById:(NSString *)reportId error:(NSError **)error {
    __block id result = nil;
    [self safeExecuteSync:^{

    NSString *sql = @"SELECT * FROM reports WHERE report_id = ?";
    NSArray<NSDictionary *> *rows = [self executeParameterizedQuery:sql params:@[reportId] error:error];
    result = rows.firstObject;
    return;
    }];
    return result;
}

- (BOOL)updateReportStatus:(NSString *)reportId status:(NSString *)status resolvedBy:(nullable NSString *)adminDid notes:(nullable NSString *)notes error:(NSError **)error {
    __block BOOL result = NO;
    [self safeExecuteSync:^{

    NSMutableString *sql = [@"UPDATE reports SET status = ?" mutableCopy];
    NSMutableArray *params = [NSMutableArray arrayWithObjects:status, nil];

    if ([status isEqualToString:@"resolved"] || [status isEqualToString:@"dismissed"]) {
        [sql appendString:@", resolved_by_did = ?, resolved_at = ?, resolution_notes = ?"];
        NSString *dateStr = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
        [params addObjectsFromArray:@[adminDid ?: [NSNull null], dateStr, notes ?: [NSNull null]]];
    }

    [sql appendString:@" WHERE report_id = ?"];
    [params addObject:reportId];

    result = [self executeParameterizedUpdate:sql params:params error:error];

    return;
    }];
    return result;
}

@end
