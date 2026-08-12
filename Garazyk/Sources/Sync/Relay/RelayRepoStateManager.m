// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayRepoStateManager.h"
#import <sqlite3.h>

static NSString *const kRelayStateSchemaSQL =
    @"CREATE TABLE IF NOT EXISTS relay_repos ("
     "  did           TEXT PRIMARY KEY NOT NULL,"
     "  root_cid      TEXT,"
     "  data_cid      TEXT,"
     "  prev_data_cid TEXT,"
     "  rev           TEXT,"
     "  seq           INTEGER NOT NULL DEFAULT 0,"
     "  status        INTEGER NOT NULL DEFAULT 0,"
     "  last_seen_at  REAL NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS relay_meta ("
    "  key   TEXT PRIMARY KEY NOT NULL,"
    "  value TEXT"
    ");";

@interface ATProtoRelayRepoStateManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoCommitCIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoDataCIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoRevs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoSeqs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoStatuses;

- (void)persistRepoOnQueue:(NSString *)repoDID;
- (void)persistStateOnQueue;

@end

@implementation ATProtoRelayRepoStateManager {
    dispatch_queue_t _stateQueue;
    NSString *_Nullable _databasePath;
    sqlite3 *_Nullable _db;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _repoCommitCIDs = [NSMutableDictionary dictionary];
        _repoDataCIDs = [NSMutableDictionary dictionary];
        _repoRevs = [NSMutableDictionary dictionary];
        _repoSeqs = [NSMutableDictionary dictionary];
        _repoStatuses = [NSMutableDictionary dictionary];
        _stateQueue = dispatch_queue_create("com.atproto.relay.state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (nullable instancetype)initWithDataDir:(NSString *)dataDir
                                   error:(NSError **)error {
    self = [super init];
    if (self) {
        _repoCommitCIDs = [NSMutableDictionary dictionary];
        _repoDataCIDs = [NSMutableDictionary dictionary];
        _repoRevs = [NSMutableDictionary dictionary];
        _repoSeqs = [NSMutableDictionary dictionary];
        _repoStatuses = [NSMutableDictionary dictionary];
        _stateQueue = dispatch_queue_create("com.atproto.relay.state", DISPATCH_QUEUE_SERIAL);

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dbDir = [dataDir stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dbDir]) {
            if (![fm createDirectoryAtPath:dbDir
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:error]) {
                return nil;
            }
        }

        _databasePath = [dataDir copy];
        int rc = sqlite3_open(dataDir.fileSystemRepresentation, &_db);
        if (rc != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.relay.state"
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithUTF8String:sqlite3_errmsg(_db)]}];
            }
            sqlite3_close(_db);
            _db = NULL;
            return nil;
        }

        sqlite3_busy_timeout(_db, 5000);
        sqlite3_exec(_db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
        sqlite3_exec(_db, "PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);
        sqlite3_exec(_db, "PRAGMA temp_store=MEMORY;", NULL, NULL, NULL);

        char *errMsg = NULL;
        rc = sqlite3_exec(_db, kRelayStateSchemaSQL.UTF8String, NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSString *msg = errMsg ? [NSString stringWithUTF8String:errMsg] : @"unknown error";
            sqlite3_free(errMsg);
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.relay.state"
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: msg}];
            }
            sqlite3_close(_db);
            _db = NULL;
            return nil;
        }

        sqlite3_stmt *tableInfo = NULL;
        BOOL hasDataCID = NO;
        if (sqlite3_prepare_v2(_db, "PRAGMA table_info(relay_repos);", -1,
                               &tableInfo, NULL) == SQLITE_OK) {
            while (sqlite3_step(tableInfo) == SQLITE_ROW) {
                const unsigned char *columnName = sqlite3_column_text(tableInfo, 1);
                if (columnName &&
                    strcmp((const char *)columnName, "data_cid") == 0) {
                    hasDataCID = YES;
                    break;
                }
            }
        }
        sqlite3_finalize(tableInfo);

        if (!hasDataCID) {
            rc = sqlite3_exec(_db,
                              "ALTER TABLE relay_repos ADD COLUMN data_cid TEXT;",
                              NULL, NULL, &errMsg);
            if (rc != SQLITE_OK) {
                NSString *msg = errMsg
                    ? [NSString stringWithUTF8String:errMsg]
                    : @"failed to add relay data_cid column";
                sqlite3_free(errMsg);
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.relay.state"
                                                 code:rc
                                             userInfo:@{NSLocalizedDescriptionKey: msg}];
                }
                sqlite3_close(_db);
                _db = NULL;
                return nil;
            }
        }

        rc = sqlite3_exec(
            _db,
            "INSERT INTO relay_meta(key, value) VALUES('schema_version', '2') "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value;",
            NULL, NULL, &errMsg);
        if (rc != SQLITE_OK) {
            NSString *msg = errMsg
                ? [NSString stringWithUTF8String:errMsg]
                : @"failed to record relay schema version";
            sqlite3_free(errMsg);
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.relay.state"
                                             code:rc
                                         userInfo:@{NSLocalizedDescriptionKey: msg}];
            }
            sqlite3_close(_db);
            _db = NULL;
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    if (_db) {
        // Not [self persistState]: that dispatch_syncs onto _stateQueue, and
        // a block captured on _stateQueue can be the last strong reference
        // to self, so -dealloc can run while already executing on
        // _stateQueue. dispatch_sync onto the queue you're already running
        // on deadlocks. By the time -dealloc runs, no other reference to
        // self exists, so no block on _stateQueue can be concurrently
        // executing (each holds self strongly for its duration) — running
        // the persistence body directly, unsynchronized, is safe here.
        [self persistStateOnQueue];
        sqlite3_close(_db);
        _db = NULL;
    }
}

#pragma mark - Commit handling

- (void)handleCommitForRepo:(NSString *)repoDID
                         root:(NSString *)rootCID
                           rev:(NSString *)rev
                           seq:(int64_t)seq {
    [self handleCommitForRepo:repoDID
                    commitCID:rootCID
                      dataCID:nil
                          rev:rev
                          seq:seq];
}

- (void)handleCommitForRepo:(NSString *)repoDID
                  commitCID:(NSString *)commitCID
                    dataCID:(nullable NSString *)dataCID
                        rev:(NSString *)rev
                        seq:(int64_t)seq {
    dispatch_async(_stateQueue, ^{
        NSNumber *currentSequence = self.repoSeqs[repoDID];
        if (currentSequence && seq <= currentSequence.longLongValue) {
            return;
        }
        self.repoCommitCIDs[repoDID] = commitCID;
        if (dataCID.length > 0) {
            self.repoDataCIDs[repoDID] = dataCID;
        } else {
            [self.repoDataCIDs removeObjectForKey:repoDID];
        }
        self.repoRevs[repoDID] = rev;
        self.repoSeqs[repoDID] = @(seq);
        self.repoStatuses[repoDID] = @(RelayRepoStatusActive);
        [self persistRepoOnQueue:repoDID];
    });
}

- (RelayRepoAdvanceResult)advanceRepo:(NSString *)repoDID
                                since:(nullable NSString *)since
                             prevData:(nullable NSString *)prevDataCID
                            commitCID:(NSString *)commitCID
                              dataCID:(nullable NSString *)dataCID
                                  rev:(NSString *)rev
                                  seq:(int64_t)seq {
    __block RelayRepoAdvanceResult result = RelayRepoAdvanceResultBaselineEstablished;
    dispatch_sync(_stateQueue, ^{
        NSString *currentRev = self.repoRevs[repoDID];
        NSString *currentDataCID = self.repoDataCIDs[repoDID];

        if (currentRev.length > 0 && rev.length > 0 &&
            [rev compare:currentRev] != NSOrderedDescending) {
            result = RelayRepoAdvanceResultStale;
            return;
        }

        if (currentDataCID.length == 0) {
            result = RelayRepoAdvanceResultBaselineEstablished;
        } else if (since.length == 0 || prevDataCID.length == 0) {
            result = RelayRepoAdvanceResultUnverifiableAdvanced;
        } else if (currentRev.length > 0 && ![since isEqualToString:currentRev]) {
            self.repoStatuses[repoDID] = @(RelayRepoStatusDesynchronized);
            [self persistRepoOnQueue:repoDID];
            result = RelayRepoAdvanceResultSinceMismatch;
            return;
        } else if (![prevDataCID isEqualToString:currentDataCID]) {
            self.repoStatuses[repoDID] = @(RelayRepoStatusDesynchronized);
            [self persistRepoOnQueue:repoDID];
            result = RelayRepoAdvanceResultPrevDataMismatch;
            return;
        } else {
            result = RelayRepoAdvanceResultAdvanced;
        }

        self.repoCommitCIDs[repoDID] = commitCID;
        if (dataCID.length > 0) {
            self.repoDataCIDs[repoDID] = dataCID;
        } else {
            [self.repoDataCIDs removeObjectForKey:repoDID];
        }
        self.repoRevs[repoDID] = rev;
        self.repoSeqs[repoDID] = @(seq);
        self.repoStatuses[repoDID] = @(RelayRepoStatusActive);
        [self persistRepoOnQueue:repoDID];
    });
    return result;
}

- (void)observeInventoryForRepo:(NSString *)repoDID
                      commitCID:(NSString *)commitCID
                            rev:(NSString *)rev
                         active:(BOOL)active {
    dispatch_async(_stateQueue, ^{
        NSString *currentRev = self.repoRevs[repoDID];
        if (currentRev.length > 0 && rev.length > 0 &&
            [rev compare:currentRev] != NSOrderedDescending) {
            return;
        }

        self.repoCommitCIDs[repoDID] = commitCID;
        [self.repoDataCIDs removeObjectForKey:repoDID];
        self.repoRevs[repoDID] = rev;
        if (!self.repoSeqs[repoDID]) {
            self.repoSeqs[repoDID] = @(0);
        }
        self.repoStatuses[repoDID] =
            @(active ? RelayRepoStatusActive : RelayRepoStatusDesynchronized);
        [self persistRepoOnQueue:repoDID];
    });
}

#pragma mark - Identity / account / tombstone

- (void)handleIdentityEventForRepo:(NSString *)repoDID {
    dispatch_async(_stateQueue, ^{
        self.repoStatuses[repoDID] = @(RelayRepoStatusDesynchronized);
        [self persistRepoOnQueue:repoDID];
    });
}

- (void)handleAccountEventForRepo:(NSString *)repoDID status:(RelayRepoStatus)status {
    dispatch_async(_stateQueue, ^{
        self.repoStatuses[repoDID] = @(status);
        [self persistRepoOnQueue:repoDID];
    });
}

- (void)handleTombstoneForRepo:(NSString *)repoDID {
    dispatch_async(_stateQueue, ^{
        [self.repoCommitCIDs removeObjectForKey:repoDID];
        [self.repoDataCIDs removeObjectForKey:repoDID];
        [self.repoRevs removeObjectForKey:repoDID];
        [self.repoSeqs removeObjectForKey:repoDID];
        self.repoStatuses[repoDID] = @(RelayRepoStatusTombstoned);
        [self persistRepoOnQueue:repoDID];
    });
}

#pragma mark - Accessors

- (nullable NSString *)rootCIDForRepo:(NSString *)repoDID {
    return [self commitCIDForRepo:repoDID];
}

- (nullable NSString *)commitCIDForRepo:(NSString *)repoDID {
    __block NSString *root;
    dispatch_sync(_stateQueue, ^{
        root = self.repoCommitCIDs[repoDID];
    });
    return root;
}

- (nullable NSString *)dataCIDForRepo:(NSString *)repoDID {
    __block NSString *dataCID;
    dispatch_sync(_stateQueue, ^{
        dataCID = self.repoDataCIDs[repoDID];
    });
    return dataCID;
}

- (nullable NSString *)revForRepo:(NSString *)repoDID {
    __block NSString *rev;
    dispatch_sync(_stateQueue, ^{
        rev = self.repoRevs[repoDID];
    });
    return rev;
}

- (int64_t)cursorForRepo:(NSString *)repoDID {
    __block int64_t cursor = -1;
    dispatch_sync(_stateQueue, ^{
        NSNumber *seq = self.repoSeqs[repoDID];
        if (seq) {
            cursor = seq.longLongValue;
        }
    });
    return cursor;
}

- (RelayRepoStatus)statusForRepo:(NSString *)repoDID {
    __block RelayRepoStatus status = RelayRepoStatusDesynchronized;
    dispatch_sync(_stateQueue, ^{
        NSNumber *s = self.repoStatuses[repoDID];
        if (s) {
            status = s.integerValue;
        }
    });
    return status;
}

- (nullable NSString *)prevDataCIDForRepo:(NSString *)repoDID {
    return [self dataCIDForRepo:repoDID];
}

- (NSArray<NSString *> *)allRepos {
    __block NSArray *repos;
    dispatch_sync(_stateQueue, ^{
        repos = [[self.repoCommitCIDs allKeys] sortedArrayUsingSelector:@selector(compare:)];
    });
    return repos;
}

- (NSUInteger)repoCount {
    __block NSUInteger count;
    dispatch_sync(_stateQueue, ^{
        count = self.repoCommitCIDs.count;
    });
    return count;
}

#pragma mark - Persistence

- (void)persistState {
    if (!_db) {
        return;
    }
    dispatch_sync(_stateQueue, ^{
        [self persistStateOnQueue];
    });
}

- (void)persistRepoOnQueue:(NSString *)repoDID {
    if (!_db || repoDID.length == 0) {
        return;
    }

    const char *upsertSQL =
        "INSERT INTO relay_repos "
        "(did, root_cid, data_cid, prev_data_cid, rev, seq, status, last_seen_at) "
        "VALUES (?, ?, ?, '', ?, ?, ?, ?) "
        "ON CONFLICT(did) DO UPDATE SET "
        "root_cid=excluded.root_cid, data_cid=excluded.data_cid, "
        "rev=excluded.rev, seq=excluded.seq, status=excluded.status, "
        "last_seen_at=excluded.last_seen_at;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(_db, upsertSQL, -1, &stmt, NULL) != SQLITE_OK) {
        return;
    }

    NSString *commitCID = self.repoCommitCIDs[repoDID] ?: @"";
    NSString *dataCID = self.repoDataCIDs[repoDID] ?: @"";
    NSString *rev = self.repoRevs[repoDID] ?: @"";
    NSNumber *seq = self.repoSeqs[repoDID] ?: @(0);
    NSNumber *status =
        self.repoStatuses[repoDID] ?: @(RelayRepoStatusDesynchronized);

    sqlite3_bind_text(stmt, 1, repoDID.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, commitCID.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, dataCID.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, rev.UTF8String, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 5, seq.longLongValue);
    sqlite3_bind_int(stmt, 6, (int)status.integerValue);
    sqlite3_bind_double(stmt, 7, [[NSDate date] timeIntervalSince1970]);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
}

// The actual persistence body. Callers must either already be executing on
// _stateQueue, or be -dealloc (see the comment there for why that's safe
// without dispatching).
- (void)persistStateOnQueue {
    sqlite3_exec(self->_db, "BEGIN TRANSACTION;", NULL, NULL, NULL);

    sqlite3_exec(self->_db, "DELETE FROM relay_repos;", NULL, NULL, NULL);

    sqlite3_stmt *stmt = NULL;
    const char *insertSQL =
        "INSERT INTO relay_repos "
        "(did, root_cid, data_cid, prev_data_cid, rev, seq, status, last_seen_at) "
        "VALUES (?, ?, ?, '', ?, ?, ?, ?);";
    sqlite3_prepare_v2(self->_db, insertSQL, -1, &stmt, NULL);

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableSet<NSString *> *dids =
        [NSMutableSet setWithArray:self.repoCommitCIDs.allKeys];
    [dids addObjectsFromArray:self.repoStatuses.allKeys];
    for (NSString *did in dids) {
        NSString *root = self.repoCommitCIDs[did] ?: @"";
        NSString *dataCID = self.repoDataCIDs[did] ?: @"";
        NSString *rev = self.repoRevs[did] ?: @"";
        NSNumber *seq = self.repoSeqs[did] ?: @(0);
        NSNumber *status = self.repoStatuses[did] ?: @(RelayRepoStatusDesynchronized);

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, root.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, dataCID.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, rev.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 5, seq.longLongValue);
        sqlite3_bind_int(stmt, 6, (int)status.integerValue);
        sqlite3_bind_double(stmt, 7, now);

        sqlite3_step(stmt);
        sqlite3_reset(stmt);
    }
    sqlite3_finalize(stmt);

    sqlite3_exec(self->_db, "COMMIT;", NULL, NULL, NULL);
}

- (BOOL)loadState:(NSError **)error {
    if (!_db) {
        return YES;
    }
    __block BOOL success = YES;
    __block NSError *loadError = nil;
    dispatch_sync(_stateQueue, ^{
        sqlite3_stmt *stmt = NULL;
        const char *querySQL =
            "SELECT did, root_cid, data_cid, rev, seq, status FROM relay_repos;";
        if (sqlite3_prepare_v2(self->_db, querySQL, -1, &stmt, NULL) != SQLITE_OK) {
            loadError = [NSError errorWithDomain:@"com.atproto.relay.state"
                                            code:sqlite3_errcode(self->_db)
                                        userInfo:@{NSLocalizedDescriptionKey:
                                           [NSString stringWithUTF8String:sqlite3_errmsg(self->_db)]}];
            success = NO;
            return;
        }

        [self.repoCommitCIDs removeAllObjects];
        [self.repoDataCIDs removeAllObjects];
        [self.repoRevs removeAllObjects];
        [self.repoSeqs removeAllObjects];
        [self.repoStatuses removeAllObjects];

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *didText   = sqlite3_column_text(stmt, 0);
            const unsigned char *rootText  = sqlite3_column_text(stmt, 1);
            const unsigned char *dataText  = sqlite3_column_text(stmt, 2);
            const unsigned char *revText   = sqlite3_column_text(stmt, 3);
            int64_t seq                    = sqlite3_column_int64(stmt, 4);
            int status                     = sqlite3_column_int(stmt, 5);

            if (!didText) continue;
            NSString *did = [NSString stringWithUTF8String:(const char *)didText];

            if (rootText && strlen((const char *)rootText) > 0) {
                self.repoCommitCIDs[did] =
                    [NSString stringWithUTF8String:(const char *)rootText];
            }
            if (dataText && strlen((const char *)dataText) > 0) {
                self.repoDataCIDs[did] =
                    [NSString stringWithUTF8String:(const char *)dataText];
            }
            if (revText && strlen((const char *)revText) > 0) {
                self.repoRevs[did] = [NSString stringWithUTF8String:(const char *)revText];
            }
            self.repoSeqs[did] = @(seq);
            self.repoStatuses[did] = @(status);
        }
        sqlite3_finalize(stmt);
    });
    if (!success && error) {
        *error = loadError;
    }
    return success;
}

@end
