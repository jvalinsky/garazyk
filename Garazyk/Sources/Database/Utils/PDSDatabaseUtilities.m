// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Database/Utils/PDSDatabaseUtilities.h"
#import <sqlite3.h>

NSString * const PDSDBErrorDomain = @"com.garazyk.db";

const PDSDBConfig PDSDBConfigDefault = {
    .flags = PDSDBConfigFlagWAL | PDSDBConfigFlagSynchronousNormal | PDSDBConfigFlagForeignKeys,
    .busyTimeout = 5000,
    .cacheSize = 0,
    .walAutocheckpoint = 0,
    .journalSizeLimit = 0,
    .mmapSize = 0,
    .pageSize = 0,
};

const PDSDBConfig PDSDBConfigActorStore = {
    .flags = PDSDBConfigFlagWAL | PDSDBConfigFlagSynchronousNormal | PDSDBConfigFlagForeignKeys,
    .busyTimeout = 5000,
    .cacheSize = -64000,
    .walAutocheckpoint = 1000,
    .journalSizeLimit = 0,
    .mmapSize = 0,
    .pageSize = 0,
};

const PDSDBConfig PDSDBConfigServiceDatabase = {
    .flags = PDSDBConfigFlagWAL | PDSDBConfigFlagSynchronousNormal
             | PDSDBConfigFlagForeignKeys | PDSDBConfigFlagTempStoreMemory,
    .busyTimeout = 5000,
    .cacheSize = -32000,
    .walAutocheckpoint = 0,
    .journalSizeLimit = 0,
    .mmapSize = 0,
    .pageSize = 0,
};

const PDSDBConfig PDSDBConfigBulkRead = {
    .flags = PDSDBConfigFlagWAL | PDSDBConfigFlagSynchronousNormal,
    .busyTimeout = 10000,
    .cacheSize = -128000,
    .walAutocheckpoint = 0,
    .journalSizeLimit = 0,
    .mmapSize = 268435456,
    .pageSize = 0,
};

BOOL PDSDBConfigurePragmas(sqlite3 *db, PDSDBConfig config) {
    if (!db) return NO;
    char *errMsg = NULL;

    if (config.flags & PDSDBConfigFlagWAL) {
        int rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.flags & PDSDBConfigFlagSynchronousNormal) {
        int rc = sqlite3_exec(db, "PRAGMA synchronous=NORMAL", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.flags & PDSDBConfigFlagForeignKeys) {
        int rc = sqlite3_exec(db, "PRAGMA foreign_keys=ON", NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            sqlite3_free(errMsg); errMsg = NULL;
        }
    }

    if (config.flags & PDSDBConfigFlagTempStoreMemory) {
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
