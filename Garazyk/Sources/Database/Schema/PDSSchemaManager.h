// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSSchemaManager.h

 @abstract Database schema management for PDS SQLite databases.

 @discussion Provides SQL schema definitions for service-level databases and
 per-actor stores. Centralizes all table schemas to ensure consistency across
 database creation and migration operations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSSchemaManager

 @abstract Central schema definition provider for PDS databases.

 @discussion PDSSchemaManager provides CREATE TABLE SQL statements for all
 database tables used in the PDS. The manager supports two database types:

 - **Service Database**: Shared tables for accounts, invite codes, refresh
   tokens, JWT keys, DID cache, and sequencer.
 - **Actor Store**: Per-user tables for repository roots, records, blocks,
   and blobs.

 Schema versions and migrations are handled by PDSMigrationManager. This
 manager only provides schema definitions.

 Thread-safety: Immutable schema strings, safe for concurrent access.

 Usage:
 @code
 PDSSchemaManager *manager = [PDSSchemaManager sharedManager];
 NSString *sql = [manager serviceSchemaSQL];
 [database executeSQL:sql error:nil];
 @endcode
 */
@interface PDSSchemaManager : NSObject

/*!
 @method sharedManager

 @abstract Get singleton schema manager instance.

 @return Shared PDSSchemaManager instance.
 */
+ (instancetype)sharedManager;

#pragma mark - Service Database Schemas

/*!
 @method serviceAccountsTableSchema

 @abstract Schema for accounts table (email, password, handle).

 @return CREATE TABLE SQL for accounts.
 */
- (NSString *)serviceAccountsTableSchema;

/*!
 @method serviceInviteCodesTableSchema

 @abstract Schema for invite codes table (code, uses, max_uses).

 @return CREATE TABLE SQL for invite codes.
 */
- (NSString *)serviceInviteCodesTableSchema;

/*!
 @method serviceAppPasswordsTableSchema

 @abstract Schema for app passwords table.

 @return CREATE TABLE SQL for app passwords.
 */
- (NSString *)serviceAppPasswordsTableSchema;

/*!
 @method serviceRefreshTokensTableSchema
 
 @abstract Schema for refresh tokens table (token, did, expires).

 @return CREATE TABLE SQL for refresh tokens.
 */
- (NSString *)serviceRefreshTokensTableSchema;

/*!
 @method serviceJWTSigningKeysTableSchema

 @abstract Schema for JWT signing keys table (kid, key_data, algorithm).

 @return CREATE TABLE SQL for JWT keys.
 */
- (NSString *)serviceJWTSigningKeysTableSchema;

/*!
 @method serviceDIDCacheTableSchema

 @abstract Schema for DID document cache (did, doc_json, expires_at).

 @return CREATE TABLE SQL for DID cache.
 */
- (NSString *)serviceDIDCacheTableSchema;

/*!
 @method serviceRepoSequenceTableSchema

 @abstract Schema for repository event sequencer (seq, did, event_type).

 @return CREATE TABLE SQL for sequencer.
 */
- (NSString *)serviceRepoSequenceTableSchema;

/*!
 @method serviceEventsTableSchema

 @abstract Schema for global firehose events table (seq, type, data).

 @return CREATE TABLE SQL for events.
 */
- (NSString *)serviceEventsTableSchema;

/*!
 @method serviceActorPreferencesTableSchema
 @abstract Returns the CREATE TABLE SQL for actor preferences.
 @return CREATE TABLE SQL for actor preferences.
 */
- (NSString *)serviceActorPreferencesTableSchema;

/*!
 @method serviceActorMutesTableSchema
 @abstract Returns the CREATE TABLE SQL for actor mutes.
 @return CREATE TABLE SQL for actor mutes.
 */
- (NSString *)serviceActorMutesTableSchema;

/*!
 @method sequencerAnalyticsTableSchema
 @abstract Schema for sequencer_analytics table (time-series metrics).
 @return CREATE TABLE SQL for sequencer analytics.
 */
- (NSString *)sequencerAnalyticsTableSchema;

/*!
 @method blobAuditJobsTableSchema
 @abstract Schema for blob_audit_jobs table (background job tracking).
 @return CREATE TABLE SQL for blob audit jobs.
 */
- (NSString *)blobAuditJobsTableSchema;

/*!
 @method serviceHostingEventsTableSchema

 @abstract Schema for hosting events (account created, handle updated, etc).

 @return CREATE TABLE SQL for hosting events.
 */
- (NSString *)serviceHostingEventsTableSchema;

/*!
 @method rateLimitHistoryTableSchema
 @abstract Schema for rate_limit_history table (admin action audit trail).
 @return CREATE TABLE SQL for rate limit history.
 */
- (NSString *)rateLimitHistoryTableSchema;

#pragma mark - Ozone Moderation Schemas

- (NSString *)ozoneEventsTableSchema;
- (NSString *)ozoneSetsTableSchema;
- (NSString *)ozoneSetMembersTableSchema;
- (NSString *)ozoneTemplatesTableSchema;
- (NSString *)ozoneTeamTableSchema;
- (NSString *)ozoneScheduledActionsTableSchema;
- (NSString *)ozoneSubjectsTableSchema;
- (NSString *)ozoneSafelinksTableSchema;

#pragma mark - BSky AppView Schemas

- (NSString *)bskyAgeAssuranceTableSchema;

- (NSString *)bskyDraftsTableSchema;

- (NSString *)bskyBookmarksTableSchema;

/*!
 @method serviceSchemaSQL
 @abstract Complete SQL for all service database tables.

 @discussion Returns concatenated CREATE TABLE statements for all service
 tables. Execute this SQL to initialize a new service database.

 @return Full service database schema SQL.
 */
- (NSString *)serviceSchemaSQL;

/*!
 @method serviceEventsTableSchema

 @abstract Schema for global firehose events table (seq, type, data).

 @return CREATE TABLE SQL for events.
 */
- (NSString *)serviceEventsTableSchema;

#pragma mark - Actor Store Schemas

/*!
 @method actorStoreRepoRootTableSchema

 @abstract Schema for repo_root table (cid, rev, indexed_at).

 @return CREATE TABLE SQL for repository root tracking.
 */
- (NSString *)actorStoreRepoRootTableSchema;

/*!
 @method actorStoreRecordsTableSchema

 @abstract Schema for records table (uri, cid, data, indexed_at).

 @return CREATE TABLE SQL for repository records.
 */
- (NSString *)actorStoreRecordsTableSchema;

/*!
 @method actorStoreBlocksTableSchema

 @abstract Schema for blocks table (cid, data).

 @return CREATE TABLE SQL for MST and CBOR blocks.
 */
- (NSString *)actorStoreBlocksTableSchema;

/*!
 @method actorStoreBlobsTableSchema

 @abstract Schema for blobs table (cid, mime_type, size, data).

 @return CREATE TABLE SQL for binary blob storage.
 */
- (NSString *)actorStoreBlobsTableSchema;

/*!
 @method actorStoreAccountUsageTableSchema
 @abstract Schema for account_usage table (per-actor storage metrics).
 @return CREATE TABLE SQL for account usage tracking.
 */
- (NSString *)actorStoreAccountUsageTableSchema;

/*!
 @method actorStoreSchemaSQL

 @abstract Complete SQL for all actor store tables.

 @discussion Returns concatenated CREATE TABLE statements for all per-actor
 tables. Execute this SQL to initialize a new actor store database.

 @return Full actor store schema SQL.
 */
- (NSString *)actorStoreSchemaSQL;

#pragma mark - Common

/*!
 @method accountsTableSchema

 @abstract Legacy accounts table schema for backward compatibility.

 @return CREATE TABLE SQL for accounts.
 */
- (NSString *)accountsTableSchema;

/*!
 @method inviteCodesTableSchema

 @abstract Legacy invite codes table schema for backward compatibility.

 @return CREATE TABLE SQL for invite codes.
 */
- (NSString *)inviteCodesTableSchema;

@end

NS_ASSUME_NONNULL_END
