/*!
 @file PDSBlobRepository.h
 @abstract Protocol for blob storage access.
 @discussion Decouples application logic from blob persistence (disk, S3, etc).
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PDSBlobRepository <NSObject>

/*! Saves a blob of data and returns its CID (or identifier). */
- (nullable NSString *)saveBlob:(NSData *)data error:(NSError **)error;

/*! Retrieves blob data by its identifier (CID). */
- (nullable NSData *)blobForId:(NSString *)blobId error:(NSError **)error;

/*! Deletes a blob by its identifier. */
- (BOOL)deleteBlob:(NSString *)blobId error:(NSError **)error;

/*! Checks if a blob exists. */
- (BOOL)hasBlob:(NSString *)blobId error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
