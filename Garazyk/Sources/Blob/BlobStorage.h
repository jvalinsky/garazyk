// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file BlobStorage.h
 * @abstract Blob storage management with CID-based addressing.
 * @discussion Provides persistent blob storage with CIDv1 identification using raw codec and SHA-256 hashing.
 * Manages blob lifecycle including upload, retrieval, listing, deletion, and validation.
 * Implements magic number verification to prevent MIME type spoofing.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class PDSDatabasePool;
@class PDSDatabaseBlob;
@class CID;
@class HttpRequest;
@class HttpResponse;
/**
 * @abstract Defines the PDSBlobProvider protocol contract.
 */
@protocol PDSBlobProvider;

/**
 * @abstract Error domain for blob storage operations.
 */
extern NSString * const BlobStorageErrorDomain;

/**
 * @abstract Error codes for blob storage.
 */
typedef NS_ENUM(NSInteger, BlobStorageError) {
    BlobStorageErrorInvalidMIMEType = 2000,
    BlobStorageErrorFileTooLarge = 2001,
    BlobStorageErrorFileNotFound = 2002,
    BlobStorageErrorCIDMismatch = 2003,
    BlobStorageErrorStorageFailure = 2004,
    BlobStorageErrorBlobNotFound = 2005,
};

/**
 * @abstract Manages persistent blob storage and metadata.
 */
@interface BlobStorage : NSObject

/**
 * @abstract The underlying database pool used for metadata.
 */
@property (nonatomic, strong, readonly) PDSDatabasePool *databasePool;

/**
 * @abstract The blob provider used for file system storage operations.
 */
@property (nonatomic, strong, readonly) id<PDSBlobProvider> provider;

/**
 * @abstract Initializes blob storage.
 * @param databasePool The SQLite database pool for blob metadata.
 * @param provider The blob provider for filesystem operations.
 * @return An initialized blob storage instance.
 */
- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool provider:(id<PDSBlobProvider>)provider;

/**
 * @abstract Uploads a blob and returns its CID.
 * @param data The blob data to store.
 * @param mimeType The MIME type of the blob.
 * @param did The DID of the account uploading the blob.
 * @param error Receives failure details.
 * @return The CID of the uploaded blob, or nil on failure.
 */
- (nullable CID *)uploadBlob:(NSData *)data
                    mimeType:(NSString *)mimeType
                         did:(NSString *)did
                       error:(NSError **)error;

/**
 * @abstract Retrieves a blob by its CID.
 * @param cid The CID of the blob to retrieve.
 * @param did The DID that owns the blob (optional, for verification/access control).
 * @param error Receives failure details.
 * @return The blob data, or nil if not found.
 */
- (nullable NSData *)getBlobWithCID:(CID *)cid did:(nullable NSString *)did error:(NSError **)error;

/**
 * @abstract Retrieves a local blob file path when available from the configured provider.
 * @param cid The CID of the blob to locate.
 * @param did The DID that owns the blob (optional, for verification/access control).
 * @param error Receives failure details.
 * @return Absolute file path if available, or nil if the provider is not file-backed.
 */
- (nullable NSString *)blobFilePathWithCID:(CID *)cid did:(nullable NSString *)did error:(NSError **)error;

/**
 * @abstract Retrieves blob metadata by its CID string.
 * @param cidString The CID string of the blob.
 * @param did The DID that owns the blob (optional, for verification/access control).
 * @param error Receives failure details.
 * @return The blob metadata object, or nil if not found.
 */
- (nullable PDSDatabaseBlob *)getBlobMetadataWithCID:(NSString *)cidString did:(nullable NSString *)did error:(NSError **)error;

/**
 * @abstract Lists blobs for a specific DID.
 * @param did The DID to list blobs for.
 * @param limit Maximum number of blobs to return.
 * @param cursor Cursor for pagination.
 * @param error Receives failure details.
 * @return Array of blob metadata objects, or nil on failure.
 */
- (nullable NSArray<PDSDatabaseBlob *> *)listBlobsForDID:(NSString *)did
                                                  limit:(NSInteger)limit
                                                 cursor:(nullable NSString *)cursor
                                                  error:(NSError **)error;

/**
 * @abstract Deletes a blob by CID for a specific DID.
 * @param cid The CID of the blob to delete.
 * @param did The DID that owns the blob.
 * @param error Receives failure details.
 * @return YES if deletion was successful.
 */
- (BOOL)deleteBlobWithCID:(CID *)cid did:(NSString *)did error:(NSError **)error;

/**
 * @abstract Validates blob data according to ATProto constraints.
 * @param data The blob data to validate.
 * @param mimeType The MIME type of the blob.
 * @param error Receives validation failure details.
 * @return YES if the blob is valid.
 */
- (BOOL)validateBlob:(NSData *)data mimeType:(NSString *)mimeType error:(NSError **)error;

/**
 * @abstract Responds to a blob request with Range header support.
 * @param blobData The blob data to send (may be nil if filePath is provided).
 * @param filePath The file path to stream from (takes precedence over blobData).
 * @param totalLength The total length of the blob.
 * @param request The HTTP request (may contain Range header).
 * @param response The HTTP response object.
 * @param outError Receives response generation failures.
 * @return YES if response was successfully configured, NO on error.
 */
- (BOOL)respondWithBlobData:(nullable NSData *)blobData
                   filePath:(nullable NSString *)filePath
                totalLength:(unsigned long long)totalLength
                 forRequest:(HttpRequest *)request
                   response:(HttpResponse *)response
                      error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
