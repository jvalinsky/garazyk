// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @protocol PDSBlobProvider
 @abstract Defines the interface for a generic blob storage backend.
 @discussion
    Implementations can store blobs on disk, S3, or other storage systems.
    The provider abstracts blob storage to allow easy switching between backends.
    All methods are thread-safe unless otherwise noted in implementation.
 */
@protocol PDSBlobProvider <NSObject>

/*!
 @method storeBlobData:forCID:error:
 @abstract Stores raw blob data with the given ATProtoCID.
 @param data The raw data to store.
 @param cid The Content Identifier (ATProtoCID) for the data.
 @param error Output error if operation fails.
 @return YES if successful, NO otherwise.
 */
- (BOOL)storeBlobData:(NSData *)data forCID:(ATProtoCID *)cid error:(NSError **)error;

/*!
 @method retrieveBlobDataForCID:error:
 @abstract Retrieves raw blob data for the given ATProtoCID.
 @param cid The ATProtoCID to retrieve.
 @param error Output error if operation fails (e.g. not found).
 @return The data if found, nil otherwise.
 */
- (nullable NSData *)retrieveBlobDataForCID:(ATProtoCID *)cid error:(NSError **)error;

/*!
 @method retrieveBlobStreamForCID:error:
 @abstract Returns an input stream for reading blob data.
 @param cid The ATProtoCID to retrieve.
 @param error Output error if operation fails.
 @return An NSInputStream for the blob, or nil on failure.
 */
- (nullable NSInputStream *)retrieveBlobStreamForCID:(ATProtoCID *)cid error:(NSError **)error;

/*!
 @method deleteBlobDataForCID:error:
 @abstract Deletes blob data for the given ATProtoCID.
 @param cid The ATProtoCID to delete.
 @param error Output error if operation fails.
 @return YES if successful or if file didn't exist, NO on failure.
 */
- (BOOL)deleteBlobDataForCID:(ATProtoCID *)cid error:(NSError **)error;

/*!
 @method hasBlobDataForCID:
 @abstract Checks if blob data exists for the given ATProtoCID.
 @param cid The ATProtoCID to check.
 @return YES if exists, NO otherwise.
 */
- (BOOL)hasBlobDataForCID:(ATProtoCID *)cid;

@optional

/*!
 @method blobFileURLForCID:error:
 @abstract Returns a local file URL for blob data when the provider can expose one.
 @discussion
    This method is optional and only implemented by file-based providers.
    Network-based providers should return nil.
 @param cid The ATProtoCID to locate.
 @param error Output error if operation fails.
 @return File URL if available, nil otherwise.
 */
- (nullable NSURL *)blobFileURLForCID:(ATProtoCID *)cid error:(NSError **)error;

/*!
 @method listAllCIDsWithError:
 @abstract Lists all CIDs currently stored by the provider.
 @param error Output error if operation fails.
 @return Array of ATProtoCID objects, or nil on failure.
 */
- (nullable NSArray<ATProtoCID *> *)listAllCIDsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
