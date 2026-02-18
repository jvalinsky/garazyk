#import "PDSSchemaManager.h"

@implementation PDSSchemaManager

+ (instancetype)sharedManager {
    static PDSSchemaManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSSchemaManager alloc] init];
    });
    return shared;
}

#pragma mark - Service Database Schemas

- (NSString *)serviceAccountsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS accounts ("
           @"    did TEXT PRIMARY KEY,"
           @"    handle TEXT UNIQUE NOT NULL,"
           @"    email TEXT,"
           @"    password_hash BLOB,"
           @"    password_salt BLOB,"
           @"    access_jwt BLOB,"
           @"    refresh_jwt BLOB,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceInviteCodesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS invite_codes ("
           @"    id TEXT PRIMARY KEY,"
           @"    code TEXT NOT NULL UNIQUE,"
           @"    account_did TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    uses INTEGER DEFAULT 0,"
           @"    max_uses INTEGER DEFAULT 1,"
           @"    disabled INTEGER DEFAULT 0"
           @")";
}

- (NSString *)serviceReservedHandlesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS reserved_handles ("
           @"    handle TEXT PRIMARY KEY,"
           @"    created_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceAppPasswordsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS app_passwords ("
           @"    id TEXT PRIMARY KEY,"
           @"    account_did TEXT NOT NULL,"
           @"    name TEXT NOT NULL,"
           @"    password_hash BLOB NOT NULL,"
           @"    password_salt BLOB NOT NULL,"
           @"    privileged INTEGER DEFAULT 0,"
           @"    created_at REAL NOT NULL,"
           @"    UNIQUE(account_did, name)"
           @")";
}

- (NSString *)serviceRefreshTokensTableSchema {
    return @"CREATE TABLE IF NOT EXISTS refresh_tokens ("
           @"    token TEXT PRIMARY KEY,"
           @"    account_did TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    expires_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceJWTSigningKeysTableSchema {
    return @"CREATE TABLE IF NOT EXISTS jwt_signing_keys ("
           @"    key_id TEXT PRIMARY KEY,"
           @"    algorithm TEXT NOT NULL,"
           @"    private_key_data BLOB NOT NULL,"
           @"    public_key_data BLOB NOT NULL,"
           @"    is_active INTEGER DEFAULT 1,"
           @"    created_at TEXT NOT NULL,"
           @"    last_used_at TEXT"
           @")";
}

- (NSString *)serviceDIDCacheTableSchema {
    return @"CREATE TABLE IF NOT EXISTS did_cache ("
           @"    did TEXT PRIMARY KEY,"
           @"    document BLOB NOT NULL,"
           @"    expires_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceRepoSequenceTableSchema {
    return @"CREATE TABLE IF NOT EXISTS repo_sequence ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    did TEXT NOT NULL,"
           @"    commit_cid BLOB NOT NULL,"
           @"    seq INTEGER NOT NULL,"
           @"    created_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceEventsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS events ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    seq INTEGER NOT NULL UNIQUE,"
           @"    event_type TEXT NOT NULL,"
           @"    event_data BLOB NOT NULL,"
           @"    created_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceSchemaSQL {
    NSMutableString *sql = [NSMutableString string];
    [sql appendString:[self serviceAccountsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceInviteCodesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceReservedHandlesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceAppPasswordsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceRefreshTokensTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceJWTSigningKeysTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceEventsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_accounts_handle ON accounts(handle);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_invite_codes_code ON invite_codes(code);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_reserved_handles_handle ON reserved_handles(handle);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_app_passwords_account ON app_passwords(account_did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_refresh_tokens_account ON refresh_tokens(account_did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_events_seq ON events(seq);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at);"];
    return sql;
}

#pragma mark - Actor Store Schemas

- (NSString *)actorStoreRepoRootTableSchema {
    return @"CREATE TABLE IF NOT EXISTS repo_root ("
           @"    cid BLOB PRIMARY KEY,"
           @"    rev TEXT,"
           @"    updated_at DATETIME NOT NULL"
           @")";
}

- (NSString *)actorStoreRecordsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS records ("
           @"    uri TEXT PRIMARY KEY,"
           @"    did TEXT NOT NULL,"
           @"    collection TEXT NOT NULL,"
           @"    rkey TEXT NOT NULL,"
           @"    cid BLOB NOT NULL,"
           @"    value BLOB,"
           @"    indexed_at DATETIME NOT NULL,"
           @"    rev TEXT,"
           @"    subject_did TEXT"
           @")";
}

- (NSString *)actorStoreBlocksTableSchema {
    return @"CREATE TABLE IF NOT EXISTS ipld_blocks ("
           @"    cid BLOB PRIMARY KEY,"
           @"    block BLOB NOT NULL,"
           @"    size INTEGER NOT NULL"
           @")";
}

- (NSString *)actorStoreRecordTombstonesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS record_tombstones ("
           @"    uri TEXT NOT NULL,"
           @"    did TEXT NOT NULL,"
           @"    collection TEXT NOT NULL,"
           @"    rkey TEXT NOT NULL,"
           @"    rev TEXT NOT NULL,"
           @"    indexed_at DATETIME NOT NULL,"
           @"    PRIMARY KEY (uri, rev)"
           @")";
}

- (NSString *)actorStoreBlobsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS blobs ("
           @"    cid BLOB PRIMARY KEY,"
           @"    did TEXT NOT NULL,"
           @"    mimeType TEXT,"
           @"    size INTEGER NOT NULL,"
           @"    created_at DATETIME NOT NULL"
           @")";
}

- (NSString *)actorStoreSchemaSQL {
    NSMutableString *sql = [NSMutableString string];
    [sql appendString:[self actorStoreRepoRootTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self actorStoreRecordsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self actorStoreBlocksTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self actorStoreRecordTombstonesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self accountsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self inviteCodesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self actorStoreBlobsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_records_collection_rkey ON records(collection, rkey);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_records_did ON records(did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_records_uri ON records(uri);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_records_subject_did ON records(subject_did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_records_subject_did_collection ON records(subject_did, collection);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_record_tombstones_rev ON record_tombstones(rev);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_record_tombstones_did_rev ON record_tombstones(did, rev);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_ipld_blocks_cid ON ipld_blocks(cid);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_accounts_handle ON accounts(handle);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_blobs_did ON blobs(did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_blobs_cid ON blobs(cid);"];
    return sql;
}

#pragma mark - Common

- (NSString *)accountsTableSchema {
    return [self serviceAccountsTableSchema];
}

- (NSString *)inviteCodesTableSchema {
    return [self serviceInviteCodesTableSchema];
}

@end
