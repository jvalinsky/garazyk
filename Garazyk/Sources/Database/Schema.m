#import "Database/Schema.h"

NSInteger const kPDSDatabaseSchemaVersion = 1;

NSString * const kPDSAccountTableName = @"accounts";
NSString * const kPDSAgeAssuranceNoVerification = @"no_verification";
NSString * const kPDSAgeAssuranceVerifiedByAdult = @"verified_by_adult";
NSString * const kPDSAgeAssuranceVerifiedByMethod = @"verified_by_method";
NSString * const kPDSRepoTableName = @"repos";
NSString * const kPDSRecordTableName = @"records";
NSString * const kPDSBlockTableName = @"blocks";
NSString * const kPDSBlobTableName = @"blobs";
NSString * const kPDSAccountUsageTableName = @"account_usage";
NSString * const kPDSInviteCodeTableName = @"invite_codes";

NSString * const kPDSAdminTakedownTableName = @"admin_takedowns";
NSString * const kPDSAdminAuditLogTableName = @"admin_audit_log";
NSString * const kPDSReportsTableName = @"reports";
NSString * const kPDSAdminConfigTableName = @"admin_config";
NSString * const kPDSLabelTableName = @"labels";
NSString * const kPDSReservedHandleTableName = @"reserved_handles";
NSString * const kPDSPasskeysTableName = @"passkeys";
NSString * const kPDSOAuthClientsTableName = @"oauth_clients";
NSString * const kPDSOAuthAuthorizationCodesTableName = @"oauth_authorization_codes";
NSString * const kPDSOAuthRefreshTokensTableName = @"oauth_refresh_tokens";
NSString * const kPDSOAuthPARTableName = @"oauth_par";
NSString * const kPDSOAuthGrantsTableName = @"oauth_grants";
NSString * const kPDSActorPreferencesTableName = @"actor_preferences";
NSString * const kPDSActorMutesTableName = @"actor_mutes";
NSString * const kPDSBookmarkTableName = @"bookmarks";
NSString * const kPDSStarterPackTableName = @"starter_packs";
NSString * const kPDSGroupsTableName = @"groups";
NSString * const kPDSGroupMembersTableName = @"group_members";
NSString * const kPDSGroupInviteLinksTableName = @"group_invite_links";
NSString * const kPDSGroupJoinRequestsTableName = @"group_join_requests";
NSString * const kPDSGroupMessagesTableName = @"group_messages";
NSString * const kPDSGroupMessageReactionsTableName = @"group_message_reactions";

NSString * const kPDSAccountTableCreateSQL = 
    @"CREATE TABLE IF NOT EXISTS accounts ("
    @"did TEXT PRIMARY KEY,"
    @"handle TEXT UNIQUE NOT NULL,"
    @"email TEXT,"
    @"password_hash BLOB,"
    @"password_salt BLOB,"
    @"access_jwt BLOB,"
    @"refresh_jwt BLOB,"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL,"
    @"tfa_enabled INTEGER DEFAULT 0,"
    @"tfa_secret BLOB,"
    @"recovery_codes BLOB,"
    @"invite_enabled INTEGER DEFAULT 0,"
    @"age_assurance TEXT,"
    @"age_verified_at TEXT"
    @")";

NSString * const kPDSRepoTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS repos ("
    @"owner_did TEXT PRIMARY KEY,"
    @"root_cid BLOB NOT NULL,"
    @"collection_data BLOB,"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL"
    @")";

NSString * const kPDSRecordTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS records ("
    @"uri TEXT PRIMARY KEY,"
    @"did TEXT NOT NULL,"
    @"collection TEXT NOT NULL,"
    @"rkey TEXT NOT NULL,"
    @"cid TEXT NOT NULL,"
    @"value TEXT,"
    @"subject_did TEXT,"
    @"created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
    @"indexed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
    @"FOREIGN KEY (did) REFERENCES accounts(did)"
    @");"
    @"CREATE INDEX IF NOT EXISTS idx_records_did_collection ON records(did, collection);"
    @"CREATE INDEX IF NOT EXISTS idx_records_did_collection_rkey ON records(did, collection, rkey);"
    @"CREATE INDEX IF NOT EXISTS idx_records_subject_did ON records(subject_did);"
    @"CREATE INDEX IF NOT EXISTS idx_records_subject_did_collection ON records(subject_did, collection);";

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

NSString * const kPDSBlobTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS blobs ("
    @"cid BLOB PRIMARY KEY,"
    @"did TEXT NOT NULL,"
    @"mime_type TEXT,"
    @"size INTEGER NOT NULL,"
    @"created_at TEXT NOT NULL,"
    @"FOREIGN KEY (did) REFERENCES accounts(did)"
    @")";

#pragma mark - Account Usage

NSString * const kPDSAccountUsageTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS account_usage ("
    @"did TEXT PRIMARY KEY,"
    @"blob_bytes INTEGER NOT NULL DEFAULT 0,"
    @"blob_count INTEGER NOT NULL DEFAULT 0,"
    @"repo_bytes INTEGER NOT NULL DEFAULT 0,"
    @"record_count INTEGER NOT NULL DEFAULT 0,"
    @"updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))"
    @")";

NSString * const kPDSAccountUsageTriggerBlobInsertSQL =
    @"CREATE TRIGGER IF NOT EXISTS trg_account_usage_blob_insert "
    @"AFTER INSERT ON blobs "
    @"BEGIN "
    @"INSERT INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count, updated_at) "
    @"VALUES (NEW.did, NEW.size, 1, 0, 0, strftime('%Y-%m-%dT%H:%M:%fZ','now')) "
    @"ON CONFLICT(did) DO UPDATE SET "
    @"blob_bytes = blob_bytes + NEW.size, "
    @"blob_count = blob_count + 1, "
    @"updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'); "
    @"END";

NSString * const kPDSAccountUsageTriggerBlobDeleteSQL =
    @"CREATE TRIGGER IF NOT EXISTS trg_account_usage_blob_delete "
    @"AFTER DELETE ON blobs "
    @"BEGIN "
    @"UPDATE account_usage SET "
    @"blob_bytes = MAX(blob_bytes - OLD.size, 0), "
    @"blob_count = MAX(blob_count - 1, 0), "
    @"updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') "
    @"WHERE did = OLD.did; "
    @"END";

NSString * const kPDSAccountUsageTriggerBlockInsertSQL =
    @"CREATE TRIGGER IF NOT EXISTS trg_account_usage_block_insert "
    @"AFTER INSERT ON ipld_blocks "
    @"BEGIN "
    @"INSERT INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count, updated_at) "
    @"VALUES ((SELECT did FROM records LIMIT 1), 0, 0, NEW.size, 0, strftime('%Y-%m-%dT%H:%M:%fZ','now')) "
    @"ON CONFLICT(did) DO UPDATE SET "
    @"repo_bytes = repo_bytes + NEW.size, "
    @"updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'); "
    @"END";

NSString * const kPDSAccountUsageTriggerBlockDeleteSQL =
    @"CREATE TRIGGER IF NOT EXISTS trg_account_usage_block_delete "
    @"AFTER DELETE ON ipld_blocks "
    @"BEGIN "
    @"UPDATE account_usage SET "
    @"repo_bytes = MAX(repo_bytes - OLD.size, 0), "
    @"updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') "
    @"WHERE did = (SELECT did FROM records LIMIT 1); "
    @"END";

NSString * const kPDSAccountUsageTriggerRecordInsertSQL =
    @"CREATE TRIGGER IF NOT EXISTS trg_account_usage_record_insert "
    @"AFTER INSERT ON records "
    @"BEGIN "
    @"INSERT INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count, updated_at) "
    @"VALUES (NEW.did, 0, 0, 0, 1, strftime('%Y-%m-%dT%H:%M:%fZ','now')) "
    @"ON CONFLICT(did) DO UPDATE SET "
    @"record_count = record_count + 1, "
    @"updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now'); "
    @"END";

NSString * const kPDSAccountUsageTriggerRecordDeleteSQL =
    @"CREATE TRIGGER IF NOT EXISTS trg_account_usage_record_delete "
    @"AFTER DELETE ON records "
    @"BEGIN "
    @"UPDATE account_usage SET "
    @"record_count = MAX(record_count - 1, 0), "
    @"updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') "
    @"WHERE did = OLD.did; "
    @"END";

NSString * const kPDSIndexBlocksRepoDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_blocks_repo_did ON blocks(repo_did)";

NSString * const kPDSIndexBlobsDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_blobs_did ON blobs(did)";

NSString * const kPDSIndexAccountsHandleSQL = 
    @"CREATE INDEX IF NOT EXISTS idx_accounts_handle ON accounts(handle)";

NSString * const kPDSInviteCodeTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS invite_codes ("
    @"id TEXT PRIMARY KEY,"
    @"code TEXT NOT NULL UNIQUE,"
    @"account_did TEXT NOT NULL,"
    @"created_at TEXT NOT NULL,"
    @"uses INTEGER DEFAULT 0,"
    @"max_uses INTEGER DEFAULT 1,"
    @"disabled INTEGER DEFAULT 0"
    @")";

NSString * const kPDSAdminTakedownTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS admin_takedowns ("
    @"id TEXT PRIMARY KEY,"
    @"subjectType TEXT NOT NULL,"
    @"subjectId TEXT NOT NULL,"
    @"reason TEXT,"
    @"takedownRef TEXT,"
    @"applied BOOLEAN NOT NULL DEFAULT 1,"
    @"createdBy TEXT NOT NULL,"
    @"createdAt DATETIME NOT NULL"
    @")";

NSString * const kPDSAdminAuditLogTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS admin_audit_log ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"admin_did TEXT NOT NULL,"
    @"action TEXT NOT NULL,"
    @"subject_type TEXT,"
    @"subject_id TEXT,"
    @"details TEXT,"
    @"ip_address TEXT,"
    @"created_at DATETIME NOT NULL"
    @")";

NSString * const kPDSReportsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS reports ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"report_id TEXT NOT NULL UNIQUE,"
    @"reason_type TEXT NOT NULL,"
    @"reason TEXT,"
    @"reported_by_did TEXT NOT NULL,"
    @"subject_type TEXT NOT NULL,"
    @"subject_did TEXT,"
    @"subject_uri TEXT,"
    @"status TEXT NOT NULL DEFAULT 'open',"
    @"resolved_by_did TEXT,"
    @"resolved_at DATETIME,"
    @"resolution_notes TEXT,"
    @"created_at DATETIME NOT NULL"
    @")";

NSString * const kPDSAdminConfigTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS admin_config ("
    @"key TEXT PRIMARY KEY,"
    @"value TEXT NOT NULL,"
    @"updated_at DATETIME NOT NULL"
    @")";

NSString * const kPDSLabelTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS labels ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"src TEXT NOT NULL,"
    @"uri TEXT NOT NULL,"
    @"cid TEXT,"
    @"val TEXT NOT NULL,"
    @"neg INTEGER DEFAULT 0,"
    @"cts TEXT NOT NULL,"
    @"exp TEXT"
    @")";

NSString * const kPDSReservedHandleTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS reserved_handles ("
    @"handle TEXT PRIMARY KEY,"
    @"created_at REAL NOT NULL"
    @")";

NSString * const kPDSIndexInviteCodesAccountDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_invite_codes_account_did ON invite_codes(account_did)";

NSString * const kPDSIndexTakedownsSubjectIdSQL =
    @"CREATE INDEX IF NOT EXISTS idx_admin_takedowns_subject_id ON admin_takedowns(subjectId)";

NSString * const kPDSIndexAuditLogAdminSQL =
    @"CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON admin_audit_log(admin_did)";

NSString * const kPDSIndexAuditLogSubjectSQL =
    @"CREATE INDEX IF NOT EXISTS idx_audit_log_subject ON admin_audit_log(subject_type, subject_id)";

NSString * const kPDSIndexAuditLogCreatedSQL =
    @"CREATE INDEX IF NOT EXISTS idx_audit_log_created ON admin_audit_log(created_at)";

NSString * const kPDSIndexReportsStatusSQL =
    @"CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status)";

NSString * const kPDSIndexReportsSubjectSQL =
    @"CREATE INDEX IF NOT EXISTS idx_reports_subject ON reports(subject_type, subject_did)";

NSString * const kPDSIndexReportsReportedBySQL =
    @"CREATE INDEX IF NOT EXISTS idx_reports_reported_by ON reports(reported_by_did)";

NSString * const kPDSIndexReportsCreatedSQL =
    @"CREATE INDEX IF NOT EXISTS idx_reports_created ON reports(created_at)";

NSString * const kPDSIndexLabelsUriSQL =
    @"CREATE INDEX IF NOT EXISTS idx_labels_uri ON labels(uri)";

NSString * const kPDSIndexLabelsSourceSQL =
    @"CREATE INDEX IF NOT EXISTS idx_labels_source ON labels(src)";

NSString * const kPDSIndexReservedHandlesHandleSQL =
    @"CREATE INDEX IF NOT EXISTS idx_reserved_handles_handle ON reserved_handles(handle)";

NSString * const kPDSPasskeysTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS passkeys ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"account_did TEXT NOT NULL,"
    @"credential_id TEXT NOT NULL,"
    @"public_key BLOB NOT NULL,"
    @"counter INTEGER DEFAULT 0,"
    @"aaguid TEXT,"
    @"created_at TEXT NOT NULL,"
    @"last_used_at TEXT,"
    @"FOREIGN KEY (account_did) REFERENCES accounts(did)"
    @")";

NSString * const kPDSIndexPasskeysAccountDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_passkeys_account_did ON passkeys(account_did)";

NSString * const kPDSIndexPasskeysCredentialIdSQL =
    @"CREATE INDEX IF NOT EXISTS idx_passkeys_credential_id ON passkeys(credential_id)";

NSString * const kPDSOAuthClientsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS oauth_clients ("
    @"client_id TEXT PRIMARY KEY,"
    @"client_secret TEXT,"
    @"redirect_uris TEXT NOT NULL,"
    @"grant_types TEXT,"
    @"scope TEXT,"
    @"created_at TEXT NOT NULL"
    @")";

NSString * const kPDSOAuthAuthorizationCodesTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS oauth_authorization_codes ("
    @"code TEXT PRIMARY KEY,"
    @"client_id TEXT NOT NULL,"
    @"redirect_uri TEXT NOT NULL,"
    @"scope TEXT,"
    @"state TEXT,"
    @"code_challenge TEXT,"
    @"code_challenge_method TEXT,"
    @"nonce TEXT,"
    @"dpop_jwk TEXT,"
    @"login_hint TEXT,"
    @"login_hint_did TEXT,"
    @"created_at REAL NOT NULL,"
    @"expires_at REAL NOT NULL"
    @")";

NSString * const kPDSOAuthRefreshTokensTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS oauth_refresh_tokens ("
    @"token_id TEXT PRIMARY KEY,"
    @"client_id TEXT NOT NULL,"
    @"did TEXT NOT NULL,"
    @"scope TEXT,"
    @"dpop_jwk TEXT,"
    @"created_at REAL NOT NULL,"
    @"expires_at REAL NOT NULL,"
    @"revoked_at REAL"
    @")";

NSString * const kPDSOAuthPARTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS oauth_par ("
    @"request_uri TEXT PRIMARY KEY,"
    @"request_data TEXT NOT NULL,"
    @"created_at REAL NOT NULL,"
    @"expires_at REAL NOT NULL"
    @")";

NSString * const kPDSOAuthGrantsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS oauth_grants ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"did TEXT NOT NULL,"
    @"client_id TEXT NOT NULL,"
    @"scope TEXT NOT NULL,"
    @"created_at REAL NOT NULL,"
    @"UNIQUE(did, client_id, scope)"
    @")";

NSString * const kPDSJWTSigningKeysTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS jwt_signing_keys ("
    @"key_id TEXT PRIMARY KEY,"
    @"algorithm TEXT NOT NULL,"
    @"private_key_data BLOB,"
    @"public_key_data BLOB NOT NULL,"
    @"keychain_tag TEXT,"
    @"is_active INTEGER DEFAULT 1,"
    @"created_at TEXT NOT NULL,"
    @"last_used_at TEXT"
    @")";

NSString * const kPDSActorPreferencesTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS actor_preferences ("
    @"did TEXT PRIMARY KEY,"
    @"preferences BLOB NOT NULL,"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL,"
    @"FOREIGN KEY (did) REFERENCES accounts(did)"
    @")";

NSString * const kPDSActorMutesTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS actor_mutes ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"did TEXT NOT NULL,"
    @"muted_did TEXT NOT NULL,"
    @"created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),"
    @"UNIQUE(did, muted_did)"
    @")";

NSString * const kPDSBookmarkTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS bookmarks ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"did TEXT NOT NULL,"
    @"uri TEXT NOT NULL UNIQUE,"
    @"subject_uri TEXT NOT NULL,"
    @"subject_cid TEXT,"
    @"created_at TEXT NOT NULL,"
    @"UNIQUE(did, subject_uri)"
    @")";

NSString * const kPDSStarterPackTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS starter_packs ("
    @"id INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"did TEXT NOT NULL,"
    @"rkey TEXT NOT NULL,"
    @"cid TEXT NOT NULL,"
    @"name TEXT,"
    @"created_at TEXT NOT NULL,"
    @"UNIQUE(did, rkey)"
    @")";

NSString * const kPDSIndexBookmarksDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_bookmarks_did ON bookmarks(did)";

NSString * const kPDSIndexStarterPacksDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_starter_packs_did ON starter_packs(did)";

#pragma mark - Groups

NSString * const kPDSGroupsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS groups ("
    @"uri TEXT PRIMARY KEY,"
    @"creator_did TEXT NOT NULL,"
    @"name TEXT NOT NULL,"
    @"description TEXT,"
    @"avatar_blob_cid TEXT,"
    @"privacy TEXT NOT NULL DEFAULT 'private',"
    @"joinability TEXT NOT NULL DEFAULT 'invite_only',"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL"
    @")";

NSString * const kPDSGroupMembersTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS group_members ("
    @"group_uri TEXT NOT NULL,"
    @"member_did TEXT NOT NULL,"
    @"role TEXT NOT NULL DEFAULT 'member',"
    @"status TEXT NOT NULL DEFAULT 'accepted',"
    @"invited_by TEXT,"
    @"joined_at TEXT NOT NULL,"
    @"PRIMARY KEY (group_uri, member_did)"
    @")";

NSString * const kPDSGroupInviteLinksTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS group_invite_links ("
    @"id TEXT PRIMARY KEY,"
    @"group_uri TEXT NOT NULL,"
    @"created_by TEXT NOT NULL,"
    @"created_at TEXT NOT NULL,"
    @"expires_at TEXT,"
    @"max_uses INTEGER,"
    @"uses INTEGER DEFAULT 0,"
    @"enabled INTEGER DEFAULT 1"
    @")";

NSString * const kPDSGroupJoinRequestsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS group_join_requests ("
    @"id TEXT PRIMARY KEY,"
    @"group_uri TEXT NOT NULL,"
    @"requester_did TEXT NOT NULL,"
    @"status TEXT NOT NULL DEFAULT 'pending',"
    @"requested_at TEXT NOT NULL,"
    @"responded_at TEXT,"
    @"responded_by TEXT,"
    @"UNIQUE(group_uri, requester_did)"
    @")";

NSString * const kPDSIndexGroupMembersGroupSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_uri)";

NSString * const kPDSIndexGroupMembersMemberSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_members_member ON group_members(member_did)";

NSString * const kPDSIndexGroupInviteLinksGroupSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_invite_links_group ON group_invite_links(group_uri)";

NSString * const kPDSIndexGroupJoinRequestsGroupSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_join_requests_group ON group_join_requests(group_uri)";

NSString * const kPDSIndexGroupJoinRequestsRequesterSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_join_requests_requester ON group_join_requests(requester_did)";

NSString * const kPDSGroupMessagesTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS group_messages ("
    @"id TEXT PRIMARY KEY,"
    @"group_uri TEXT NOT NULL,"
    @"sender_did TEXT NOT NULL,"
    @"text TEXT,"
    @"embed_json TEXT,"
    @"created_at TEXT NOT NULL,"
    @"deleted_for_json TEXT,"
    @"FOREIGN KEY (group_uri) REFERENCES groups(uri)"
    @")";

NSString * const kPDSGroupMessageReactionsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS group_message_reactions ("
    @"message_id TEXT NOT NULL,"
    @"actor_did TEXT NOT NULL,"
    @"emoji TEXT NOT NULL,"
    @"created_at TEXT NOT NULL,"
    @"PRIMARY KEY (message_id, actor_did, emoji),"
    @"FOREIGN KEY (message_id) REFERENCES group_messages(id)"
    @")";

NSString * const kPDSIndexGroupMessagesGroupSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_messages_group ON group_messages(group_uri)";

NSString * const kPDSIndexGroupMessagesCreatedSQL =
    @"CREATE INDEX IF NOT EXISTS idx_group_messages_created ON group_messages(created_at)";

#pragma mark - Video Jobs

NSString * const kPDSVideoJobsTableCreateSQL =
    @"CREATE TABLE IF NOT EXISTS video_jobs ("
    @"job_id TEXT PRIMARY KEY,"
    @"did TEXT NOT NULL,"
    @"blob_cid TEXT NOT NULL,"
    @"original_filename TEXT,"
    @"mime_type TEXT,"
    @"file_size INTEGER,"
    @"duration_seconds INTEGER,"
    @"width INTEGER,"
    @"height INTEGER,"
    @"state TEXT NOT NULL DEFAULT 'PENDING',"
    @"progress INTEGER DEFAULT 0,"
    @"message TEXT,"
    @"error_code TEXT,"
    @"error_message TEXT,"
    @"thumbnail_blob_cid TEXT,"
    @"processed_blob_cid TEXT,"
    @"created_at TEXT NOT NULL,"
    @"updated_at TEXT NOT NULL,"
    @"completed_at TEXT,"
    @"expires_at TEXT,"
    @"retry_count INTEGER DEFAULT 0"
    @")";

NSString * const kPDSVideoJobsIndexDidSQL =
    @"CREATE INDEX IF NOT EXISTS idx_video_jobs_did ON video_jobs(did)";

NSString * const kPDSVideoJobsIndexStateSQL =
    @"CREATE INDEX IF NOT EXISTS idx_video_jobs_state ON video_jobs(state)";

NSString * const kPDSVideoJobsIndexCreatedSQL =
    @"CREATE INDEX IF NOT EXISTS idx_video_jobs_created ON video_jobs(created_at)";
