// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService.h"

NS_ASSUME_NONNULL_BEGIN

/** @abstract Provides actor-store writes within an active transaction. */
@protocol PDSActorStoreTransactor;

/**
 * @abstract Maintains the blob references owned by persisted repository records.
 * @discussion A reference sync replaces every blob_refs row for a record URI, marks matching actor
 * blobs as referenced, and deletes previously referenced blobs that have no remaining
 * reference for the actor. Invalid CIDs and CIDs without a matching actor blob are ignored.
 */
@interface PDSRecordService (BlobLifecycle)

/**
 * @abstract Replaces a record's blob references within a caller-owned actor-store transaction.
 * @discussion This method neither begins nor commits; propagate error from the transaction callback so its layer can roll back record and reference writes.
 * @param recordURI The persisted record URI whose references are replaced.
 * @param recordValue The record JSON value from which blob CIDs are extracted.
 * @param did The actor DID that scopes inserted references and blob reclamation.
 * @param transactor The active actor-store transactor for did.
 * @param error Receives SQL preparation, query, insertion, promotion, or reclamation failures.
 * @return YES when the replacement and orphan reclamation statements succeed; otherwise NO.
 */
- (BOOL)syncBlobReferencesForRecordURI:(NSString *)recordURI
                           recordValue:(NSDictionary *)recordValue
                                forDid:(NSString *)did
                            transactor:(id<PDSActorStoreTransactor>)transactor
                                 error:(NSError **)error;

/**
 * @abstract Replaces a record's blob references in a new actor-store transaction.
 * @discussion The database pool owns begin, commit, and rollback.
 * @param recordURI The persisted record URI whose references are replaced.
 * @param recordValue The record JSON value from which blob CIDs are extracted.
 * @param did The actor DID that owns the record and blobs.
 * @param error Receives transaction or blob-reference synchronization failures.
 * @return YES when synchronization succeeds and the transaction commits; otherwise NO.
 */
- (BOOL)syncBlobReferencesForRecordURI:(NSString *)recordURI
                              recordValue:(NSDictionary *)recordValue
                                   forDid:(NSString *)did
                                    error:(NSError **)error;

/**
 * @abstract Removes a record's blob references within a caller-owned transaction.
 * @discussion Equivalent to syncing an empty record value; unreferenced formerly linked blobs for did are deleted, and the caller owns rollback.
 * @param recordURI The persisted record URI whose references are removed.
 * @param did The actor DID that owns the record and blobs.
 * @param transactor The active actor-store transactor for did.
 * @param error Receives SQL or orphan-reclamation failures.
 * @return YES when the reference removal succeeds; otherwise NO.
 */
- (BOOL)removeBlobReferencesForRecordURI:(NSString *)recordURI
                                  forDid:(NSString *)did
                              transactor:(id<PDSActorStoreTransactor>)transactor
                                   error:(NSError **)error;

/**
 * @abstract Removes a record's blob references in a new actor-store transaction.
 * @discussion The database pool owns begin, commit, and rollback; this is equivalent to syncing an empty record value.
 * @param recordURI The persisted record URI whose references are removed.
 * @param did The actor DID that owns the record and blobs.
 * @param error Receives transaction or orphan-reclamation failures.
 * @return YES when reference removal succeeds and the transaction commits; otherwise NO.
 */
- (BOOL)removeBlobReferencesForRecordURI:(NSString *)recordURI
                                  forDid:(NSString *)did
                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
