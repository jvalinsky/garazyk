#import <Foundation/Foundation.h>
#import "Video/VideoTranscoderBackend.h"
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class CID;

extern NSString * const ATProtoVideoTranscoderErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoVideoTranscoderError) {
    ATProtoVideoTranscoderErrorAssetNotFound = 1,
    ATProtoVideoTranscoderErrorExportFailed = 2,
    ATProtoVideoTranscoderErrorUnsupportedFormat = 3,
    ATProtoVideoTranscoderErrorCancelled = 4,
};

@protocol ATProtoVideoTranscoderDelegate <NSObject>
@optional
- (void)transcoder:(id)transcoder didUpdateProgress:(float)progress;
- (void)transcoderDidComplete:(id)transcoder;
- (void)transcoder:(id)transcoder didFailWithError:(NSError *)error;
@end

@interface ATProtoVideoTranscoder : NSObject

@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;
@property (nonatomic, weak, nullable) id<ATProtoVideoTranscoderDelegate> delegate;
@property (nonatomic, assign) NSInteger maxConcurrentExports;

+ (instancetype)sharedTranscoder;

- (nullable NSData *)transcodeVideoAtURL:(NSURL *)inputURL
                              toQuality:(ATProtoVideoTranscoderQuality)quality
                                   error:(NSError **)error;

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float progress))progressBlock
                 completion:(void (^)(NSURL * _Nullable outputURL, NSError * _Nullable error))completion;

- (void)cancelAllExports;

@end

NS_ASSUME_NONNULL_END
