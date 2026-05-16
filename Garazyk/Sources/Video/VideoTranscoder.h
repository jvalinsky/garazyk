// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Video/VideoTranscoderBackend.h"
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class CID;

/**
 * @abstract Error domain for video transcoding operations.
 */
extern NSString * const ATProtoVideoTranscoderErrorDomain;

/**
 * @abstract Error codes for video transcoding.
 */
typedef NS_ENUM(NSInteger, ATProtoVideoTranscoderError) {
    ATProtoVideoTranscoderErrorAssetNotFound = 1,
    ATProtoVideoTranscoderErrorExportFailed = 2,
    ATProtoVideoTranscoderErrorUnsupportedFormat = 3,
    ATProtoVideoTranscoderErrorCancelled = 4,
};

/**
 * @abstract Delegate protocol for monitoring transcoding progress.
 */
@protocol ATProtoVideoTranscoderDelegate <NSObject>
@optional

/**
 * @abstract Invoked when transcoding progress updates.
 * @param transcoder The calling transcoder instance.
 * @param progress Progress value from 0.0 to 1.0.
 */
- (void)transcoder:(id)transcoder didUpdateProgress:(float)progress;

/**
 * @abstract Invoked when transcoding completes successfully.
 */
- (void)transcoderDidComplete:(id)transcoder;

/**
 * @abstract Invoked when transcoding fails.
 * @param transcoder The calling transcoder instance.
 * @param error The failure reason.
 */
- (void)transcoder:(id)transcoder didFailWithError:(NSError *)error;
@end

/**
 * @abstract Manages video transcoding processes.
 */
@interface ATProtoVideoTranscoder : NSObject

/**
 * @abstract Backend blob storage provider used for fetching/caching source videos.
 */
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/**
 * @abstract Delegate for progress notifications.
 */
@property (nonatomic, weak, nullable) id<ATProtoVideoTranscoderDelegate> delegate;

/**
 * @abstract Limit for concurrent transcoding operations.
 */
@property (nonatomic, assign) NSInteger maxConcurrentExports;

/**
 * @abstract Returns the shared singleton transcoder.
 */
+ (instancetype)sharedTranscoder;

/**
 * @abstract Synchronously transcode a video.
 * @param inputURL URL of the source video.
 * @param quality Target transcoding quality.
 * @param error Receives failure details.
 * @return Transcoded data, or nil on failure.
 */
- (nullable NSData *)transcodeVideoAtURL:(NSURL *)inputURL
                              toQuality:(ATProtoVideoTranscoderQuality)quality
                                   error:(NSError **)error;

/**
 * @abstract Asynchronously transcode a video.
 * @param inputURL Source video URL.
 * @param quality Target quality.
 * @param outputURL Optional custom output URL.
 * @param progressBlock Optional block for progress monitoring.
 * @param completion Completion handler.
 */
- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float progress))progressBlock
                 completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

/**
 * @abstract Cancels all active transcoding operations.
 */
- (void)cancelAllExports;

@end

NS_ASSUME_NONNULL_END
