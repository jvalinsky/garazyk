#import "Media/PDSVideoTranscoder.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"

NSString * const PDSVideoTranscoderErrorDomain = @"com.atproto.pds.video.transcoder";

@interface PDSVideoTranscoder ()
@property (nonatomic, strong) NSMutableSet *activeExports;
@property (nonatomic, strong) dispatch_queue_t exportQueue;
@end

@implementation PDSVideoTranscoder

+ (instancetype)sharedTranscoder {
    static PDSVideoTranscoder *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSVideoTranscoder alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeExports = [NSMutableSet set];
        _exportQueue = dispatch_queue_create("com.atproto.pds.video.transcoder", DISPATCH_QUEUE_SERIAL);
        _maxConcurrentExports = 2;
    }
    return self;
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
}

- (nullable NSData *)transcodeVideoAtURL:(NSURL *)inputURL
                       toQuality:(PDSVideoTranscoderQuality)quality
                            error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:PDSVideoTranscoderErrorDomain
                                   code:PDSVideoTranscoderErrorExportFailed
                               userInfo:@{NSLocalizedDescriptionKey: @"Video processing requires macOS with AVFoundation"}];
    }
    return nil;
}

- (void)transcodeVideoAtURL:(NSURL *)inputURL
              toQuality:(PDSVideoTranscoderQuality)quality
              outputURL:(NSURL *)outputURL
              progress:(void (^)(float))progressBlock
            completion:(void (^)(NSURL *, NSError *))completion {
    NSError *err = [NSError errorWithDomain:PDSVideoTranscoderErrorDomain
                                   code:PDSVideoTranscoderErrorExportFailed
                               userInfo:@{NSLocalizedDescriptionKey: @"Video processing requires macOS with AVFoundation"}];
    if (completion) {
        completion(nil, err);
    }
}

- (void)cancelAllExports {
    @synchronized(self.activeExports) {
        [self.activeExports removeAllObjects];
    }
}

- (NSString *)presetForQuality:(PDSVideoTranscoderQuality)quality {
    return @"passthrough";
}

@end