/*!
 @file PDSBlobService.h

 @abstract Blob management service layer.

 @discussion Provides operations for uploading, retrieving, listing, and
 deleting binary blobs associated with ATProto repositories.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Blob/BlobStorage.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@protocol PDSBlobRepository;

/*!
 @class PDSBlobService

 @abstract Service for blob management operations.
 */
@interface PDSBlobService : NSObject

/*! Database pool for user stores. */
@property (nonatomic, strong) PDSDatabasePool *databasePool;

/*! Blob repository. */
@property (nonatomic, strong) id<PDSBlobRepository> blobRepository;

/*! Underlying storage mechanism. */
@property (nonatomic, strong) BlobStorage *blobStorage;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool storage:(BlobStorage *)storage;

#pragma mark - Blob Operations

/*! Gets blob data by CID. */
- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error;

/*! Uploads a blob and returns its CID. */
- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                              forDid:(NSString *)did
                             mimeType:(NSString *)mimeType
                               error:(NSError **)error;

/*! Gets blob metadata by CID string. */
- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid
                                       did:(NSString *)did
                                    error:(NSError **)error;

/*! Gets file-backed streaming metadata for a blob when available. */
- (nullable NSDictionary *)getBlobStreamWithCID:(NSString *)cid
                                            did:(NSString *)did
                                          error:(NSError **)error;

/*! Lists blobs for a DID with pagination. */
- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error;

/*! Deletes a blob by CID. */
- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
