/*!
 @file BlobStorage.h

 @abstract Blob storage management with CID-based addressing.

 @discussion Provides persistent blob storage with CIDv1 identification using
 raw codec and SHA-256 hashing. Manages blob lifecycle including upload, retrieval,
 listing, deletion, and validation. Implements magic number verification to prevent
 MIME type spoofing.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class PDSDatabasePool;
@class PDSDatabaseBlob;
@class CID;
@protocol PDSBlobProvider;

extern NSString * const BlobStorageErrorDomain;

typedef NS_ENUM(NSInteger, BlobStorageError) {
    BlobStorageErrorInvalidMIMEType = 2000,
    BlobStorageErrorFileTooLarge = 2001,
    BlobStorageErrorFileNotFound = 2002,
    BlobStorageErrorCIDMismatch = 2003,
    BlobStorageErrorStorageFailure = 2004,
    BlobStorageErrorBlobNotFound = 2005,
};

@interface BlobStorage : NSObject

@property (nonatomic, strong, readonly) PDSDatabasePool *databasePool;
@property (nonatomic, strong, readonly) id<PDSBlobProvider> provider;

/*!
 @method initWithDatabasePool:provider:

 @abstract Designated initializer for blob storage.

 @discussion Creates blob storage with the specified database pool for metadata
 and provider for blob files.

 @param databasePool The SQLite database pool for blob metadata.
 @param provider The blob provider for filesystem operations.
 @return An initialized blob storage instance.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool provider:(id<PDSBlobProvider>)provider;

/// Upload a blob and return its CID
/// @param data The blob data to store
/// @param mimeType The MIME type of the blob
/// @param did The DID of the account uploading the blob
/// @param error Error pointer for failure details
/// @return The CID of the uploaded blob, or nil on failure
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error;

/// Retrieve a blob by its CID
/// @param cid The CID of the blob to retrieve
/// @param did The DID that owns the blob (optional, for verification/access control)
/// @param error Error pointer for failure details
/// @return The blob data, or nil if not found
- (nullable NSData *)getBlobWithCID:(CID *)cid did:(nullable NSString *)did error:(NSError **)error;

/// Retrieve a local blob file path when available from the configured provider
/// @param cid The CID of the blob to locate
/// @param did The DID that owns the blob (optional, for verification/access control)
/// @param error Error pointer for failure details
/// @return Absolute file path if available, or nil if the provider is not file-backed
- (nullable NSString *)blobFilePathWithCID:(CID *)cid did:(nullable NSString *)did error:(NSError **)error;

/// Retrieve blob metadata by its CID string
/// @param cidString The CID string of the blob to retrieve metadata for
/// @param did The DID that owns the blob (optional, for verification/access control)
/// @param error Error pointer for failure details
/// @return The blob metadata object, or nil if not found
- (nullable PDSDatabaseBlob *)getBlobMetadataWithCID:(NSString *)cidString did:(nullable NSString *)did error:(NSError **)error;

/// List blobs for a specific DID
/// @param did The DID to list blobs for
/// @param limit Maximum number of blobs to return
/// @param cursor Cursor for pagination
/// @param error Error pointer for failure details
/// @return Array of blob metadata objects, or nil on failure
- (nullable NSArray<PDSDatabaseBlob *> *)listBlobsForDID:(NSString *)did
                                                  limit:(NSInteger)limit
                                                 cursor:(nullable NSString *)cursor
                                                  error:(NSError **)error;

/// Delete a blob by CID for a specific DID
/// @param cid The CID of the blob to delete
/// @param did The DID that owns the blob
/// @param error Error pointer for failure details
/// @return YES if deletion was successful
- (BOOL)deleteBlobWithCID:(CID *)cid did:(NSString *)did error:(NSError **)error;

/// Validate blob data according to ATProto constraints
/// @param data The blob data to validate
/// @param mimeType The MIME type of the blob
/// @param error Error pointer for validation failure details
/// @return YES if the blob is valid
- (BOOL)validateBlob:(NSData *)data mimeType:(NSString *)mimeType error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
