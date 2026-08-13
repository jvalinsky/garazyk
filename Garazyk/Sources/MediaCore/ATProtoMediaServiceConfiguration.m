// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "MediaCore/ATProtoMediaServiceConfiguration.h"

@implementation ATProtoMediaServiceConfiguration

- (instancetype)init {
    self = [super init];
    if (self) {
        _caObjectSweepEnabled = NO;
        _caObjectGracePeriodSeconds = 6 * 60 * 60;
    }
    return self;
}

+ (instancetype)configurationFromEnvironmentWithPrefix:(NSString *)prefix {
    ATProtoMediaServiceConfiguration *config = [[ATProtoMediaServiceConfiguration alloc] init];
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    config.port             = [self envInt:env key:[prefix stringByAppendingString:@"_PORT"] default:2586];
    config.dataDirectory    = env[[prefix stringByAppendingString:@"_DATA_DIR"]] ?: @"./data/media";
    config.blobDirectory    = env[[prefix stringByAppendingString:@"_BLOB_DIR"]] ?: @"./data/media/blobs";
    config.pdsURL           = env[[prefix stringByAppendingString:@"_PDS_URL"]] ?: @"http://localhost:2583";
    config.plcURL           = env[[prefix stringByAppendingString:@"_PLC_URL"]] ?: @"http://localhost:2582";
    config.serviceDID       = env[[prefix stringByAppendingString:@"_DID"]] ?: @"did:web:localhost";
    config.maxConcurrentJobs = [self envInt:env key:[prefix stringByAppendingString:@"_MAX_CONCURRENT_JOBS"] default:2];
    config.pollInterval     = [self envDouble:env key:[prefix stringByAppendingString:@"_POLL_INTERVAL"] default:5.0];
    config.maxUploadBytes   = (NSUInteger)[self envInt:env key:[prefix stringByAppendingString:@"_MAX_UPLOAD_BYTES"] default:(100 * 1024 * 1024)];
    config.maxOutputBytes   = (NSUInteger)[self envInt:env key:[prefix stringByAppendingString:@"_MAX_OUTPUT_BYTES"] default:(50 * 1024 * 1024)];
    config.maxDurationSeconds = [self envInt:env key:[prefix stringByAppendingString:@"_MAX_DURATION"] default:180];

    config.outputDirectory  = env[[prefix stringByAppendingString:@"_OUTPUT_DIR"]];
    config.outputBaseUrl    = env[[prefix stringByAppendingString:@"_OUTPUT_BASE_URL"]];
    config.includeHighQuality = [self envBool:env key:[prefix stringByAppendingString:@"_HIGH_QUALITY"] default:NO];
    config.enableContentAddressedManifest =
        [self envBool:env key:[prefix stringByAppendingString:@"_CA_MANIFEST"] default:NO];
    config.caObjectStoreDirectory = env[[prefix stringByAppendingString:@"_CA_STORE_DIR"]];
    config.caObjectSweepEnabled =
        [self envBool:env key:[prefix stringByAppendingString:@"_CA_SWEEP"] default:NO];
    NSString *graceKey = [prefix stringByAppendingString:@"_CA_GRACE_SECONDS"];
    NSString *graceEnv = env[graceKey];
    if ([graceEnv isKindOfClass:[NSString class]] && graceEnv.length > 0) {
        config.caObjectGracePeriodSeconds = [self envDouble:env key:graceKey default:(6 * 60 * 60)];
    }
    config.enableCAMirrorFetch =
        [self envBool:env key:[prefix stringByAppendingString:@"_CA_MIRROR_FETCH"] default:NO];
    NSString *mirrors = env[[prefix stringByAppendingString:@"_CA_MIRROR_PROVIDERS"]];
    if ([mirrors isKindOfClass:[NSString class]] && mirrors.length > 0) {
        NSMutableArray<NSString *> *providers = [NSMutableArray array];
        for (NSString *part in [mirrors componentsSeparatedByString:@","]) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [providers addObject:trimmed];
            }
        }
        config.caMirrorProviders = providers.count > 0 ? [providers copy] : nil;
    }

    config.s3Bucket         = env[[prefix stringByAppendingString:@"_S3_BUCKET"]];
    config.s3Region         = env[[prefix stringByAppendingString:@"_S3_REGION"]] ?: @"us-east-1";
    config.s3Endpoint       = env[[prefix stringByAppendingString:@"_S3_ENDPOINT"]];
    config.s3AccessKey      = env[[prefix stringByAppendingString:@"_S3_ACCESS_KEY"]];
    config.s3SecretKey      = env[[prefix stringByAppendingString:@"_S3_SECRET_KEY"]];

    return config;
}

#pragma mark - Helpers

+ (NSInteger)envInt:(NSDictionary *)env key:(NSString *)key default:(NSInteger)def {
    NSString *val = env[key];
    return val.length > 0 ? val.integerValue : def;
}

+ (double)envDouble:(NSDictionary *)env key:(NSString *)key default:(double)def {
    NSString *val = env[key];
    return val.length > 0 ? val.doubleValue : def;
}

+ (BOOL)envBool:(NSDictionary *)env key:(NSString *)key default:(BOOL)def {
    NSString *val = env[key];
    if (!val) return def;
    return [val boolValue];
}

@end
