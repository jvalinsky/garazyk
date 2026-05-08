#import "Video/VideoTranscoder.h"
#import "Video/VideoTranscoderBackend.h"
#import "Video/AVFoundationTranscoder.h"
#import "Video/FFmpegTranscoder.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

// Suppress -Wblock-capture-autoreleasing: the error out-parameter captured
// by the completion block is written before dispatch_semaphore_signal,
// and the caller waits on the semaphore, so the autorelease pool is valid.
#pragma clang diagnostic ignored "-Wblock-capture-autoreleasing"

NSString * const ATProtoVideoTranscoderErrorDomain = @"com.atproto.video.transcoder";

@interface ATProtoVideoTranscoder ()
@property (nonatomic, strong) id<VideoTranscoderBackend> backend;
@end

@implementation ATProtoVideoTranscoder

+ (instancetype)sharedTranscoder {
    static ATProtoVideoTranscoder *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ATProtoVideoTranscoder alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxConcurrentExports = 2;
        _backend = [self createBackend];
    }
    return self;
}

- (id<VideoTranscoderBackend>)createBackend {
#if TARGET_OS_MAC
    return [[AVFoundationTranscoder alloc] init];
#else
    return [[FFmpegTranscoder alloc] initWithFFmpegPath:nil ffprobePath:nil];
#endif
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
}

- (nullable NSData *)transcodeVideoAtURL:(NSURL *)inputURL
                              toQuality:(ATProtoVideoTranscoderQuality)quality
                                   error:(NSError **)error {
    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [self transcodeVideoAtURL:inputURL
                    toQuality:quality
                    outputURL:nil
                    progress:nil
                  completion:^(NSURL *outputURL, NSError *err) {
        if (outputURL) {
            result = [NSData dataWithContentsOfURL:outputURL];
        }
        if (error) *error = err;
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return result;
}

- (void)transcodeVideoAtURL:(NSURL *)inputURL
                  toQuality:(ATProtoVideoTranscoderQuality)quality
                  outputURL:(nullable NSURL *)outputURL
                   progress:(nullable void (^)(float))progressBlock
                 completion:(void (^)(NSURL *, NSError *))completion {

    if (self.backend) {
        [self.backend transcodeVideoAtURL:inputURL
                                toQuality:quality
                                outputURL:outputURL
                                 progress:progressBlock
                               completion:completion];
        return;
    }

    // No backend available
    NSError *err = [NSError errorWithDomain:ATProtoVideoTranscoderErrorDomain
                                        code:ATProtoVideoTranscoderErrorUnsupportedFormat
                                    userInfo:@{NSLocalizedDescriptionKey: @"No transcoding backend available"}];
    if (completion) completion(nil, err);
}

- (void)cancelAllExports {
    if (self.backend) {
        [self.backend cancelAllExports];
    }
}

@end
