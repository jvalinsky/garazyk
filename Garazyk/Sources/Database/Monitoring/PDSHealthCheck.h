// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @file PDSHealthCheck.h

 @abstract Health check and monitoring utilities for PDS database.

 @discussion This module provides PDSHealthCheck for monitoring database
 health, including:
 - Database integrity checks
 - Foreign key verification
 - Table size reporting
 - Fragmentation analysis
 - Pool metrics collection

 Health status is returned as PDSHealthStatus (healthy, warning, critical).

 @see PDSDatabasePool
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

@class PDSDatabasePool;
@class PDSServiceDatabases;

typedef NS_ENUM(NSInteger, PDSHealthStatus) {
    PDSHealthStatusHealthy = 0,
    PDSHealthStatusWarning,
    PDSHealthStatusCritical,
};

@interface PDSHealthCheck : NSObject

+ (instancetype)sharedInstance;

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

- (void)configureWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

- (NSDictionary<NSString *, id> *)performHealthCheck;

- (PDSHealthStatus)checkDatabaseIntegrity:(NSError **)error;
- (BOOL)checkForeignKeys:(NSError **)error;
- (NSDictionary<NSString *, NSNumber *> *)getTableSizes;
- (NSUInteger)getFragmentationPercent;

- (NSDictionary<NSString *, id> *)collectMetrics;

- (NSArray<NSString *> *)getWarnings;
- (NSArray<NSString *> *)getErrors;

@end

NS_ASSUME_NONNULL_END
