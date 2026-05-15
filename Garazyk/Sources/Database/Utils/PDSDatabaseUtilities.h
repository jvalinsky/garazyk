// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

static inline void PDSDBBindValue(sqlite3_stmt *stmt, int idx, id value) {
    if (!stmt || idx < 1) return;
    if (value == nil || value == [NSNull null]) {
        sqlite3_bind_null(stmt, idx);
    } else if ([value isKindOfClass:[NSString class]]) {
        sqlite3_bind_text(stmt, idx, [value UTF8String], -1, SQLITE_TRANSIENT);
    } else if ([value isKindOfClass:[NSData class]]) {
        sqlite3_bind_blob(stmt, idx, [value bytes], (int)[value length], SQLITE_TRANSIENT);
    } else if ([value isKindOfClass:[NSNumber class]]) {
        const char *objCType = [value objCType];
        if (strcmp(objCType, @encode(double)) == 0 ||
            strcmp(objCType, @encode(float)) == 0) {
            sqlite3_bind_double(stmt, idx, [value doubleValue]);
        } else {
            sqlite3_bind_int64(stmt, idx, [value longLongValue]);
        }
    }
}

static inline void PDSDBBindParams(sqlite3_stmt *stmt, NSArray *params) {
    for (NSUInteger i = 0; i < params.count; i++) {
        PDSDBBindValue(stmt, (int)(i + 1), params[i]);
    }
}

static inline id PDSDBColumnValue(sqlite3_stmt *stmt, int col) {
    if (!stmt) return nil;
    int type = sqlite3_column_type(stmt, col);
    switch (type) {
        case SQLITE_INTEGER:
            return @(sqlite3_column_int64(stmt, col));
        case SQLITE_FLOAT:
            return @(sqlite3_column_double(stmt, col));
        case SQLITE_TEXT: {
            const char *text = (const char *)sqlite3_column_text(stmt, col);
            return text ? @(text) : [NSNull null];
        }
        case SQLITE_BLOB: {
            const void *bytes = sqlite3_column_blob(stmt, col);
            int len = sqlite3_column_bytes(stmt, col);
            return bytes ? [NSData dataWithBytes:bytes length:len] : [NSNull null];
        }
        case SQLITE_NULL:
        default:
            return [NSNull null];
    }
}

static inline NSString *PDSDBPlaceholders(NSUInteger count) {
    if (count == 0) return @"";
    NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [placeholders addObject:@"?"];
    }
    return [placeholders componentsJoinedByString:@", "];
}

static inline NSError *PDSDBError(NSString *domain, NSString *message, NSInteger code) {
    return [NSError errorWithDomain:domain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

static inline NSError *PDSDBSQLError(NSString *domain, sqlite3 *db, NSInteger code) {
    const char *msg = db ? sqlite3_errmsg(db) : "Unknown error";
    return PDSDBError(domain, @(msg), code);
}

NS_ASSUME_NONNULL_END
