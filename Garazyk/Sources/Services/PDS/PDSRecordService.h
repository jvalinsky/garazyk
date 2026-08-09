// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSRecordService.h
 *
 * @abstract Record management service layer.
 *
 * @discussion Provides CRUD operations for ATProto records within repositories.
 * Handles record listing with pagination and repository statistics.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/PDSRecordEvents.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Error domain for PDSRecordService errors.
 */
extern NSErrorDomain const PDSRecordServiceErrorDomain;

/**
 * @abstract Defines PDSRecordServiceError values exposed by this API.
 */
typedef NS_ENUM(NSInteger, PDSRecordServiceError) {
    PDSRecordServiceErrorUnauthorized = 1,
};

@class ATProtoMST;
@class ATProtoCID;

/**
 * @abstract Defines the PDSRecordRepository protocol contract.
 */
@protocol PDSRecordRepository;
@class PDSDatabasePool;
@class ATProtoLexiconValidator;
@class PDSServiceDatabases;

/**
 * @abstract Defines PDSValidationMode values exposed by this API.
 */
typedef NS_ENUM(NSInteger, PDSValidationMode) {
    /** Fail if lexicon unknown or validation fails. */
    PDSValidationModeRequired,
    /** Validate if known, allow if unknown. */
    PDSValidationModeOptimistic,
    /** Skip validation. */
    PDSValidationModeOff
};

/**
 * @abstract Service for record management operations.
 */
@interface PDSRecordService : NSObject

/**
 * @abstract Record repository.
 */
@property (nonatomic, strong) id<PDSRecordRepository> recordRepository;

/**
 * @abstract Database pool.
 * @discussion The owner (PDSController) must outlive this service.
 */
@property (nonatomic, strong) PDSDatabasePool *databasePool;

/**
 * @abstract Optional service databases for collection membership index maintenance.
 * @discussion When set, the service automatically upserts collection_membership entries
 * on record create/update so listReposByCollection can query membership
 * without scanning per-user actor stores. May be nil in test contexts.
 */
@property (nonatomic, strong, nullable) PDSServiceDatabases *serviceDatabases;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Record Operations

/**
 * @abstract Gets a record by AT URI.
 * @param uri The AT URI of the record.
 * @param did The decentralized identifier of the repository owner.
 * @param error Error pointer for retrieval failures.
 * @return The record dictionary, or nil if not found.
 */
- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Lists records in a collection with pagination.
 * @param collection The collection NSID.
 * @param did The decentralized identifier of the repository owner.
 * @param limit Maximum number of records to return.
 * @param cursor Pagination cursor.
 * @param error Error pointer for listing failures.
 * @return Array of record dictionaries, or nil if listing fails.
 */
- (nullable NSArray *)listRecords:(NSString *)collection
                          forDid:(NSString *)did
                           limit:(NSUInteger)limit
                          cursor:(nullable NSString *)cursor
                          error:(NSError **)error;

/**
 * @abstract Creates or updates a record.
 * @param collection The collection NSID (e.g., "app.bsky.feed.post").
 * @param rkey The record key within the collection.
 * @param value The record value as a dictionary.
 * @param did The repository owner DID.
 * @param actorDid The authenticated actor's DID (for authorization). Must equal did for self-modification.
 * @param mode Validation mode.
 * @param error On failure, describes what went wrong.
 * @return YES on success, NO on failure.
 */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
          actorDid:(NSString *)actorDid
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error;

/**
 * @abstract Creates or updates a record for the repository owner.
 * @param collection The collection NSID.
 * @param rkey The record key.
 * @param value The record value.
 * @param did The repository owner DID.
 * @param mode Validation mode.
 * @param error On failure, describes what went wrong.
 * @return YES on success, NO on failure.
 */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
    validationMode:(PDSValidationMode)mode
             error:(NSError **)error;

/**
 * @abstract Creates or updates a record for the repository owner with optimistic validation.
 * @param collection The collection NSID.
 * @param rkey The record key.
 * @param value The record value.
 * @param did The repository owner DID.
 * @param error On failure, describes what went wrong.
 * @return YES on success, NO on failure.
 */
- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
             error:(NSError **)error;

/**
 * @abstract Deletes a record.
 * @param collection The collection NSID.
 * @param rkey The record key.
 * @param did The repository owner DID.
 * @param actorDid The authenticated actor's DID (for authorization). Must equal did for self-modification.
 * @param error On failure, describes what went wrong.
 * @return YES on success, NO on failure.
 */
- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
             actorDid:(NSString *)actorDid
                error:(NSError **)error;

/**
 * @abstract Deletes a record for the repository owner.
 * @param collection The collection NSID.
 * @param rkey The record key.
 * @param did The repository owner DID.
 * @param error On failure, describes what went wrong.
 * @return YES on success, NO on failure.
 */
- (BOOL)deleteRecord:(NSString *)collection
                 rkey:(NSString *)rkey
               forDid:(NSString *)did
                error:(NSError **)error;

/**
 * @abstract Atomically applies a batch of writes in a single transaction.
 * @discussion If any write fails, all preceding writes in the batch are rolled back.
 * @param writes Array of write operations, each a dictionary with keys: action, collection, rkey (required for update/delete), and value (for create/update). Optional key 'swapRecord' (ATProtoCID string) is supported for update/delete. Legacy key 'record' is also accepted for compatibility.
 * @param did The repository DID.
 * @param actorDid The authenticated actor's DID (for authorization). Must equal did for self-modification.
 * @param mode Validation mode.
 * @param swapCommit If non-nil, the expected current repo root ATProtoCID. Fails if it doesn't match.
 * @param error On failure, describes what went wrong.
 * @return Result dictionary with commit info on success, nil on failure.
 */
- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                               actorDid:(NSString *)actorDid
                         validationMode:(PDSValidationMode)mode
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error;

/**
 * @abstract Atomically applies a batch of writes for the repository owner in a single transaction.
 * @discussion If any write fails, all preceding writes in the batch are rolled back.
 * @param writes Array of write operations.
 * @param did The repository DID.
 * @param mode Validation mode.
 * @param swapCommit If non-nil, the expected current repo root ATProtoCID. Fails if it doesn't match.
 * @param error On failure, describes what went wrong.
 * @return Result dictionary with commit info on success, nil on failure.
 */
- (nullable NSDictionary *)applyWrites:(NSArray<NSDictionary *> *)writes
                                 forDid:(NSString *)did
                         validationMode:(PDSValidationMode)mode
                             swapCommit:(nullable NSString *)swapCommit
                                  error:(NSError **)error;

/**
 * @abstract Gets repository statistics.
 * @param did The repository DID.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary containing record count, blob count, etc., or nil on failure.
 */
- (nullable NSDictionary *)getRepoStatsForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
