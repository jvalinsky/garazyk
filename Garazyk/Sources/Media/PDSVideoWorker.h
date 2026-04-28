#import <Foundation/Foundation.h>
#import "Blob/PDSBlobProvider.h"

@class PDSServiceDatabases;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSVideoWorkerErrorDomain;

typedef NS_ENUM(NSInteger, PDSVideoWorkerError) {
    PDSVideoWorkerErrorDatabaseUnavailable = 1,
    PDSVideoWorkerErrorBlobProviderUnavailable = 2,
    PDSVideoWorkerErrorProcessingFailed = 3,
};

typedef NS_ENUM(NSInteger, PDSVideoJobState) {
    PDSVideoJobStatePending = 0,
    PDSVideoJobStateProcessing = 1,
    PDSVideoJobStateTranscoding = 2,
    PDSVideoJobStateGeneratingThumbnail = 3,
    PDSVideoJobStateCompleted = 4,
    PDSVideoJobStateFailed = 5,
};

@interface PDSVideoWorker : NSObject

+ (instancetype)sharedWorker;

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@property (nonatomic, assign) NSTimeInterval pollInterval;
@property (nonatomic, assign) NSInteger maxConcurrentJobs;
@property (nonatomic, strong, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

- (void)start;
- (void)stop;
- (void)processJob:(NSString *)jobId;
- (void)processPendingJobs;

- (void)updateJobProgress:(NSString *)jobId
                progress:(NSInteger)progress
                 message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END