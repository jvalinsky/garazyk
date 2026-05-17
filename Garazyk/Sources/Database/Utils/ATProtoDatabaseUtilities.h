// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ATProtoDBErrorDomain;

/**
 * @abstract Defines ATProtoDBErrorCode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, ATProtoDBErrorCode) {
    ATProtoDBErrorNotOpen = 1000,
    ATProtoDBErrorQueryFailed = 1001,
    ATProtoDBErrorMigrationFailed = 1002,
};

#pragma mark - ATProtoDBConfig

/**
 * @abstract Defines ATProtoDBConfigFlags values exposed by this API.
 */
typedef NS_OPTIONS(NSUInteger, ATProtoDBConfigFlags) {
    ATProtoDBConfigFlagWAL              = 1 << 0,
    ATProtoDBConfigFlagSynchronousNormal = 1 << 1,
    ATProtoDBConfigFlagForeignKeys       = 1 << 2,
    ATProtoDBConfigFlagTempStoreMemory   = 1 << 3,
};

typedef struct {
    ATProtoDBConfigFlags flags;
    int busyTimeout;           // ms (0 = default)
    int cacheSize;             // pages (positive) or KB (negative)
    int walAutocheckpoint;     // pages (0 = default)
    int journalSizeLimit;      // bytes (0 = default)
    int mmapSize;              // bytes (0 = default)
    int pageSize;              // bytes (0 = default)
} ATProtoDBConfig;

extern const ATProtoDBConfig ATProtoDBConfigDefault;
extern const ATProtoDBConfig ATProtoDBConfigActorStore;
extern const ATProtoDBConfig ATProtoDBConfigServiceDatabase;
extern const ATProtoDBConfig ATProtoDBConfigBulkRead;

BOOL ATProtoDBConfigurePragmas(sqlite3 *db, ATProtoDBConfig config);

static inline void ATProtoDBBindValue(sqlite3_stmt *stmt, int idx, id value) {
    if (!stmt || idx < 1) return;
    if (value == nil || value == [NSNull null]) {
        sqlite3_bind_null(stmt, idx);
    } else if ([value isKindOfClass:[NSString class]]) {
        sqlite3_bind_text(stmt, idx, [value UTF8String], -1, SQLITE_TRANSIENT);
    } else if ([value isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)value;
        if (data.length == 0) {
            sqlite3_bind_zeroblob(stmt, idx, 0);
        } else {
            sqlite3_bind_blob(stmt, idx, data.bytes, (int)data.length, SQLITE_TRANSIENT);
        }
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

static inline void ATProtoDBBindParams(sqlite3_stmt *stmt, NSArray *params) {
    for (NSUInteger i = 0; i < params.count; i++) {
        ATProtoDBBindValue(stmt, (int)(i + 1), params[i]);
    }
}

static inline id ATProtoDBColumnValue(sqlite3_stmt *stmt, int col) {
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

static inline NSString *ATProtoDBPlaceholders(NSUInteger count) {
    if (count == 0) return @"";
    NSMutableArray *placeholders = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [placeholders addObject:@"?"];
    }
    return [placeholders componentsJoinedByString:@", "];
}

static inline NSError *ATProtoDBError(NSString *domain, NSString *message, NSInteger code) {
    return [NSError errorWithDomain:domain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

static inline NSError *ATProtoDBSQLError(NSString *domain, sqlite3 *db, NSInteger code) {
    const char *msg = db ? sqlite3_errmsg(db) : "Unknown error";
    return ATProtoDBError(domain, @(msg), code);
}

NS_ASSUME_NONNULL_END

// ATProtoDBConfig constants and ATProtoDBConfigurePragmas are defined in ATProtoDatabaseUtilities.m
