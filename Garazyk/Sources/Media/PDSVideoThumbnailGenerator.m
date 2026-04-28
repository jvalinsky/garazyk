#import "Media/PDSVideoThumbnailGenerator.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import <AVFoundation/AVFoundation.h>

NSString * const PDSVideoThumbnailErrorDomain = @"com.atproto.pds.video.thumbnail";

@implementation PDSVideoThumbnailGenerator

+ (instancetype)sharedGenerator {
    static PDSVideoThumbnailGenerator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSVideoThumbnailGenerator alloc] init];
    });
    return sharedInstance;
}

- (void)setBlobProvider:(id<PDSBlobProvider>)provider {
    _blobProvider = provider;
}

- (nullable NSData *)generateThumbnailAtTime:(NSTimeInterval)seconds
                           fromVideoURL:(NSURL *)videoURL
                             maxWidth:(NSInteger)maxWidth
                            maxHeight:(NSInteger)maxHeight
                               error:(NSError **)error {

    __block NSData *result = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [self generateThumbnailAtTime:seconds
                    fromVideoURL:videoURL
                      maxWidth:maxWidth
                     maxHeight:maxHeight
                   completion:^(NSData *thumbnailData, NSError *err) {
        result = thumbnailData;
        if (error) *error = err;
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return result;
}

- (void)generateThumbnailAtTime:(NSTimeInterval)seconds
                   fromVideoURL:(NSURL *)videoURL
                     maxWidth:(NSInteger)maxWidth
                    maxHeight:(NSInteger)maxHeight
                  completion:(void (^)(NSData *, NSError *))completion {

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
            if (!asset) {
                NSError *err = [NSError errorWithDomain:PDSVideoThumbnailErrorDomain
                                                   code:PDSVideoThumbnailErrorAssetNotFound
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to load video asset"}];
                if (completion) completion(nil, err);
                return;
            }

            AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(maxWidth, maxHeight);
            generator.requestedTimeToleranceBefore = kCMTimeZero;
            generator.requestedTimeToleranceAfter = kCMTimeZero;

            CMTime time = CMTimeMakeWithSeconds(seconds, 600);
            NSError *genError = nil;
            CGImageRef imgRef = [generator copyCGImageAtTime:time actualTime:NULL error:&genError];

            if (!imgRef) {
                NSError *err = genError ?: [NSError errorWithDomain:PDSVideoThumbnailErrorDomain
                                                                 code:PDSVideoThumbnailErrorGenerationFailed
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate thumbnail"}];
                if (completion) completion(nil, err);
                return;
            }

            UIImage *thumbnail = [UIImage imageWithCGImage:imgRef];
            NSData *jpegData = UIImageJPEGRepresentation(thumbnail, 0.8);
            CGImageRelease(imgRef);

            if (!jpegData) {
                NSError *err = [NSError errorWithDomain:PDSVideoThumbnailErrorDomain
                                                   code:PDSVideoThumbnailErrorGenerationFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode thumbnail as JPEG"}];
                if (completion) completion(nil, err);
                return;
            }

            if (completion) completion(jpegData, nil);
        }
    });
}

- (nullable CID *)storeThumbnailData:(NSData *)thumbnailData
                          forJob:(NSString *)jobId
                          error:(NSError **)error {
    if (!self.blobProvider) {
        if (error) {
            *error = [NSError errorWithDomain:PDSVideoThumbnailErrorDomain
                                         code:PDSVideoThumbnailErrorWriteFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Blob provider not configured"}];
        }
        return nil;
    }

    CID *cid = [CID sha256:thumbnailData];
    BOOL stored = [self.blobProvider storeBlobData:thumbnailData forCID:cid error:error];
    return stored ? cid : nil;
}

@end
