// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class CID;

extern NSString * const ATProtoVideoThumbnailErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoVideoThumbnailError) {
    ATProtoVideoThumbnailErrorAssetNotFound = 1,
    ATProtoVideoThumbnailErrorGenerationFailed = 2,
    ATProtoVideoThumbnailErrorInvalidTime = 3,
    ATProtoVideoThumbnailErrorWriteFailed = 4,
};

@interface ATProtoVideoThumbnailGenerator : NSObject

@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

+ (instancetype)sharedGenerator;

- (nullable NSData *)generateThumbnailAtTime:(NSTimeInterval)seconds
                              fromVideoURL:(NSURL *)videoURL
                                maxWidth:(NSInteger)maxWidth
                               maxHeight:(NSInteger)maxHeight
                                  error:(NSError **)error;

- (void)generateThumbnailAtTime:(NSTimeInterval)seconds
                  fromVideoURL:(NSURL *)videoURL
                    maxWidth:(NSInteger)maxWidth
                   maxHeight:(NSInteger)maxHeight
                 completion:(void (^)(NSData * _Nullable thumbnailData, NSError * _Nullable error))completion;

- (nullable CID *)storeThumbnailData:(NSData *)thumbnailData
                             forJob:(NSString *)jobId
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
