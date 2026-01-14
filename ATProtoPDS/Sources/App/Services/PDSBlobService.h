/*!
 @file PDSBlobService.h

 @abstract Blob management service layer.

 @discussion Provides operations for uploading, retrieving, listing, and
 deleting binary blobs associated with ATProto repositories.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

/*!
 @class PDSBlobService

 @abstract Service for blob management operations.
 */
@interface PDSBlobService : NSObject

/*! Database pool for user stores. */
@property (nonatomic, weak) PDSDatabasePool *databasePool;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

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

/*! Lists blobs for a DID with pagination. */
- (nullable NSArray *)listBlobsForDID:(NSString *)did
                                limit:(NSUInteger)limit
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error;

/*! Deletes a blob by CID. */
- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END