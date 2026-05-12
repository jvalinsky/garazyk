// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSReadinessCheck.m
 @brief Implementation of server startup readiness verification.
 */

#import "PDSReadinessCheck.h"
#import "PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Debug/GZLogger.h"

NSString * const PDSReadinessErrorDomain = @"com.atproto.pds.readiness";

@implementation PDSReadinessCheck

+ (BOOL)performReadinessChecksWithConfig:(PDSConfiguration *)config
                                   error:(NSError **)error {
    PDSServiceDatabases *serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:config.dataDirectory
                                                                            serviceMaxSize:100
                                                                           didCacheMaxSize:1000
                                                                         sequencerMaxSize:100];
    return [self performReadinessChecksWithConfig:config serviceDatabases:serviceDatabases error:error];
}

+ (BOOL)performReadinessChecksWithConfig:(PDSConfiguration *)config
                           serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                       error:(NSError **)error {
    GZ_LOG_CORE_INFO(@"Starting server readiness checks...");

    // 1. Database connection pool initialization
    if (![self checkDatabasePools:config serviceDatabases:serviceDatabases error:error]) {
        GZ_LOG_CORE_ERROR(@"Database pool readiness check failed");
        return NO;
    }

    // 2. PLC directory reachability
    if (![self checkPLCDirectory:config error:error]) {
        GZ_LOG_CORE_ERROR(@"PLC directory readiness check failed");
        return NO;
    }

    // 3. Signing key availability
    if (![self checkSigningKeys:config serviceDatabases:serviceDatabases error:error]) {
        GZ_LOG_CORE_ERROR(@"Signing key readiness check failed");
        return NO;
    }

    // 4. Blob storage accessibility
    if (![self checkBlobStorage:config error:error]) {
        GZ_LOG_CORE_ERROR(@"Blob storage readiness check failed");
        return NO;
    }

    // 5. Disk space check (non-fatal warning)
    if (![self checkDiskSpace:config error:error]) {
        GZ_LOG_CORE_WARN(@"Disk space check warning (non-fatal)");
        // Don't fail, just warn
    }

    GZ_LOG_CORE_INFO(@"All readiness checks passed - server ready to accept traffic");
    return YES;
}

#pragma mark - Individual Checks

+ (BOOL)checkDatabasePools:(PDSConfiguration *)config serviceDatabases:(PDSServiceDatabases *)serviceDatabases error:(NSError **)error {
    // Attempt to acquire connection from service pool
    @try {
        NSError *dbError = nil;
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&dbError];

        if (!db || !db.isOpen) {
            if (error) {
                *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                             code:PDSReadinessErrorDatabaseUnavailable
                                         userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
            }
            return NO;
        }

        // Test query to verify database is responsive
        NSArray *result = [db executeParameterizedQuery:@"SELECT 1" params:@[] error:error];
        if (!result) {
            return NO;
        }

        GZ_LOG_CORE_DEBUG(@"Database pool check passed");
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                         code:PDSReadinessErrorDatabaseUnavailable
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Database check failed"}];
        }
        return NO;
    }
}

+ (BOOL)checkPLCDirectory:(PDSConfiguration *)config error:(NSError **)error {
    // Skip check in mock/test mode - matches pattern in XrpcIdentityMethods.m and PDSAccountService.m
    if ([config.plcURL isEqualToString:@"mock"] ||
        config.plcURL.length == 0 ||
        [config.plcURL hasPrefix:@"http://127.0.0.1"] ||
        [config.plcURL hasPrefix:@"http://localhost"]) {
        GZ_LOG_CORE_DEBUG(@"PLC directory check skipped (test/mock mode)");
        return YES;
    }

    // Attempt to resolve a well-known DID (bsky.app)
    NSString *testURL = [NSString stringWithFormat:@"%@/did:plc:z72i7hdynmk6r22z27h6tvur",
                        config.plcURL];

    NSURL *url = [NSURL URLWithString:testURL];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                         code:PDSReadinessErrorPLCUnreachable
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid PLC directory URL"}];
        }
        return NO;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 5.0;
    request.HTTPMethod = @"GET";

    NSHTTPURLResponse *response = nil;
    NSError *urlError = nil;

    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&urlError];

    // Accept 200 (success) or 404 (not found) - both mean PLC is reachable
    if (response && (response.statusCode == 200 || response.statusCode == 404)) {
        GZ_LOG_CORE_DEBUG(@"PLC directory reachable (%ld)", (long)response.statusCode);
        return YES;
    }

    if (error) {
        *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                     code:PDSReadinessErrorPLCUnreachable
                                 userInfo:@{NSLocalizedDescriptionKey:
                                           [NSString stringWithFormat:@"PLC directory unreachable (status: %ld, error: %@)",
                                                                    (long)(response ? response.statusCode : 0),
                                                                    urlError ? urlError.localizedDescription : @"unknown"]}];
    }
    return NO;
}

+ (BOOL)checkSigningKeys:(PDSConfiguration *)config serviceDatabases:(PDSServiceDatabases *)serviceDatabases error:(NSError **)error {
    @try {
        NSError *dbError = nil;
        PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&dbError];
        if (!db) {
            if (error) {
                *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                             code:PDSReadinessErrorSigningKeyUnavailable
                                         userInfo:@{NSLocalizedDescriptionKey: @"Service database not available"}];
            }
            return NO;
        }

        id<PDSKeyManager> keyManager = [PDSKeyManagerFactory createKeyManagerWithDatabase:db];
        if (!keyManager) {
            if (error) {
                *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                             code:PDSReadinessErrorSigningKeyUnavailable
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize key manager"}];
            }
            return NO;
        }

        id<PDSKeyPair> keyPair = [keyManager getActiveKeyPair:error];
        if (!keyPair) {
            if (error && !*error) {
                *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                             code:PDSReadinessErrorSigningKeyUnavailable
                                         userInfo:@{NSLocalizedDescriptionKey: @"No active signing key available"}];
            }
            return NO;
        }

        GZ_LOG_CORE_DEBUG(@"Signing key check passed");
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                         code:PDSReadinessErrorSigningKeyUnavailable
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Signing key check failed"}];
        }
        return NO;
    }
}

+ (BOOL)checkBlobStorage:(PDSConfiguration *)config error:(NSError **)error {
    if ([config.blobStorageType isEqualToString:@"disk"]) {
        // Test disk blob storage by writing a test file
        NSString *testPath = [config.dataDirectory stringByAppendingPathComponent:@".readiness_test"];

        BOOL success = [@"test" writeToFile:testPath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:error];

        // Clean up test file
        [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];

        if (success) {
            GZ_LOG_CORE_DEBUG(@"Blob storage (disk) check passed");
            return YES;
        }

        if (error && !*error) {
            *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                         code:PDSReadinessErrorBlobStorageUnavailable
                                     userInfo:@{NSLocalizedDescriptionKey: @"Data directory not writable"}];
        }
        return NO;
    } else if ([config.blobStorageType isEqualToString:@"s3"]) {
        // S3 readiness check - for now just warn (full S3 check is complex)
        GZ_LOG_CORE_DEBUG(@"S3 blob storage readiness check: assuming valid configuration");
        return YES;
    }

    return YES;
}

+ (BOOL)checkDiskSpace:(PDSConfiguration *)config error:(NSError **)error {
    NSError *fsError = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager]
                          attributesOfFileSystemForPath:config.dataDirectory
                                                  error:&fsError];

    if (!attrs) {
        if (error) {
            *error = fsError;
        }
        return NO;
    }

    NSNumber *freeSpace = attrs[NSFileSystemFreeSize];
    unsigned long long freeBytes = freeSpace.unsignedLongLongValue;
    unsigned long long freeGB = freeBytes / (1024 * 1024 * 1024);

    // Critical: less than 1GB
    if (freeGB < 1) {
        GZ_LOG_CORE_ERROR(@"CRITICAL: Less than 1GB free disk space (%llu GB remaining)", freeGB);
        if (error) {
            *error = [NSError errorWithDomain:PDSReadinessErrorDomain
                                         code:PDSReadinessErrorInsufficientDiskSpace
                                     userInfo:@{NSLocalizedDescriptionKey:
                                               [NSString stringWithFormat:@"Insufficient disk space: %llu GB remaining",
                                                                        freeGB]}];
        }
        return NO;
    }

    // Warning: less than 10GB
    if (freeGB < 10) {
        GZ_LOG_CORE_WARN(@"Low disk space warning: %llu GB free (consider cleanup)", freeGB);
    }

    GZ_LOG_CORE_DEBUG(@"Disk space check passed: %llu GB free", freeGB);
    return YES;
}

@end
