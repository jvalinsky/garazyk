// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Shared constants for did:plc directory, export, and replica behavior. */
FOUNDATION_EXPORT NSUInteger const PLCMaxDAGCborOperationBytes;
FOUNDATION_EXPORT NSUInteger const PLCExportDefaultCount;
FOUNDATION_EXPORT NSUInteger const PLCExportMaxCount;
FOUNDATION_EXPORT NSTimeInterval const PLCRecoveryWindowSeconds;
FOUNDATION_EXPORT NSUInteger const PLCReplicaDefaultBatchSize;
FOUNDATION_EXPORT NSTimeInterval const PLCReplicaDefaultPollInterval;
FOUNDATION_EXPORT NSUInteger const PLCExportStreamOutboundQueueLimit;
FOUNDATION_EXPORT NSString * const PLCJSONLinesContentType;
FOUNDATION_EXPORT NSString * const PLCRouteExport;
FOUNDATION_EXPORT NSString * const PLCRouteExportStream;
FOUNDATION_EXPORT NSString * const PLCRouteLogAudit;

NS_ASSUME_NONNULL_END

