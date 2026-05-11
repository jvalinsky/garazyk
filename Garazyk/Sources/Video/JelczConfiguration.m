#import "Video/JelczConfiguration.h"

@implementation JelczConfiguration

+ (instancetype)configurationFromEnvironment {
    JelczConfiguration *config = [[JelczConfiguration alloc] init];

    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    config.port = env[@"JELCZ_PORT"] ? [env[@"JELCZ_PORT"] integerValue] : 2586;
    config.dataDirectory = env[@"JELCZ_DATA_DIR"] ?: @"./data/jelcz";
    config.blobDirectory = env[@"JELCZ_BLOB_DIR"] ?: @"./data/jelcz/blobs";
    config.pdsURL = env[@"JELCZ_PDS_URL"] ?: @"http://localhost:2583";
    config.plcURL = env[@"JELCZ_PLC_URL"] ?: @"http://localhost:2582";
    config.serviceDID = env[@"JELCZ_DID"] ?: @"did:web:localhost";
    config.maxConcurrentJobs = env[@"JELCZ_MAX_CONCURRENT_JOBS"] ? [env[@"JELCZ_MAX_CONCURRENT_JOBS"] integerValue] : 2;
    config.pollInterval = env[@"JELCZ_POLL_INTERVAL"] ? [env[@"JELCZ_POLL_INTERVAL"] doubleValue] : 5.0;
    config.maxUploadBytes = env[@"JELCZ_MAX_UPLOAD_BYTES"] ? [env[@"JELCZ_MAX_UPLOAD_BYTES"] integerValue] : 100 * 1024 * 1024;
    config.maxOutputBytes = env[@"JELCZ_MAX_OUTPUT_BYTES"] ? [env[@"JELCZ_MAX_OUTPUT_BYTES"] integerValue] : 50 * 1024 * 1024;
    config.maxDurationSeconds = env[@"JELCZ_MAX_DURATION"] ? [env[@"JELCZ_MAX_DURATION"] integerValue] : 180;

    config.s3Bucket = env[@"JELCZ_S3_BUCKET"];
    config.s3Region = env[@"JELCZ_S3_REGION"] ?: @"us-east-1";
    config.s3Endpoint = env[@"JELCZ_S3_ENDPOINT"];
    config.s3AccessKey = env[@"JELCZ_S3_ACCESS_KEY"];
    config.s3SecretKey = env[@"JELCZ_S3_SECRET_KEY"];

    return config;
}

@end
