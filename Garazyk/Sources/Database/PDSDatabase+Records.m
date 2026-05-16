// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/PDSDatabase+Records.h"
#import "Database/PDSDatabase+Private.h"
#import <sqlite3.h>
#import "Database/Utils/PDSSQLiteUtils.h"
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"

#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

static NSString *const kRecordsColumns = @"uri, did, collection, rkey, cid, "
    @"value, subject_did, created_at, indexed_at";

@implementation PDSDatabase (Records)

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri error:(NSError **)error {
    NSString *sql = [NSString stringWithFormat:@"SELECT %@ FROM records WHERE uri = ?", kRecordsColumns];
    NSArray *results = [self executeParameterizedQuery:sql params:@[uri] modelClass:[PDSDatabaseRecord class] error:error];
    return results.firstObject;
}

- (BOOL)saveRecord:(PDSDatabaseRecord *)record error:(NSError **)error {
    NSString *sql = @"INSERT OR REPLACE INTO records (uri, did, collection, rkey, cid, created_at) VALUES (?, ?, ?, ?, ?, ?)";
    NSArray *params = @[
        record.uri ?: [NSNull null],
        record.did ?: [NSNull null],
        record.collection ?: [NSNull null],
        record.rkey ?: [NSNull null],
        record.cid ?: [NSNull null],
        [NSDateFormatter atproto_stringFromDate:record.createdAt]
    ];
    return [self executeParameterizedUpdate:sql params:params error:error];
}

- (NSArray<PDSDatabaseRecord *> *)getRecordsForDid:(NSString *)did collection:(nullable NSString *)collection error:(NSError **)error {
    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT %@ FROM records WHERE did = ?", kRecordsColumns];
    NSMutableArray *params = [NSMutableArray arrayWithObject:did];

    if (collection.length > 0) {
        [sql appendString:@" AND collection = ?"];
        [params addObject:collection];
    }
    [sql appendString:@" ORDER BY created_at DESC"];

    return [self executeParameterizedQuery:sql params:params modelClass:[PDSDatabaseRecord class] error:error] ?: @[];
}

- (PDSDatabaseRecord *)recordFromStatement:(sqlite3_stmt *)stmt {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = [self valueFromStatement:stmt columnIndex:0];
    record.did = [self valueFromStatement:stmt columnIndex:1];
    record.collection = [self valueFromStatement:stmt columnIndex:2];
    record.rkey = [self valueFromStatement:stmt columnIndex:3];
    record.cid = [self valueFromStatement:stmt columnIndex:4];
    record.value = [self valueFromStatement:stmt columnIndex:5];
    record.subjectDid = [self valueFromStatement:stmt columnIndex:6];
    
    id createdAtStr = [self valueFromStatement:stmt columnIndex:7];
    if (createdAtStr) {
        record.createdAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:createdAtStr];
    }

    id indexedAtStr = [self valueFromStatement:stmt columnIndex:8];
    if (indexedAtStr) {
        record.indexedAt = [[NSDateFormatter atproto_iso8601Formatter] dateFromString:indexedAtStr];
    }

    return record;
}

@end
