// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file PDSBlobService.h
 *
 * @abstract Blob management service layer.
 *
 * @discussion Provides operations for uploading, retrieving, listing, and
 * deleting binary blobs associated with ATProto repositories.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Blob/BlobStorage.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/**
 * @abstract Defines the PDSBlobRepository protocol contract.
 */
@protocol PDSBlobRepository;

/**
 * @abstract Service for blob management operations.
 */
@interface PDSBlobService : NSObject

/**
 * @abstract Database pool for user stores.
 */
@property (nonatomic, strong) PDSDatabasePool *databasePool;

/**
 * @abstract Blob repository.
 */
@property (nonatomic, strong) id<PDSBlobRepository> blobRepository;

/**
 * @abstract Underlying storage mechanism.
 */
@property (nonatomic, strong) BlobStorage *blobStorage;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool storage:(BlobStorage *)storage;

#pragma mark - Blob Operations

/**
 * @abstract Gets blob data by CID.
 * @param cid The content identifier data.
 * @param did The decentralized identifier of the repository owner.
 * @param error Error pointer for retrieval failures.
 * @return The blob data, or nil if not found.
 */
- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;

/**
 * @abstract Uploads a blob and returns its CID.
 * @param blobData The raw blob data.
 * @param did The decentralized identifier of the repository owner.
 * @param mimeType The MIME type of the blob.
 * @param error Error pointer for upload failures.
 * @return Dictionary containing CID and size, or nil on failure.
 */
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error;

/**
 * @abstract Gets blob metadata by CID string.
 * @param cid The content identifier string.
 * @param did The decentralized identifier of the repository owner.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary containing blob metadata, or nil if not found.
 */
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid
                                       did:(NSString *)did
                                    error:(NSError **)error;

/**
 * @abstract Gets file-backed streaming metadata for a blob when available.
 * @param cid The content identifier string.
 * @param did The decentralized identifier of the repository owner.
 * @param error Error pointer for retrieval failures.
 * @return Dictionary containing file stream information, or nil if not available.
 */
- (nullable NSDictionary *)getBlobStreamWithCID:(NSString *)cid
                                            did:(NSString *)did
                                          error:(NSError **)error;

/**
 * @abstract Lists blobs for a DID with pagination.
 * @param did The decentralized identifier of the repository owner.
 * @param limit Maximum number of blobs to return.
 * @param cursor Pagination cursor.
 * @param error Error pointer for listing failures.
 * @return Array of blob metadata dictionaries, or nil if listing fails.
 * @discussion The cursor is an opaque decimal offset issued by the sync
 * endpoint. Invalid cursors fail with an error rather than restarting at the
 * first page.
 */
- (nullable NSArray<NSDictionary<NSString *, id> *> *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error;

/**
 * @abstract Deletes a blob by CID.
 * @param cid The content identifier string.
 * @param did The decentralized identifier of the repository owner.
 * @param error Error pointer for deletion failures.
 * @return YES on success, NO on failure.
 */
- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
