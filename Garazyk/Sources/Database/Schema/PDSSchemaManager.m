// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSSchemaManager.h"
#import "Database/Schema.h"

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
           @"    status TEXT NOT NULL DEFAULT 'active',"
           @"    deactivated_at REAL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL,"
           @"    tfa_enabled INTEGER DEFAULT 0,"
           @"    tfa_secret BLOB,"
           @"    recovery_codes BLOB,"
           @"    invite_enabled INTEGER DEFAULT 0,"
           @"    age_assurance TEXT,"
           @"    age_verified_at TEXT,"
           @"    webauthn_enabled INTEGER DEFAULT 0"
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

- (NSString *)serviceWebAuthnCredentialsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS webauthn_credentials ("
           @"    id TEXT PRIMARY KEY,"
           @"    account_did TEXT NOT NULL,"
           @"    credential_id BLOB NOT NULL,"
           @"    public_key_cose BLOB NOT NULL,"
           @"    sign_count INTEGER DEFAULT 0,"
           @"    aaguid BLOB,"
           @"    created_at REAL NOT NULL,"
           @"    UNIQUE(account_did, credential_id)"
           @")";
}

- (NSString *)servicePendingFactorTokensTableSchema {
    return @"CREATE TABLE IF NOT EXISTS pending_factor_tokens ("
           @"    id TEXT PRIMARY KEY,"
           @"    token_hash BLOB NOT NULL UNIQUE,"
           @"    account_did TEXT NOT NULL,"
           @"    method TEXT NOT NULL,"
           @"    challenge BLOB,"
           @"    expires_at REAL NOT NULL,"
           @"    consumed_at REAL,"
           @"    created_at REAL NOT NULL"
           @")";
}

- (NSString *)serviceJWTSigningKeysTableSchema {
    return @"CREATE TABLE IF NOT EXISTS jwt_signing_keys ("
           @"    key_id TEXT PRIMARY KEY,"
           @"    algorithm TEXT NOT NULL,"
           @"    private_key_data BLOB," // NULL for Secure Enclave keys
           @"    public_key_data BLOB NOT NULL,"
           @"    keychain_tag TEXT," // Label/Tag for loading from Keychain
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

- (NSString *)serviceActorPreferencesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS actor_preferences ("
           @"    did TEXT PRIMARY KEY,"
           @"    preferences BLOB NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL,"
           @"    FOREIGN KEY (did) REFERENCES accounts(did)"
           @")";
}

- (NSString *)serviceActorMutesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS actor_mutes ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    did TEXT NOT NULL,"
           @"    muted_did TEXT NOT NULL,"
           @"    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
           @"    UNIQUE(did, muted_did)"
           @")";
}

- (NSString *)sequencerAnalyticsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS sequencer_analytics ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    timestamp INTEGER NOT NULL,"
           @"    seq_number INTEGER NOT NULL,"
           @"    events_per_second REAL,"
           @"    subscriber_count INTEGER,"
           @"    backpressure_warnings INTEGER,"
           @"    backpressure_critical INTEGER,"
           @"    queue_overflows INTEGER,"
           @"    event_type_distribution TEXT,"
           @"    created_at INTEGER NOT NULL"
           @")";
}

- (NSString *)blobAuditJobsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS blob_audit_jobs ("
           @"    id TEXT PRIMARY KEY,"
           @"    job_type TEXT NOT NULL,"
           @"    status TEXT NOT NULL,"
           @"    started_at INTEGER,"
           @"    completed_at INTEGER,"
           @"    progress REAL DEFAULT 0.0,"
           @"    results TEXT,"
           @"    error TEXT,"
           @"    created_at INTEGER NOT NULL"
           @")";
}

- (NSString *)rateLimitHistoryTableSchema {
    return @"CREATE TABLE IF NOT EXISTS rate_limit_history ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    identifier TEXT NOT NULL,"
           @"    type TEXT NOT NULL,"
           @"    action TEXT NOT NULL,"
           @"    admin_did TEXT,"
           @"    reason TEXT,"
           @"    timestamp INTEGER NOT NULL"
           @")";
}

- (NSString *)serviceHostingEventsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS hosting_events ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    did TEXT NOT NULL,"
           @"    event_type TEXT NOT NULL,"
           @"    details_json TEXT,"
           @"    created_by TEXT,"
           @"    created_at REAL NOT NULL"
           @")";
}

#pragma mark - Ozone Moderation Schemas

- (NSString *)ozoneEventsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_events ("
           @"    id TEXT PRIMARY KEY,"
           @"    action TEXT NOT NULL,"
           @"    subject_did TEXT NOT NULL,"
           @"    subject_type TEXT NOT NULL,"
           @"    reason TEXT,"
           @"    created_by TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    details_json TEXT"
           @")";
}

- (NSString *)ozoneSetsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_sets ("
           @"    id TEXT PRIMARY KEY,"
           @"    name TEXT NOT NULL,"
           @"    description TEXT,"
           @"    created_by TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL"
           @")";
}

- (NSString *)ozoneSetMembersTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_set_members ("
           @"    set_id TEXT NOT NULL,"
           @"    did TEXT NOT NULL,"
           @"    added_at REAL NOT NULL,"
           @"    PRIMARY KEY (set_id, did),"
           @"    FOREIGN KEY (set_id) REFERENCES moderation_sets(id) ON DELETE CASCADE"
           @")";
}

- (NSString *)ozoneTemplatesTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_templates ("
           @"    id TEXT PRIMARY KEY,"
           @"    name TEXT NOT NULL,"
           @"    text TEXT NOT NULL,"
           @"    created_by TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL"
           @")";
}

- (NSString *)ozoneTeamTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_team ("
           @"    did TEXT PRIMARY KEY,"
           @"    role TEXT NOT NULL,"
           @"    joined_at REAL NOT NULL"
           @")";
}

- (NSString *)ozoneScheduledActionsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_scheduled_actions ("
           @"    id TEXT PRIMARY KEY,"
           @"    subject_did TEXT NOT NULL,"
           @"    action_type TEXT NOT NULL,"
           @"    comment TEXT,"
           @"    duration_in_hours INTEGER,"
           @"    acknowledge_account_subjects INTEGER DEFAULT 0,"
           @"    policies_json TEXT,"
           @"    severity_level TEXT,"
           @"    strike_count INTEGER,"
           @"    strike_expires_at REAL,"
           @"    email_content TEXT,"
           @"    email_subject TEXT,"
           @"    execute_at REAL,"
           @"    execute_after REAL,"
           @"    execute_until REAL,"
           @"    created_by TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    status TEXT NOT NULL DEFAULT 'pending',"
           @"    mod_tool TEXT"
           @")";
}

- (NSString *)ozoneSubjectsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_subjects ("
           @"    subject_did TEXT NOT NULL,"
           @"    subject_type TEXT NOT NULL,"
           @"    review_state TEXT NOT NULL DEFAULT 'tools.ozone.moderation.defs#reviewOpen',"
           @"    last_event_id TEXT,"
           @"    updated_at REAL NOT NULL,"
           @"    PRIMARY KEY(subject_did, subject_type)"
           @")";
}

- (NSString *)ozoneSafelinksTableSchema {
    return @"CREATE TABLE IF NOT EXISTS moderation_safelinks ("
           @"    id INTEGER PRIMARY KEY AUTOINCREMENT,"
           @"    url TEXT NOT NULL,"
           @"    pattern TEXT NOT NULL,"
           @"    action TEXT NOT NULL,"
           @"    reason TEXT NOT NULL,"
           @"    comment TEXT,"
           @"    created_by TEXT NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL,"
           @"    UNIQUE(url, pattern)"
           @")";
}

#pragma mark - BSky AppView Schemas

- (NSString *)bskyAgeAssuranceTableSchema {
    return @"CREATE TABLE IF NOT EXISTS age_assurance_states ("
           @"    id TEXT PRIMARY KEY,"
           @"    did TEXT NOT NULL,"
           @"    status TEXT NOT NULL,"
           @"    email TEXT,"
           @"    country_code TEXT,"
           @"    region_code TEXT,"
           @"    language TEXT,"
           @"    token TEXT,"
           @"    created_at INTEGER,"
           @"    updated_at INTEGER"
           @")";
}

- (NSString *)bskyDraftsTableSchema {
    return @"CREATE TABLE IF NOT EXISTS drafts ("
           @"    id TEXT PRIMARY KEY,"
           @"    did TEXT NOT NULL,"
           @"    content TEXT,"
           @"    created_at INTEGER,"
           @"    updated_at INTEGER"
           @")";
}

- (NSString *)bskyBookmarksTableSchema {
    return @"CREATE TABLE IF NOT EXISTS bookmarks ("
           @"    uri TEXT PRIMARY KEY,"
           @"    did TEXT NOT NULL,"
           @"    created_at TEXT NOT NULL"
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
    [sql appendString:[self serviceWebAuthnCredentialsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self servicePendingFactorTokensTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceJWTSigningKeysTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceEventsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceActorPreferencesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self serviceActorMutesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self sequencerAnalyticsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self blobAuditJobsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self rateLimitHistoryTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneEventsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneSetsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneSetMembersTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneTemplatesTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneTeamTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneScheduledActionsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneSubjectsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self ozoneSafelinksTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self bskyAgeAssuranceTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self bskyDraftsTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self bskyBookmarksTableSchema]];
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
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_webauthn_credentials_account ON webauthn_credentials(account_did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_pending_factor_tokens_account ON pending_factor_tokens(account_did, method, expires_at);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_events_seq ON events(seq);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_sequencer_analytics_timestamp ON sequencer_analytics(timestamp);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_blob_audit_jobs_status ON blob_audit_jobs(status);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_rate_limit_history_identifier ON rate_limit_history(identifier);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_rate_limit_history_timestamp ON rate_limit_history(timestamp);"];
    [sql appendString:@";\n\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mod_events_subject ON moderation_events(subject_did, subject_type);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mod_events_created ON moderation_events(created_at);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mod_subjects_state ON moderation_subjects(review_state);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mod_set_members_did ON moderation_set_members(did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_mod_safelinks_url_pattern ON moderation_safelinks(url, pattern);"];
    [sql appendString:@";\n\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_age_assurance_did ON age_assurance_states(did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_drafts_did ON drafts(did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_bookmarks_did ON bookmarks(did);"];
    [sql appendString:@";\n"];

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
           @"    created_at DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
           @"    indexed_at DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
           @"    rev TEXT,"
           @"    subject_did TEXT"
           @")";
}

- (NSString *)actorStoreBlocksTableSchema {
    return @"CREATE TABLE IF NOT EXISTS ipld_blocks ("
           @"    cid BLOB PRIMARY KEY,"
           @"    block BLOB NOT NULL,"
           @"    size INTEGER NOT NULL,"
           @"    rev TEXT"
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

- (NSString *)actorStoreAccountUsageTableSchema {
    return @"CREATE TABLE IF NOT EXISTS account_usage ("
           @"    did TEXT PRIMARY KEY,"
           @"    blob_bytes INTEGER NOT NULL DEFAULT 0,"
           @"    blob_count INTEGER NOT NULL DEFAULT 0,"
           @"    repo_bytes INTEGER NOT NULL DEFAULT 0,"
           @"    record_count INTEGER NOT NULL DEFAULT 0,"
           @"    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))"
           @")";
}

- (NSString *)actorStoreRotationKeysTableSchema {
    return @"CREATE TABLE IF NOT EXISTS rotation_keys ("
           @"    did TEXT PRIMARY KEY,"
           @"    encrypted_private_key BLOB NOT NULL,"
           @"    public_key_compressed BLOB NOT NULL,"
           @"    encryption_salt BLOB NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL"
           @")";
}

- (NSString *)actorStoreSigningKeysTableSchema {
    return @"CREATE TABLE IF NOT EXISTS signing_keys ("
           @"    did TEXT PRIMARY KEY,"
           @"    private_key BLOB NOT NULL,"
           @"    public_key_compressed BLOB NOT NULL,"
           @"    created_at REAL NOT NULL,"
           @"    updated_at REAL NOT NULL"
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
    [sql appendString:[self actorStoreRotationKeysTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self actorStoreSigningKeysTableSchema]];
    [sql appendString:@";\n\n"];
    [sql appendString:[self actorStoreAccountUsageTableSchema]];
    [sql appendString:@";\n\n"];
    // Triggers to maintain account_usage from blobs, ipld_blocks, and records
    [sql appendString:kPDSAccountUsageTriggerBlobInsertSQL];
    [sql appendString:@";\n\n"];
    [sql appendString:kPDSAccountUsageTriggerBlobDeleteSQL];
    [sql appendString:@";\n\n"];
    [sql appendString:kPDSAccountUsageTriggerBlockInsertSQL];
    [sql appendString:@";\n\n"];
    [sql appendString:kPDSAccountUsageTriggerBlockDeleteSQL];
    [sql appendString:@";\n\n"];
    [sql appendString:kPDSAccountUsageTriggerRecordInsertSQL];
    [sql appendString:@";\n\n"];
    [sql appendString:kPDSAccountUsageTriggerRecordDeleteSQL];
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
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_ipld_blocks_rev ON ipld_blocks(rev);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_accounts_handle ON accounts(handle);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_blobs_did ON blobs(did);"];
    [sql appendString:@";\n"];
    [sql appendString:@"CREATE INDEX IF NOT EXISTS idx_blobs_cid ON blobs(cid);"];
    [sql appendString:@";\n\n"];
    [sql appendString:[self schemaVersionTableSQL]];
    return sql;
}

#pragma mark - Schema Version Tracking

- (NSString *)schemaVersionTableSQL {
    return @"CREATE TABLE IF NOT EXISTS schema_version ("
           @"    version INTEGER PRIMARY KEY,"
           @"    applied_at DATETIME NOT NULL DEFAULT (datetime('now')),"
           @"    description TEXT NOT NULL"
           @")";
}

#pragma mark - Common

- (NSString *)accountsTableSchema {
    return [self serviceAccountsTableSchema];
}

- (NSString *)inviteCodesTableSchema {
    return [self serviceInviteCodesTableSchema];
}

@end
