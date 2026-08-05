// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSDatabase (Blobs)

 @abstract Blob metadata methods for PDSDatabase.

 @discussion These methods manage blob references and metadata. Blobs are
 large binary attachments stored separately from the repository data.
 */
@interface PDSDatabase (Blobs)

/*!
 @method saveBlob:error:

 @abstract Saves blob metadata to the database.

 @param blob The blob object to save.
 @param error On return, contains an error if the operation failed.
 @return YES if the blob was saved successfully, NO otherwise.
 */
- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error;

/*!
 @method getBlobWithCid:error:

 @abstract Retrieves blob metadata by ATProtoCID.

 @param cid The ATProtoCID of the blob.
 @param error On return, contains an error if the operation failed.
 @return The blob object, or nil if not found.
 */
- (nullable PDSDatabaseBlob *)getBlobWithCid:(NSData *)cid error:(NSError **)error;

/*!
 @method getBlobsForDid:limit:offset:error:

 @abstract Retrieves blobs uploaded by an account.

 @param did The DID of the account.
 @param limit Maximum number of blobs to return.
 @param offset Number of blobs to skip.
 @param error On return, contains an error if the operation failed.
 @return An array of blob objects.
 */
/**
 * @abstract Get blobs for did.
 * @param did Actor DID for the request.
 * @param limit Maximum number of records to return.
 * @param offset Zero-based result offset.
 * @param error Receives details when the operation fails.
 * @return The response array, or nil when the request fails.
 */
- (NSArray<PDSDatabaseBlob *> *)getBlobsForDid:(NSString *)did limit:(NSInteger)limit offset:(NSInteger)offset error:(NSError **)error;

/*!
 @method getBlobCountForDid:error:

 @abstract Counts blobs uploaded by an account.

 @param did The DID of the account.
 @param error On return, contains an error if the operation failed.
 @return The number of blobs uploaded by the account.
 */
- (NSInteger)getBlobCountForDid:(NSString *)did error:(NSError **)error;

/*!
 @method deleteBlob:did:error:

 @abstract Deletes a blob owned by the given DID.

 @discussion Scoped by (cid, did) so one account cannot delete another
 account's row for a shared content-addressed ATProtoCID (§5.1).

 @param cid The ATProtoCID of the blob to delete.
 @param did The DID that must own the blob row.
 @param error On return, contains an error if the operation failed.
 @return YES if the blob was deleted successfully, NO otherwise.
 */
- (BOOL)deleteBlob:(NSData *)cid did:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
