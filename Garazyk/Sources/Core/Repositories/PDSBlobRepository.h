/*!
 @file PDSBlobRepository.h
 @abstract Protocol for blob storage access.
 @discussion Decouples application logic from blob persistence (disk, S3, etc).
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabaseBlob;
@protocol PDSBlobRepository <NSObject>

/*! Saves blob metadata. */
- (BOOL)saveBlob:(PDSDatabaseBlob *)blob error:(NSError **)error;

/*! Retrieves blob data by its identifier (CID). */
- (nullable NSData *)blobForId:(NSString *)blobId error:(NSError **)error;

/*! Deletes a blob by its identifier. */
- (BOOL)deleteBlob:(NSString *)blobId error:(NSError **)error;

/*! Checks if a blob exists. */
- (BOOL)hasBlob:(NSString *)blobId error:(NSError **)error;

/*! Gets blob metadata by CID and DID. */
- (nullable PDSDatabaseBlob *)blobWithCid:(NSData *)cid did:(NSString *)did error:(NSError **)error;

/*! Lists blobs for a DID. */
- (nullable NSArray<PDSDatabaseBlob *> *)blobsForDid:(NSString *)did 
                                               limit:(NSInteger)limit 
                                              offset:(NSInteger)offset 
                                               error:(NSError **)error;

/*! Gets total blob count for a DID. */
- (NSInteger)blobCountForDid:(NSString *)did error:(NSError **)error;

/*! Deletes a blob record. */
- (BOOL)deleteBlob:(NSData *)cid did:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
