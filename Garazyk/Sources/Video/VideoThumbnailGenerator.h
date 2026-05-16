// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class CID;

/**
 * @abstract Error domain for video thumbnail generation.
 */
extern NSString * const ATProtoVideoThumbnailErrorDomain;

/**
 * @abstract Error codes for thumbnail generation.
 */
typedef NS_ENUM(NSInteger, ATProtoVideoThumbnailError) {
    ATProtoVideoThumbnailErrorAssetNotFound = 1,
    ATProtoVideoThumbnailErrorGenerationFailed = 2,
    ATProtoVideoThumbnailErrorInvalidTime = 3,
    ATProtoVideoThumbnailErrorWriteFailed = 4,
};

/**
 * @abstract Generates video thumbnails.
 */
@interface ATProtoVideoThumbnailGenerator : NSObject

/**
 * @abstract Provider for storing generated thumbnail blobs.
 */
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/**
 * @abstract Returns the shared singleton generator.
 */
+ (instancetype)sharedGenerator;

/**
 * @abstract Synchronously generates a thumbnail from a video.
 * @param seconds Timestamp in the video.
 * @param videoURL URL to the source video.
 * @param maxWidth Maximum thumbnail width.
 * @param maxHeight Maximum thumbnail height.
 * @param error Receives failure details.
 * @return JPEG data of the thumbnail, or nil on failure.
 */
- (nullable NSData *)generateThumbnailAtTime:(NSTimeInterval)seconds
                              fromVideoURL:(NSURL *)videoURL
                                maxWidth:(NSInteger)maxWidth
                               maxHeight:(NSInteger)maxHeight
                                  error:(NSError **)error;

/**
 * @abstract Asynchronously generates a thumbnail from a video.
 * @param seconds Timestamp in the video.
 * @param videoURL URL to the source video.
 * @param maxWidth Maximum thumbnail width.
 * @param maxHeight Maximum thumbnail height.
 * @param completion Completion handler.
 */
- (void)generateThumbnailAtTime:(NSTimeInterval)seconds
                  fromVideoURL:(NSURL *)videoURL
                    maxWidth:(NSInteger)maxWidth
                   maxHeight:(NSInteger)maxHeight
                 completion:(void (^)(NSData * _Nullable thumbnailData, NSError * _Nullable error))completion;

/**
 * @abstract Stores thumbnail data as a blob.
 * @param thumbnailData JPEG thumbnail data.
 * @param jobId The associated job identifier.
 * @param error Receives failure details.
 * @return The CID of the stored thumbnail, or nil on failure.
 */
- (nullable CID *)storeThumbnailData:(NSData *)thumbnailData
                             forJob:(NSString *)jobId
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
