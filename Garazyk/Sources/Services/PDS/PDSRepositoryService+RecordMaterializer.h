// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Loads repository records and produces DAG-CBOR values used for repository export.
 * @discussion The category reads actor-scoped records through the supplied store or database pool.
 * It does not persist materialized record blocks itself.
 */
@interface PDSRepositoryService (RecordMaterializer)

/**
 * @abstract Loads all records for one actor, subject to the export safety limit.
 * @discussion Reads pages of 1,000 records and rejects repositories at or above 100,000 records
 * rather than returning a partial result.
 * @param store The actor store to query.
 * @param did The actor DID whose records are loaded.
 * @param error Receives record-listing failures or the export safety-cap error.
 * @return All records for did, or nil when listing fails or the repository reaches the safety cap.
 */
- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                      did:(NSString *)did
                                                    error:(NSError **)error;
/**
 * @abstract Returns the canonical DAG-CBOR block for a persisted record.
 * @discussion The actor store's IPLD block is preferred. If it is absent, the method encodes the
 * record's JSON value and returns it only when its computed CID matches record.cid. The fallback
 * does not write the reconstructed block.
 * @param record The persisted record whose CID and value identify the block.
 * @return Block bytes, or nil when no canonical block is available or fallback validation fails.
 */
- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record;
/**
 * @abstract Encodes a CID as a DAG-CBOR link value.
 * @param cid The CID to encode.
 * @return A CBOR tag 42 value containing the CID link representation.
 */
- (ATProtoCBORValue *)cidLinkValueForCID:(CID *)cid;

@end

NS_ASSUME_NONNULL_END
