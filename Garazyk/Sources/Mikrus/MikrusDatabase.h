// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file MikrusDatabase.h
 * @abstract SQLite-backed link index for Microcosm Mikrus-style queries.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MikrusSourceSpec;

/**
 * @abstract Error domain for Mikrus database operations.
 */
extern NSString * const MikrusDatabaseErrorDomain;

/**
 * @abstract Database manager for Mikrus link indexing.
 */
@interface MikrusDatabase : NSObject

/**
 * @abstract Initializes the database connection.
 * @param path File system path to the SQLite file.
 * @param error Receives failure details.
 * @return An initialized database instance.
 */
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;

/**
 * @abstract Runs database schema migrations.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)runMigrations:(NSError **)error;

/**
 * @abstract Closes the database connection.
 */
- (void)close;

/**
 * @abstract Indexes a new record.
 * @param record Record data.
 * @param did Account DID.
 * @param collection Collection path.
 * @param rkey Record key.
 * @param cid Optional CID string.
 * @param seq Sequence number.
 * @param error Receives failure details.
 * @return YES if successful.
 */
/**
 * @abstract Performs the indexRecord operation.
 */
- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
                seq:(int64_t)seq
              error:(NSError **)error;

/**
 * @abstract Deletes a record from the index.
 * @param did Account DID.
 * @param collection Collection path.
 * @param rkey Record key.
 * @param error Receives failure details.
 * @return YES if successful.
 */
- (BOOL)deleteRecordForDID:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error;

/**
 * @abstract Queries backlink records for a given subject.
 * @param subject Subject URI.
 * @param source Specification for source records.
 * @param didFilters Array of DIDs to filter by.
 * @param limit Pagination limit.
 * @param cursor Pagination cursor.
 * @param nextCursor Output parameter for the next cursor.
 * @param total Output parameter for result count.
 * @param error Receives failure details.
 * @return Array of backlink records.
 */
/**
 * @abstract Performs the backlinkRecordsForSubject operation.
 */
- (nullable NSArray<NSDictionary *> *)backlinkRecordsForSubject:(NSString *)subject
                                                         source:(MikrusSourceSpec *)source
                                                     didFilters:(NSArray<NSString *> *)didFilters
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                     nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                          total:(NSInteger * _Nullable)total
                                                          error:(NSError **)error;

/**
 * @abstract Queries backlink DIDs for a given subject.
 * @param subject Subject URI.
 * @param source Specification for source records.
 * @param limit Pagination limit.
 * @param cursor Pagination cursor.
 * @param nextCursor Output parameter for the next cursor.
 * @param total Output parameter for result count.
 * @param error Receives failure details.
 * @return Array of DIDs.
 */
/**
 * @abstract Performs the backlinkDIDsForSubject operation.
 */
- (nullable NSArray<NSString *> *)backlinkDIDsForSubject:(NSString *)subject
                                                  source:(MikrusSourceSpec *)source
                                                   limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                              nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                   total:(NSInteger * _Nullable)total
                                                   error:(NSError **)error;

/**
 * @abstract Counts backlinks for a given subject.
 * @param subject Subject URI.
 * @param source Specification for source records.
 * @param error Receives failure details.
 * @return Backlink count.
 */
- (NSInteger)backlinksCountForSubject:(NSString *)subject
                                source:(MikrusSourceSpec *)source
                                 error:(NSError **)error;

/**
 * @abstract Queries many-to-many relationship items.
 * @param subject Subject URI.
 * @param source Specification for source records.
 * @param pathToOther Path to the related item.
 * @param linkDIDs Array of link DIDs.
 * @param otherSubjects Array of other subject URIs.
 * @param limit Pagination limit.
 * @param cursor Pagination cursor.
 * @param nextCursor Output parameter for the next cursor.
 * @param error Receives failure details.
 * @return Array of relationship results.
 */
/**
 * @abstract Performs the manyToManyItemsForSubject operation.
 */
- (nullable NSArray<NSDictionary *> *)manyToManyItemsForSubject:(NSString *)subject
                                                         source:(MikrusSourceSpec *)source
                                                    pathToOther:(NSString *)pathToOther
                                                     linkDIDs:(NSArray<NSString *> *)linkDIDs
                                                  otherSubjects:(NSArray<NSString *> *)otherSubjects
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                     nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                          error:(NSError **)error;

/**
 * @abstract Queries many-to-many relationship counts.
 * @param subject Subject URI.
 * @param source Specification for source records.
 * @param pathToOther Path to the related item.
 * @param dids Account DIDs.
 * @param otherSubjects Array of other subject URIs.
 * @param limit Pagination limit.
 * @param cursor Pagination cursor.
 * @param nextCursor Output parameter for the next cursor.
 * @param error Receives failure details.
 * @return Array of relationship count results.
 */
/**
 * @abstract Performs the manyToManyCountsForSubject operation.
 */
- (nullable NSArray<NSDictionary *> *)manyToManyCountsForSubject:(NSString *)subject
                                                          source:(MikrusSourceSpec *)source
                                                     pathToOther:(NSString *)pathToOther
                                                            dids:(NSArray<NSString *> *)dids
                                                   otherSubjects:(NSArray<NSString *> *)otherSubjects
                                                           limit:(NSInteger)limit
                                                          cursor:(nullable NSString *)cursor
                                                      nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                           error:(NSError **)error;

/**
 * @abstract Retrieves a record by its URI.
 * @param uri Record URI.
 * @param cid Optional CID string.
 * @param error Receives failure details.
 * @return Record dictionary.
 */
- (nullable NSDictionary *)recordByURI:(NSString *)uri
                                   cid:(nullable NSString *)cid
                                 error:(NSError **)error;

/**
 * @abstract Saves handle mapping to DID.
 * @param handle Handle string.
 * @param did DID string.
 * @param error Receives failure details.
 * @return YES if saved successfully.
 */
- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error;

/**
 * @abstract Resolves handle to DID.
 * @param handle Handle string.
 * @param error Receives failure details.
 * @return DID string or nil if not found.
 */
- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error;

/**
 * @abstract Resolves DID to handle.
 * @param did DID string.
 * @param error Receives failure details.
 * @return Handle string or nil if not found.
 */
- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
