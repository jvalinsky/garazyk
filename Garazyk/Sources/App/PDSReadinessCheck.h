// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSReadinessCheck.h
 @brief Server startup readiness verification.

 @discussion Performs pre-flight checks before the server accepts traffic.
 Verifies database pools, external dependencies, signing keys, and storage
 are all accessible and functional.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoServiceConfiguration;
@class PDSServiceDatabases;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const PDSReadinessErrorDomain;

/**
 * @abstract Defines PDSReadinessError values exposed by this API.
 */
typedef NS_ENUM(NSInteger, PDSReadinessError) {
    PDSReadinessErrorDatabaseUnavailable = 1,
    PDSReadinessErrorPLCUnreachable = 2,
    PDSReadinessErrorSigningKeyUnavailable = 3,
    PDSReadinessErrorBlobStorageUnavailable = 4,
    PDSReadinessErrorInsufficientDiskSpace = 5,
    PDSReadinessErrorConfigurationInvalid = 6,
};

/*!
 @interface PDSReadinessCheck
 @abstract Performs startup readiness verification.

 @discussion Checks critical dependencies before the server starts accepting
 traffic. This prevents situations where the server reports healthy but is
 unable to process requests due to missing resources.
 */
@interface PDSReadinessCheck : NSObject

/*!
 @brief Performs all startup readiness checks.

 @discussion Checks:
 1. Database connection pools are initialized and responding
 2. PLC directory is reachable (network connectivity)
 3. JWT signing keys are available
 4. Blob storage (disk/S3) is accessible
 5. Sufficient disk space (>= 1GB warning threshold)

 @param config Configuration object with deployment settings.
 @param error Error output parameter with failure details.
 @return YES if all checks pass, NO otherwise (server should not start).
 */
/**
 * @abstract Performs the performReadinessChecksWithConfig operation.
 */
+ (BOOL)performReadinessChecksWithConfig:(ATProtoServiceConfiguration *)config
                           serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                       error:(NSError **)error;

/**
 * @abstract Performs the performReadinessChecksWithConfig operation.
 */
+ (BOOL)performReadinessChecksWithConfig:(ATProtoServiceConfiguration *)config
                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
