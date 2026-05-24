// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCConstants.h"

NSUInteger const PLCMaxDAGCborOperationBytes = 7500;
NSUInteger const PLCExportDefaultCount = 10;
NSUInteger const PLCExportMaxCount = 1000;
NSTimeInterval const PLCRecoveryWindowSeconds = 72 * 60 * 60;
NSUInteger const PLCReplicaDefaultBatchSize = 100;
NSTimeInterval const PLCReplicaDefaultPollInterval = 5.0;
NSUInteger const PLCExportStreamOutboundQueueLimit = 1024;
NSString * const PLCJSONLinesContentType = @"application/jsonlines; charset=utf-8";
NSString * const PLCRouteExport = @"/export";
NSString * const PLCRouteExportStream = @"/export/stream";
NSString * const PLCRouteLogAudit = @"/:did/log/audit";

