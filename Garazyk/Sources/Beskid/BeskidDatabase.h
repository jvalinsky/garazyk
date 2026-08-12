// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file GZBeskidDatabase.h
 * @abstract SQLite-backed high-performance edge record and identity cache.
 */

#import <Foundation/Foundation.h>

@class GZBeskidMetrics;

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for Beskid database operations.
 */
extern NSString * const BeskidDatabaseErrorDomain;

/**
 * @abstract Database manager for Beskid edge record and identity caching.
 */
@interface GZBeskidDatabase : NSObject

/**
 * @abstract Initializes the database connection pool.
 * @param path File system path to the SQLite file.
 * @param error Receives failure details.
 * @return An initialized database instance.
 */
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;

/**
 * @abstract Runs database schema migrations (creates tables and indices).
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)runMigrations:(NSError **)error;

/**
 * @abstract Closes all connections in the connection pool.
 */
- (void)close;

#pragma mark - Record Cache Operations

/**
 * @abstract Retrieves a cached record by its URI.
 * @param uri Record URI (e.g., at://did:plc:.../collection/rkey).
 * @param cid Optional ATProtoCID string for strict version checking.
 * @param error Receives failure details.
 * @return Record dictionary, or nil if not found or expired.
 */
- (nullable NSDictionary *)recordByURI:(NSString *)uri
                                   cid:(nullable NSString *)cid
                                 error:(NSError **)error;

/**
 * @abstract Caches a new record with a TTL.
 * @param record Record JSON dictionary.
 * @param did Account DID.
 * @param collection Collection path (NSID).
 * @param rkey Record key.
 * @param cid Target ATProtoCID.
 * @param ttl Time-to-live in seconds.
 * @param error Receives failure details.
 * @return YES if cached successfully.
 */
- (BOOL)saveRecord:(NSDictionary *)record
               did:(NSString *)did
        collection:(NSString *)collection
              rkey:(NSString *)rkey
               cid:(NSString *)cid
               ttl:(NSTimeInterval)ttl
             error:(NSError **)error;

/**
 * @abstract Deletes a record from the cache.
 */
- (BOOL)deleteRecordForDID:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error;

/**
 * @abstract Deletes all cached records for an account (conservative invalidation).
 */
- (BOOL)deleteAllRecordsForDID:(NSString *)did error:(NSError **)error;

#pragma mark - Identity Cache Operations

/**
 * @abstract Caches a handle mapping to a DID.
 */
- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error;

/**
 * @abstract Resolves a handle to a DID locally.
 */
- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error;

/**
 * @abstract Resolves a DID to a handle locally.
 */
- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error;

/**
 * @abstract Caches a complete identity record with a TTL.
 */
- (BOOL)saveIdentity:(NSString *)did
              handle:(NSString *)handle
         pdsEndpoint:(NSString *)pdsEndpoint
          signingKey:(NSString *)signingKey
        rawDocument:(NSDictionary *)rawDocument
                 ttl:(NSTimeInterval)ttl
               error:(NSError **)error;

/**
 * @abstract Retrieves a cached identity record for a DID.
 */
- (nullable NSDictionary *)identityForDID:(NSString *)did error:(NSError **)error;

/**
 * @abstract Deletes a cached identity row for a DID.
 */
- (BOOL)deleteIdentityForDID:(NSString *)did error:(NSError **)error;

#pragma mark - Metrics

/** @abstract Metrics recorder: set to wire cache counters; lazily creates a private instance when nil. */
@property (nonatomic, strong) GZBeskidMetrics *metrics;

/** @abstract One-time COUNT of live record and identity entries for gauge seeding. */
- (NSDictionary<NSString *, NSNumber *> *)entryCountsWithError:(NSError **)error;

/** @abstract Total database storage in bytes via PRAGMA (cheap in-process lookup). */
- (long long)storageBytes;

@end

NS_ASSUME_NONNULL_END
