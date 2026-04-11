#import "PDSBlobProviderFactory.h"
#import "PDSCloudStorageBlobProvider.h"
#import "PDSDiskBlobProvider.h"
#import "App/PDSConfiguration.h"
#import "Core/PDSDataPaths.h"
#import "Debug/PDSLogger.h"

NSString * const PDSBlobProviderFactoryErrorDomain = @"com.atproto.pds.blobproviderfactory";

@implementation PDSBlobProviderFactory

+ (nullable id<PDSBlobProvider>)blobProviderWithConfiguration:(PDSConfiguration *)configuration
                                                        error:(NSError **)error {
    if (!configuration) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Configuration is nil"}];
        }
        return nil;
    }

    // Read storage type from configuration (defaults to "disk" for backward compatibility)
    NSString *storageType = [configuration stringForKey:@"blobStorageType"];
    if (!storageType || storageType.length == 0) {
        storageType = @"disk";
    }

    if ([storageType isEqualToString:@"disk"]) {
        return [self diskBlobProviderWithConfiguration:configuration error:error];
    } else if ([storageType isEqualToString:@"s3"]) {
        return [self cloudStorageBlobProviderWithConfiguration:configuration error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Unknown blob storage type: %@", storageType]}];
        }
        return nil;
    }
}

#pragma mark - Private Helpers

+ (nullable id<PDSBlobProvider>)diskBlobProviderWithConfiguration:(PDSConfiguration *)configuration
                                                            error:(NSError **)error {
    // Get blob storage directory from data paths
    PDSDataPaths *dataPaths = configuration.dataPaths;
    if (!dataPaths) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not determine data paths"}];
        }
        return nil;
    }

    NSString *blobStoragePath = dataPaths.blobsDirectory;
    if (!blobStoragePath || blobStoragePath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not determine blob storage directory"}];
        }
        return nil;
    }

    NSURL *blobStorageDir = [NSURL fileURLWithPath:blobStoragePath];
    PDS_LOG_INFO_C(PDSLogComponentBlob, @"Initializing disk blob provider at: %@", blobStoragePath);
    return [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobStorageDir];
}

+ (nullable id<PDSBlobProvider>)cloudStorageBlobProviderWithConfiguration:(PDSConfiguration *)configuration
                                                                  error:(NSError **)error {
    // Read S3 configuration from config or environment variables
    NSString *bucket = [configuration stringForKey:@"s3Bucket"];
    NSString *region = [configuration stringForKey:@"s3Region"];
    NSString *endpoint = [configuration stringForKey:@"s3Endpoint"];
    NSString *keyPrefix = [configuration stringForKey:@"s3KeyPrefix"];

    NSString *accessKeyId = [configuration stringForKey:@"s3AccessKeyId"];
    NSString *secretAccessKey = [configuration stringForKey:@"s3SecretAccessKey"];

    // Fall back to environment variables
    if (!accessKeyId || accessKeyId.length == 0) {
        accessKeyId = [[NSProcessInfo processInfo].environment objectForKey:@"S3_ACCESS_KEY_ID"];
    }
    if (!secretAccessKey || secretAccessKey.length == 0) {
        secretAccessKey = [[NSProcessInfo processInfo].environment objectForKey:@"S3_SECRET_ACCESS_KEY"];
    }

    // Validate required configuration
    if (!bucket || bucket.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"S3 bucket not configured"}];
        }
        return nil;
    }

    if (!region || region.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"S3 region not configured"}];
        }
        return nil;
    }

    if (!accessKeyId || accessKeyId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"S3 access key ID not configured"}];
        }
        return nil;
    }

    if (!secretAccessKey || secretAccessKey.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"S3 secret access key not configured"}];
        }
        return nil;
    }

    // Create cloud storage provider
    PDSCloudStorageBlobProvider *provider = [[PDSCloudStorageBlobProvider alloc]
        initWithBucket:bucket
               region:region
             endpoint:endpoint
            keyPrefix:keyPrefix
        accessKeyId:accessKeyId
     secretAccessKey:secretAccessKey];

    if (!provider) {
        if (error) {
            *error = [NSError errorWithDomain:PDSBlobProviderFactoryErrorDomain
                                         code:9
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize S3 blob provider"}];
        }
        return nil;
    }

    PDS_LOG_INFO_C(PDSLogComponentBlob, @"Initializing S3 blob provider: bucket=%@, region=%@, endpoint=%@",
                   bucket, region, endpoint ?: @"(AWS S3 default)");

    return provider;
}

@end
