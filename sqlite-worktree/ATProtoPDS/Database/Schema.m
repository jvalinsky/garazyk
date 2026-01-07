#import "Schema.h"

NSInteger const kPDSDatabaseSchemaVersion = 1;

NSString * const kPDSAccountTableName = @"accounts";
NSString * const kPDSRepoTableName = @"repos";
NSString * const kPDSBlockTableName = @"blocks";

NSString * const kPDSAccountTableCreateSQL = 
    @"CREATE TABLE IF NOT EXISTS accounts ("
    @"did TEXT PRIMARY KEY,"
    @"handle TEXT UNIQUE NOT NULL,"
    @"email TEXT,"
    @"password_hash BLOB,"
    @"access_jwt BLOB,"
    @"refresh_jwt BLOB,"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL"
    @")";

NSString * const kPDSRepoTableCreateSQL = 
    @"CREATE TABLE IF NOT EXISTS repos ("
    @"owner_did TEXT PRIMARY KEY,"
    @"root_cid BLOB NOT NULL,"
    @"collection_data BLOB,"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL"
    @")";

NSString * const kPDSBlockTableCreateSQL = 
    @"CREATE TABLE IF NOT EXISTS blocks ("
    @"cid BLOB PRIMARY KEY,"
    @"repo_did TEXT NOT NULL,"
    @"block_data BLOB,"
    @"content_type TEXT,"
    @"size INTEGER,"
    @"created_at TEXT NOT NULL,"
    @"FOREIGN KEY (repo_did) REFERENCES repos(owner_did)"
    @")";

NSString * const kPDSIndexBlocksRepoDidSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_blocks_repo_did ON blocks(repo_did)";

NSString * const kPDSIndexAccountsHandleSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_accounts_handle ON accounts(handle)";
