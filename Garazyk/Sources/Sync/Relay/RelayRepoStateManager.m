// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayRepoStateManager.h"
#import <sqlite3.h>

static NSString *const kRelayStateSchemaSQL =
    @"CREATE TABLE IF NOT EXISTS relay_repos ("
     "  did           TEXT PRIMARY KEY NOT NULL,"
     "  root_cid      TEXT,"
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

@interface RelayRepoStateManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoRoots;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoRevs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoSeqs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoStatuses;

@end

@implementation RelayRepoStateManager {
    dispatch_queue_t _stateQueue;
    NSString *_Nullable _databasePath;
    sqlite3 *_Nullable _db;
    /** Root CID before the most recent commit, keyed by DID. */
    NSMutableDictionary<NSString *, NSString *> *_prevDataCIDs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _repoRoots = [NSMutableDictionary dictionary];
        _repoRevs = [NSMutableDictionary dictionary];
        _repoSeqs = [NSMutableDictionary dictionary];
        _repoStatuses = [NSMutableDictionary dictionary];
        _prevDataCIDs = [NSMutableDictionary dictionary];
        _stateQueue = dispatch_queue_create("com.atproto.relay.state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (nullable instancetype)initWithDataDir:(NSString *)dataDir
                                   error:(NSError **)error {
    self = [super init];
    if (self) {
        _repoRoots = [NSMutableDictionary dictionary];
        _repoRevs = [NSMutableDictionary dictionary];
        _repoSeqs = [NSMutableDictionary dictionary];
        _repoStatuses = [NSMutableDictionary dictionary];
        _prevDataCIDs = [NSMutableDictionary dictionary];
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
    dispatch_async(_stateQueue, ^{
        NSNumber *currentSequence = self.repoSeqs[repoDID];
        if (currentSequence && seq <= currentSequence.longLongValue) {
            return;
        }
        NSString *oldRoot = self.repoRoots[repoDID];
        if (oldRoot) {
            self->_prevDataCIDs[repoDID] = oldRoot;
        }
        self.repoRoots[repoDID] = rootCID;
        self.repoRevs[repoDID] = rev;
        self.repoSeqs[repoDID] = @(seq);
        self.repoStatuses[repoDID] = @(RelayRepoStatusActive);
    });
}

#pragma mark - Identity / account / tombstone

- (void)handleIdentityEventForRepo:(NSString *)repoDID {
    dispatch_async(_stateQueue, ^{
        self.repoStatuses[repoDID] = @(RelayRepoStatusDesynchronized);
    });
}

- (void)handleAccountEventForRepo:(NSString *)repoDID status:(RelayRepoStatus)status {
    dispatch_async(_stateQueue, ^{
        self.repoStatuses[repoDID] = @(status);
    });
}

- (void)handleTombstoneForRepo:(NSString *)repoDID {
    dispatch_async(_stateQueue, ^{
        [self.repoRoots removeObjectForKey:repoDID];
        [self.repoRevs removeObjectForKey:repoDID];
        [self.repoSeqs removeObjectForKey:repoDID];
        self.repoStatuses[repoDID] = @(RelayRepoStatusTombstoned);
    });
}

#pragma mark - Accessors

- (nullable NSString *)rootCIDForRepo:(NSString *)repoDID {
    __block NSString *root;
    dispatch_sync(_stateQueue, ^{
        root = self.repoRoots[repoDID];
    });
    return root;
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
    __block NSString *prev;
    dispatch_sync(_stateQueue, ^{
        prev = self->_prevDataCIDs[repoDID];
    });
    return prev;
}

- (NSArray<NSString *> *)allRepos {
    __block NSArray *repos;
    dispatch_sync(_stateQueue, ^{
        repos = [[self.repoRoots allKeys] sortedArrayUsingSelector:@selector(compare:)];
    });
    return repos;
}

- (NSUInteger)repoCount {
    __block NSUInteger count;
    dispatch_sync(_stateQueue, ^{
        count = self.repoRoots.count;
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

// The actual persistence body. Callers must either already be executing on
// _stateQueue, or be -dealloc (see the comment there for why that's safe
// without dispatching).
- (void)persistStateOnQueue {
    sqlite3_exec(self->_db, "BEGIN TRANSACTION;", NULL, NULL, NULL);

    sqlite3_exec(self->_db, "DELETE FROM relay_repos;", NULL, NULL, NULL);

    sqlite3_stmt *stmt = NULL;
    const char *insertSQL =
        "INSERT INTO relay_repos (did, root_cid, prev_data_cid, rev, seq, status, last_seen_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?);";
    sqlite3_prepare_v2(self->_db, insertSQL, -1, &stmt, NULL);

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    for (NSString *did in self.repoRoots) {
        NSString *root = self.repoRoots[did] ?: @"";
        NSString *prev = self->_prevDataCIDs[did] ?: @"";
        NSString *rev = self.repoRevs[did] ?: @"";
        NSNumber *seq = self.repoSeqs[did] ?: @(0);
        NSNumber *status = self.repoStatuses[did] ?: @(RelayRepoStatusDesynchronized);

        sqlite3_bind_text(stmt, 1, did.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, root.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, prev.UTF8String, -1, SQLITE_TRANSIENT);
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
    dispatch_sync(_stateQueue, ^{
        sqlite3_stmt *stmt = NULL;
        const char *querySQL =
            "SELECT did, root_cid, prev_data_cid, rev, seq, status FROM relay_repos;";
        if (sqlite3_prepare_v2(self->_db, querySQL, -1, &stmt, NULL) != SQLITE_OK) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.relay.state"
                                             code:sqlite3_errcode(self->_db)
                                         userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithUTF8String:sqlite3_errmsg(self->_db)]}];
            }
            success = NO;
            return;
        }

        [self.repoRoots removeAllObjects];
        [self.repoRevs removeAllObjects];
        [self.repoSeqs removeAllObjects];
        [self.repoStatuses removeAllObjects];
        [self->_prevDataCIDs removeAllObjects];

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *didText   = sqlite3_column_text(stmt, 0);
            const unsigned char *rootText  = sqlite3_column_text(stmt, 1);
            const unsigned char *prevText  = sqlite3_column_text(stmt, 2);
            const unsigned char *revText   = sqlite3_column_text(stmt, 3);
            int64_t seq                    = sqlite3_column_int64(stmt, 4);
            int status                     = sqlite3_column_int(stmt, 5);

            if (!didText) continue;
            NSString *did = [NSString stringWithUTF8String:(const char *)didText];

            if (rootText && strlen((const char *)rootText) > 0) {
                self.repoRoots[did] = [NSString stringWithUTF8String:(const char *)rootText];
            }
            if (prevText && strlen((const char *)prevText) > 0) {
                self->_prevDataCIDs[did] = [NSString stringWithUTF8String:(const char *)prevText];
            }
            if (revText && strlen((const char *)revText) > 0) {
                self.repoRevs[did] = [NSString stringWithUTF8String:(const char *)revText];
            }
            self.repoSeqs[did] = @(seq);
            self.repoStatuses[did] = @(status);
        }
        sqlite3_finalize(stmt);
    });
    return success;
}

@end
