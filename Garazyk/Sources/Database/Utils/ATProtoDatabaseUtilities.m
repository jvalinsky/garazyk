// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/Utils/ATProtoDatabaseUtilities.h"
#import <sqlite3.h>

NSString * const ATProtoDBErrorDomain = @"com.garazyk.db";

const ATProtoDBConfig ATProtoDBConfigDefault = {
    .flags = ATProtoDBConfigFlagWAL | ATProtoDBConfigFlagSynchronousNormal | ATProtoDBConfigFlagForeignKeys
             | ATProtoDBConfigFlagTempStoreMemory,
    .busyTimeout = 5000,
    .cacheSize = 0,
    .walAutocheckpoint = 0,
    .journalSizeLimit = 0,
    .mmapSize = 0,
    .pageSize = 0,
};

const ATProtoDBConfig ATProtoDBConfigActorStore = {
    .flags = ATProtoDBConfigFlagWAL | ATProtoDBConfigFlagSynchronousNormal | ATProtoDBConfigFlagForeignKeys
             | ATProtoDBConfigFlagTempStoreMemory,
    .busyTimeout = 5000,
    .cacheSize = -64000,
    .walAutocheckpoint = 1000,
    .journalSizeLimit = 0,
    .mmapSize = 268435456,
    .pageSize = 0,
};

const ATProtoDBConfig ATProtoDBConfigServiceDatabase = {
    .flags = ATProtoDBConfigFlagWAL | ATProtoDBConfigFlagSynchronousNormal
             | ATProtoDBConfigFlagForeignKeys | ATProtoDBConfigFlagTempStoreMemory,
    .busyTimeout = 5000,
    .cacheSize = -32000,
    .walAutocheckpoint = 0,
    .journalSizeLimit = 0,
    .mmapSize = 0,
    .pageSize = 0,
};

const ATProtoDBConfig ATProtoDBConfigBulkRead = {
    .flags = ATProtoDBConfigFlagWAL | ATProtoDBConfigFlagSynchronousNormal | ATProtoDBConfigFlagForeignKeys,
    .busyTimeout = 10000,
    .cacheSize = -128000,
    .walAutocheckpoint = 0,
    .journalSizeLimit = 0,
    .mmapSize = 268435456,
    .pageSize = 0,
};

BOOL ATProtoDBConfigurePragmas(sqlite3 *db, ATProtoDBConfig config) {
    if (!db) return NO;
    char *errMsg = NULL;

    if (config.flags & ATProtoDBConfigFlagWAL) {
        int rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.flags & ATProtoDBConfigFlagSynchronousNormal) {
        int rc = sqlite3_exec(db, "PRAGMA synchronous=NORMAL", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.flags & ATProtoDBConfigFlagForeignKeys) {
        int rc = sqlite3_exec(db, "PRAGMA foreign_keys=ON", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.flags & ATProtoDBConfigFlagTempStoreMemory) {
        int rc = sqlite3_exec(db, "PRAGMA temp_store=MEMORY", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.busyTimeout > 0) {
        sqlite3_busy_timeout(db, config.busyTimeout);
    }

    if (config.cacheSize != 0) {
        char sql[64];
        snprintf(sql, sizeof(sql), "PRAGMA cache_size=%d", config.cacheSize);
        int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.walAutocheckpoint > 0) {
        char sql[64];
        snprintf(sql, sizeof(sql), "PRAGMA wal_autocheckpoint=%d", config.walAutocheckpoint);
        int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.journalSizeLimit > 0) {
        char sql[64];
        snprintf(sql, sizeof(sql), "PRAGMA journal_size_limit=%d", config.journalSizeLimit);
        int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.mmapSize > 0) {
        char sql[64];
        snprintf(sql, sizeof(sql), "PRAGMA mmap_size=%d", config.mmapSize);
        int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.pageSize > 0) {
        char sql[64];
        snprintf(sql, sizeof(sql), "PRAGMA page_size=%d", config.pageSize);
        int rc = sqlite3_exec(db, sql, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    return YES;
}
