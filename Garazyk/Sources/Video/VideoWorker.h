#import <Foundation/Foundation.h>
#import "Video/VideoJobStore.h"
#import "Video/VideoBlobUploader.h"
#import "Video/VideoAuthProvider.h"
#import "Blob/PDSBlobProvider.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ATProtoVideoWorkerErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoVideoWorkerError) {
    ATProtoVideoWorkerErrorDatabaseUnavailable = 1,
    ATProtoVideoWorkerErrorBlobProviderUnavailable = 2,
    ATProtoVideoWorkerErrorProcessingFailed = 3,
};

typedef NS_ENUM(NSInteger, ATProtoVideoJobState) {
    ATProtoVideoJobStatePending = 0,
    ATProtoVideoJobStateProcessing = 1,
    ATProtoVideoJobStateTranscoding = 2,
    ATProtoVideoJobStateGeneratingThumbnail = 3,
    ATProtoVideoJobStateCompleted = 4,
    ATProtoVideoJobStateFailed = 5,
};

@interface ATProtoVideoWorker : NSObject

+ (instancetype)sharedWorker;

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) NSTimeInterval pollInterval;
@property (nonatomic, assign) NSInteger maxConcurrentJobs;
@property (nonatomic, strong, nullable) id<VideoJobStore> jobStore;
@property (nonatomic, strong, nullable) id<VideoBlobUploader> blobUploader;
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;
@property (nonatomic, strong, nullable) id<VideoAuthProvider> authProvider;

- (void)start;
- (void)stop;
- (void)processJob:(NSString *)jobId;
- (void)processPendingJobs;

- (void)updateJobProgress:(NSString *)jobId
                progress:(NSInteger)progress
                 message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
