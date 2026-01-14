/*!
 @file BlobStorage.h

 @abstract Blob storage management with CID-based addressing.

 @discussion Provides persistent blob storage with CIDv1 identification using
 raw codec and SHA-256 hashing. Manages blob lifecycle including upload, retrieval,
 listing, deletion, and validation. Implements magic number verification to prevent
 MIME type spoofing.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class CID;

extern NSString * const BlobStorageErrorDomain;

typedef NS_ENUM(NSInteger, BlobStorageError) {
    BlobStorageErrorInvalidMIMEType = 2000,
    BlobStorageErrorFileTooLarge = 2001,
    BlobStorageErrorFileNotFound = 2002,
    BlobStorageErrorCIDMismatch = 2003,
    BlobStorageErrorStorageFailure = 2004,
};

@interface BlobStorage : NSObject

@property (nonatomic, readonly) NSURL *storageDirectory;
@property (nonatomic, readonly) PDSDatabase *database;

/*!
 @method initWithDatabase:storageDirectory:

 @abstract Designated initializer for blob storage.

 @discussion Creates blob storage with the specified database for metadata
 and directory for blob files. Creates the storage directory if needed.

 @param database The SQLite database for blob metadata.
 @param storageDirectory The filesystem directory for blob files.
 @return An initialized blob storage instance.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database storageDirectory:(NSURL *)storageDirectory;

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
/// @param error Error pointer for failure details
/// @return The blob data, or nil if not found
- (nullable NSData *)getBlobWithCID:(CID *)cid error:(NSError **)error;

/// List blobs for a specific DID
/// @param did The DID to list blobs for
/// @param limit Maximum number of blobs to return
/// @param cursor Cursor for pagination
/// @param error Error pointer for failure details
/// @return Array of blob metadata dictionaries, or nil on failure
- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
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