#import "Media/PDSVideoThumbnailGenerator.h"
#import "Core/CID.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

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
    if (error) {
        *error = [NSError errorWithDomain:PDSVideoThumbnailErrorDomain
                                   code:PDSVideoThumbnailErrorGenerationFailed
                               userInfo:@{NSLocalizedDescriptionKey: @"Video processing requires macOS with AVFoundation"}];
    }
    return nil;
}

- (void)generateThumbnailAtTime:(NSTimeInterval)seconds
                  fromVideoURL:(NSURL *)videoURL
                    maxWidth:(NSInteger)maxWidth
                   maxHeight:(NSInteger)maxHeight
                 completion:(void (^)(NSData *, NSError *))completion {
    NSError *err = [NSError errorWithDomain:PDSVideoThumbnailErrorDomain
                                   code:PDSVideoThumbnailErrorGenerationFailed
                               userInfo:@{NSLocalizedDescriptionKey: @"Video processing requires macOS with AVFoundation"}];
    if (completion) {
        completion(nil, err);
    }
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