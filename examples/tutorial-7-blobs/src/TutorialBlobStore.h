/*!
 @file TutorialBlobStore.h

 @abstract Blob storage with CID addressing for tutorial examples.

 @discussion Implements blob upload, retrieval, and deletion with:
 - CID-based addressing (blobs referenced by content hash)
 - MIME type validation and storage
 - Size limits and quota tracking
 - Range request support for partial content
 - Thread-safe via serial dispatch queue

 This is the educational version of the production blob storage in
 Garazyk/Sources/Blob/ (PDSBlobStore, PDSBlobService).

 Key concepts:
 - Blobs are opaque binary data identified by CID (content hash)
 - MIME type is stored alongside the blob
 - ATProto uses CIDv1 (dag-cbor + sha2-256) for blob references
 - Size limits prevent abuse (default 1MB per blob, 100MB per DID)
 - Range requests enable resumable uploads and partial reads

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class TutorialCIDGenerator;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TutorialBlobErrorDomain;

typedef NS_ENUM(NSInteger, TutorialBlobError) {
    TutorialBlobErrorBlobTooLarge = 1,
    TutorialBlobErrorQuotaExceeded = 2,
    TutorialBlobErrorNotFound = 3,
    TutorialBlobErrorInvalidMIMEType = 4,
    TutorialBlobErrorWriteFailed = 5,
    TutorialBlobErrorReadFailed = 6,
};

@interface TutorialBlobStore : NSObject

/*! Maximum blob size in bytes (default: 1MB). */
@property (nonatomic, assign) NSUInteger maxBlobSize;

/*! Maximum total storage per DID in bytes (default: 100MB). */
@property (nonatomic, assign) NSUInteger maxQuotaPerDID;

/*!
 @method initWithDataDirectory:

 @abstract Creates a blob store with a data directory for file storage.

 @param dataDir The directory to store blob files.
 @return A new blob store instance.
 */
- (instancetype)initWithDataDirectory:(NSString *)dataDir;

/*!
 @method putBlob:forDID:mimeType:error:

 @abstract Stores a blob and returns its CID.

 @param data The blob data.
 @param did The DID of the account owning the blob.
 @param mimeType The MIME type of the blob (e.g., "image/png").
 @param error On failure, contains error details.
 @return The CID string for the stored blob, or nil on failure.
 */
- (nullable NSString *)putBlob:(NSData *)data
                        forDID:(NSString *)did
                      mimeType:(NSString *)mimeType
                         error:(NSError **)error;

/*!
 @method getBlob:forDID:outMimeType:outSize:error:

 @abstract Retrieves a blob by CID.

 @param cid The CID of the blob.
 @param did The DID of the account (for authorization).
 @param outMimeType On return, the MIME type of the blob.
 @param outSize On return, the size of the blob in bytes.
 @param error On failure, contains error details.
 @return The blob data, or nil if not found.
 */
- (nullable NSData *)getBlob:(NSString *)cid
                      forDID:(NSString *)did
                outMimeType:(NSString * _Nullable __autoreleasing * _Nullable)outMimeType
                     outSize:(NSUInteger * _Nullable)outSize
                       error:(NSError **)error;

/*!
 @method getBlob:forDID:range:outMimeType:outSize:error:

 @abstract Retrieves a partial blob by CID with range support.

 @param cid The CID of the blob.
 @param did The DID of the account.
 @param range The byte range to retrieve (NSRange with location and length).
 @param outMimeType On return, the MIME type of the blob.
 @param outSize On return, the total size of the blob.
 @param error On failure, contains error details.
 @return The partial blob data, or nil if not found.
 */
- (nullable NSData *)getBlob:(NSString *)cid
                      forDID:(NSString *)did
                       range:(NSRange)range
                outMimeType:(NSString * _Nullable __autoreleasing * _Nullable)outMimeType
                     outSize:(NSUInteger * _Nullable)outSize
                       error:(NSError **)error;

/*!
 @method deleteBlob:forDID:error:

 @abstract Deletes a blob by CID.

 @param cid The CID of the blob.
 @param did The DID of the account.
 @param error On failure, contains error details.
 @return YES if deleted, NO if not found or error.
 */
- (BOOL)deleteBlob:(NSString *)cid
            forDID:(NSString *)did
             error:(NSError **)error;

/*!
 @method listBlobsForDID:limit:cursor:error:

 @abstract Lists blobs for a DID.

 @param did The DID of the account.
 @param limit Maximum number of blobs to return.
 @param cursor Pagination cursor (nil for first page).
 @param error On failure, contains error details.
 @return Array of dictionaries with "cid", "mimeType", "size" keys.
 */
- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
                                                limit:(NSUInteger)limit
                                               cursor:(nullable NSString *)cursor
                                                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
