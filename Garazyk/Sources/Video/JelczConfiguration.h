#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JelczConfiguration : NSObject

@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, copy) NSString *dataDirectory;
@property (nonatomic, copy) NSString *blobDirectory;
@property (nonatomic, copy) NSString *pdsURL;
@property (nonatomic, copy, nullable) NSString *plcURL;
@property (nonatomic, copy) NSString *serviceDID;
@property (nonatomic, assign) NSInteger maxConcurrentJobs;
@property (nonatomic, assign) NSTimeInterval pollInterval;
@property (nonatomic, assign) NSUInteger maxUploadBytes;
@property (nonatomic, assign) NSUInteger maxOutputBytes;
@property (nonatomic, assign) NSInteger maxDurationSeconds;

// S3 configuration
@property (nonatomic, copy, nullable) NSString *s3Bucket;
@property (nonatomic, copy) NSString *s3Region;
@property (nonatomic, copy, nullable) NSString *s3Endpoint;
@property (nonatomic, copy, nullable) NSString *s3AccessKey;
@property (nonatomic, copy, nullable) NSString *s3SecretKey;

+ (instancetype)configurationFromEnvironment;

@end

NS_ASSUME_NONNULL_END
