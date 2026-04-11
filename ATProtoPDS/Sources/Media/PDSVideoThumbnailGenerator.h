#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

@class CID;

extern NSString * const PDSVideoThumbnailErrorDomain;

typedef NS_ENUM(NSInteger, PDSVideoThumbnailError) {
    PDSVideoThumbnailErrorAssetNotFound = 1,
    PDSVideoThumbnailErrorGenerationFailed = 2,
    PDSVideoThumbnailErrorInvalidTime = 3,
    PDSVideoThumbnailErrorWriteFailed = 4,
};

@interface PDSVideoThumbnailGenerator : NSObject

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