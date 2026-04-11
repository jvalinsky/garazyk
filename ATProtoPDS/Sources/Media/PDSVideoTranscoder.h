#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class CID;
@class AVAssetExportSession;

extern NSString * const PDSVideoTranscoderErrorDomain;

typedef NS_ENUM(NSInteger, PDSVideoTranscoderError) {
    PDSVideoTranscoderErrorAssetNotFound = 1,
    PDSVideoTranscoderErrorExportFailed = 2,
    PDSVideoTranscoderErrorUnsupportedFormat = 3,
    PDSVideoTranscoderErrorCancelled = 4,
};

typedef NS_ENUM(NSInteger, PDSVideoTranscoderQuality) {
    PDSVideoTranscoderQuality480p = 0,
    PDSVideoTranscoderQuality720p = 1,
    PDSVideoTranscoderQuality1080p = 2,
    PDSVideoTranscoderQualityHEVC = 3,
};

@protocol PDSVideoTranscoderDelegate <NSObject>
@optional
- (void)transcoder:(id)transcoder didUpdateProgress:(float)progress;
- (void)transcoderDidComplete:(id)transcoder;
- (void)transcoder:(id)transcoder didFailWithError:(NSError *)error;
@end

@interface PDSVideoTranscoder : NSObject

@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

+ (instancetype)sharedTranscoder;

@property (nonatomic, weak, nullable) id<PDSVideoTranscoderDelegate> delegate;
@property (nonatomic, assign) NSInteger maxConcurrentExports;

- (nullable NSData *)transcodeVideoAtURL:(NSURL *)inputURL
                           toQuality:(PDSVideoTranscoderQuality)quality
                                error:(NSError **)error;

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                 toQuality:(PDSVideoTranscoderQuality)quality
                 outputURL:(NSURL *)outputURL
                 progress:(void (^)(float progress))progressBlock
               completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

- (void)cancelAllExports;

- (NSString *)presetForQuality:(PDSVideoTranscoderQuality)quality;

@end

NS_ASSUME_NONNULL_END