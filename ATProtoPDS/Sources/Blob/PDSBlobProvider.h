#import <Foundation/Foundation.h>
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @protocol PDSBlobProvider
 * @abstract Defines the interface for a generic blob storage backend.
 * @discussion Implementations can store blobs on disk, S3, or other storage systems.
 */
@protocol PDSBlobProvider <NSObject>

/**
 * Stores raw blob data.
 * @param data The raw data to store
 * @param cid The Content Identifier (CID) for the data
 * @param error Output error if operation fails
 * @return YES if successful, NO otherwise
 */
- (BOOL)storeBlobData:(NSData *)data forCID:(CID *)cid error:(NSError **)error;

/**
 * Retrieves raw blob data.
 * @param cid The CID to retrieve
 * @param error Output error if operation fails (e.g. not found)
 * @return The data if found, nil otherwise
 */
- (nullable NSData *)retrieveBlobDataForCID:(CID *)cid error:(NSError **)error;

/**
 * Deletes blob data.
 * @param cid The CID to delete
 * @param error Output error if operation fails
 * @return YES if successful or if file didn't exist, NO on failure
 */
- (BOOL)deleteBlobDataForCID:(CID *)cid error:(NSError **)error;

/**
 * Checks if blob data exists.
 * @param cid The CID to check
 * @return YES if exists, NO otherwise
 */
- (BOOL)hasBlobDataForCID:(CID *)cid;

@end

NS_ASSUME_NONNULL_END
